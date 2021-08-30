#include <stdio.h>
#include "adcTransmit.h"
#include "gpio.h"
#include "util.h"

/*
 * CSR R/W bits
 */
#define ADC_TRANSMIT_CSR_PMA_INIT           0x1
#define ADC_TRANSMIT_CSR_AURORA_RESET       0x2

/*
 * CSR read-only bits
 */
#define ADC_TRANSMIT_CSR_LANE_1_UP          0x100
#define ADC_TRANSMIT_CSR_LANE_2_UP          0x200
#define ADC_TRANSMIT_CSR_CHANNEL_UP         0x400
#define ADC_TRANSMIT_CSR_TX_SOFT_ERROR      0x1000
#define ADC_TRANSMIT_CSR_TX_HARD_ERROR      0x2000
#define ADC_TRANSMIT_CSR_MMCM_UNLOCKED      0x4000

void
adcTransmitInit(void)
{
    unsigned int then;
    unsigned int r;

    GPIO_WRITE(GPIO_IDX_ADC_TRANSMIT_CSR, ADC_TRANSMIT_CSR_PMA_INIT |
                                          ADC_TRANSMIT_CSR_AURORA_RESET);
    nanosecondSpin(100000000);
    GPIO_WRITE(GPIO_IDX_ADC_TRANSMIT_CSR, 0);
    then = secondsSinceBoot();
    for (;;) {
        r = GPIO_READ(GPIO_IDX_ADC_TRANSMIT_CSR);
        if (r & ADC_TRANSMIT_CSR_CHANNEL_UP) {
            printf("Raw ADC data transmission active.\n");
            break;
        }
        if ((secondsSinceBoot() - then) > 5) {
            printf("\nADC transmit CSR ");
            showReg(GPIO_IDX_ADC_TRANSMIT_CSR);
            printf("Note -- No transmission of raw ADC data\n");
            break;
        }
    }
}
