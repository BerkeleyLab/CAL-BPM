/*
 * Auto-trim support
 */

#include <stdio.h>
#include "autotrim.h"
#include "bpmProtocol.h"
#include "gpio.h"
#include "util.h"

#define AUTOTRIM_CSR_MODE_MASK              0x7
#define AUTOTRIM_CSR_TIME_MUX_PILOT_PULSES  0x8
#define AUTOTRIM_CSR_STATUS_MASK            0x70
#define AUTOTRIM_CSR_STATUS_SHIFT           4
#define AUTOTRIM_CSR_FILTER_SHIFT_MASK      0x700
#define AUTOTRIM_CSR_FILTER_SHIFT_SHIFT     8
#define AUTOTRIM_CSR_TIME_MUX_SIMULATE_BEAM 0x80000000

#define AUTOTRIM_CSR_MODE_OFF               0x0
#define AUTOTRIM_CSR_MODE_LOW               0x1
#define AUTOTRIM_CSR_MODE_HIGH              0x2
#define AUTOTRIM_CSR_MODE_DUAL              0x3
#define AUTOTRIM_MODE_INBAND                0x4

#define AUTOTRIM_CSR_STATUS_OFF             0x0
#define AUTOTRIM_CSR_STATUS_NO_TONE         0x1
#define AUTOTRIM_CSR_STATUS_EXCESS_DIFF     0x2
#define AUTOTRIM_CSR_STATUS_ACTIVE          0x3

#define AUTOTRIM_CSR_FILTER_SHIFT_MAX       7

void
autotrimUsePulsePilot(int flag)
{
    uint32_t csr = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);

    if (flag)
        csr |=  AUTOTRIM_CSR_TIME_MUX_PILOT_PULSES;
    else
        csr &= ~AUTOTRIM_CSR_TIME_MUX_PILOT_PULSES;
    GPIO_WRITE(GPIO_IDX_AUTOTRIM_CSR, csr);
}

static void
setMode(int mode)
{
    uint32_t csr = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);

    csr &= ~AUTOTRIM_CSR_MODE_MASK;
    csr |= (mode & AUTOTRIM_CSR_MODE_MASK);
    GPIO_WRITE(GPIO_IDX_AUTOTRIM_CSR, csr);
}

void
autotrimEnable(int mode)
{
    switch (mode) {
    case AUTOTRIM_CSR_MODE_OFF:
    case AUTOTRIM_CSR_MODE_LOW:
    case AUTOTRIM_CSR_MODE_HIGH:
    case AUTOTRIM_CSR_MODE_DUAL:
    case AUTOTRIM_MODE_INBAND:
        setMode(mode);
        break;
    }
}

int
autotrimStatus(void)
{
    uint32_t status = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);
    return (status & AUTOTRIM_CSR_STATUS_MASK) >> AUTOTRIM_CSR_STATUS_SHIFT;
}

void
autotrimSetThreshold(unsigned int threshold)
{
    GPIO_WRITE(GPIO_IDX_AUTOTRIM_THRESHOLD, threshold);
}

unsigned int
autotrimGetThreshold(void)
{
    return GPIO_READ(GPIO_IDX_AUTOTRIM_THRESHOLD);
}

void
autotrimSetFilterShift(unsigned int filterShift)
{
    uint32_t csr = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);

    csr &= ~AUTOTRIM_CSR_FILTER_SHIFT_MASK;
    csr |= (filterShift << AUTOTRIM_CSR_FILTER_SHIFT_SHIFT) &
                                                 AUTOTRIM_CSR_FILTER_SHIFT_MASK;
    GPIO_WRITE(GPIO_IDX_AUTOTRIM_CSR, csr);
}

unsigned int
autotrimGetFilterShift(void)
{
    uint32_t csr = GPIO_READ(GPIO_IDX_AUTOTRIM_CSR);
    return (csr & AUTOTRIM_CSR_FILTER_SHIFT_MASK) >>
                                                AUTOTRIM_CSR_FILTER_SHIFT_SHIFT;
}
