/*
 * Useful utility routines
 */

#ifndef _UTIL_H_
#define _UTIL_H_

#define DEBUGFLAG_SA_TIMING_CHECK               0x8000
#define DEBUGFLAG_FILTER_IMPULSE_RESPONSE  0x2000
#define DEBUGFLAG_ALTERNATE_FA_CHANNELS    0x1000
#define DEBUGFLAG_RECORDER_DIAG            0x800
#define DEBUGFLAG_WAVEFORM_XFER            0x400
#define DEBUGFLAG_WAVEFORM_HEAD            0x100
#define DEBUGFLAG_TFTP                     0x80
#define DEBUGFLAG_AUTOTRIM                 0x40
#define DEBUGFLAG_SERVER                   0x8
#define DEBUGFLAG_PUBLISHER                0x4
#define DEBUGFLAG_CELL_COMM                0x2
extern volatile int debugFlags;

#define MS_TO_SYSTICK(ms) (((XPAR_MICROBLAZE_FREQ)/1000)*(ms))

extern char firmwareRevision[];
extern char softwareRevision[];
void setRevisionStrings(void);

void checkForWork(void);
void criticalWarning(const char *msg);
void fatal(const char *msg);
void fatal1(const char *msg, int i);
void nanosecondSpin(unsigned int ns);
void showReg(int i);
char *trimStringRight(char *cp);
void uintPrint(unsigned int n);
void resetFPGA(void);

#endif
