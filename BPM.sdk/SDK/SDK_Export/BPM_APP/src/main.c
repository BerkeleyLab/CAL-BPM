#include <stdio.h>
#include <string.h>
#include <lwip/init.h>
#include <xparameters.h>
#include <netif/xadapter.h>
#include "platform.h"
#include "adcTransmit.h"
#include "afePLL.h"
#include "axiSysmon.h"
#include "cellComm.h"
#include "evr.h"
#include "gpio.h"
#include "linearFlash.h"
#include "positionCalc.h"
#include "publisher.h"
#include "server.h"
#include "sfp.h"
#include "systemParameters.h"
#include "tftp.h"
#include "util.h"
#include "waveformRecorder.h"

int
main(void)
{
    static struct ip_addr ipaddr, netmask, gw;
    static struct netif netif;

    /*
     * Set up infrastructure
     */
    init_platform();
    microblaze_enable_interrupts();
    setRevisionStrings();

    /* Announce our presence */
    xil_printf("\r\n");
    xil_printf("=====================================================\r\n");
    xil_printf("    Firmware built on %s\r\n", firmwareRevision);
    xil_printf("    Software built on %s\r\n", softwareRevision);
    xil_printf("=====================================================\r\n\n");

    /* Set up and read out flash memory */
    linearFlashInit();
    filesystemReadbacks();

    /* Continue initializing hardware */
    evrInit();
    afePLLinit();
    axiSysmonInit();
    printf("\n");
    sfpInit();
    positionCalcInit();
    wfrInit();

    /* Start network */
    printf("\nIf things lock up at this point it's likely because\n"
             "the network driver can't negotiate a connection.\n");
    ipaddr.addr = systemParameters.ipv4.address;
    netmask.addr = systemParameters.ipv4.netmask;
    gw.addr = systemParameters.ipv4.gateway;
    lwip_init();
    if (!xemac_add(&netif, &ipaddr, &netmask, &gw,
                    systemParameters.ethernetAddress, XPAR_ETHERNET_BASEADDR))
        fatal("Error adding network interface");
    netif_set_default(&netif);
    netif_set_up(&netif);
 
    /* Set up packet handlers */
    tftpInit();
    publisherInit();
    serverInit();

    /* Set up hardware */
    cellCommInit();
    adcTransmitInit();
    GPIO_WRITE(GPIO_IDX_LOSS_OF_BEAM_THRSH, 5000); /* Reasonable default */

    /* And away we go */
    printf("\nBPM running.\n");
    for (;;) {
        xemacif_input(&netif);
        checkForWork();
    }
}
