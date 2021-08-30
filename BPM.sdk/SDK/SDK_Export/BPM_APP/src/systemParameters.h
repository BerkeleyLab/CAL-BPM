/*
 * Global settings
 */

#ifndef _SYSTEM_PARAMETERS_H_
#define _SYSTEM_PARAMETERS_H_

struct sysNetParms {
    unsigned long  address;
    unsigned long  netmask;
    unsigned long  gateway;
};

extern struct systemParameters {
    unsigned char  ethernetAddress[8]; /* Pad to 4-byte boundary */
    struct sysNetParms ipv4;
    int            rfDivisor;
    int            pllMultiplier;
    int            isSinglePass;
    int            singlePassEvent;
    int            autoTrimStartEvent;
    int            evrPerFaMarker;
    int            evrPerSaMarker;
    int            adcOrder;
    float          xCalibration;
    float          yCalibration;
    float          qCalibration;
    int            buttonRotation;
    int            afeTrim[4]; /* Per-channel trims in units of 0.25 dB */
    unsigned long  checksum;
} systemParameters;

int systemParametersGetTable(unsigned char *buf, int capacity);
int systemParametersSetTable(unsigned char *buf, int size);
void systemParametersReadback(const unsigned char *buf);
void systemParametersUpdateChecksum(void);

char *formatIP(void *val);
int   parseIP(const char *str, void *val);
char *formatMAC(void *val);
int   parseMAC(const char *str, void *val);

#endif
