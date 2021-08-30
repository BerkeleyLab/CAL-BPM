/*
 * Linear flash access
 */

#ifndef _LINEAR_FLASH_H_
#define _LINEAR_FLASH_H_

int linearFlashInit(void);
int linearFlashRead(unsigned int address, char *buf, unsigned int nBytes);
int linearFlashWrite(unsigned int address, const char *buf, unsigned int nBytes);
void linearFlashEraseAll(void);

#endif
