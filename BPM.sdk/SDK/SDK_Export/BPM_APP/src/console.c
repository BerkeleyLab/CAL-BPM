/*
 * Simple command interperter
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <lwip/def.h>
#include <lwip/stats.h>
#include <lwip/udp.h>
#include <xparameters.h>
#include <xuartlite_l.h>
#include "cellStreamFilter.h"
#include "evr.h"
#include "gpio.h"
#include "systemParameters.h"
#include "tftp.h"
#include "util.h"

enum consoleMode { consoleModeCommand,
                   consoleModeLogReplay,
                   consoleModeBootQuery,
                   consoleModeNetQuery,
                   consoleModeMacQuery };
static enum consoleMode consoleMode;

/*
 * UDP console support
 */
#define BPM_CONSOLE_UDP_PORT    50003
#define UDP_CONSOLE_BUF_SIZE    1400
static struct udpConsole {
    struct udp_pcb *pcb;
    char            obuf[UDP_CONSOLE_BUF_SIZE];
    int             outIndex;
    uint32_t        ticksAtFirstOutputCharacter;
    struct pbuf    *pbufIn;
    int             inIndex;
    struct ip_addr  fromAddr;
    uint16_t        fromPort;
} udpConsole;

static void
udpConsoleDrain(void)
{
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, udpConsole.outIndex, PBUF_RAM);
    if (p) {
        memcpy(p->payload, udpConsole.obuf, udpConsole.outIndex);
        udp_sendto(udpConsole.pcb, p, &udpConsole.fromAddr, udpConsole.fromPort);
    }
    udpConsole.outIndex = 0;
}

/*
 * Hang on to start messages
 */
#define STARTBUF_SIZE   120000
static char startBuf[STARTBUF_SIZE];
static int startIdx = 0;
static int isStartup = 1;

void
outbyte(int c)
{
    XUartLite_SendByte(STDOUT_BASEADDRESS, c);
    if (isStartup && (startIdx < STARTBUF_SIZE))
        startBuf[startIdx++] = c;
    if (udpConsole.fromPort) {
        if (udpConsole.outIndex == 0)
            udpConsole.ticksAtFirstOutputCharacter = sysTicksSinceBoot();
        udpConsole.obuf[udpConsole.outIndex++] = c;
        if (udpConsole.outIndex >= UDP_CONSOLE_BUF_SIZE)
            udpConsoleDrain();
    }
}

static int
cmdLOG(int argc, char **argv)
{
    consoleMode = consoleModeLogReplay;
    return 0;
}
static int
cmdLOGactive(void)
{
    static int i;

    if (consoleMode == consoleModeLogReplay) {
        if (i < startIdx) {
            outbyte(startBuf[i++]);
            return 1;
        }
        else {
            i = 0;
            consoleMode = consoleModeCommand;
        }
    }
    return 0;
}

/*
 * boot command
 */
static void
bootQueryCallback(int argc, char **argv)
{
    if (argc == 1) {
        if (strcasecmp(argv[0], "Y") == 0) {
            resetFPGA();
            return;
        }
        if (strcasecmp(argv[0], "N") == 0) {
            consoleMode = consoleModeCommand;
            return;
        }
    }
    printf("Reboot FPGA (y or n)? ");
    fflush(stdout);
}
static int
cmdBOOT(int argc, char **argv)
{
    char *cp = NULL;

    consoleMode = consoleModeBootQuery;
    bootQueryCallback(0, &cp);
    return 0;
}

static int
cmdDEBUG(int argc, char **argv)
{
    char *endp;
    int d;

    if (argc > 1) {
        d = strtol(argv[1], &endp, 16);
        if (*endp == '\0') {
            debugFlags = d;
            cellStreamFilterApplyDebugFlags();
        }
    }
    printf("Debug flags: %#x\n", debugFlags);
    return 0;
}

static int
cmdEVR(int argc, char **argv)
{
    evrShow();
    return 0;
}

static int
cmdGEN(int argc, char **argv)
{
    uint32_t csr = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);
    const uint32_t csrSimulateBeam = 0x80000000;
    if (argc > 1) {
        if (strcasecmp(argv[1], "off") == 0) {
            csr &= ~csrSimulateBeam;
        }
        else if (strcasecmp(argv[1], "on") == 0) {
            csr |= csrSimulateBeam;
        }
        else {
            printf ("Argument must be off or on\n");
            return 1;
        }
        GPIO_WRITE(GPIO_IDX_AUTOTRIM_CSR, csr);
    }
    printf("Simulated beam signal %s.\n", csr & csrSimulateBeam ? "on" : "off");
    return 0;
}

/*
 * Network configuration
 */
static struct sysNetParms ipv4;
static void
netQueryCallback(int argc, char **argv)
{
    if (argc == 1) {
        if (strcasecmp(argv[0], "Y") == 0) {
            systemParameters.ipv4 = ipv4;
            stashSystemParameters();
            consoleMode = consoleModeCommand;
            return;
        }
        if (strcasecmp(argv[0], "N") == 0) {
            consoleMode = consoleModeCommand;
            return;
        }
    }
    printf("       IP ADDR: %s\n", formatIP(&ipv4.address));
    printf("      NET MASK: %s\n", formatIP(&ipv4.netmask));
    printf("       GATEWAY: %s\n", formatIP(&ipv4.gateway));
    if ((consoleMode == consoleModeNetQuery)
     || (ipv4.address != systemParameters.ipv4.address)
     || (ipv4.netmask != systemParameters.ipv4.netmask)
     || (ipv4.gateway != systemParameters.ipv4.gateway)) {
        printf("Write parameters to flash (y or n)? ");
        fflush(stdout);
        consoleMode = consoleModeNetQuery;
    }
}
static int
cmdNET(int argc, char **argv)
{
    int bad = 0;
    int i;
    char *cp;
    int netLen = 24;
    char *endp;

    if (argc == 1) {
        ipv4 = systemParameters.ipv4;
    }
    else if (argc == 2) {
        cp = argv[1];
        i = parseIP(cp, &ipv4.address);
        if (i < 0) {
            bad = 1;
        }
        else if (cp[i] == '/') {
            netLen = strtol(cp + i + 1, &endp, 0);
            if ((*endp != '\0')
             || (netLen < 8)
             || (netLen > 24)) {
                bad = 1;
            }
        }
        ipv4.netmask = ~0 << (32 - netLen);
        ipv4.gateway = (ntohl(ipv4.address) & ipv4.netmask) | 1;
        ipv4.netmask = htonl(ipv4.netmask);
        ipv4.gateway = htonl(ipv4.gateway);
    }
    else {
        bad = 1;
    }
    if (bad) {
        printf("Command takes single optional argument of the form "
               "www.xxx.yyy.xxx[/n]\n");
        return 1;
    }
    cp = NULL;
    netQueryCallback(0, &cp);
    return 0;
}

/*
 * MAC configuration
 */
static unsigned char macBuf[6];
static void
macQueryCallback(int argc, char **argv)
{
    if (argc == 1) {
        if (strcasecmp(argv[0], "Y") == 0) {
            memcpy(systemParameters.ethernetAddress, macBuf, sizeof macBuf);
            stashSystemParameters();
            consoleMode = consoleModeCommand;
            return;
        }
        if (strcasecmp(argv[0], "N") == 0) {
            consoleMode = consoleModeCommand;
            return;
        }
    }
    printf("   ETHERNET ADDRESS: %s\n", formatMAC(&macBuf));
    if ((consoleMode == consoleModeMacQuery)
     || (memcmp(systemParameters.ethernetAddress, macBuf, sizeof macBuf))) {
        printf("Write parameters to flash (y or n)? ");
        fflush(stdout);
        consoleMode = consoleModeMacQuery;
    }
}
static int
cmdMAC(int argc, char **argv)
{
    int bad = 0;
    int i;
    char *cp;

    if (argc == 1) {
        memcpy(macBuf, systemParameters.ethernetAddress,
                                    sizeof systemParameters.ethernetAddress);
    }
    else if (argc == 2) {
        i = parseMAC(argv[1], macBuf);
        if ((i < 0) || (argv[1][i] != '\0')) {
            bad = 1;
        }
    }
    else {
        bad = 1;
    }
    if (bad) {
        printf("Command takes single optional argument of the form "
               "aa:bb:cc:dd:ee:ff\n");
        return 1;
    }
    cp = NULL;
    macQueryCallback(0, &cp);
    return 0;
}

static int
cmdSTATS(int argc, char **argv)
{
    stats_display();
    return 0;
}

static int
cmdREG(int argc, char **argv)
{
    char *endp;
    int i;
    int first;
    int n = 1;

    if (argc > 1) {
        first = strtol(argv[1], &endp, 0);
        if (*endp != '\0')
            return 1;
        if (argc > 2) {
            n = strtol(argv[2], &endp, 0);
            if (*endp != '\0')
                return 1;
        }
        if ((first < 0) || (first >= GPIO_IDX_COUNT) || (n <= 0))
            return 1;
        if ((first + n) > GPIO_IDX_COUNT)
            n = GPIO_IDX_COUNT - first;
        for (i = first ; i < first + n ; i++) {
            showReg(i);
        }
    }
    return 0;
}

struct commandInfo {
    const char *name;
    int       (*handler)(int argc, char **argv);
    const char *description;
};
static struct commandInfo commandTable[] = {
  { "boot",  cmdBOOT,  "Reboot FPGA"                        },
  { "debug", cmdDEBUG, "Set debug flags"                    },
  { "evr",   cmdEVR,   "Show EVR registers"                 },
  { "gen",   cmdGEN,   "Generate simulated button signals"  },
  { "log",   cmdLOG,   "Replay startup console output"      },
  { "mac",   cmdMAC,   "Set Ethernet MAC address"           },
  { "net",   cmdNET,   "Set network parameters"             },
  { "reg",   cmdREG,   "Show GPIO register(s)"              },
  { "stats", cmdSTATS, "Show network statistics"            },
};
static void
commandCallback(int argc, char **argv)
{
    int i;
    int len;
    int matched = -1;

    if (argc <= 0)
        return;
    len = strlen(argv[0]);
    for (i = 0 ; i < sizeof commandTable / sizeof commandTable[0] ; i++) {
        if (strncasecmp(argv[0], commandTable[i].name, len) == 0) {
            if (matched >= 0) {
                printf("Not unique.\n");
                return;
            }
            matched = i;
        }
    }
    if (matched >= 0) {
        (*commandTable[matched].handler)(argc, argv);
        return;
    }
    if ((strncasecmp(argv[0], "help", len) == 0) || (argv[0][0] == '?')) {
        printf("Commands:\n");
        for (i = 0 ; i < sizeof commandTable / sizeof commandTable[0] ; i++) {
            printf("%8s -- %s\n", commandTable[i].name,
                                  commandTable[i].description);
        }
    }
    else {
        printf("Invalid command\n");
    }
}

static void
handleLine(char *line)
{
    char *argv[10];
    int argc;
    char *tokArg, *tokSave;

    argc = 0;
    tokArg = line;
    while ((argc < (sizeof argv / sizeof argv[0]) - 1)) {
        char *cp = strtok_r(tokArg, " ,", &tokSave);
        if (cp == NULL)
            break;
        argv[argc++] = cp;
        tokArg = NULL;
    }
    argv[argc] = NULL;
    switch (consoleMode) {
    case consoleModeCommand:   commandCallback(argc, argv);           break;
    case consoleModeLogReplay:                                        break;
    case consoleModeBootQuery: bootQueryCallback(argc, argv);         break;
    case consoleModeNetQuery:  netQueryCallback(argc, argv);          break;
    case consoleModeMacQuery:  macQueryCallback(argc, argv);          break;
    }
}

/*
 * Handle UDP console input
 */
void
console_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                                      struct ip_addr *fromAddr, u16_t fromPort)
{
    /* Silently ignore runt packets and overruns */
    if ((p->len == 0) || (udpConsole.pbufIn != NULL)) {
        pbuf_free(p);
        return;
    }
    udpConsole.fromAddr = *fromAddr;
    udpConsole.fromPort = fromPort;
    udpConsole.pbufIn = p;
    udpConsole.inIndex = 0;
}

/*
 * Check for and act upon character from console
 */
void
consoleCheck(void)
{
    int c = -1;
    static char line[200];
    static int idx = 0;
    static int firstTime = 1;

    if (firstTime) {
        int err;
        firstTime = 0;
        udpConsole.pcb = udp_new();
        if (udpConsole.pcb == NULL)
            fatal("Can't create console PCB");
        err = udp_bind(udpConsole.pcb, IP_ADDR_ANY, BPM_CONSOLE_UDP_PORT);
        if (err != ERR_OK)
            fatal1("Can't bind to console port, error:%d", err);
        udp_recv(udpConsole.pcb, console_callback, NULL);
    }
    if (udpConsole.outIndex != 0) {
        if ((sysTicksSinceBoot() - udpConsole.ticksAtFirstOutputCharacter) >
                                                (XPAR_MICROBLAZE_FREQ / 10)) {
            udpConsoleDrain();
        }
    }
    if (cmdLOGactive()) return;
    if (!XUartLite_IsReceiveEmpty(STDIN_BASEADDRESS)) {
        c = XUartLite_RecvByte(STDIN_BASEADDRESS) & 0xFF;
        udpConsole.fromPort = 0;
    }
    else if (udpConsole.pbufIn) {
        c = *((char *)udpConsole.pbufIn->payload + udpConsole.inIndex++);
        if (udpConsole.inIndex >= udpConsole.pbufIn->len) {
            pbuf_free(udpConsole.pbufIn);
            udpConsole.pbufIn = NULL;
        }
    }
    else {
        return;
    }
    if ((c == '\001') || (c > '\177')) return;
    if (c == '\t') c = ' ';
    else if (c == '\177') c = '\b';
    else if (c == '\r') c = '\n';
    if (c == '\n') {
        isStartup = 0;
        printf("\n");
        line[idx] = '\0';
        idx = 0;
        handleLine(line);
        return;
    }
    if (c == '\b') {
        if (idx) {
            printf("\b \b");
            fflush(stdout);
            idx--;
        }
        return;
    }
    if (c < ' ')
        return;
    if (idx < ((sizeof line) - 1)) {
        printf("%c", c);
        fflush(stdout);
        line[idx++] = c;
    }
}
