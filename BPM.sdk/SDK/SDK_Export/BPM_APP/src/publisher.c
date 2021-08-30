/*
 * Publish monitor values
 */
#include <stdio.h>
#include <string.h>
#include <lwip/udp.h>
#include <xparameters.h>
#include "autotrim.h"
#include "bpmProtocol.h"
#include "cellComm.h"
#include "publisher.h"
#include "afePLL.h"
#include "axiSysmon.h"
#include "cellComm.h"
#include "evr.h"
#include "gpio.h"
#include "localOscillator.h"
#include "server.h"
#include "sfp.h"
#include "systemParameters.h"
#include "util.h"
#include "waveformRecorder.h"

static struct udp_pcb *pcb;
static struct ip_addr  subscriberAddr;
static int             subscriberPort;

/*
 * Send values to subscriber
 */
static void
publishSlowAcquisition(unsigned int saSeconds, unsigned int saTicks)
{
    int i;
    struct pbuf *p;
    struct bpmSlowAcquisition *pk;
    static epicsUInt32 packetNumber = 1;
    uint32_t r;
    p = pbuf_alloc(PBUF_TRANSPORT, sizeof *pk, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocate pbuf for fast data\n");
        return;
    }
    pk = (struct bpmSlowAcquisition *)p->payload;
    pk->packetNumber = packetNumber++;
    pk->seconds = saSeconds;
    pk->ticks = saTicks;
    pk->magic = BPM_PROTOCOL_MAGIC_SLOW_ACQUISITION;
    pk->xPos = GPIO_READ(GPIO_IDX_POSITION_CALC_SA_X);
    pk->yPos = GPIO_READ(GPIO_IDX_POSITION_CALC_SA_Y);
    pk->skew = GPIO_READ(GPIO_IDX_POSITION_CALC_SA_Q);
    pk->buttonSum = GPIO_READ(GPIO_IDX_POSITION_CALC_SA_S);
    pk->xRMSwide =  GPIO_READ(GPIO_IDX_RMS_X_WIDE);
    pk->yRMSwide =  GPIO_READ(GPIO_IDX_RMS_Y_WIDE);
    pk->xRMSnarrow =  GPIO_READ(GPIO_IDX_RMS_X_NARROW);
    pk->yRMSnarrow =  GPIO_READ(GPIO_IDX_RMS_Y_NARROW);
    pk->recorderStatus = wfrStatus();
    pk->syncStatus = GPIO_READ(GPIO_IDX_CLOCK_STATUS);
    pk->clipStatus = GPIO_READ(GPIO_IDX_SELFTRIGGER_CSR) >> 24;
    pk->sdSyncStatus = localOscGetSdSyncStatus();
    pk->cellCommStatus = cellCommStatus();
    pk->autotrimStatus = autotrimStatus();
    for (i = 0 ; i < BPM_PROTOCOL_ADC_COUNT ; i++) {
        pk->rfMag[i] = GPIO_READ(GPIO_IDX_PRELIM_RF_MAG_0+i);
        pk->ptLoMag[i] = GPIO_READ(GPIO_IDX_PRELIM_PT_LO_MAG_0+i);
        pk->ptHiMag[i] = GPIO_READ(GPIO_IDX_PRELIM_PT_HI_MAG_0+i);
        pk->gainFactor[i] = GPIO_READ(GPIO_IDX_ADC_GAIN_FACTOR_0+i);
    }
    r = GPIO_READ(GPIO_IDX_ADC_10_PEAK);
    pk->adcPeak[0] = r;
    pk->adcPeak[1] = r >> 16;
    r = GPIO_READ(GPIO_IDX_ADC_32_PEAK);
    pk->adcPeak[2] = r;
    pk->adcPeak[3] = r >> 16;
    udp_sendto(pcb, p, &subscriberAddr, subscriberPort);
    pbuf_free(p);
}

static void
publishSystemMonitor(void)
{
    struct pbuf *p;
    struct bpmSystemMonitor *pk;
    int i;
    uint32_t v;
    struct evrTimestamp now;
    static epicsUInt32 packetNumber = 1;

    p = pbuf_alloc(PBUF_TRANSPORT, sizeof *pk, PBUF_RAM);
    if (p == NULL) {
        printf("Can't allocate pbuf for slow data\n");
        return;
    }
    pk = (struct bpmSystemMonitor *)p->payload;
    evrCurrentTime(&now);
    pk->magic = BPM_PROTOCOL_MAGIC_SYSTEM_MONITOR;
    pk->packetNumber = packetNumber++;
    pk->seconds = now.secPastEpoch;
    pk->ticks = now.ticks;
    for (i = 0 ; i < BPM_PROTOCOL_SFP_COUNT ; i++) {
        pk->sfpTemperature[i] = getSFPtemperature(i);
        pk->sfpRxPower[i] = getSFPrxPower(i);
    }
    pk->fanRPM = GPIO_READ(GPIO_IDX_DFE_FAN_RPM);
    pk->adcClkDelay = adcClkDelay();
    pk->duplicateIOC = duplicateIOCcheck(0, 0);
    pk->adcClkRate = GPIO_READ(GPIO_IDX_AFE_CLOCK_RATE);
    pk->fofbIndex = cellCommGetFOFB();
    pk->evrTooFew = evrNtooFewSecondEvents();
    pk->evrTooMany = evrNtooManySecondEvents();
    pk->evrOutOfSeq = evrNoutOfSequenceSeconds();
    axiSysmonReadADC(pk->fpgaMonitor);
    for (i = 0 ; i < (BPM_PROTOCOL_DFE_TEMPERATURE_COUNT/2) ; i++) {
        v = GPIO_READ(GPIO_IDX_DFE_TEMP_1_0 + i);
        pk->dfeTemperature[2*i+0] = v;
        pk->dfeTemperature[2*i+1] = v >> 16;
    }
    for (i = 0 ; i < (BPM_PROTOCOL_AFE_TEMPERATURE_COUNT/2) ; i++) {
        v = GPIO_READ(GPIO_IDX_AFE_TEMP_1_0 + i);
        pk->afeTemperature[2*i+0] = v;
        pk->afeTemperature[2*i+1] = v >> 16;
    }
    for (i = 0 ; i < BPM_PROTOCOL_AFE_POWER_COUNT ; i++) {
        v = GPIO_READ(GPIO_IDX_AFE_POWER_IV0 + i);
        pk->afeVoltage[i] = v;
        pk->afeCurrent[i] = v >> 16;
    }
    pk->crcFaultsCCW = cellCommCRCfaultsCCW();
    pk->crcFaultsCW = cellCommCRCfaultsCW();
    udp_sendto(pcb, p, &subscriberAddr, subscriberPort);
    pbuf_free(p);
}

/*
 * Publish when appropriate
 */
void
publisherCheck(void)
{
    struct pbuf *p;
    uint32_t now = sysTicksSinceBoot();
    unsigned int saSeconds;
    unsigned int saTicks;
    static unsigned int previousSaSeconds, previousSaTicks, previousMonSysTicks;
    
    /*
     * Wait for SA time stamp to stabilize
     */
    saTicks = GPIO_READ(GPIO_IDX_SA_TIMESTAMP_TICKS);
    for (;;) {
        unsigned int checkTicks;
        saSeconds = GPIO_READ(GPIO_IDX_SA_TIMESTAMP_SEC);
        checkTicks = GPIO_READ(GPIO_IDX_SA_TIMESTAMP_TICKS);
        if (checkTicks == saTicks) break;
        saTicks = checkTicks;
    }
    if (subscriberPort == 0) {
        previousSaSeconds = saSeconds;
        previousSaTicks = saTicks;
        previousMonSysTicks = now;
        cellCommStatus();
    }
    else {
        if ((saTicks != previousSaTicks) || (saSeconds != previousSaSeconds)) {
            int evrTickDiff = (saTicks - previousSaTicks) +
                                ((saSeconds-previousSaSeconds) * 124910000);
            unsigned int sysTicks = sysTicksSinceBoot();
            static int sysTicksOld, evrTickDiffOld, sysTickDiffOld;
            int sysTickDiff = sysTicks - sysTicksOld;
            if ((debugFlags & DEBUGFLAG_SA_TIMING_CHECK)
             && ((evrTickDiff < 11241900) || (evrTickDiff > 13740100)
              || (sysTickDiff < 9700000) || (sysTickDiff > 10200000))) {
                printf("old:%d:%09d  new:%d:%09d "
                       "evrTickDiff:%d sysTickDiff:%d "
                       "evrTickDiffOld:%d sysTickDiffOld:%d\n",
                                             previousSaSeconds, previousSaTicks,
                                             saSeconds, saTicks,
                                             evrTickDiff, sysTickDiff,
                                             evrTickDiffOld, sysTickDiffOld);
            }
            sysTicksOld = sysTicks;
            evrTickDiffOld = evrTickDiff;
            sysTickDiffOld = sysTickDiff;
            previousSaSeconds = saSeconds;
            previousSaTicks = saTicks;
            publishSlowAcquisition(saSeconds, saTicks);
        }
        if ((now - previousMonSysTicks) >
             (BPM_PROTOCOL_SECONDS_PER_MONITOR_UPDATE * XPAR_MICROBLAZE_FREQ)) {
            previousMonSysTicks = now;
            publishSystemMonitor();
        }
        if ((p = wfrCheckForWork()) != NULL) {
            udp_sendto(pcb, p, &subscriberAddr, subscriberPort);
            pbuf_free(p);
        }
    }
}

/*
 * Handle a subscription request or a waveform recorder ACK
 */
static void
publisher_callback(void *arg, struct udp_pcb *pcb, struct pbuf *p,
                   struct ip_addr *fromAddr, u16_t fromPort)
{
    const char *cp = p->payload;
    static epicsInt16 fofbIndex = -1000;

    /*
     * Must copy paylaod rather than just using payload area
     * since the latter is not aligned on a 32-bit boundary
     * which results in (silently mangled) misaligned accesses.
     */
    if (debugFlags & DEBUGFLAG_PUBLISHER) {
        long addr = ntohl(fromAddr->addr);
        printf("publisher_callback: %d (%x) from %d.%d.%d.%d:%d\n",
                                                p->len,
                                                p->len >= 1 ? (*cp & 0xFF) : 0,
                                                (int)((addr >> 24) & 0xFF),
                                                (int)((addr >> 16) & 0xFF),
                                                (int)((addr >>  8) & 0xFF),
                                                (int)((addr      ) & 0xFF),
                                                fromPort);
    }
    if (p->len == sizeof fofbIndex) {
        epicsInt16 newIndex;
        memcpy(&newIndex, p->payload, sizeof newIndex);
        if (newIndex != fofbIndex) {
            fofbIndex = newIndex;
            cellCommSetFOFB(fofbIndex);
        }
        subscriberAddr = *fromAddr;
        subscriberPort = fromPort;
    }
    else if (subscriberPort && (p->len == sizeof(struct bpmWaveformAck))) {
        struct bpmWaveformAck bpmAck;
        struct pbuf *txPacket;
        memcpy(&bpmAck, p->payload, sizeof bpmAck);
        txPacket = wfrAckPacket(&bpmAck);
        if (txPacket) {
            udp_sendto(pcb, txPacket, &subscriberAddr, subscriberPort);
            pbuf_free(txPacket);
        }
    }
    pbuf_free(p);
}

/*
 * Set up publisher UDP port
 */
void
publisherInit(void)
{
    int err;

    pcb = udp_new();
    if (pcb == NULL) {
        fatal("Can't create publisher PCB");
        return;
    }
    err = udp_bind(pcb, IP_ADDR_ANY, BPM_PROTOCOL_PUBLISHER_UDP_PORT);
    if (err != ERR_OK) {
        fatal1("Can't bind to publisher port, error:%d", err);
        return;
    }
    udp_recv(pcb, publisher_callback, NULL);
}
