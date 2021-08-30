/*
 * Get information from SFP modules
 */

#ifndef _SFP_H_
#define _SFP_H_

void sfpInit(void);
void sfpCheck(void);

const char * getSFPvendorName(int sfp);
const char * getSFPvendorPartNumber(int sfp);
const char * getSFPvendorSerialNumber(int sfp);
const char * getSFPvendorDateCode(int sfp);

int getSFPrxPower(int sfp);
int getSFPtemperature(int sfp);

#endif
