/*
 * BPM/cell controller communication
 */

#ifndef _CELLCOMM_H_
#define _CELLCOMM_H_

void cellCommInit(void);
int cellCommStatus(void);
void cellCommSetFOFB(int fofbIndex);
int  cellCommGetFOFB(void);
unsigned int cellCommCRCfaultsCCW(void);
unsigned int cellCommCRCfaultsCW(void);
#endif

