/*
 * Global settings
 */
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "lwip/def.h"
#include "linearFlash.h"
#include "localOscillator.h"
#include "systemParameters.h"
#include "tftp.h"
#include "util.h"

struct systemParameters systemParameters;

static int
checksum(void)
{
    int i, sum = 0xCAFEF00D;
    const int *ip = (int *)&systemParameters;

    for (i = 0 ; i < ((sizeof systemParameters -
                    sizeof systemParameters.checksum) / sizeof(*ip)) ; i++)
        sum += *ip++;
    return sum;
}

void systemParametersUpdateChecksum(void)
{
    systemParameters.checksum = checksum();
}

/*
 * Process values read back from flash on system startup.
 */
void
systemParametersReadback(const unsigned char *buf)
{
    int sfRatio;

    memcpy(&systemParameters, buf, sizeof systemParameters);

    /*
     * Perform sanity check on parameters read from flash.
     * If they aren't good then assign default values.
     */
    sfRatio = systemParameters.evrPerSaMarker / systemParameters.evrPerFaMarker;
    if (((checksum() != systemParameters.checksum) 
      || ((unsigned int)systemParameters.autoTrimStartEvent >= 127)
      || (sfRatio < 900)
      || (sfRatio > 1100))) {
        unsigned long addr = ntohl(systemParameters.ipv4.address);
        unsigned long mask = ntohl(systemParameters.ipv4.netmask);
        unsigned long gw   = ntohl(systemParameters.ipv4.gateway);
        printf("\n====== WARNING -- CORRUPT PARAMETER TABLE -- "
                                        "ASSIGNING DEFAULT VALUES =====\n\n");
        systemParameters.rfDivisor = 328;
        systemParameters.pllMultiplier = 77;
        systemParameters.isSinglePass = 0;
        systemParameters.singlePassEvent = 0;
        systemParameters.autoTrimStartEvent = 0;
        systemParameters.evrPerFaMarker = 152 * 82;
        systemParameters.evrPerSaMarker = 152 * 82 * 1000;
        systemParameters.adcOrder = 3120;
        systemParameters.xCalibration = 16.0;
        systemParameters.yCalibration = 16.0;
        systemParameters.qCalibration = 16.0;
        systemParameters.buttonRotation = 45;
        memset(systemParameters.afeTrim, 0, sizeof systemParameters.afeTrim);

        /* Replace network parameters if they look questionable */
        if (((mask != 0xFFFFFF00) && (mask != 0xFFFFFC00))
         || ((addr & mask) != (gw & mask))) {
            printf("\n====== WARNING -- ALSO "
                                "ASSIGNING DEFAULT NETWORK PARAMETERS ===\n\n");
            systemParameters.ethernetAddress[0] = 'B'; /* Local addr bit set */
            systemParameters.ethernetAddress[1] = 'P';
            systemParameters.ethernetAddress[2] = 'M';
            systemParameters.ethernetAddress[3] = 'A';
            systemParameters.ethernetAddress[4] = 'L';
            systemParameters.ethernetAddress[5] = 'S';
            systemParameters.ipv4.address = htonl((192<<24) |
                                                  (168<<16) |
                                                  (  1<< 8) |
                                                    20);
            systemParameters.ipv4.netmask = htonl((255<<24) |
                                                  (255<<16) |
                                                  (255<< 8) |
                                                     0);
            systemParameters.ipv4.gateway = htonl((192<<24) |
                                                  (168<<16) |
                                                  (  1<< 8) |
                                                     1);
        }
        systemParametersUpdateChecksum();
    }
}

/*
 * Serializer/deserializers
 * Note -- Format routines share common static buffer.
 */
static char cbuf[40];
char *
formatMAC(void *val)
{
    const unsigned char *addr = (const unsigned char *)val;
    sprintf(cbuf, "%02X:%02X:%02X:%02X:%02X:%02X", addr[0], addr[1], addr[2],
                                                   addr[3], addr[4], addr[5]);
    return cbuf;
}

int
parseMAC(const char *str, void *val)
{
    const char *cp = str;
    int i = 0;
    long l;
    char *endp;

    for (;;) {
        l = strtol(cp, &endp, 16);
        if ((l < 0) || (l > 255))
            return -1;
        *((unsigned char *)val + i) = l;
        if (++i == 6)
            return endp - str;
        if (*endp++ != ':')
            return -1;
        cp = endp;
    }
}

char *
formatIP(void *val)
{
    unsigned long l = ntohl(*(unsigned long *)val);
    sprintf(cbuf, "%d.%d.%d.%d", (int)(l >> 24) & 0xFF, (int)(l >> 16) & 0xFF,
                                 (int)(l >>  8) & 0xFF, (int)(l >>  0) & 0xFF);
    return cbuf;
}

int
parseIP(const char *str, void *val)
{
    const char *cp = str;
    unsigned long addr = 0;
    int i = 0;
    long l;
    char *endp;

    for (;;) {
        l = strtol(cp, &endp, 10);
        if ((l < 0) || (l > 255))
            return -1;
        addr = (addr << 8) | l;
        if (++i == 4) {
            *(unsigned long *)val = htonl(addr);
            return endp - str;
        }
        if (*endp++ != '.')
            return -1;
        cp = endp;
    }
}

static char *
formatAtrim(void *val)
{
    int i;
    const int *ip = (const int *)val;
    char *cp = cbuf;
    for (i = 0 ; ; ) {
        cp += sprintf(cp, "%g", (float)*ip++ / 4.0);
        if (++i >=
            sizeof systemParameters.afeTrim/sizeof systemParameters.afeTrim[0])
            break;
        *cp++ = ' ';
    }
    return cbuf;
}

static int
parseAtrim(const char *str, void *val)
{
    const char *cp = str;
    int *ip = (int *)val;
    const char *term = " ";
    int i = 0;
    int n =  sizeof systemParameters.afeTrim/sizeof systemParameters.afeTrim[0];
    double d;
    char *endp;

    for (;;) {
        d = strtod(cp, &endp);
        if ((d < 0) || (d >= 1.8)) return -1;
        if ((endp != cp) && (strchr(term, *endp) != NULL)) {
            *ip++ = (d * 4.0) + 0.5;
            i++;
            if (i == (n - 1)) term = "\r\n";
            else if (i == n) return endp - str;
        }
        if (strchr("\r\n", *endp) != NULL) return -1;
        cp = endp + 1;
    }
}

#if 0  // Unused for now -- '#if'd out to inhibit unused function warning */
static char *formatDouble(void *val)
{
    sprintf(cbuf, "%.15g", *(double *)val);
    return cbuf;
}
#endif

static int
parseDouble(const char *str, void *val)
{
    char *endp;
    double d = strtod(str, &endp);
    if ((endp != str)
     && ((*endp == ',') || (*endp == '\r') || (*endp == '\n'))) {
        *(double *)val = d;
        return endp - str;
    }
    return -1;
}

static char *
formatFloat(void *val)
{
    sprintf(cbuf, "%.7g", *(float *)val);
    return cbuf;
}

static int
parseFloat(const char *str, void *val)
{
    int i;
    double d;

    i = parseDouble(str, &d);
    if (i > 0)
        *(float *)val = d;
    return i;
}

static char *
formatInt(void *val)
{
    sprintf(cbuf, "%d", *(int *)val);
    return cbuf;
}

static int
parseInt(const char *str, void *val)
{
    int i;
    double d;

    i = parseDouble(str, &d);
    if ((i > 0) && ((int)d == d))
        *(int *)val = d;
    return i;
}

static char *
formatInt4(void *val)
{
    sprintf(cbuf, "%04d", *(int *)val);
    return cbuf;
}

/*
 * Conversion table
 */
static struct conv {
    const char *name;
    void       *addr;
    char     *(*format)(void *val);
    int       (*parse)(const char *str, void *val);
} conv[] = {
  {"Ethernet Address", &systemParameters.ethernetAddress,formatMAC,  parseMAC},
  {"IP Address",       &systemParameters.ipv4.address,    formatIP,   parseIP},
  {"IP Netmask",       &systemParameters.ipv4.netmask,    formatIP,   parseIP},
  {"IP Gateway",       &systemParameters.ipv4.gateway,    formatIP,   parseIP},
  {"PLL RF divisor",   &systemParameters.rfDivisor,      formatInt,  parseInt},
  {"PLL multiplier",   &systemParameters.pllMultiplier,  formatInt,  parseInt},
  {"Single pass?",     &systemParameters.isSinglePass,   formatInt,  parseInt},
  {"Single pass event",&systemParameters.singlePassEvent,formatInt,  parseInt},
  {"RF auto-trim event",
                       &systemParameters.autoTrimStartEvent,formatInt,parseInt},
  {"EVR clocks per fast acquisition",
                       &systemParameters.evrPerFaMarker, formatInt,  parseInt},
  {"EVR clocks per slow acquisition",
                       &systemParameters.evrPerSaMarker, formatInt,  parseInt},
  {"ADC for button ABCD",
                       &systemParameters.adcOrder,      formatInt4,  parseInt},
  {"X calibration (mm p.u.)",
                       &systemParameters.xCalibration, formatFloat,parseFloat},
  {"Y calibration (mm p.u.)",
                       &systemParameters.yCalibration, formatFloat,parseFloat},
  {"Q calibration (p.u.)",
                       &systemParameters.qCalibration, formatFloat,parseFloat},
  {"Button rotation (0 or 45)",
                       &systemParameters.buttonRotation, formatInt,  parseInt},
  {"AFE attenuator trims (dB)",
                       &systemParameters.afeTrim[0],   formatAtrim,parseAtrim},
};

/*
 * Serialize/deserialize complete table
 */
int
systemParametersGetTable(unsigned char *buf, int capacity)
{
    char *cp = (char *)buf;
    int i;

    for (i = 0 ; i < (sizeof conv / sizeof conv[0]) ; i++)
        cp += sprintf(cp, "%s,%s\n", conv[i].name, (*conv[i].format)(conv[i].addr));
    return cp - (char *)buf;
}

static int
parseTable(unsigned char *buf, int size, char **err)
{
    const char *base = (const char *)buf;
    const char *cp = base;
    int i, l;
    int line = 1;

    for (i = 0 ; i < (sizeof conv / sizeof conv[0]) ; i++) {
        l = strlen(conv[i].name);
        if (((cp - base) + l + 2) >= size) {
            *err = "Unexpected EOF";
            return -line;
        }
        if (strncmp(cp, conv[i].name, l) != 0) {
            *err = "Unexpected parameter name";
            return -line;
        }
        cp += l;
        if (*cp++ != ',') {
            *err = "Missing comma after parameter name";
            return -line;
        }
        l = (*conv[i].parse)(cp, conv[i].addr);
        if (l <= 0) {
            *err = "Invalid value";
            return -line;
        }
        cp += l;
        while (((cp - base) < size)
            && (((isspace((unsigned char)*cp))) || (*cp == ','))) {
            if (*cp == '\n')
                line++;
            cp++;
        }
    }
    return cp - base;
}

int
systemParametersSetTable(unsigned char *buf, int size)
{
    char *err = "";
    int i = parseTable(buf, size, &err);

    if (i <= 0) {
        sprintf((char *)buf, "Bad file contents at line %d: %s", -i, err);
        return -1;
    }
    if (systemParameters.buttonRotation == 90)
        systemParameters.buttonRotation = 0;
    if ((systemParameters.buttonRotation != 0)
     && (systemParameters.buttonRotation != 45)) {
        sprintf((char *)buf, "Bad button rotation (must be 0 or 45)");
        return -1;
    }
    systemParametersUpdateChecksum();
    memcpy(buf, &systemParameters, sizeof systemParameters);
    return sizeof systemParameters;
}
