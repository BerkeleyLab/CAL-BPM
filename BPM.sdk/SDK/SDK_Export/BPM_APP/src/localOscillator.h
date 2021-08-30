/*
 * Manipulate local oscillator tables
 */

#ifndef _LOCAL_OSC_H_
#define _LOCAL_OSC_H_

int localOscGetRfTable(unsigned char *buf, int capacity);
int localOscSetRfTable(unsigned char *buf, int size);
void localOscRfReadback(const unsigned char *buf);
int localOscGetPtTable(unsigned char *buf, int capacity);
int localOscSetPtTable(unsigned char *buf, int size);
void localOscPtReadback(const unsigned char *buf);

int localOscGetDspAlgorithm(void);
void localOscSetDspAlgorithm(int useRMS);

int localOscGetRfTurnCount(void);
void localOscSetRfTurnCount(int turns);
int localOscGetPtTurnCount(void);
void localOscSetPtTurnCount(int turns);
int localOscGetSdSyncStatus(void);

int sdAccumulateGetTbtSumShift(void);
void sdAccumulateSetTbtSumShift(int shift);
int sdAccumulateGetMtSumShift(void);
void sdAccumulateSetMtSumShift(int shift);

#endif
