#ifndef _AXI_SYSMON_H_
#define _AXI_SYSMON_H_

#include <stdint.h>

#define AXI_SYSMON_ADC_COUNT    4

void axiSysmonInit(void);
void axiSysmonReadADC(uint16_t *adc);

#endif
