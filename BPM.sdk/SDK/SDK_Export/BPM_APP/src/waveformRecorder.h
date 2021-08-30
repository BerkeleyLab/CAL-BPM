/*
 * Waveform recorders
 */

#ifndef _WAVEFORMRECORDER_H_
#define _WAVEFORMRECORDER_H_

#include <lwip/pbuf.h>
#include "bpmProtocol.h"

void wfrInit(void);

void waveformRecorderCommand(const struct bpmCommand *cmd, struct bpmReply *reply);

struct pbuf *wfrAckPacket(struct bpmWaveformAck *ackp);
struct pbuf *wfrCheckForWork(void);
int wfrStatus(void);

#endif
