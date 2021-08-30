/*
 * TFTP and simple file system for:
 *      FPGA Firmware
 *      BPM application software
 *      AFE attenuator compensation table
 *      System settings (Ethenet address, IP address, etc.)
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <lwip/udp.h>
#include <xparameters.h>
#include "afeAtten.h"
#include "gpio.h"
#include "linearFlash.h"
#include "localOscillator.h"
#include "systemParameters.h"
#include "util.h"

#define TFTP_PORT 69

#define TFTP_OPCODE_RRQ   1
#define TFTP_OPCODE_WRQ   2
#define TFTP_OPCODE_DATA  3
#define TFTP_OPCODE_ACK   4
#define TFTP_OPCODE_ERROR 5

#define TFTP_ERROR_ACCESS_VIOLATION 2
#define TFTP_PAYLOAD_CAPACITY   512
#define TFTP_PACKET_CAPACITY    ((2 * sizeof (u16_t)) + TFTP_PAYLOAD_CAPACITY)

#define TRANSFER_TIMEOUT_SECONDS 30 /* Assume client is gone after this long */
#define ticks2microsec(t) ((unsigned int)(t)/(XPAR_MICROBLAZE_FREQ/1000000))

static struct udp_pcb *pcb;

/*
 * Very simple "file system"
 * Be careful changing locations -- things like the SREC
 * bootstrap loader have these addresses burned in.
 */
struct fileInfo {
    const char *name;
    const char *description;
    int         baseAddress;
    int         maxSize;
    int       (*preTransmit)(unsigned char *buf, int capacity);
    int       (*postReceive)(unsigned char *buf, int size);
    void      (*readback)(const unsigned char *buf);
};

#define MB(x) ((x)*1024*1024)
#define kB(x) ((x)*1024)

static struct fileInfo fileTable[] = {
 {"BPM.bin",         "FPGA firmware",     MB(64), MB(16)-kB(128),  NULL, NULL},
 {"BPM_APP.srec",    "System software",   MB(80), MB(4),           NULL, NULL},
 {"Parameters.csv",  "Parameter table",   MB(84), MB(1),
                                                    systemParametersGetTable,
                                                    systemParametersSetTable,
                                                    systemParametersReadback},
 {"Attenuation.csv", "Attenuation table", MB(85), MB(1),
                                                    afeAttenGetTable,
                                                    afeAttenSetTable,
                                                    afeAttenReadback},
 {"rfTable.csv", "Local oscillator table (RF)", MB(86), MB(1),
                                                    localOscGetRfTable,
                                                    localOscSetRfTable,
                                                    localOscRfReadback},
 {"ptTable.csv", "Local oscillator table (Pilot Tones)", MB(87), MB(1),
                                                    localOscGetPtTable,
                                                    localOscSetPtTable,
                                                    localOscPtReadback},
 {"FLASHIMAGE.bin",  "Full flash image",       0, MB(128),         NULL, NULL},
};
#define FILE_TABLE_SIZE ((sizeof fileTable / sizeof fileTable[0]))
#define SIZE_TABLE_OFFSET (fileTable[0].baseAddress+fileTable[0].maxSize)
#define FILE_TABLE_PARAMETER_TABLE_INDEX 2

/*
 * UDP transfer buffer
 * Allow space for extra terminating '\0'.
 */
static unsigned char ioBuf[MB(1)+1];
static unsigned char *ioPtr = ioBuf;

/*
 * Get the size of a file
 */
static int
getSize(int fileIndex)
{
    int *ip = (int *)(XPAR_LINEAR_FLASH_S_AXI_MEM0_BASEADDR + SIZE_TABLE_OFFSET);

    if (fileIndex == (FILE_TABLE_SIZE-1))
        return fileTable[fileIndex].maxSize;
    ip += 2 * fileIndex;
    if (ip[1] == (ip[0] + 0x123456)) {
        return ip[0];
    }
    else {
        printf("=== WARNING === Can't get size of \"%s\".  Assum %d.\n",
                                                fileTable[fileIndex].name,
                                                fileTable[fileIndex].maxSize);
        return fileTable[fileIndex].maxSize;
    }
}

/*
 * Remember the size of a file
 */
static void
setSize(int fileIndex, int size)
{
    int *ip = (int *)(XPAR_LINEAR_FLASH_S_AXI_MEM0_BASEADDR + SIZE_TABLE_OFFSET);
    int *sv = (int *)ioBuf;
    int io = 2 * FILE_TABLE_SIZE * sizeof(*ip);

    memcpy(sv, ip, io);
    sv[(2 * fileIndex)] = size;
    sv[(2 * fileIndex) + 1] = size + 0x123456;
    linearFlashWrite(SIZE_TABLE_OFFSET, (char *)sv, io);
}

/*
 * Send an error reply
 */
static void
replyERR(const char *msg, struct ip_addr *addr, int port)
{
    int l = (2 * sizeof (u16_t)) + strlen(msg) + 1;
    struct pbuf *p;
    u16_t *p16;

    p = pbuf_alloc(PBUF_TRANSPORT, l, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocate TFTP ERROR pbuf\n");
        return;
    }
    p16 = (u16_t *)p->payload;
    *p16++ = htons(TFTP_OPCODE_ERROR);
    *p16++ = htons(TFTP_ERROR_ACCESS_VIOLATION);
    strcpy((char *)p16, msg);
    udp_sendto(pcb, p, addr, port);
    pbuf_free(p);
}

/*
 * Send a success reply
 */
static void
replyACK(int block, struct ip_addr *addr, int port)
{
    int l = 2 * sizeof (u16_t);
    struct pbuf *p;
    u16_t *p16;

    p = pbuf_alloc(PBUF_TRANSPORT, l, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocte TFTP ACK pbuf\n");
        return;
    }
    p16 = (u16_t *)p->payload;
    *p16++ = htons(TFTP_OPCODE_ACK);
    *p16++ = htons(block);
    if (debugFlags & DEBUGFLAG_TFTP)
        printf("TFTP %10u ACK block %d\n",
                                    ticks2microsec(sysTicksSinceBoot()), block);
    udp_sendto(pcb, p, addr, port);
    pbuf_free(p);
}

/*
 * Send a data packet
 */
static int
sendBlock(int block, int offset, int bytesLeft, struct ip_addr *addr, int port)
{
    int l, nSend;
    struct pbuf *p;
    u16_t *p16;

    nSend = bytesLeft;
    if (nSend > TFTP_PAYLOAD_CAPACITY)
        nSend = TFTP_PAYLOAD_CAPACITY;
    l = (2 * sizeof(u16_t)) + nSend;
    p = pbuf_alloc(PBUF_TRANSPORT, l, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocte TFTP DATA pbuf\n");
        return 0;
    }
    p16 = (u16_t*)p->payload;
    *p16++ = htons(TFTP_OPCODE_DATA);
    *p16++ = htons(block);
    if (nSend)
        memcpy(p16, ioPtr + offset, nSend);
    if (debugFlags & DEBUGFLAG_TFTP)
        printf("TFTP %10u send %d (block %d) from %d\n",
                    ticks2microsec(sysTicksSinceBoot()), nSend, block, offset);
    udp_sendto(pcb, p, addr, port);
    pbuf_free(p);
    return nSend;
}

/*
 * Filename matcher
 *   Ignore case.
 *   Ignore characters after table name and before name extension.
 */
static int
match(const char *name, const char *table)
{
    const char *fileExt, *tableExt;
    int l;

    fileExt = strrchr(name, '.');
    tableExt = strrchr(table, '.');
    if ((fileExt == NULL) || (tableExt == NULL))
        return 0;
    l =  tableExt - table;
    if ((strncasecmp(name, table, l) != 0)
     || (strcasecmp(fileExt, tableExt) != 0))
        return 0;
    return 1;
}

/*
 * Simple-minded TFTP server
 * Likely could be mangled by nefarious and/or duplicate clients
 */
static void
handlePacket(void *arg, struct udp_pcb *pcb, struct pbuf *p,
              struct ip_addr *fromAddr, u16_t fromPort)
{
    unsigned char *cp = p->payload;
    int opcode = (cp[0] << 8) | cp[1];
    static int ioOffset;
    static int bytesLeft;
    static u16_t lastBlock;
    static int lastSend;
    static int fileIndex = -1;
    static int lastSeconds;

    if (debugFlags & DEBUGFLAG_TFTP) {
        long addr = ntohl(fromAddr->addr);
        printf("TFTP %10u size %d from %d.%d.%d.%d:%d  OP:%04x\n",
                                            ticks2microsec(sysTicksSinceBoot()),
                                            p->len,
                                            (int)((addr >> 24) & 0xFF),
                                            (int)((addr >> 16) & 0xFF),
                                            (int)((addr >>  8) & 0xFF),
                                            (int)((addr      ) & 0xFF),
                                            fromPort, opcode);
    }
    if ((opcode == TFTP_OPCODE_RRQ) || (opcode == TFTP_OPCODE_WRQ)) {
        char *name = (char *)cp + 2, *mode = NULL;
        int nullCount = 0, i = 2;
        lastBlock = 0;
        if ((fileIndex >= 0)
         && ((secondsSinceBoot() - lastSeconds) < TRANSFER_TIMEOUT_SECONDS)) {
            replyERR("Busy", fromAddr, fromPort);
            return;
        }
        fileIndex = -1;
        for (;;) {
            if (i >= p->len) {
                replyERR("TFTP request too short", fromAddr, fromPort);
                return;
            }
            if (cp[i++] == '\0') {
                nullCount++;
                if (nullCount == 1)
                    mode = (char *)cp + i;
                if (nullCount == 2) {
                    int f;
                    if (debugFlags & DEBUGFLAG_TFTP)
                        printf("NAME:%s  MODE:%s\n", name, mode);
                    if (strcasecmp(mode, "octet") != 0) {
                        replyERR("Bad Type", fromAddr, fromPort);
                        return;
                    }
                    for (f = 0 ; f < FILE_TABLE_SIZE ; f++) {
                        if (match(name, fileTable[f].name)) {
                            ioOffset = 0;
                            fileIndex = f;
                            break;
                        }
                    }
                    break;
                }
            }
        }
        if (fileIndex < 0) {
            replyERR("Bad Name", fromAddr, fromPort);
            return;
        }
        if (opcode == TFTP_OPCODE_RRQ) {
            int (*fp)(unsigned char *, int) = fileTable[fileIndex].preTransmit;
            if (fp) {
                bytesLeft = (*fp)(ioBuf, sizeof ioBuf);
                ioPtr = ioBuf;
            }
            else {
                bytesLeft = getSize(fileIndex);
                ioPtr = (unsigned char *)(XPAR_LINEAR_FLASH_S_AXI_MEM0_BASEADDR
                                            + fileTable[fileIndex].baseAddress);
            }
            lastBlock = 1;
            lastSend = sendBlock(lastBlock, ioOffset, bytesLeft, fromAddr, fromPort);
            return;
        }
        replyACK(0, fromAddr, fromPort);
    }
    else if ((opcode == TFTP_OPCODE_DATA) && (fileIndex >= 0)) {
        int block = (cp[2] << 8) | cp[3];
        if (block == lastBlock) {
            replyACK(block, fromAddr, fromPort);
        }
        else if (block == (u16_t)(lastBlock + 1)) {
            int nBytes = p->len - (2 * sizeof(u16_t));
            lastBlock = block;
            if (nBytes > 0) {
                if ((fileTable[fileIndex].maxSize - ioOffset) < nBytes) {
                    replyERR("File too big", fromAddr, fromPort);
                    return;
                }
                else {
                    if (fileTable[fileIndex].postReceive) {
                        memcpy(ioBuf + ioOffset, cp+4, nBytes);
                    }
                    else {
                        if (linearFlashWrite(fileTable[fileIndex].baseAddress +
                                                            ioOffset,
                                                            (char *)(cp+4),
                                                            nBytes) != nBytes) {
                            replyERR("Write error", fromAddr, fromPort);
                            fileIndex = -1;
                            return;
                        }
                    }
                    ioOffset += nBytes;
                }
            }
            if (nBytes < TFTP_PAYLOAD_CAPACITY) {
                if (fileTable[fileIndex].postReceive) {
                    int n;
                    ioBuf[ioOffset] = '\0';
                    n = (*fileTable[fileIndex].postReceive)(ioBuf, ioOffset);
                    if (n < 0) {
                        replyERR((char *)ioBuf, fromAddr, fromPort);
                        return;
                    }
                    else if (linearFlashWrite(fileTable[fileIndex].baseAddress,
                                                    (char *)ioBuf, n) != n) {
                        replyERR("Write error", fromAddr, fromPort);
                        return;
                    }
                }
                else {
                    setSize(fileIndex, ioOffset);
                }
                fileIndex = -1;
            }
            replyACK(block, fromAddr, fromPort);
        }
        lastSeconds = secondsSinceBoot();
    }
    else if ((opcode == TFTP_OPCODE_ACK) && (fileIndex >= 0)) {
        int block = (cp[2] << 8) | cp[3];
        if (block == lastBlock) {
            lastBlock++;
            ioOffset += lastSend;
            bytesLeft -= lastSend;
            if (lastSend == TFTP_PAYLOAD_CAPACITY)
                lastSend = sendBlock(lastBlock, ioOffset, bytesLeft, fromAddr, fromPort);
            else
                fileIndex = -1;
        }
        else {
            lastSend = sendBlock(lastBlock, ioOffset, bytesLeft, fromAddr, fromPort);
        }
        lastSeconds = secondsSinceBoot();
    }
}

static void
tftp_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
              struct ip_addr *fromAddr, u16_t fromPort)
{
    /*
     * Processing a TFTP packet can take a long time if it results in a flash
     * erase operation so it would be good to keep polling for work while
     * waiting for the erase to complete.
     * Unfortunately it appears that recursive calls to the network input
     * routine breaks things, so for now we'll just live with blocking network
     * input while the erase is active.
     * Ignore runt packets.
     */
    if (p->len >= (2 * sizeof (u16_t)))
        handlePacket(arg, pcb, p, fromAddr, fromPort);
    pbuf_free(p);
}

void tftpInit(void)
{
    int err;

    pcb = udp_new();
    if (pcb == NULL) {
        fatal("Can't create tftp PCB");
        return;
    }
    err = udp_bind(pcb, IP_ADDR_ANY, TFTP_PORT);
    if (err != ERR_OK) {
        fatal1("Can't bind to publisher port, error:%d", err);
        return;
    }
    udp_recv(pcb, tftp_callback, NULL);
}

/*
 * Read back 'filesystem' values on startup
 */
void
filesystemReadbacks(void)
{
    int i;
    const unsigned char *cp;

    for (i = 0 ; i < FILE_TABLE_SIZE ; i++) {
        if (fileTable[i].readback) {
            cp = (const unsigned char *)(XPAR_LINEAR_FLASH_S_AXI_MEM0_BASEADDR +
                                         fileTable[i].baseAddress);
            (*fileTable[i].readback)(cp);
            if (fileTable[i].preTransmit) {
                const char *cp = (char *)ioBuf;
                int l = (*fileTable[i].preTransmit)(ioBuf, sizeof ioBuf);
                int newline = 1;
                if (l >= 0) {
                    printf("\n%s (%s):\n", fileTable[i].description,
                                               fileTable[i].name);
                    while(l-- > 0) {
                        if (newline) {
                            newline = 0;
                            printf("    ");
                        }
                        if (*cp == '\n')
                            newline = 1;
                        printf("%c", *cp++);
                    }
                }
            }
        }
    }
    printf("\n");
}

/*
 * Write system parameters (console callback)
 */
void
stashSystemParameters(void)
{
    int base = fileTable[FILE_TABLE_PARAMETER_TABLE_INDEX].baseAddress;
    const char *buf = (char *)&systemParameters;
    int count =  sizeof systemParameters;

    systemParametersUpdateChecksum();
    if (linearFlashWrite(base, buf, count) != count)
        printf("Flash write failed!\n");
}

