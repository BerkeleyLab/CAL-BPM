/*
 * Cell data stream filter support
 */
#include <stdio.h>
#include "cellStreamFilter.h"
#include "gpio.h"
#include "util.h"

#define FILTER_CSR_ENABLE_FA_CHANNEL_SELECTION      0x80000000
#define FILTER_CSR_FA_CHANNEL_SELECT_FILTERED       0x40000000
#define FILTER_CSR_ENABLE_FILTER_INPUT_SELECTION    0x20000000
#define FILTER_CSR_FILTER_INPUT_IMPULSE             0x10000000
#define FILTER_CSR_BEGIN_COEFFICIENT_LOAD           0x100
#define FILTER_CSR_LOAD_Y                           0x2
#define FILTER_CSR_LOAD_X                           0x1

void
cellStreamFilterUpdateCoefficients(struct bpmFilterCoefficients *pc)
{
    int i = 0, j = 0, fragmentIndex = 0;

    GPIO_WRITE(GPIO_IDX_CELL_FILTER_CSR, FILTER_CSR_BEGIN_COEFFICIENT_LOAD |
                         ((pc->header.code == 0) ? FILTER_CSR_LOAD_X
                                                        : FILTER_CSR_LOAD_Y));
    while (j < BPM_PROTOCOL_COEFFICIENT_COUNT) {
        GPIO_WRITE(GPIO_IDX_CELL_FILTER_DATA, pc->coefficients[i++]);
        if (fragmentIndex != 0) j++;
        fragmentIndex = (fragmentIndex == 8) ? 0 : fragmentIndex + 1;
    }
}

void
cellStreamFilterApplyDebugFlags(void)
{
    uint32_t d = FILTER_CSR_ENABLE_FA_CHANNEL_SELECTION |
                 FILTER_CSR_ENABLE_FILTER_INPUT_SELECTION;

    if (debugFlags & DEBUGFLAG_ALTERNATE_FA_CHANNELS)
        d |= FILTER_CSR_FA_CHANNEL_SELECT_FILTERED;
    if (debugFlags & DEBUGFLAG_FILTER_IMPULSE_RESPONSE)
        d |= FILTER_CSR_FILTER_INPUT_IMPULSE;
    GPIO_WRITE(GPIO_IDX_CELL_FILTER_CSR, d);
}
