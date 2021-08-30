/*
 * Deal with position calculation firmware
 */

#include <stdio.h>
#include <stdint.h>
#include "gpio.h"
#include "systemParameters.h"

/*
 * Operand selection
 * Dividend = (OP0 + OP1) - (OP2 + OP3)
 */
#define OP0_SHIFT 0
#define OP1_SHIFT 2
#define OP2_SHIFT 5
#define OP3_SHIFT 7
#define OP0(x)  ((x) << OP0_SHIFT)
#define OP1(x)  ((x) << OP1_SHIFT)
#define OP1_000  (4  << OP1_SHIFT)
#define OP2(x)  ((x) << OP2_SHIFT)
#define OP3(x)  ((x) << OP3_SHIFT)
#define OP3_000  (4  << OP3_SHIFT)
#define CALC_SHIFT 10

void
positionCalcInit(void)
{
    int buttonA = ((systemParameters.adcOrder / 1000) % 10) & 0x3;
    int buttonB = ((systemParameters.adcOrder / 100 ) % 10) & 0x3;
    int buttonC = ((systemParameters.adcOrder / 10  ) % 10) & 0x3;
    int buttonD = ((systemParameters.adcOrder       ) % 10) & 0x3;
    int xCalc, yCalc, qCalc;
    int xFactor, yFactor, qFactor;
    int rotationCompensation;

    if (systemParameters.buttonRotation == 0) {
        /*
         * Button orientation (looking downstream) is
         *             A
         *          D     B
         *             C
         *
         * +X is to the left
         * +Y is up
         *
         * Calibration factor must be multiplied by two because
         * this arrangement uses two buttons in the numerator, but
         * still uses four buttons in the denominator.
         */
        rotationCompensation = 2;
        xCalc = OP3_000      | OP2(buttonB) | OP1_000      | OP0(buttonD);
        yCalc = OP3_000      | OP2(buttonC) | OP1_000      | OP0(buttonA);
        qCalc = OP3(buttonD) | OP2(buttonB) | OP1(buttonC) | OP0(buttonA);
    }
    else {
        /*
         * Button orientation (looking downstream) is
         *
         *           A    B
         *
         *           D    C
         *
         * +X is to the left
         * +Y is up
         */
        rotationCompensation = 1;
        xCalc = OP3(buttonC) | OP2(buttonB) | OP1(buttonD) | OP0(buttonA);
        yCalc = OP3(buttonD) | OP2(buttonC) | OP1(buttonB) | OP0(buttonA);
        qCalc = OP3(buttonD) | OP2(buttonB) | OP1(buttonC) | OP0(buttonA);
    }
    xFactor = systemParameters.xCalibration * 1.0e6 * rotationCompensation;
    yFactor = systemParameters.yCalibration * 1.0e6 * rotationCompensation;
    qFactor = systemParameters.qCalibration * 1.0e6;
    GPIO_WRITE(GPIO_IDX_POSITION_CALC_CSR, ((qCalc << (2 * CALC_SHIFT)) |
                                            (yCalc <<      CALC_SHIFT)  |
                                            xCalc));
    GPIO_WRITE(GPIO_IDX_POSITION_CALC_XCAL, xFactor);
    GPIO_WRITE(GPIO_IDX_POSITION_CALC_YCAL, yFactor);
    GPIO_WRITE(GPIO_IDX_POSITION_CALC_QCAL, qFactor);
}
