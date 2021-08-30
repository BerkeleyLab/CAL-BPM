/*
 * Manipulate the AFE PLL
 */

#include <stdio.h>
#include <stdint.h>
#include "afePLL.h"
#include "gpio.h"
#include "localOscillator.h"
#include "systemParameters.h"
#include "util.h"

/*
 * GPIO_IDX_AFE_PLL_SPI register
 */
#define PLL_FAULT_LATCH_CLEAR 0x80000000 /* Write-only */
#define PLL_CLOCKBITS_SHIFT  16
#define PLL_SPI_BUSY         0x8000
#define PLL_UNLOCKED         0x4000
#define PLL_READBACK_MASK    0xFF

/*
 * GPIO_IDX_CLOCK_STATUS register
 * Bits are read-only unless specified otherwise
 */
#define CLOCKSTATUS_ADC_CLOCK_DELAY_RESET   0x8000 /* Write-only */
#define CLOCKSTATUS_ADC_CLOCK_DELAY_READY   0x8000 /* Read-only */
#define CLOCKSTATUS_ADC_CLOCK_DELAY_MASK    0x1F00 /* Read/Write */
#define CLOCKSTATUS_ADC_CLOCK_DELAY_SHIFT   8
#define CLOCKSTATUS_AFE_PLL_FAULT     0x80
#define CLOCKSTATUS_FA_SYNCED         0x40
#define CLOCKSTATUS_SA_SYNCED         0x20
#define CLOCKSTATUS_AFE_REF_SYNCED    0x04
#define CLOCKSTATUS_EVR_UNLOCKED      0x02
#define CLOCKSTATUS_RFLO_SYNCED       0x01
#define SetDelay(n) GPIO_WRITE(GPIO_IDX_CLOCK_STATUS, \
                                    (n) << CLOCKSTATUS_ADC_CLOCK_DELAY_SHIFT)

/*
 * Programmable delay tap range
 */
#define DELAY_ADJUST_RANGE 32

/*
 * Keep track of ADC clock delay nominal value in case we need to tweak
 * the delay to avoid a race condition with the EVR heartbeat trigger.
 */
static int adcClkDelayBase;

/*
 * 16 bit command code, 8 bit value.
 * Most significant bit of command code is R/W*.
 * Least significant 7 bits of command code is address.
 */
static int
ad9510Transfer(int value)
{
    int i = 100;

    GPIO_WRITE(GPIO_IDX_AFE_PLL_SPI, value);
    while (((value = GPIO_READ(GPIO_IDX_AFE_PLL_SPI)) & PLL_SPI_BUSY) != 0) {
        if (--i == 0) fatal("TIMED OUT WAITING FOR AFE PLL SPI");
    }
    return value & PLL_READBACK_MASK;
}

void
writeAD9510(int x)
{
    int reg = x & 0x7F00;
    int val = x & 0xFF;
    int readback;
    ad9510Transfer(x);
    if (reg != 0x5A00) {
        readback = ad9510Transfer(0x800000 | reg);
        if (readback != val) {
            printf("Wrote %2.2X to AFE PLL register %2.2X.   Read %2.2X\n",
                                                    val, reg >> 8, readback);
        }
    }
}

static int
readAD9510(int reg)
{
    return ad9510Transfer((0x8000 | (reg & 0xFF)) << 8);
}

static void
afePLLshow(void)
{
    int i;
    int v;
    const char *cp;

    printf("AFE PLL (AD9510) is %slocked:\n",
                 GPIO_READ(GPIO_IDX_AFE_PLL_SPI) & PLL_UNLOCKED ? "un" : "");
    for (i = 0 ; i <= 0x58 ; i++) {
        if (((i >= 0x01) && (i <= 0x03))
         || ((i >= 0x0E) && (i <= 0x33))
         || (i == 0x37)
         || (i == 0x3B)
         || (i == 0x44)
         || (i == 0x46)
         || (i == 0x47))
            continue;
        cp = NULL;
        v = readAD9510(i);
        printf("     %2.2X: %2.2X", i, v);
        switch(i) {
        case 0x00:
            printf("  %s%s%s%s",
                        v & 0x80 ? "SDO Inactive, " : "SDO active, ",
                        v & 0x40 ? "LSB first, " : "MSB first, ",
                        v & 0x20 ? "Soft reset, " : "",
                        v & 0x10 ? "16 bit instruction" : "8 bit instruction");
            break;

        case 0x04:
            {
            int r0A, fd, p, b, n, r;
            r = (readAD9510(0x0B) & 0x3F) | readAD9510(0xC);
            r0A = readAD9510(0xA);
            if (r0A & 0x40) {
                b = 1;
            }
            else {
                b = ((readAD9510(0x05) & 0x1F) << 8) | readAD9510(0x06);
            }
            switch ((r0A >> 2) & 0x7) {
            case 0: fd = 1;     p = 1;  break;
            case 1: fd = 1;     p = 2;  break;
            case 2: fd = -1;    p = 2;  break;
            case 3: fd = -1;    p = 4;  break;
            case 4: fd = -1;    p = 8;  break;
            case 5: fd = -1;    p = 16; break;
            case 6: fd = -1;    p = 32; break;
            case 7: fd = 1;     p = 3;  break;
            }
            if (fd > 0) {
                n = p * b;
            }
            else {
                n = p * b + (readAD9510(0x04) & 0x1F);
            }
            printf("  Fvco = Fref");
            if (n != 1) printf(" * %d", n);
            if (r != 1) printf(" / %d", r);
            }
            break;

        case 0x07:
            if (v & 0x4) {
                int cyc = 0;
                switch((v >> 5) & 0x3) {
                case 0: cyc = 3;   break;
                case 1: cyc = 6;   break;
                case 2: cyc = 12;  break;
                default:cyc = 24;  break;
                }
                printf("  Loss Of Reference after %d PFD cycles", cyc);
            }
            else {
                printf("  Loss Of Reference disabled");
            }
            break;

        case 0x08:
            printf("  PFD polarity: %s, MUX: %s, CP: %s",
                        (v & 0x40) ? "Positive" : "Negative",
                        ((v & 0x3C) == 0x00) ? "Gnd" : 
                        ((v & 0x3C) == 0x2C) ? "Tristate" : 
                        ((v & 0x3C) == 0x34) ? "Loss of ref/lock (active hi)" : 
                                               "Other",
                        ((v & 0x3) == 0x3) ? "Normal" : "Other");
            break;

        case 0x0A:
            switch (v & 0x3) {
            case 1: cp = "Asynchronous PLL power-down";          break;
            case 3: cp = "Synchronous PLL power-down";           break;
            default:cp = "Normal PLL operation (no power-down)"; break;
            }
            printf("  %s", cp);
            break;
            
        case 0x0D:
            printf("  Lock detect %sabled", v & 0x040 ? "dis" : "en");
            switch (v & 0x3) {
            case 1: cp = "2.9";    break;
            case 2: cp = "6.0";    break;
            default:cp = "1.3";    break;
            }
            printf(", antibacklash %s ns", cp);
            break;

        case 0x34: case 0x38:
            if (v & 0x1) printf("  Output %d -- Bypass Delay", (i==0x34)?5:6);
            break;

        case 0x3C: case 0x3E: case 0x3D: case 0x3F: 
            switch(v & 0x3) {
            case 1: cp ="Invalid power-down state!"; break;
            case 2: cp ="Safe power-down";           break;
            case 3: cp ="Total power-down";          break;
            }
            printf("  Output %d -- LVPECL, ", i - 0x3C);
            if (cp) {
                printf("%s", cp);
            }
            else {
                const short d[] = { 500, 340, 810, 660 };;
                printf("%d mV", d[(v >> 2) & 0x3]);
            }
            break;

        case 0x40: case 0x41: case 0x42: case 0x43: 
            printf("  Output %d -- %s", i - 0x3C, v & 0x8 ? "CMOS" : "LVDS");
            if (v & 0x1) {
                printf(", Power down");
            }
            else {
                if ((v & 0x8) == 0) {
                    int t;
                    float a;
                    switch((v >> 1) & 0x3) {
                    case 0: a = 1.75; t = 100; break;
                    case 1: a = 3.50; t = 100; break;
                    case 2: a = 5.25; t =  50; break;
                    case 3: a = 7.00; t =  50; break;
                    }
                    printf(", %.2f mA, %d ohm", a, t);
                }
            }
            break;

        case 0x45:
            printf("  CLK%d active", v & 0x1 ? 1 : 2);
            if (v & 0x2) printf(", CLK1 down");
            if (v & 0x4) printf(", CLK2 down");
            if (v & 0x8) printf(", prescaler down");
            if (v & 0x10) printf(", REFIN down");
            if (v & 0x20) printf(", ALL down");
            break;

        case 0x49: case 0x4B: case 0x4D: case 0x4F: 
        case 0x51: case 0x53: case 0x55: case 0x57: 
            printf("  Output %d -- %s Divider", (i - 0x49) / 2,
                                                v & 0x80 ? "Bypass" : "Enable");
            break;

        case 0x58:
            switch (v & 0x60) {
            case 0x00: cp = "RESETB";          break;
            case 0x20: cp = "SYNCB";           break;
            case 0x60: cp = "PDB";             break;
            default:   cp = "TEST--ILLEGAL!";  break;
            }
            printf("  Func pin: %s", cp);
            printf(", Sync select: %s", (v & 0x2) ? "0.5-1" : "1-1.5");
            if (v & 0x1) printf(", STATUS is SYNC");
            break;

        }
        printf("\n");
    }
}

/*
 * Return current ADC clock delay
 */
int
adcClkDelay(void)
{
    return (GPIO_READ(GPIO_IDX_CLOCK_STATUS) & CLOCKSTATUS_ADC_CLOCK_DELAY_MASK)
                                        >> CLOCKSTATUS_ADC_CLOCK_DELAY_SHIFT;
}

/*
 * Jog the delay a little to avoid a race condition with EVR clock
 */
static void
adcJogDelay(void)
{
    int delay;
    static int jog;

    if ((++jog > 3) || (adcClkDelayBase + jog) >= DELAY_ADJUST_RANGE) jog = -3;
    if ((adcClkDelayBase + jog) < 0) jog = -adcClkDelayBase;
    delay = adcClkDelayBase + jog;
    printf("Jog %d to %d\n", jog, delay);
    SetDelay(delay);
}

/*
 * The ADC data sheet indicates that data transitions occur on the falling edge
 * of the CLKOUT signal.  Based on that the optimum time to sample the data
 * lines is in the middle of the rising edge of the four CLKOUT transitions.
 */
static void
scanAdcClkdelay(int verbose)
{
    int delay;
    int warned = 0, pass = 0;
    int previous = ~0;
    int c;
    char clkStates[DELAY_ADJUST_RANGE];
    int i;
    int indexOfFirstRise = -1, indexOfLastRise = -1;
    int indexOfFirstFall = -1, indexOfLastFall = -1;

    for (delay = 0 ; delay < DELAY_ADJUST_RANGE ; delay++) {
        SetDelay(delay);
        nanosecondSpin(1000);
        while (GPIO_READ(GPIO_IDX_AFE_PLL_SPI) & PLL_UNLOCKED) {
            if (!warned) {
                warned = 1;
                printf("PLL UNLOCKED!\n");
            }
            if (++pass == 1000) {
                pass = 0;
                if (warned < 2) {
                    printf("PLL STILL UNLOCKED -- PROCEEDING ANYWAY!\n");
                    warned = 2;
                }
                break;
            }
        }
        if (warned) {
            if ((GPIO_READ(GPIO_IDX_AFE_PLL_SPI) & PLL_UNLOCKED) == 0) {
                warned = 0;
                printf("PLL LOCKED.\n");
            }
        }
        c = (GPIO_READ(GPIO_IDX_AFE_PLL_SPI) >> PLL_CLOCKBITS_SHIFT) & 0xF;
        if (verbose && (c != previous)) {
            printf("ADC clock delay %d, clk: %X\n", delay, c);
            previous = c;
        }
        clkStates[delay] = c;
    }

    /*
     * Try to find find at least one leading edge
     */
    for (i = 1 ; i < DELAY_ADJUST_RANGE ; i++) {
        if (clkStates[i] & ~clkStates[i-1]) {
            if (indexOfFirstRise < 0) indexOfFirstRise = i;
            indexOfLastRise = i;
        }
        if (clkStates[i-1] & ~clkStates[i]) {
            if (indexOfFirstFall < 0) indexOfFirstFall = i;
            indexOfLastFall = i;
        }
    }
    if ((indexOfFirstRise < 0) && (indexOfFirstFall < 0)) {
        criticalWarning("Can't find any clock transitions!\n");
        delay = 16;
    }
    else if (indexOfFirstRise < 0) {
        criticalWarning("Can't find any rising edge\n");
        if (indexOfLastFall < (DELAY_ADJUST_RANGE/2))
            delay = DELAY_ADJUST_RANGE-1;
        else
            delay = 0;
    }
    else {
        if ((clkStates[0] != 0x0) || (clkStates[DELAY_ADJUST_RANGE-1] != 0xF)) {
            printf("Warning -- can't find all leading edges\n");
        }
        delay = (indexOfFirstRise + indexOfLastRise) / 2;
    }
    printf("SET ADC CLOCK DELAY %d\n\n", delay);
    SetDelay(delay);
    adcClkDelayBase = delay;
}

/*
 * Handle (re)appearance of timing reference clock from EVR
 */
void
afeCheck(void)
{
    static int firstLock = 1;
    static int wasLocked = 0;
    static unsigned int whenLocked;
    uint32_t csr = GPIO_READ(GPIO_IDX_CLOCK_STATUS);

    if (csr & CLOCKSTATUS_EVR_UNLOCKED) {
        static int warned = 0;
        if (!warned || wasLocked) criticalWarning("EVR UNLOCKED");
        wasLocked = 0;
        whenLocked = 0;
        warned = 1;
    }
    else if (!wasLocked) {
        if (whenLocked == 0) {
            whenLocked = sysTicksSinceBoot();
        }
        if (firstLock
         || ((sysTicksSinceBoot() - whenLocked) > XPAR_PROC_BUS_0_FREQ_HZ)) {
            wasLocked = 1;
            scanAdcClkdelay(firstLock);
        }
        firstLock = 0;
    }
}

/*
 * Explicit rescan
 */
void
rescanAdcClkDelay(void)
{
    scanAdcClkdelay(1);
}

/*
 * Set reference clock divisor
 */
static void
initRefClock(void)
{
    int refDivisor = systemParameters.rfDivisor / 4;
    int refHi = refDivisor / 2;
    int refLo = refDivisor - refHi;

    if ((systemParameters.rfDivisor <= 0)
     || ((systemParameters.rfDivisor % 4) != 0))
        criticalWarning("RF DIVISOR SYSTEM PARAMETER NOT A MULTIPLE OF 4");
    GPIO_WRITE(GPIO_IDX_AFE_REFCLK_CSR, ((refHi - 1) << 8) | (refLo - 1));
    GPIO_WRITE(GPIO_IDX_EVR_FA_RELOAD, systemParameters.evrPerFaMarker - 2);
    GPIO_WRITE(GPIO_IDX_EVR_SA_RELOAD, systemParameters.evrPerSaMarker - 2);
    nanosecondSpin(1200*1000*1000); /* Allow for heartbeat to occur */
}

void
afePLLinit(void)
{
    int pass;

    // Initialize ADC clock delay controller
    GPIO_WRITE(GPIO_IDX_CLOCK_STATUS, CLOCKSTATUS_ADC_CLOCK_DELAY_RESET);
    GPIO_WRITE(GPIO_IDX_CLOCK_STATUS, 0);
    for (pass = 0 ; ; ) {
        nanosecondSpin(10000);
        if (GPIO_READ(GPIO_IDX_CLOCK_STATUS)&CLOCKSTATUS_ADC_CLOCK_DELAY_READY)
            break;
        if (++pass == 100) {
            criticalWarning("ADC clock delay controller never became ready");
            break;
        }
    }

    // Enable PLL reference
    initRefClock();

    // SDO active, MSB first, No reset, Long instruction
    writeAD9510(0x0010);

    // Sync Disabled
    writeAD9510(0x5800);

    // Disable loss of reference
    writeAD9510(0x0700);

    // Use CLK2 in clock distribution mode
    if (systemParameters.pllMultiplier <= 1)
        writeAD9510(0x451D);
    else
        writeAD9510(0x4502);

    // ADC 0 -- OUT0 LVPECL, 810 mV, divider bypass
    writeAD9510(0x3C08);
    writeAD9510(0x4980);

    // ADC 1 -- OUT1 LVPECL, 810 mV, divider bypass
    writeAD9510(0x3D08);
    writeAD9510(0x4B80);

    // ADC 2 -- OUT2 LVPECL, 810 mV, divider bypass
    writeAD9510(0x3E08);
    writeAD9510(0x4D80);

    // ADC 3 -- OUT3 LVPECL, 810 mV, divider bypass
    writeAD9510(0x3F08);
    writeAD9510(0x4F80);

    // OUT4 LVDS, 3.5 mA, 100 ohm, divider bypass
    writeAD9510(0x4002);
    writeAD9510(0x5180);

    // OUT5 LVDS, 3.5 mA, 100 ohm, divider bypass, no phase adjust
    writeAD9510(0x4102);
    writeAD9510(0x5380);
    writeAD9510(0x3401);

    // DFE global ADC clock -- OUT6 LVDS, 3.5 mA, 100 ohm, divider bypass
    //                              No phase adjust
    writeAD9510(0x4202);
    writeAD9510(0x5580);
    writeAD9510(0x3801);

    // OUT7 LVDS, 3.5 mA, 100 ohm, divider bypass
    writeAD9510(0x4302);
    writeAD9510(0x5780);
    
    // A = 0
    writeAD9510(0x0400);

    // B depends on AFE VCXO
    writeAD9510(0x0500 | ((systemParameters.pllMultiplier >> 8) & 0x1F));
    writeAD9510(0x0600 | (systemParameters.pllMultiplier & 0xFF));

    // R = 0
    writeAD9510(0x0B00);
    writeAD9510(0x0C01);

    // +PFD polarity
    // Normal charge pump
    if (systemParameters.pllMultiplier <= 1)
        writeAD9510(0x0843); // STATUS=Gnd
    else
        writeAD9510(0x0877); // STATUS=loss of reference or loss of lock

    // Charge pump = 0.6 mA, normal counter operation
    writeAD9510(0x0900);

    // Power-down PLL when in clock distribution mode
    if (systemParameters.pllMultiplier <= 1)
        writeAD9510(0x0A01);
    else
        writeAD9510(0x0A02);

    // Normal lock detect, default 1.3 ns antibacklash
    writeAD9510(0x0D00);

    // Update registers
    writeAD9510(0x5A01);

    // Give some time for the PLL to lock
    for (pass = 0 ;;) {
        nanosecondSpin(1000000);
        if ((GPIO_READ(GPIO_IDX_AFE_PLL_SPI) & PLL_UNLOCKED) == 0) {
            nanosecondSpin(100000000);
            break;
        }
        if(++pass == 1000) {
            criticalWarning("AFE PLL UNLOCKED");
            break;
        }
    }

    // See if the reference source is good
    afeCheck();

    // Clear effects of the various startup manipulations
    afePLLclearLatch();

    // Show the results
    afePLLshow();
}

/*
 * The local oscillators are in the ADC clock domain but are synchronized to
 * the SA marker in the event receiver clock domain.  The timing between the
 * ADC and EVR clocks at the SA marker varies depending upon when the ADC
 * PLL happens to start up.  This means that the ADC clock sampling of the
 * SA marker can be at a point where there's a race condition that makes
 * the local oscillator jitter in and out of synchronization.
 * Handle this with this simple state machine that jogs the delay of
 * the clock driving the FPGA ADC-rate logic when local oscillator
 * synchronization jitter is detected.  This should happen only once and
 * then be good until a BPM power cycle or major timing system upset.
 */
void
afeLOsyncCheck(void)
{
    static int state;
    static int secondsAtStateEntry;
    int clockStatus = GPIO_READ(GPIO_IDX_CLOCK_STATUS);

    switch (state) {
    case 0:
        /* Wait until EVR FA/SA markers have synchronized */
        if ((clockStatus & (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED))
                        == (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED)) {
            secondsAtStateEntry = secondsSinceBoot();
            state = 1;
        }
        break;

    case 1:
        /* Wait until EVR FA/SA markers have been good for 10 seconds */
        if ((clockStatus & (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED)) !=
                           (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED)) {
            state = 0;
        }
        else if ((secondsSinceBoot() - secondsAtStateEntry) > 10) {
            state = 2;
        }
        break;

    case 2:
        /* Stay here as long as local oscillator remains synchronized */
        if ((clockStatus & (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED))
                        != (CLOCKSTATUS_FA_SYNCED | CLOCKSTATUS_SA_SYNCED)) {
            state = 0;
        }
        else if ((clockStatus & CLOCKSTATUS_RFLO_SYNCED) == 0) {
            adcJogDelay();
            secondsAtStateEntry = secondsSinceBoot();
            state = 1;
        }
        break;

    default:
        state = 0;
        break;
    }
}

/*
 * Clear AFE PLL latched fault
 */
void
afePLLclearLatch(void)
{
    GPIO_WRITE(GPIO_READ(GPIO_IDX_EVR_FA_RELOAD), GPIO_IDX_EVR_FA_RELOAD);
    GPIO_WRITE(GPIO_READ(GPIO_IDX_EVR_SA_RELOAD), GPIO_IDX_EVR_SA_RELOAD);
    GPIO_WRITE(GPIO_IDX_AFE_PLL_SPI, PLL_FAULT_LATCH_CLEAR);
}
