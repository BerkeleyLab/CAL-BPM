/*
 * Manipulate AFE attenuators
 */

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "afeAtten.h"
#include "bpmProtocol.h"
#include "gpio.h"
#include "linearFlash.h"
#include "systemParameters.h"
#include "util.h"

#define AFE_ATTEN_ROWS   32

#define AFE_ATTEN_CSR_BUSY 0x1

// 1 << NumberOfBitsInMagnitude
#define FULL_SCALE  (1<<26)

static float afeAttenTable[AFE_ATTEN_ROWS][BPM_PROTOCOL_ADC_COUNT];
static int attenuationIndex;
static int gainCompensation[BPM_PROTOCOL_ADC_COUNT];

/*
 * Set gain as adjusted by attenuator compensation table
 */
static void
afeWriteGainCompensation(int channel)
{
    uint32_t compensation = (gainCompensation[channel] *
                                afeAttenTable[attenuationIndex][channel]) + 0.5;
    GPIO_WRITE(GPIO_IDX_ADC_GAIN_FACTOR_0 + channel, compensation);
}

/*
 * Set/get gain compensation
 */
void
afeSetGainCompensation(int channel, int gain)
{
    if ((channel < 0) || (channel >= BPM_PROTOCOL_ADC_COUNT))
        return;
    if (gain < 0) gain = 0;
    if (gain > FULL_SCALE) gain = FULL_SCALE;
    gainCompensation[channel] = gain;
    afeWriteGainCompensation(channel);
}

int
afeGetGainCompensation(int channel)
{
    if ((channel < 0) || (channel >= BPM_PROTOCOL_ADC_COUNT))
        return 0;
    return gainCompensation[channel];
}

/*
 * Set attenuators
 */
void
afeAttenSet(int dB)
{
    int i = 0;

    /*
     * Write trimmed value
     */
    do {
        int pass = 0;
        int v = (dB * 4) + systemParameters.afeTrim[i];
        if (v > 127) v = 127;
        else if (v < 0) v = 0;
        v |= (1 << i) << 8;
        while  (GPIO_READ(GPIO_IDX_AFE_ATTEN) & AFE_ATTEN_CSR_BUSY) {
            if (++pass >= 100) {
                criticalWarning("ATTENUATOR UPDATE FAILED TO COMPLETE");
                break;
            }
        }
        GPIO_WRITE(GPIO_IDX_AFE_ATTEN, v);
    } while (++i < sizeof systemParameters.afeTrim /
                                            sizeof systemParameters.afeTrim[0]);

    /*
     * Update attenuator compenstation coefficients in FPGA
     */
    attenuationIndex = dB;
    for (i = 0 ; i < BPM_PROTOCOL_ADC_COUNT ; i++) {
        afeWriteGainCompensation(i);
    }
}

/*
 * Read back attenuator setting
 */
int
afeAttenGet(void)
{
    return attenuationIndex;
}

/*
 * Called when complete file has been uploaded to the TFTP server
 */
int
afeAttenSetTable(unsigned char *buf, int size)
{
    int r, c;
    int dB;
    const unsigned char *cp = buf;
    static float tempTable[AFE_ATTEN_ROWS][BPM_PROTOCOL_ADC_COUNT];

    for (r = 0 ; r < AFE_ATTEN_ROWS ; r++) {
        for (c = 0 ; c < BPM_PROTOCOL_ADC_COUNT ; c++) {
            char expectedEnd = (c == (BPM_PROTOCOL_ADC_COUNT-1)) ? '\n' : ',';
            char *endp;
            double x;

            x = strtod((char *)cp, &endp);
            if ((*endp != expectedEnd)
             && ((expectedEnd == '\n') && (*endp != '\r'))) {
                sprintf((char *)buf, "Unexpected character  on line %d", r + 1);
                return -1;
            }
            if ((x < 0.75) || (x > 1.0)) {
                sprintf((char *)buf, "Value out of range at line %d", r + 1);
                return -1;
            }
            tempTable[r][c] = x;
            cp = (unsigned char *)endp + 1;
            if ((cp - buf) > size) {
                sprintf((char *)buf, "Too short at line %d", r + 1);
                return -1;
            }
        }
    }
    memcpy(afeAttenTable, tempTable, sizeof afeAttenTable);
    dB = attenuationIndex;
    afeAttenSet(dB);
    memcpy(buf, tempTable, sizeof afeAttenTable);
    return sizeof afeAttenTable;
}

/*
 * Called when attenuator settings are to be downloaded
 */
int
afeAttenGetTable(unsigned char *buf, int capacity)
{
    int r, c;
    int i;
    unsigned char *cp = buf;

    for (r = 0 ; r < AFE_ATTEN_ROWS ; r++) {
        for (c = 0 ; c < BPM_PROTOCOL_ADC_COUNT ; c++) {
            char sep = (c == (BPM_PROTOCOL_ADC_COUNT-1)) ? '\n' : ',';
            i = sprintf((char *)cp, "%.7g%c", afeAttenTable[r][c], sep);
            cp += i;
        }
    }
    return cp - buf;
}

/*
 * Initialize AFE attenuator stuff
 */
void
afeAttenReadback(const unsigned char *buf)
{
    int r, c, bad = 0;
    int i;

    memcpy(afeAttenTable, buf, sizeof afeAttenTable);
    for (r = 0 ; r < AFE_ATTEN_ROWS ; r++) {
        for (c = 0 ; c < BPM_PROTOCOL_ADC_COUNT ; c++) {
            /* The odd-looking comparison is there to deal with NANs */
            if (!((afeAttenTable[r][c] >= 0) && (afeAttenTable[r][c] <= 1)))
                bad = 1;
        }
    }
    if (bad) {
        printf("\n====== WARNING -- CORRUPT ATTENUATION TABLE -- "
                                        "ASSIGNING DEFAULT VALUES =====\n\n");
        for (r = 0 ; r < AFE_ATTEN_ROWS ; r++) {
            for (c = 0 ; c < BPM_PROTOCOL_ADC_COUNT ; c++) {
                afeAttenTable[r][c] = 1.0;
            }
        }
    }

    /*
     * Set attenuators to a reasonable default value
     */
    for (i = 0 ; i < BPM_PROTOCOL_ADC_COUNT ; i++)
        gainCompensation[i] = FULL_SCALE;
    afeAttenSet(20);
}
