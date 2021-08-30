/*
 * BPM/cell controller communication
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "bpmProtocol.h"
#include "cellComm.h"
#include "gpio.h"
#include "util.h"

/*
 * CSR R/W bits
 */
#define CELLCOMM_CSR_CCW_GT_RESET       0x1
#define CELLCOMM_CSR_CCW_AURORA_RESET   0x2
#define CELLCOMM_CSR_CW_GT_RESET        0x4
#define CELLCOMM_CSR_CW_AURORA_RESET    0x8
#define CELLCOMM_CSR_RESETS_MASK        0xF
#define CELLCOMM_CSR_FOFB_INDEX_MASK    0x1FF0000
#define CELLCOMM_CSR_FOFB_INDEX_SHIFT   16
#define CELLCOMM_CSR_FOFB_INDEX_VALID   0x2000000
#define CELLCOMM_CSR_FOFB_INDEX_ENABLE  0x4000000

/*
 * CSR read-only bits
 */
#define CELLCOMM_CSR_CCW_CHANNEL_UP     0x10
#define CELLCOMM_CSR_CCW_RX_DATA_GOOD   0x20
#define CELLCOMM_CSR_CW_CHANNEL_UP      0x40
#define CELLCOMM_CSR_CW_RX_DATA_GOOD    0x80
#define CELLCOMM_CSR_CCW_FRAME_ERROR    0x100
#define CELLCOMM_CSR_CCW_SOFT_ERROR     0x200
#define CELLCOMM_CSR_CCW_HARD_ERROR     0x400
#define CELLCOMM_CSR_CW_FRAME_ERROR     0x1000
#define CELLCOMM_CSR_CW_SOFT_ERROR      0x2000
#define CELLCOMM_CSR_CW_HARD_ERROR      0x4000

#define CELLCOMM_CSR_CHANNELS_UP (CELLCOMM_CSR_CCW_CHANNEL_UP | \
                                  CELLCOMM_CSR_CW_CHANNEL_UP)
#define CELLCOMM_CSR_CW_ERRORS  (CELLCOMM_CSR_CW_HARD_ERROR | \
                                 CELLCOMM_CSR_CW_SOFT_ERROR | \
                                 CELLCOMM_CSR_CW_FRAME_ERROR)
#define CELLCOMM_CSR_CCW_ERRORS (CELLCOMM_CSR_CCW_HARD_ERROR | \
                                 CELLCOMM_CSR_CCW_SOFT_ERROR | \
                                 CELLCOMM_CSR_CCW_FRAME_ERROR)

struct auroraStateMachine {
    const char *name;
    enum auState
        {S_UP, S_DOWN1, S_AURORA_RESET1, S_DOWN2, S_BOTH_RESET, S_AURORA_RESET2}
                state;
    uint32_t    gtReset;
    uint32_t    auroraReset;
    uint32_t    channelUp;
    uint32_t    base;
    uint32_t    limit;
};
static struct auroraStateMachine cw = {
    .name        = "CW",
    .state       = S_UP,
    .gtReset     = CELLCOMM_CSR_CW_AURORA_RESET,
    .auroraReset = CELLCOMM_CSR_CW_GT_RESET,
    .channelUp   = CELLCOMM_CSR_CW_CHANNEL_UP
};
static struct auroraStateMachine ccw = {
    .name        = "CCW",
    .state       = S_UP,
    .gtReset     = CELLCOMM_CSR_CCW_AURORA_RESET,
    .auroraReset = CELLCOMM_CSR_CCW_GT_RESET,
    .channelUp   = CELLCOMM_CSR_CCW_CHANNEL_UP
};

static const char *
stateName(enum auState state)
{
    switch (state) {
    case S_UP:            return "S_UP";
    case S_DOWN1:         return "S_DOWN1";
    case S_AURORA_RESET1: return "S_AURORA_RESET1";
    case S_DOWN2:         return "S_DOWN2";
    case S_BOTH_RESET:    return "S_BOTH_RESET";
    case S_AURORA_RESET2: return "S_AURORA_RESET2";
    default:              return "S_?";
    }
}

static uint32_t control;
static void
crank(struct auroraStateMachine *p)
{
    uint32_t usec = sysTicksSinceBoot() / (XPAR_MICROBLAZE_FREQ / 1000000);
    uint32_t status = GPIO_READ(GPIO_IDX_CELL_COMM_CSR);
    int timeout = ((usec - p->base) > p->limit);
    enum auState oldState = p->state;

    switch (p->state) {
    case S_UP:
        if ((status & p->channelUp) == 0) {
            p->base = usec;
            p->limit = 30000000;
            p->state = S_DOWN1;
        }
        break;

    case S_DOWN1:
        if (status & p->channelUp) {
            p->state = S_UP;
        }
        else if (timeout) {
            control |= p->auroraReset;
            GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, control);
            p->base = usec;
            p->limit = 100000;
            p->state = S_AURORA_RESET1;
        }
        break;

    case S_AURORA_RESET1:
        if (timeout) {
            control &= ~p->auroraReset;
            GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, control);
            p->base = usec;
            p->limit = 1000000;
            p->state = S_DOWN2;
        }
        break;

    case S_DOWN2:
        if (status & p->channelUp) {
            p->state = S_UP;
        }
        else if (timeout) {
            control |= p->auroraReset | p->gtReset;
            GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, control);
            p->base = usec;
            p->limit = 100000;
            p->state = S_BOTH_RESET;
        }
        break;

    case S_BOTH_RESET:
        if (timeout) {
            control &= ~p->gtReset;
            GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, control);
            p->base = usec;
            p->limit = 1000000;
            p->state = S_AURORA_RESET2;
        }
        break;

    case S_AURORA_RESET2:
        if (timeout) {
            control &= ~p->auroraReset;
            GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, control);
            p->base = usec;
            p->limit = 30000000;
            p->state = S_DOWN1;
        }
        break;
    }
    if ((debugFlags & DEBUGFLAG_CELL_COMM) && (p->state != oldState))
        printf("%3s control 0x%02x, status 0x%02x, state %s\n", p->name,
            (unsigned int)control, (unsigned int)status, stateName(p->state));
}

void
cellCommInit(void)
{
    unsigned int then;
    unsigned int r;

    GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, CELLCOMM_CSR_CW_AURORA_RESET  |
                                       CELLCOMM_CSR_CW_GT_RESET      |
                                       CELLCOMM_CSR_CCW_AURORA_RESET |
                                       CELLCOMM_CSR_CCW_GT_RESET);
    nanosecondSpin(100000000);
    GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, CELLCOMM_CSR_CW_AURORA_RESET | 
                                       CELLCOMM_CSR_CCW_AURORA_RESET);
    nanosecondSpin(1000000000);
    GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, 0);
    then = secondsSinceBoot();
    for (;;) {
        r = GPIO_READ(GPIO_IDX_CELL_COMM_CSR) & CELLCOMM_CSR_CHANNELS_UP;
        if (r == CELLCOMM_CSR_CHANNELS_UP) {
            printf("Aurora communication active.\n");
            break;
        }
        if ((secondsSinceBoot() - then) > 5) {
            printf("\nCell communication CSR ");
            showReg(GPIO_IDX_CELL_COMM_CSR);
            printf("Warning -- %s.\n", r==0 ? "NO CELL COMMUNICATION" :
                                       (r&CELLCOMM_CSR_CCW_CHANNEL_UP)==0 ?
                                                  "NO CCW CELL COMMUNICATION" :
                                                  "NO CW CELL COMMUNICATION");
            printf("Will continue attempting to connect after boot "
                    "sequence completes.\n");
            break;
        }
    }
}

int
cellCommStatus(void)
{
    unsigned int now;
    unsigned int r;
    static unsigned int secondsAtLastReport;

    crank(&cw);
    crank(&ccw);
    r = GPIO_READ(GPIO_IDX_CELL_COMM_CSR);
    if ((r & CELLCOMM_CSR_CHANNELS_UP) != CELLCOMM_CSR_CHANNELS_UP) {
        now = secondsSinceBoot();       
        if ((now - secondsAtLastReport) > 5) {
            if (r & (CELLCOMM_CSR_CW_ERRORS | CELLCOMM_CSR_CCW_ERRORS)) {
                printf("Aurora Fault:");
                if (r&CELLCOMM_CSR_CW_HARD_ERROR)   printf("  CW hard error");
                if (r&CELLCOMM_CSR_CW_SOFT_ERROR)   printf("  CW soft error");
                if (r&CELLCOMM_CSR_CW_FRAME_ERROR)  printf("  CW frame error");
                if (r&CELLCOMM_CSR_CCW_HARD_ERROR)  printf("  CCW hard error");
                if (r&CELLCOMM_CSR_CCW_SOFT_ERROR)  printf("  CCW soft error");
                if (r&CELLCOMM_CSR_CCW_FRAME_ERROR) printf("  CCW frame error");
                printf("\n");
            }
            secondsAtLastReport = now;
        }
    }
    return (r >> 4) & 0xF;
}

void
cellCommSetFOFB(int fofbIndex)
{
    uint32_t r = GPIO_READ(GPIO_IDX_CELL_COMM_CSR) & CELLCOMM_CSR_RESETS_MASK;
    
    r |= CELLCOMM_CSR_FOFB_INDEX_ENABLE;
    if ((fofbIndex >= 0) && (fofbIndex < BPM_PROTOCOL_FOFB_CAPACITY))  {
        r |= CELLCOMM_CSR_FOFB_INDEX_VALID |
                                 ((fofbIndex << CELLCOMM_CSR_FOFB_INDEX_SHIFT) &
                              
                                                CELLCOMM_CSR_FOFB_INDEX_MASK);
    }
    GPIO_WRITE(GPIO_IDX_CELL_COMM_CSR, r);
}

int
cellCommGetFOFB(void)
{
    return (GPIO_READ(GPIO_IDX_CELL_COMM_CSR) & CELLCOMM_CSR_FOFB_INDEX_MASK)
                                             >> CELLCOMM_CSR_FOFB_INDEX_SHIFT;
}

/*
 * Read receiver CRC error count
 * Counts are maintained in different clock domain so require consitency checks.
 */
unsigned int
cellCommCRCfaultsCCW(void)
{
    uint32_t c0 = GPIO_READ(GPIO_IDX_BPM_CCW_CRC_FAULTS);
    for (;;) {
        uint32_t c1 = GPIO_READ(GPIO_IDX_BPM_CCW_CRC_FAULTS);
        if (c1 == c0) return c0;
        c0 = c1;
    }
}
unsigned int
cellCommCRCfaultsCW(void)
{
    uint32_t c0 = GPIO_READ(GPIO_IDX_BPM_CW_CRC_FAULTS);
    for (;;) {
        uint32_t c1 = GPIO_READ(GPIO_IDX_BPM_CW_CRC_FAULTS);
        if (c1 == c0) return c0;
        c0 = c1;
    }
}
