/*
 * Manipulate the AFE PLL
 */

#ifndef _AFE_PLL_H
#define _AFE_PLL_H

void afePLLinit(void);
void afeLOsyncCheck(void);
void rescanAdcClkDelay(void);
int adcClkDelay(void);
void afeCheck(void);
void afePLLclearLatch(void);

#endif
