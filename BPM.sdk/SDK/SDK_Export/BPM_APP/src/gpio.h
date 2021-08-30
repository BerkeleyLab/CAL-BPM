/*
 * Indices into the big general purpose I/O block.
 * Used to generate Verilog parameter statements too, so be careful with
 * the syntax:
 *      Spaces only (no tabs).
 *      Register definitions must precede include statements.
 *      All defines before first include statement must be base-10 constants.
 * Remember to run createVerilogIDX.sh after making any changes here.
 */

#ifndef _GPIO_H_
#define _GPIO_H_

#define GPIO_IDX_COUNT 128

#define GPIO_IDX_LOTABLE_ADDRESS     3 // Local oscillator table write address
#define GPIO_IDX_LOTABLE_CSR         4 // Local oscillator tables
#define GPIO_IDX_SUM_SHIFT_CSR       5 // Accumulator scaling values

#define GPIO_IDX_ADC_10_PEAK         6 // Peak value of channel 1 and 0
#define GPIO_IDX_ADC_32_PEAK         7 // Peak value of channel 3 and 2
#define GPIO_IDX_SELFTRIGGER_CSR     8 // Self-triggering (and ADC clip status)

#define GPIO_IDX_EVR_FA_RELOAD      10 // Fast acquisition divider reload
#define GPIO_IDX_EVR_SA_RELOAD      11 // Slow acquisition divider reload

#define GPIO_IDX_BPM_CCW_CRC_FAULTS 12 // Count CRC faults on CCW link
#define GPIO_IDX_BPM_CW_CRC_FAULTS  13 // Count CRC faults on CW link

#define GPIO_IDX_AUTOTRIM_CSR       14 // Auto gain compensation control/status
#define GPIO_IDX_AUTOTRIM_THRESHOLD 15 // Auto gain compensation tone threshold
#define GPIO_IDX_ADC_GAIN_FACTOR_0  16 // Gain factor for ADC 0
#define GPIO_IDX_ADC_GAIN_FACTOR_1  17 // Gain factor for ADC 1
#define GPIO_IDX_ADC_GAIN_FACTOR_2  18 // Gain factor for ADC 2
#define GPIO_IDX_ADC_GAIN_FACTOR_3  19 // Gain factor for ADC 3

#define GPIO_IDX_POSITION_CALC_CSR  20 // Position calculation control/status
#define GPIO_IDX_POSITION_CALC_XCAL 21 // X calibration factor
#define GPIO_IDX_POSITION_CALC_YCAL 22 // Y calibration factor
#define GPIO_IDX_POSITION_CALC_QCAL 23 // Q calibration factor
#define GPIO_IDX_POSITION_CALC_SA_X 24 // Slow acquisition X position
#define GPIO_IDX_POSITION_CALC_SA_Y 25 // Slow acquisition Y position
#define GPIO_IDX_POSITION_CALC_SA_Q 26 // Slow acquisition skew
#define GPIO_IDX_POSITION_CALC_SA_S 27 // Slow acquisition sum

#define GPIO_IDX_SA_TIMESTAMP_SEC   30 // Slow acquisition time stamp
#define GPIO_IDX_SA_TIMESTAMP_TICKS 31 // Slow acquisition time stamp

#define GPIO_IDX_CELL_COMM_CSR      32 // Cell controller communication CSR
#define GPIO_IDX_CELL_FILTER_CSR    33 // Cell data stream filter CSR
#define GPIO_IDX_CELL_FILTER_DATA   34 // Cell data stream filters coefficients

#define GPIO_IDX_LOSS_OF_BEAM_THRSH 35 // Loss-of-beam threshold

#define GPIO_IDX_RMS_X_WIDE         36 // X motion (wideband)
#define GPIO_IDX_RMS_Y_WIDE         37 // Y motion (wideband)
#define GPIO_IDX_RMS_X_NARROW       38 // X motion (narrowband)
#define GPIO_IDX_RMS_Y_NARROW       39 // Y motion (narrowband)

#define GPIO_IDX_PRELIM_RF_MAG_0    40 // ADC 0 RF (SA) magnitude
#define GPIO_IDX_PRELIM_RF_MAG_1    41 // ADC 1 RF (SA) magnitude
#define GPIO_IDX_PRELIM_RF_MAG_2    42 // ADC 2 RF (SA) magnitude
#define GPIO_IDX_PRELIM_RF_MAG_3    43 // ADC 3 RF (SA) magnitude
#define GPIO_IDX_PRELIM_PT_LO_MAG_0 44 // ADC 0 low freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_LO_MAG_1 45 // ADC 1 low freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_LO_MAG_2 46 // ADC 2 low freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_LO_MAG_3 47 // ADC 3 low freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_HI_MAG_0 48 // ADC 0 high freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_HI_MAG_1 49 // ADC 1 high freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_HI_MAG_2 50 // ADC 2 high freq pilot tone magnitude
#define GPIO_IDX_PRELIM_PT_HI_MAG_3 51 // ADC 3 high freq pilot tone magnitude

#define GPIO_IDX_AFE_PLL_SPI        100 // SPI connection to AFE PLL
#define GPIO_IDX_AFE_REFCLK_CSR     101 // AFE PLL reference clock generator
#define GPIO_IDX_CLOCK_STATUS       102 // AFE (and other) clock status
#define GPIO_IDX_EVR_CLOCK_RATE     103 // EVR clock frequency
#define GPIO_IDX_AFE_CLOCK_RATE     104 // ADC clock frequency
#define GPIO_IDX_DFE_TEMP_1_0       105 // DFE temperatures 1 and 0
#define GPIO_IDX_DFE_TEMP_3_2       106 // DFE temperatures 3 and 2
#define GPIO_IDX_AFE_TEMP_1_0       107 // AFE temperatures 1 and 0
#define GPIO_IDX_AFE_TEMP_3_2       108 // AFE temperatures 3 and 2
#define GPIO_IDX_AFE_TEMP_5_4       109 // AFE temperatures 5 and 4
#define GPIO_IDX_AFE_TEMP_7_6       110 // AFE temperatures 7 and 6
#define GPIO_IDX_AFE_POWER_IV0      111 // AFE power monitor channel 0
#define GPIO_IDX_AFE_POWER_IV1      112 // AFE power monitor channel 1
#define GPIO_IDX_AFE_POWER_IV2      113 // AFE power monitor channel 2
#define GPIO_IDX_DFE_FAN_RPM        114 // DFE fan speed
#define GPIO_IDX_SFP_READ_CSR       115 // Initiate/monitor SFP readback
#define GPIO_IDX_SFP_READ_5_4       116 // Readback from SFP slots 5:4
#define GPIO_IDX_SFP_READ_3_2       117 // Readback from SFP slots 3:2
#define GPIO_IDX_SFP_READ_1_0       118 // Readback from SFP slots 1:0
#define GPIO_IDX_AFE_ATTEN          119 // Set AFE attenuator(s)
#define GPIO_IDX_ADC_CONTROL        120 // ADC control lines
#define GPIO_IDX_SYSCLK_COUNTER     121 // Count system clocks
#define GPIO_IDX_SECONDS_SINCE_BOOT 122 // Count 'seconds' (based on sysclk)
#define GPIO_IDX_FIRMWARE_DATE      123 // Firmware build date
#define GPIO_IDX_ADC_TRANSMIT_CSR   124 // ADC data transmission CSR
#define GPIO_IDX_SERIAL_NUMBERS     125 // AFE/DFE serial numbers

// Waveform recorders
// Capacities must be powers of two
#define GPIO_IDX_ADC_RECORDER_BASE  64  // ADC recorder
#define GPIO_IDX_TBT_RECORDER_BASE  70  // Turn-by-turn recorder
#define GPIO_IDX_FA_RECORDER_BASE   76  // Fast acquisition recorder
#define GPIO_IDX_PL_RECORDER_BASE   82  // Low pilot tone recorder
#define GPIO_IDX_PH_RECORDER_BASE   88  // High pilot tone recorder
#define GPIO_IDX_WFR_SOFT_TRIGGER   94  // Software trigger

#define GPIO_LO_RF_ROW_CAPACITY 1024
#define GPIO_LO_PT_ROW_CAPACITY 8192

#define GPIO_RECORDER_ADC_SAMPLE_CAPACITY 16*1024*1024
#define GPIO_RECORDER_TBT_SAMPLE_CAPACITY 4*1024*1024
#define GPIO_RECORDER_FA_SAMPLE_CAPACITY  4*1024*1024
#define GPIO_RECORDER_PT_SAMPLE_CAPACITY  1*1024*1024

#include <xil_io.h>
#include <xparameters.h>

#define GPIO_READ(i)    Xil_In32(XPAR_BPM_GPIB_0_S_AXI_MEM0_BASEADDR+(4*(i)))
#define GPIO_WRITE(i,x) Xil_Out32(XPAR_BPM_GPIB_0_S_AXI_MEM0_BASEADDR+(4*(i)),(x))

#define sysTicksSinceBoot() (GPIO_READ(GPIO_IDX_SYSCLK_COUNTER))
#define secondsSinceBoot()  (GPIO_READ(GPIO_IDX_SECONDS_SINCE_BOOT))

#endif
