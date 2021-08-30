/*
 * Auto-trim support
 */

#ifndef _AUTOTRIM_H_
#define _AUTOTRIM_H_ 1
#
#define AUTOTRIM_STATUS_DISABLED            0
#define AUTOTRIM_STATUS_NO_TONES            1
#define AUTOTRIM_STATUS_EXCESSIVE_VARIATION 2
#define AUTOTRIM_STATUS_SINGLE_SIDED        3
#define AUTOTRIM_STATUS_DOUBLE_SIDED        4

void         autotrimEnable(int flag);
void         autotrimUsePulsePilot(int flag);
int          autotrimStatus(void);
void         autotrimSetThreshold(unsigned int threshold);
unsigned int autotrimGetThreshold(void);
void         autotrimSetFilterShift(unsigned int filterShift);
unsigned int autotrimGetFilterShift(void);

#endif
