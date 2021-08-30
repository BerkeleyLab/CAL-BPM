/*
 * Manipulate AFE attenuators
 */

#ifndef _AFE_ATTEN_H_
#define _AFE_ATTEN_H_

void afeSetGainCompensation(int channel, int gain);
int afeGetGainCompensation(int channel);
void afeAttenSet(int dB);
int afeAttenGet(void);
int afeAttenGetTable(unsigned char *buf, int capacity);
int afeAttenSetTable(unsigned char *buf, int size);
void afeAttenReadback(const unsigned char *buf);

#endif
