/*
 * Useful utility routines
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <lwip/def.h>
#include "afePLL.h"
#include "console.h"
#include "evr.h"
#include "gpio.h"
#include "publisher.h"
#include "sfp.h"
#include "util.h"

volatile int debugFlags = DEBUGFLAG_SA_TIMING_CHECK;

/*
 * See if there's stuff to do.
 * Called from main processing loop and from flash operation completion loop.
 */
void
checkForWork(void)
{
    afeCheck();
    sfpCheck();
    afeLOsyncCheck();
    publisherCheck();
    consoleCheck();
}

/*
 * Indicate that things are unlikely to work very well from now on
 */
void
criticalWarning(const char *msg)
{
    int i;
    static const char h[] = {
 "+---------------------------------------------------------------------------+"
    };
    static const int hl = sizeof h - 1;
    printf("\n%s\n|%*s|\n", h, hl - 2, "");
    i = printf("| CRITICAL WARNING: %s", msg);
    if (i < (hl-1))
        printf("%*s|", hl - 1 - i, "");
    printf("\n|%*s|\n%s\n", hl - 2, "", h);
}

/*
 * Send out a final message
 */
void
fatal1(const char *msg, int i)
{
    for (;;) {
        xil_printf("\r\n\n"
           "**************************************************************\r\n"
           "****** FATAL ERROR: ");
        xil_printf(msg, i);
        nanosecondSpin(1000000000);
    }
}

void
fatal(const char *msg)
{
    fatal1(msg, 0);
}

/*
 * Spin away some time
 */
void
nanosecondSpin(unsigned int ns)
{
    uint32_t ticks = ns / (1000000000 / XPAR_MICROBLAZE_FREQ);
    uint32_t then = sysTicksSinceBoot();
    while ((sysTicksSinceBoot() - then) < ticks)
        continue;
}

/*
 * Show register contents
 */
void
showReg(int i)
{
    int r = GPIO_READ(i & 0x7F);
    printf("  R%d = %4.4X:%4.4X %11d\n", i, (r>>16)&0xFFFF, r&0xFFFF, r);
}

/*
 * Remove trailing spaces
 */
char *
trimStringRight(char *cp)
{
    char *eos = cp + strlen(cp);

    while (eos > cp) {
        if (eos[-1] != ' ')
            break;
        eos--;
    }
    *eos = '\0';
    return cp;
}

/*
 * Pretty-print an unsigned integer value
 */
void
uintPrint(unsigned int n)
{
    int i;
    int t[4];
    for (i = 0 ; i < 4 ; i++) {
        t[i] = n % 1000;
        n /= 1000;
    }
    if (t[3])      printf("%d,%03d,%03d,%03d", t[3], t[2], t[1], t[0]) ;
    else if (t[2]) printf("%5d,%03d,%03d", t[2], t[1], t[0]) ;
    else if (t[1]) printf("%9d,%03d", t[1], t[0]) ;
    else           printf("%13d", t[0]) ;
}

/*
 * Set firmware and software revision strings
 */
char firmwareRevision[24];
char softwareRevision[] = { __DATE__ " " __TIME__ };
void
setRevisionStrings(void)
{
    time_t firmwareTime;

    /* Get firmware revision date/time string. */
    firmwareTime = GPIO_READ(GPIO_IDX_FIRMWARE_DATE);
    strftime(firmwareRevision, sizeof firmwareRevision,
                                    "%b %e %Y %H:%M:%S", gmtime(&firmwareTime));
}

/*
 * Write to the ICAP_VIRTEX6 instance to force a warm reboot
 * Command sequence from UG360 -- IPROG Using ICAP_VIRTEX6.
 */
static void
writeICAP(int value)
{
    Xil_Out32(XPAR_FPGA_ICAP_BASEADDR+0x100, value); /* Write FIFO */
    Xil_Out32(XPAR_FPGA_ICAP_BASEADDR+0x10C, 0x1);   /* Initiate WRITE */
    while((Xil_In32(XPAR_FPGA_ICAP_BASEADDR+0x10C) & 0x1) != 0)
        continue;
}
void
resetFPGA(void)
{
    xil_printf("====== FPGA REBOOT ======\r\n\n\n");
    nanosecondSpin(50000000);
    writeICAP(0xFFFFFFFF); /* Dummy word */
    writeICAP(0xAA995566); /* Sync word */
    writeICAP(0x20000000); /* Type 1 NO-OP */
    writeICAP(0x30020001); /* Type 1 write 1 to Warm Boot STart Address Reg */
    writeICAP(0x00000000); /* Warm boot start addr */
    writeICAP(0x30008001); /* Type 1 write 1 to CMD */
    writeICAP(0x0000000F); /* IPROG command */
    writeICAP(0x20000000); /* Type 1 NO-OP */
    xil_printf("====== FPGA REBOOT FAILED ======\r\n");
}
