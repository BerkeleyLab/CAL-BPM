/*
 * Cell data stream filter support
 */

#ifndef _CELL_STREAM_FILTER_H_
#define _CELL_STREAM_FILTER_H_

#include "bpmProtocol.h"

void cellStreamFilterUpdateCoefficients(struct bpmFilterCoefficients *pc);
void cellStreamFilterApplyDebugFlags(void);

#endif /* _CELL_STREAM_FILTER_H_ */
