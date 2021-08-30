/*
 * Accept and act upon commands from the IOC
 */
#include <stdio.h>
#include <string.h>
#include <lwip/udp.h>
#include "bpmProtocol.h"
#include "afeAtten.h"
#include "afePLL.h"
#include "autotrim.h"
#include "cellStreamFilter.h"
#include "evr.h"
#include "gpio.h"
#include "localOscillator.h"
#include "server.h"
#include "sfp.h"
#include "util.h"
#include "waveformRecorder.h"

/*
 * ADC control
 */
#define ADC_CONTROL_GAIN_SELECT 0x1 /* 0/1, gain=1.0/1.5 */

static struct udp_pcb *pcb;

int
duplicateIOCcheck(unsigned long address, unsigned int port)
{
    uint32_t now = secondsSinceBoot();
    static unsigned long oldAddress;
    static unsigned short oldPort;
    static uint32_t whenChanged, whenDuplicate;
    
    if (address != 0) {
        if ((address != oldAddress) || (port != oldPort)) {
            if ((now - whenChanged) < 10) whenDuplicate = now;
            oldPort = port;
            oldAddress = address;
            whenChanged = now;
        }
    }
    return ((now - whenDuplicate) < 15);
}

static void
io_debug(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        debugFlags = cmd->value;
        cellStreamFilterApplyDebugFlags();
    }
    reply->u.value = debugFlags;
}

static void
io_IDstring(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    const char *cp = NULL;
    int type = (cmd->value >> 4) & 0xF;
    int idx = cmd->value & 0xF;

    switch(type) {
    case 0: switch(idx) {
        case 0: cp = firmwareRevision;          break;
        case 1: cp = softwareRevision;          break;
        } break;
    case 1: cp = getSFPvendorName(idx);         break;
    case 2: cp = getSFPvendorPartNumber(idx);   break;
    case 3: cp = getSFPvendorSerialNumber(idx); break;
    case 4: cp = getSFPvendorDateCode(idx);     break;
    case 5: switch(idx) {
        case 0:
            reply->u.value = ~GPIO_READ(GPIO_IDX_SERIAL_NUMBERS) & 0x3FF;
            return;
        case 1:
            reply->u.value = (~GPIO_READ(GPIO_IDX_SERIAL_NUMBERS) >> 10) & 0x3FF;
            return;
        default: reply->u.value = 0; break;
        }
        return;
    }
    if (cp == NULL) cp = "Invalid subaddress";
    strncpy(reply->u.str, cp, sizeof reply->u.str);
}

static void
io_atten(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        afeAttenSet(cmd->value);
    reply->u.value = afeAttenGet();
}

static void
io_adcGain(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    uint32_t reg = GPIO_READ(GPIO_IDX_ADC_CONTROL);
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        reg &= ~ADC_CONTROL_GAIN_SELECT;
        if (cmd->value)
            reg |= ADC_CONTROL_GAIN_SELECT;
        GPIO_WRITE(GPIO_IDX_ADC_CONTROL, reg);
    }
    reply->u.value = ((reg & ADC_CONTROL_GAIN_SELECT) != 0);
}

static void
io_lobLimit(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        GPIO_WRITE(GPIO_IDX_LOSS_OF_BEAM_THRSH, cmd->value);
    reply->u.value = GPIO_READ(GPIO_IDX_LOSS_OF_BEAM_THRSH);
}

static void
io_atEnable(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        autotrimEnable(cmd->value);
    reply->u.value = (autotrimStatus() != AUTOTRIM_STATUS_DISABLED);
}

static void
io_atThresh(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        autotrimSetThreshold(cmd->value);
    reply->u.value = autotrimGetThreshold();
}

static void
io_atFilter(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        autotrimSetFilterShift(cmd->value);
    reply->u.value = autotrimGetFilterShift();
}

static void
io_selfTrigLevel(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        GPIO_WRITE(GPIO_IDX_SELFTRIGGER_CSR, cmd->value);
    }
    reply->u.value = GPIO_READ(GPIO_IDX_SELFTRIGGER_CSR);
}

static void
io_dspType(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        localOscSetDspAlgorithm(cmd->value & 0x1);
    }
    reply->u.value = localOscGetDspAlgorithm();
}

static void
io_fpgaReset(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    static int idx;
    static const int match[] = { 0, 100, 10000 };
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        if (cmd->value == 0x1) {
            rescanAdcClkDelay();
        }
        else if (cmd->value == match[0]) {
            idx = 1;
        }
        else if (cmd->value == match[idx++]) {
            if (idx >= (sizeof match / sizeof match[0]))
                resetFPGA();
        }
        else {
            idx = 0;
        }
    }
    reply->u.value = 0;
}

static void
io_latchClear(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        if (cmd->value & 0x1) afePLLclearLatch();
    }
    reply->u.value = 0;
}

static void
io_tbtSumShift(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        sdAccumulateSetTbtSumShift(cmd->value);
    }
    reply->u.value = sdAccumulateGetTbtSumShift();
}

static void
io_mtSumShift(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        sdAccumulateSetMtSumShift(cmd->value);
    }
    reply->u.value = sdAccumulateGetMtSumShift();
}

static void
cv_command(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    int code = cmd->code &  0xF0;
    int adcChan = cmd->code & 0x0F;

    switch (code) {
    case BPM_PROTOCOL_COMMAND_CHANVAL_GAIN:
        if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
            afeSetGainCompensation(adcChan, cmd->value);
        reply->u.value = afeGetGainCompensation(adcChan);
        break;
    }
}

static void
evr_eventTriggers(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    int event = cmd->code & 0xFF;

    if (cmd->code & BPM_PROTOCOL_WRITE_MASK) {
        int saveAction = evrGetEventAction(event) & ~0xF0;
        evrSetEventAction(event, (cmd->value & 0xF0) | saveAction);
    }
    reply->u.value = evrGetEventAction(event) & 0xF0;
}

static void
evr_triggerDelay(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    int trig = cmd->code & 0xFF;

    if (trig >= EVR_TRIGGER_COUNT) return;
    if (cmd->code & BPM_PROTOCOL_WRITE_MASK)
        evrSetTriggerDelay(trig, cmd->value);
    reply->u.value = evrGetTriggerDelay(trig);
}

void
processCommand(const struct bpmCommand *cmd, struct bpmReply *reply)
{
    switch (cmd->code & BPM_PROTOCOL_GROUP_MASK) {
    case BPM_PROTOCOL_GROUP_IOPOINT:
        switch (cmd->code & ~(BPM_PROTOCOL_WRITE_MASK|BPM_PROTOCOL_GROUP_MASK)) {
        case BPM_PROTOCOL_COMMAND_IO_DEBUG:     io_debug(cmd, reply);    break;
        case BPM_PROTOCOL_COMMAND_IO_ID:        io_IDstring(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_ATTEN:     io_atten(cmd, reply);    break;
        case BPM_PROTOCOL_COMMAND_IO_ADC_GAIN:  io_adcGain(cmd, reply);  break;
        case BPM_PROTOCOL_COMMAND_IO_LOB_LIMIT: io_lobLimit(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_AT_ENABLE: io_atEnable(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_AT_THRESH: io_atThresh(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_AT_FILTER: io_atFilter(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_SELFTRIG_LEV:
                                                io_selfTrigLevel(cmd, reply);
                                                break;
        case BPM_PROTOCOL_COMMAND_IO_BTN_DSP_ALG:io_dspType(cmd, reply); break;
        case BPM_PROTOCOL_COMMAND_IO_FPGA_RESET:io_fpgaReset(cmd, reply);break;
        case BPM_PROTOCOL_COMMAND_IO_LATCH_CLEAR:io_latchClear(cmd, reply);break;
        case BPM_PROTOCOL_COMMAND_IO_TBT_SUM_SHIFT:io_tbtSumShift(cmd, reply);break;
        case BPM_PROTOCOL_COMMAND_IO_MT_SUM_SHIFT:io_mtSumShift(cmd, reply);break;
        }
        break;

    case BPM_PROTOCOL_GROUP_PER_CHANNEL_VALUE:
        cv_command(cmd, reply);
        break;

    case BPM_PROTOCOL_GROUP_RECORDER:
        waveformRecorderCommand(cmd, reply);
        break;

    case BPM_PROTOCOL_GROUP_EVENT_TRIGGERS:
        evr_eventTriggers(cmd, reply);
        break;

    case BPM_PROTOCOL_GROUP_TRIGGER_DELAY:
        evr_triggerDelay(cmd, reply);
        break;

    default: break;
    }
}

/*
 * Send reply to client
 */
static void
sendReply(const void *buf, int n, struct ip_addr *addr, u16_t port)
{
    struct pbuf *p;

    p = pbuf_alloc(PBUF_TRANSPORT, n, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocate pbuf for reply\n");
        return;
    }
    memcpy(p->payload, buf, n);
    udp_sendto(pcb, p, addr, port);
    pbuf_free(p);
}

/*
 * Handle commands from clients
 */
void
server_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                   struct ip_addr *fromAddr, u16_t fromPort)
{
    long addr = ntohl(fromAddr->addr);
    struct bpmCommand command;
    static struct bpmCommand lastCommand;
    static struct bpmReply reply;

    if (debugFlags & DEBUGFLAG_SERVER) {
        printf("server_callback: %d from %d.%d.%d.%d:%d\n",
                                                p->len,
                                                (int)((addr >> 24) & 0xFF),
                                                (int)((addr >> 16) & 0xFF),
                                                (int)((addr >>  8) & 0xFF),
                                                (int)((addr      ) & 0xFF),
                                                fromPort);
    }
    duplicateIOCcheck(addr, fromPort);
    if (p->len >= sizeof command) {
        /*
         * Must make copy rather than just using payload area
         * since the latter is not aligned on a 32-bit boundary
         * which results in (silently-mangled) misaligned accesses.
         */
        memcpy(&command, p->payload, sizeof command);
        if (((command.magic == BPM_PROTOCOL_MAGIC_COMMAND)
          && (p->len == sizeof command))
         || ((command.magic == BPM_PROTOCOL_MAGIC_FILTER_UPDATE)
          && (p->len == sizeof(struct bpmFilterCoefficients)))) {
            if (debugFlags & DEBUGFLAG_SERVER) {
                printf("Command number %-6d code:0x%x value:%d\n",
                                            (unsigned int)command.commandNumber,
                                            (int)command.code,
                                            (int)command.value);
            }
            if ((command.commandNumber == lastCommand.commandNumber)
             && (command.code == lastCommand.code)) {
                sendReply(&reply, sizeof reply, fromAddr, fromPort);
            }
            else {
                lastCommand = command;
                reply.magic = BPM_PROTOCOL_MAGIC_REPLY;
                reply.commandNumber = command.commandNumber;
                if (command.magic == BPM_PROTOCOL_MAGIC_COMMAND) {
                    processCommand(&command, &reply);
                }
                else {
                    static struct bpmFilterCoefficients coef;
                    memcpy(&coef, p->payload, sizeof coef);
                    cellStreamFilterUpdateCoefficients(&coef);
                }
                sendReply(&reply, sizeof reply, fromAddr, fromPort);
            }
        }
    }
    pbuf_free(p);
}

void serverInit(void)
{
    int err;

    pcb = udp_new();
    if (pcb == NULL) {
        fatal("Can't create server PCB");
        return;
    }
    err = udp_bind(pcb, IP_ADDR_ANY, BPM_PROTOCOL_COMMAND_UDP_PORT);
    if (err != ERR_OK) {
        fatal1("Can't bind to publisher port, error:%d", err);
        return;
    }
    udp_recv(pcb, server_callback, NULL);
}
