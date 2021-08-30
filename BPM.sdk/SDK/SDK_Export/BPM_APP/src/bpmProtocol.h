/*
 * Communication between BPM front end and IOC
 * We take the easy way out and assume the same endianness on both ends.
 */

#ifndef _BPM_PROTOCOL_H_
#define _BPM_PROTOCOL_H_

#ifdef __MICROBLAZE__
# include <stdint.h>
  typedef uint8_t  epicsUInt8;
  typedef int8_t   epicsInt8;
  typedef uint16_t epicsUInt16;
  typedef int16_t  epicsInt16;
  typedef uint32_t epicsUInt32;
  typedef int32_t  epicsInt32;
#else
# include <epicsTypes.h>
#endif

#define BPM_PROTOCOL_COMMAND_UDP_PORT        7073
#define BPM_PROTOCOL_PUBLISHER_UDP_PORT      7074

#define BPM_PROTOCOL_WAVEFORM_PAYLOAD_CAPACITY  1440
#define BPM_PROTOCOL_STRING_CAPACITY            24
#define BPM_PROTOCOL_FOFB_CAPACITY              512
#define BPM_PROTOCOL_RECORDER_COUNT             5

#define BPM_PROTOCOL_MAGIC_COMMAND           0xCAFE0001
#define BPM_PROTOCOL_MAGIC_REPLY             0xCAFE0002
#define BPM_PROTOCOL_MAGIC_SYSTEM_MONITOR    0xCAFE0003
#define BPM_PROTOCOL_MAGIC_SLOW_ACQUISITION  0xCAFE0004
#define BPM_PROTOCOL_MAGIC_WAVEFORM_HEADER   0xCAFE0005
#define BPM_PROTOCOL_MAGIC_WAVEFORM_DATA     0xCAFE0006
#define BPM_PROTOCOL_MAGIC_WAVEFORM_ACK      0xCAFE0007
#define BPM_PROTOCOL_MAGIC_FILTER_UPDATE     0xCAFE000A

/*
 * Subcommand structure
 */
#define BPM_PROTOCOL_GROUP_MASK     0x7F00
#define BPM_PROTOCOL_WRITE_MASK     0x8000

/*
 * General commands
 */
#define BPM_PROTOCOL_GROUP_IOPOINT  0x0000
#define BPM_PROTOCOL_COMMAND_IO_DEBUG         1
#define BPM_PROTOCOL_COMMAND_IO_ID            2
#define BPM_PROTOCOL_COMMAND_IO_ATTEN         3
#define BPM_PROTOCOL_COMMAND_IO_ADC_GAIN      4
#define BPM_PROTOCOL_COMMAND_IO_LOB_LIMIT     5
#define BPM_PROTOCOL_COMMAND_IO_AT_ENABLE     6
#define BPM_PROTOCOL_COMMAND_IO_AT_THRESH     7
#define BPM_PROTOCOL_COMMAND_IO_SELFTRIG_LEV  8
#define BPM_PROTOCOL_COMMAND_IO_BTN_DSP_ALG   9
#define BPM_PROTOCOL_COMMAND_IO_FPGA_RESET    10
#define BPM_PROTOCOL_COMMAND_IO_AT_FILTER     11
#define BPM_PROTOCOL_COMMAND_IO_LATCH_CLEAR   12
#define BPM_PROTOCOL_COMMAND_IO_TBT_SUM_SHIFT 13
#define BPM_PROTOCOL_COMMAND_IO_MT_SUM_SHIFT  14

/*
 * Waveform recorder commands
 * Least-significant 4 bits are recorder number
 */
#define BPM_PROTOCOL_GROUP_RECORDER 0x0100
#define BPM_PROTOCOL_COMMAND_WF_ARM                 0x00
#define BPM_PROTOCOL_COMMAND_WF_TRIGGER_MASK        0x10
#define BPM_PROTOCOL_COMMAND_WF_PRETRIGGER_COUNT    0x20
#define BPM_PROTOCOL_COMMAND_WF_ACQUISITION_COUNT   0x30
#define BPM_PROTOCOL_COMMAND_WF_ACQUISITION_MODE    0x40
#define BPM_PROTOCOL_COMMAND_WF_SOFT_TRIGGER        0x90

/*
 * Per-ADC values
 * Least-significant 4 bits are ADC channel number
 */
#define BPM_PROTOCOL_GROUP_PER_CHANNEL_VALUE  0x0200
#define BPM_PROTOCOL_COMMAND_CHANVAL_GAIN       0x00

/*
 * Event receiver event trigger enables (RAM setting)
 * Least-significant 8 bits are event number
 */
#define BPM_PROTOCOL_GROUP_EVENT_TRIGGERS  0x0300

/*
 * Event receiver trigger delays
 * Least-significant 3 bits are trigger number
 */
#define BPM_PROTOCOL_GROUP_TRIGGER_DELAY   0x0400

/*
 * Command packet
 */
struct bpmCommand {
    epicsUInt32 magic;
    epicsUInt32 commandNumber;
    epicsUInt16 code;
    epicsUInt16 pad;
    epicsUInt32 value;
};

/*
 * Response packets
 */
struct bpmReply {
    epicsUInt32 magic;
    epicsUInt32 commandNumber;
    union {
      epicsUInt32         value;
      char                str[BPM_PROTOCOL_STRING_CAPACITY];
    }                   u;
};

/*
 * Low speed system monitoring
 */
#define BPM_PROTOCOL_SECONDS_PER_MONITOR_UPDATE   2
#define BPM_PROTOCOL_ADC_COUNT               4
#define BPM_PROTOCOL_SFP_COUNT               6
#define BPM_PROTOCOL_FGPA_MONITOR_COUNT      4
#define BPM_PROTOCOL_DFE_TEMPERATURE_COUNT   4
#define BPM_PROTOCOL_AFE_TEMPERATURE_COUNT   8
#define BPM_PROTOCOL_AFE_POWER_COUNT         3
struct bpmSystemMonitor {
    epicsUInt32 magic;
    epicsUInt32 packetNumber;
    epicsUInt32 seconds;
    epicsUInt32 ticks;
    epicsUInt32 adcClkRate;
    epicsUInt16 fanRPM;
    epicsUInt8  adcClkDelay;
    epicsUInt8  duplicateIOC;
    epicsUInt16 fofbIndex;
    epicsUInt16 evrTooFew;
    epicsUInt16 evrTooMany;
    epicsUInt16 evrOutOfSeq;
    epicsUInt16 fpgaMonitor[BPM_PROTOCOL_FGPA_MONITOR_COUNT];
    epicsInt16  dfeTemperature[BPM_PROTOCOL_DFE_TEMPERATURE_COUNT];
    epicsInt16  afeTemperature[BPM_PROTOCOL_AFE_TEMPERATURE_COUNT];
    epicsUInt16 afeVoltage[BPM_PROTOCOL_AFE_POWER_COUNT];
    epicsUInt16 afeCurrent[BPM_PROTOCOL_AFE_POWER_COUNT];
    epicsInt16  sfpTemperature[BPM_PROTOCOL_SFP_COUNT];
    epicsUInt16 sfpRxPower[BPM_PROTOCOL_SFP_COUNT];
    epicsUInt32 crcFaultsCCW;
    epicsUInt32 crcFaultsCW;
};

/*
 * Slow acquisition (typically 10 Hz) monitoring
 */
struct bpmSlowAcquisition {
    epicsUInt32 magic;
    epicsUInt32 packetNumber;
    epicsUInt32 seconds;
    epicsUInt32 ticks;
    epicsUInt8  syncStatus;
    epicsUInt8  recorderStatus;
    epicsUInt8  clipStatus;
    epicsUInt8  cellCommStatus;
    epicsUInt8  autotrimStatus;
    epicsUInt8  sdSyncStatus;
    epicsUInt8  pad1;
    epicsUInt8  pad2;
    epicsUInt16 adcPeak[BPM_PROTOCOL_ADC_COUNT];
    epicsUInt32 rfMag[BPM_PROTOCOL_ADC_COUNT];
    epicsUInt32 ptLoMag[BPM_PROTOCOL_ADC_COUNT];
    epicsUInt32 ptHiMag[BPM_PROTOCOL_ADC_COUNT];
    epicsUInt32 gainFactor[BPM_PROTOCOL_ADC_COUNT];
    epicsInt32  xPos;
    epicsInt32  yPos;
    epicsInt32  skew;
    epicsInt32  buttonSum;
    epicsInt32  xRMSwide;
    epicsInt32  yRMSwide;
    epicsInt32  xRMSnarrow;
    epicsInt32  yRMSnarrow;
};

/*
 * Waveform transfer
 * When a waveform recorder completes acquisition it sends the header
 * unsolicited.  It then sends each block when requested.
 * The header is retransmitted if a block request does not arrive in a
 * reasonable interval.
 */
struct bpmWaveformHeader {
    epicsUInt32 magic;
    epicsUInt32 waveformNumber;
    epicsUInt16 recorderNumber;
    epicsUInt32 seconds;
    epicsUInt32 ticks;
    epicsUInt32 byteCount;
};
struct bpmWaveformData {
    epicsUInt32 magic;
    epicsUInt32 waveformNumber;
    epicsUInt32 recorderNumber;
    epicsUInt32 blockNumber;
    unsigned char payload[BPM_PROTOCOL_WAVEFORM_PAYLOAD_CAPACITY];
};
struct bpmWaveformAck {
    epicsUInt32 magic;
    epicsUInt32 waveformNumber;
    epicsUInt32 recorderNumber;
    epicsUInt32 blockNumber;
};

/*
 * Filter coeffiient update
 * The tricky expression on the array size is because
 * the filter coefficients are 36 bits each.
 */
#define BPM_PROTOCOL_COEFFICIENT_COUNT 300
struct bpmFilterCoefficients {
    struct bpmCommand header;
    epicsUInt32 coefficients[((BPM_PROTOCOL_COEFFICIENT_COUNT*9)+7)/8];
};

#endif /* _BPM_PROTOCOL_H_ */
