/*
 * Read SFP parameters and value
 */
#include <stdio.h>
#include <stdint.h>
#include "gpio.h"
#include "util.h"

#define INFO_STRING_CHARS   16
#define DATE_STRING_CHARS   6

#define BIT_RATE_ADDRESS      12
#define VENDOR_NAME_ADDRESS   20
#define PART_NAME_ADDRESS     40
#define PART_NUMBER_ADDRESS   68
#define DATE_CODE_ADDRESS     84
#define TEMPERATURE_ADDRESS   (0x100+96)
#define RX_POWER_ADDRESS      (0x100+104)

static const uint8_t regMap[] = { GPIO_IDX_SFP_READ_1_0,
                                  GPIO_IDX_SFP_READ_3_2,
                                  GPIO_IDX_SFP_READ_5_4 };
#define NSFP (2 * sizeof regMap)

static enum { S_IDLE, S_INIT, S_RUNNING } state = S_IDLE;

static struct sfpInfo {
    char     vendorName[INFO_STRING_CHARS+1];
    char     partName  [INFO_STRING_CHARS+1];
    char     partNumber[INFO_STRING_CHARS+1];
    char     dateCode  [11]; // We reformat to ISO 8601.
    int16_t  rxPower;
    int16_t  temperature;
    uint8_t  bitRate;
} sfpInfo[NSFP];

static const struct ioInfo {
    short   base;
    short   count;
} ioInfo[] = {
    { VENDOR_NAME_ADDRESS,    INFO_STRING_CHARS },
    { PART_NAME_ADDRESS,      INFO_STRING_CHARS },
    { PART_NUMBER_ADDRESS,    INFO_STRING_CHARS },
    { DATE_CODE_ADDRESS,      DATE_STRING_CHARS },
    { TEMPERATURE_ADDRESS,    sizeof(uint16_t) },
    { RX_POWER_ADDRESS,       sizeof(uint16_t) },
    { BIT_RATE_ADDRESS,       sizeof(uint16_t) },
};
static uint16_t iobuf[NSFP][INFO_STRING_CHARS/sizeof(uint16_t)];

static void
stashString(int sfp, char *dest)
{
    int i;

    for (i = 0 ; i < INFO_STRING_CHARS ; i++) {
        int c = iobuf[sfp][i/2] >> ((~i & 0x1) * 8);
        if (c == 0xFF) c = 0;
        dest[i] = c;
    }
    trimStringRight(dest);
}

/*
 * Reformat date code to ISO 8601
 */
static void
stashDateCode(int sfp)
{
    char *dateCode = sfpInfo[sfp].dateCode;
    
    if (iobuf[sfp][0] == 0xFFFF) {
        dateCode[0] ='\0';
        return;
    }
    dateCode[0] = '2';
    dateCode[1] = '0'; /* No, I am not Y2.1K-compliant */
    dateCode[2] = iobuf[sfp][0] >> 8;
    dateCode[3] = iobuf[sfp][0];
    dateCode[4] = '-';
    dateCode[5] = iobuf[sfp][1] >> 8;
    dateCode[6] = iobuf[sfp][1];
    dateCode[7] = '-';
    dateCode[8] = iobuf[sfp][2] >> 8;
    dateCode[9] = iobuf[sfp][2];
    dateCode[10] = '\0';
}

static void
stashInt(int sfp, int16_t *dest)
{
    int i = iobuf[sfp][0];

    if (i == 0xFFFF) i = 0;
    *dest = i;
}

static void
stashHighByte(int sfp, uint8_t *dest)
{
    *dest = iobuf[sfp][0] >> 8;
}

#define GPIO_BUSY_FLAG 0x1

static void
stashBuf(int base)
{
    int sfp;

    for (sfp = 0 ; sfp < NSFP ; sfp++) {
        switch(base) {
        case VENDOR_NAME_ADDRESS:stashString(sfp,sfpInfo[sfp].vendorName);break;
        case PART_NAME_ADDRESS:  stashString(sfp,sfpInfo[sfp].partName);  break;
        case PART_NUMBER_ADDRESS:stashString(sfp,sfpInfo[sfp].partNumber);break;
        case DATE_CODE_ADDRESS:  stashDateCode(sfp);                      break;
        case TEMPERATURE_ADDRESS:stashInt(sfp,&sfpInfo[sfp].temperature); break;
        case RX_POWER_ADDRESS:   stashInt(sfp,&sfpInfo[sfp].rxPower);     break;
        case BIT_RATE_ADDRESS:   stashHighByte(sfp,&sfpInfo[sfp].bitRate);break;
        }
    }
}

static void
fetchWord(int idx)
{
    int sfp;
    int regIndex;

    for (sfp = 0, regIndex = 0 ; regIndex < sizeof regMap ; regIndex++) {
        uint32_t r = GPIO_READ(regMap[regIndex]);
        iobuf[sfp++][idx] = (uint16_t)r;
        iobuf[sfp++][idx] = (uint16_t)(r >> 16);
    }
}

void
sfpCheck(void)
{
    static int ioIndex = 0;
    static int wordIndex = 0;

    if ((GPIO_READ(GPIO_IDX_SFP_READ_CSR)) & GPIO_BUSY_FLAG)
        return;
    if (state == S_IDLE) {
        state = S_INIT;
    }
    else {
        fetchWord(wordIndex);
        if ((++wordIndex * sizeof(uint16_t)) >= ioInfo[ioIndex].count) {
            stashBuf(ioInfo[ioIndex].base);
            wordIndex = 0;
            if (++ioIndex >= (sizeof ioInfo / sizeof ioInfo[0])) {
                ioIndex = 0;
                state = S_RUNNING;
            }
        }
    }
    GPIO_WRITE(GPIO_IDX_SFP_READ_CSR, ioInfo[ioIndex].base + wordIndex *
                                                             sizeof(uint16_t));
}

const char *
getSFPvendorName(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return "";
    return sfpInfo[sfp].vendorName;
}

const char *
getSFPvendorPartNumber(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return "";
    return sfpInfo[sfp].partName;
}


const char *
getSFPvendorSerialNumber(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return "";
    return sfpInfo[sfp].partNumber;
}

const char *
getSFPvendorDateCode(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return "";
    return sfpInfo[sfp].dateCode;
}

int
getSFPrxPower(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return 0;
    return sfpInfo[sfp].rxPower;
}

int
getSFPtemperature(int sfp)
{
    if ((sfp < 0) || (sfp >= NSFP)) return 0;
    return sfpInfo[sfp].temperature;
}

void
sfpInit(void)
{
    int sfp;
    static const uint8_t minRates[NSFP] = { 25, 32, 32, 50, 50, 0 };

    while (state != S_RUNNING)
        sfpCheck();
    for (sfp = 0 ; sfp < NSFP ; sfp++) {
        const char *cp = getSFPvendorName(sfp);
        if (*cp) {
            printf("SFP %d:  Vendor: %s\n", sfp, cp);
            printf("          Part: %s\n", getSFPvendorPartNumber(sfp));
            printf("        Serial: %s\n", getSFPvendorSerialNumber(sfp));
            printf("          Date: %s\n", getSFPvendorDateCode(sfp));
            printf("      Bit rate: %d.%d Gb/s", sfpInfo[sfp].bitRate / 10,
                                                 sfpInfo[sfp].bitRate % 10);
            if (sfpInfo[sfp].bitRate < minRates[sfp])
                printf(" -- WARNING -- TOO SLOW -- MINIMUM is %d.%d",
                                        minRates[sfp] / 10, minRates[sfp] % 10);
            printf("\n");
        }
    }
}
