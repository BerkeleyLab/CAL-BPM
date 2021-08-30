/*
 * Read system monitor
 * Code based on ML-605 system monitor example application
 */
#include <stdio.h>
#include <xil_io.h>
#include <xparameters.h>
#include "axiSysmon.h"

#define In32(offset)    Xil_In32(XPAR_SYSMON_BASEADDR+(offset))
#define Out32(offset,v) Xil_Out32(XPAR_SYSMON_BASEADDR+(offset),(v))

#define R_SRR           0x00  /* Software Reset Register */
#define R_TEMP          0x200 /* On-chip Temperature Reg */
#define R_VCCINT        0x204 /* On-chip VCCINT Data Reg */
#define R_VCCAUX        0x208 /* On-chip VCCAUX Data Reg */
#define R_VPVN          0x20C /* ADC out of VP/VN       */
#define R_AUX12         0x270 /* ADC out of VAUXP12/VAUXN12 */
#define R_AUX13         0x274 /* ADC out of VAUXP13/VAUXN13 */
#define R_CFR0          0x300 /* Configuration Register 0 */
#define R_CFR1          0x304 /* Configuration Register 1 */
#define R_CFR2          0x308 /* Configuration Register 2 */
#define R_SEQ00         0x320 /* Seq Reg 00 Adc Channel Selection */
#define R_SEQ01         0x324 /* Seq Reg 01 Adc Channel Selection */
#define R_SEQ02         0x328 /* Seq Reg 02 Adc Average Enable */
#define R_SEQ03         0x32C /* Seq Reg 03 Adc Average Enable */
#define R_SEQ04         0x330 /* Seq Reg 04 Adc Input Mode Select */
#define R_SEQ05         0x334 /* Seq Reg 05 Adc Input Mode Select */
#define R_SEQ06         0x338 /* Seq Reg 06 Adc Acquisition Time Select */
#define R_SEQ07         0x33C /* Seq Reg 07 Adc Acquisition Time Select */

void
axiSysmonInit(void)
{
    volatile int d;
    /*
     * Reset
     */
    Out32(R_SRR, 0x0A);
    for (d = 0 ; d < 8 ; d++);

    /*
     * 16-sample averaging
     */
    Out32(R_CFR0, 0x1000);

    /*
     * ADC to 5 MHz
     * DCLK = System clock / 2
     */
    Out32(R_CFR2, ((XPAR_PROC_BUS_0_FREQ_HZ/2)/5000000) << 8);

    /*
     * Cal, Temp, Vccint, Vccaux, VPVN, and no aux channels
     * Averaging on same
     * All channels unipolar
     * All channels standard acquisition time
     */
    Out32(R_SEQ00, 0x0F01);
    Out32(R_SEQ01, 0x0000);
    Out32(R_SEQ02, 0x0F01);
    Out32(R_SEQ03, 0x0000);
    Out32(R_SEQ04, 0x0000);
    Out32(R_SEQ05, 0x0000);
    Out32(R_SEQ06, 0x0000);
    Out32(R_SEQ07, 0x0000);

    /*
     * Continuous sampling, calibration on, no alarms
     */
    Out32(R_CFR1, 0x20FF);
}

void
axiSysmonReadADC(uint16_t *adc)
{
    adc[0] = In32(R_TEMP);    /* FPGA temperature */
    adc[1] = In32(R_VCCINT);  /* FPGA core voltage */
    adc[2] = In32(R_VCCAUX);  /* FPGA auxiliary voltage */
    adc[3] = In32(R_VPVN);    /* Board voltage */
}
