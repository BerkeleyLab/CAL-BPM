#include <stdio.h>
#include <stdint.h>
#include <xil_io.h>
#include <xparameters.h>
#include "gpio.h"
#include "evr.h"
#include "systemParameters.h"
#include "util.h"

#define EVENT_HEARTBEAT         122
#define EVENT_PPS               125

#define EVR_REG17_BANK_B        0x1
#define EVR_REG17_DB_DISABLE    0x4

#define EVR_REG28_FIFO_EMPTY    0x1
#define EVR_REG28_FIFO_FULL     0x2

#define EVR_REG(r)   (XPAR_EVR_0_S_AXI_MEM0_BASEADDR+((r)*sizeof(uint32_t)))
#define EVR_DELAY(t)  EVR_REG((t)*2)
#define EVR_WIDTH(t)  EVR_REG((t)*2+1)

#define EVR_RAM_A(e) (XPAR_EVR_0_S_AXI_MEM0_BASEADDR+0x2000+((e)*sizeof(uint32_t)))
#define EVR_RAM_B(e) (XPAR_EVR_0_S_AXI_MEM0_BASEADDR+0x4000+((e)*sizeof(uint32_t)))

struct eventCheck {
    int      count;
    uint32_t ticks[2];
};

static void
evChk(const char *name, struct eventCheck *ep)
{
    unsigned int diff;

    switch (ep->count) {
    case 0: printf("No %s events!\n", name);        break;
    case 1: printf("Only one %s event!\n", name);  break;
    default:
        diff = (ep->ticks[1] - ep->ticks[0]) / (XPAR_MICROBLAZE_FREQ / 1000000);
        if ((diff <= 900000) || (diff >= 1100000)) {
            printf("Warning -- %s events arriving %u microseconds apart).\n",
                                                                    name, diff);
        }
        break;
    }
}

static void
evGot(struct eventCheck *ep)
{
    if (ep->count < 2) ep->ticks[ep->count] = sysTicksSinceBoot();
    ep->count++;
}

void
evrInit(void)
{
    int i;
    unsigned int then;
    struct eventCheck heartbeat, pps;

    /*
     * Generate and remove reset
     */
    Xil_Out32(EVR_REG(20), 1);
    Xil_Out32(EVR_REG(20), 0);

    /*
     * Disable distributed data buffer
     */
    Xil_Out32(EVR_REG(17), EVR_REG17_DB_DISABLE);

    /*
     * Use trigger 0 as the heartbeat event '1 second' marker used
     * to synchronize all acquisition and processing.
     * Make the output nice and wide so we can also use it as a
     * visual 'event receiver active' front panel indicator.
     */
    evrSetTriggerDelay(0, 1);
    evrSetTriggerWidth(0, 12500000);

    /*
     * Confirm that heartbeat and PPS markers are present
     */
    heartbeat.count = 0;
    pps.count = 0;
    evrSetEventAction(EVENT_HEARTBEAT, EVR_RAM_WRITE_FIFO|EVR_RAM_TRIGGER_0);
    evrSetEventAction(EVENT_PPS,       EVR_RAM_WRITE_FIFO|EVR_RAM_TRIGGER_3);
    then = sysTicksSinceBoot();
    for (;;) {
        evrTimestamp when;
        int eventCode = evrCheckEventFIFO(&when);
        if (eventCode >= 0) {
            switch(eventCode) {
            case EVENT_HEARTBEAT: evGot(&heartbeat); break;
            case EVENT_PPS:       evGot(&pps);       break;
            default:
                printf("Warning -- Unexpected event %d (seconds/ticks:%d/%d)\n",
                            eventCode, (int)when.secPastEpoch, (int)when.ticks);
                break;
            }
        }
        if ((((sysTicksSinceBoot() - then) / 5) > XPAR_MICROBLAZE_FREQ)
         || ((heartbeat.count >= 2) && (pps.count >= 2))) break;
    }
    evChk("Heartbeat", &heartbeat);
    evChk("PPS", &pps);
    evrSetEventAction(EVENT_HEARTBEAT, EVR_RAM_TRIGGER_0);
    evrSetEventAction(EVENT_PPS, 0);

    /*
     * Trigger 1 is the single-pass trigger.  Delay value will almost
     * certainly be overridden by the IOC.
     * Trigger 2 is triggers the time-multiplexed auto-trim pilot tone.
     * Trigger 3 is used as a 1.0000 Hz marker.
     * Remainder of triggers are available as waveform recorder triggers.
     * In all cases, make the output wide enough to easily cross
     * clock boundaries.
     */
    for (i = 1 ; i < EVR_TRIGGER_COUNT ; i++) {
        evrSetTriggerDelay(i, 1);
        evrSetTriggerWidth(i, 100);
    }
    if ((systemParameters.singlePassEvent > 0) 
     && (systemParameters.singlePassEvent < EVR_EVENT_COUNT)) {
        evrAddEventAction(systemParameters.singlePassEvent, EVR_RAM_TRIGGER_1);
    }
    if ((systemParameters.autoTrimStartEvent > 0) 
     && (systemParameters.autoTrimStartEvent < EVR_EVENT_COUNT)) {
        evrAddEventAction(systemParameters.autoTrimStartEvent, EVR_RAM_TRIGGER_2);
    }
    evrAddEventAction(EVENT_PPS, EVR_RAM_TRIGGER_3);
    evrShow();
}

void
evrShow(void)
{
    int i;
    int activeState = Xil_In32(EVR_REG(16));
    unsigned int csr, action;
    uint16_t actionPresent = 0;

    printf("EVR:\n");
    csr = Xil_In32(EVR_REG(17));
    printf("   Distributed data buffer %sabled.\n",
                                (csr & EVR_REG17_DB_DISABLE) ? "dis" : "en");
    printf("   RAM %s active.\n", (csr & 0x1) ? "B" : "A");
    for (i = 0 ; i < EVR_EVENT_COUNT ; i++) {
        action = evrGetEventAction(i);
        if (action) {
            int b;
            actionPresent |= action;
            printf("   Event %3d: ", i);
            for (b = 15 ; b >= 0 ; b--) {
                int m = 1 << b;
                if (action & m) {
                    switch (b) {
                    case 15:    printf("IRQ");                break;
                    case 14:    printf("LATCH TIME");         break;
                    case 13:    printf("FIFO");               break;
                    default: if (b <= 7) printf("TRG %d", b);
                             else        printf("0x%x", 1<<b);break;
                    }
                    action &= ~m;
                    if (action == 0) {
                        printf("\n");
                        break;
                    }
                    printf(", ");
                }
            }
        }
    }
    for (i = 0 ; i < EVR_TRIGGER_COUNT ; i++) {
        unsigned int delay = Xil_In32(EVR_DELAY(i));
        unsigned int width = Xil_In32(EVR_WIDTH(i));
        if (actionPresent & (1 << i)) {
            printf("   TRG %d: Delay:%-8d Width:%-8d Active %s\n",
                    i, delay, width, (activeState & (1 << i)) ? "Low" : "High");
        }
    }
    if (evrNoutOfSequenceSeconds())
        printf("  Out of sequence seconds: %d\n", evrNoutOfSequenceSeconds());
    if (evrNtooFewSecondEvents())
        printf("    Too few seconds codes: %d\n", evrNtooFewSecondEvents());
    if (evrNtooManySecondEvents())
        printf("   Too many seconds codes: %d\n", evrNtooManySecondEvents());
}

uint32_t
evrStatus(void)
{
    return Xil_In32(EVR_REG(23));
}

void evrCurrentTime(evrTimestamp *ts)
{
    uint32_t s;

    ts->secPastEpoch = Xil_In32(EVR_REG(24));
    for (;;) {
        ts->ticks = Xil_In32(EVR_REG(25));
        s = Xil_In32(EVR_REG(24));
        if (s == ts->secPastEpoch)
            return;
        ts->secPastEpoch = s;
    }
}

void
evrSetTriggerDelay(unsigned int triggerNumber, int ticks)
{
    if (triggerNumber < EVR_TRIGGER_COUNT)
        Xil_Out32(EVR_DELAY(triggerNumber), ticks);
}

int
evrGetTriggerDelay(unsigned int triggerNumber)
{
    if (triggerNumber < EVR_TRIGGER_COUNT)
        return Xil_In32(EVR_DELAY(triggerNumber));
    return 0;
}

void
evrSetTriggerWidth(unsigned int triggerNumber, int ticks)
{
    if (triggerNumber < EVR_TRIGGER_COUNT)
        Xil_Out32(EVR_WIDTH(triggerNumber), ticks);
}

void
evrSetEventAction(unsigned int eventNumber, int action)
{
    uint32_t csr = Xil_In32(EVR_REG(17));
    uint32_t addr;

    if ((eventNumber > 0) && (eventNumber < EVR_EVENT_COUNT)) {
        addr = (csr & EVR_REG17_BANK_B) ? EVR_RAM_B(eventNumber) :
                                          EVR_RAM_A(eventNumber);
        Xil_Out32(addr, (Xil_In32(addr) & ~0xFFFF) | (action & 0xFFFF));
    }
}

void
evrAddEventAction(unsigned int eventNumber, int action)
{
    evrSetEventAction(eventNumber, evrGetEventAction(eventNumber) | action);
}

void
evrRemoveEventAction(unsigned int eventNumber, int action)
{
    evrSetEventAction(eventNumber, evrGetEventAction(eventNumber) & ~action);
}

int
evrGetEventAction(unsigned int eventNumber)
{
    uint32_t csr = Xil_In32(EVR_REG(17));
    uint32_t addr;
    int action = 0;

    if ((eventNumber > 0) && (eventNumber < EVR_EVENT_COUNT)) {
        addr = (csr & EVR_REG17_BANK_B) ? EVR_RAM_B(eventNumber) :
                                          EVR_RAM_A(eventNumber);
        action = Xil_In32(addr);
    }
    return action;
}

int
evrCheckEventFIFO(evrTimestamp *when)
{
    if (Xil_In32(EVR_REG(28)) & EVR_REG28_FIFO_EMPTY) return -1;
    if (when) {
        when->secPastEpoch = Xil_In32(EVR_REG(29));
        when->ticks = Xil_In32(EVR_REG(30));
    }
    return Xil_In32(EVR_REG(31));
}

unsigned int
evrNoutOfSequenceSeconds(void)
{
    return (Xil_In32(EVR_REG(28)) >> 2) & 0x3FF;
}

unsigned int
evrNtooFewSecondEvents(void)
{
    return (Xil_In32(EVR_REG(28)) >> 12) & 0x3FF;
}

unsigned int
evrNtooManySecondEvents(void)
{
    return (Xil_In32(EVR_REG(28)) >> 22) & 0x3FF;
}
