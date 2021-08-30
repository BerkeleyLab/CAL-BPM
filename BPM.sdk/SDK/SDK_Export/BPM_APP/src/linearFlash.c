/*
 * Linear flash access
 */

#include <stdio.h>
#include <xilflash.h>
#include <xparameters.h>
#include "linearFlash.h"
#include "util.h"

#define PAGESIZE    (128*1024)

static XFlash f;

int
linearFlashInit(void)
{
    int i;
    DeviceCtrlParam parms;

    i = XFlash_Initialize(&f, XPAR_LINEAR_FLASH_S_AXI_MEM0_BASEADDR, 2, 0);
    if (i != XST_SUCCESS)
        fatal1("XFlash_Initialize failed -- %d", i);
    i = XFlash_Reset(&f);
    if (i != XST_SUCCESS) {
        xil_printf("XFlash_Reset failed -- %d\r\n", i);
        return 0;
    }

    i = XFlash_DeviceControl(&f, XFL_DEVCTL_GET_PROPERTIES, &parms);
    if (i != XST_SUCCESS) {
        xil_printf("XFlash GET_PROPERTIES failed -- %d\r\n", i);
        return 0;
    }
    xil_printf("Flash Properties\n\r");
    xil_printf("    PartID.ManufacturerID = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->PartID.ManufacturerID);
    xil_printf("    PartID.DeviceID = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->PartID.DeviceID);
    xil_printf("    PartID.CommandSet = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->PartID.CommandSet);
    xil_printf("    TimeTypical.WriteSingle_Us = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeTypical.WriteSingle_Us);
    xil_printf("    TimeTypical.WriteBuffer_Us = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeTypical.WriteBuffer_Us);
    xil_printf("    TimeTypical.EraseBlock_Ms = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeTypical.EraseBlock_Ms);
    xil_printf("    TimeTypical.EraseChip_Ms = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeTypical.EraseChip_Ms);
    xil_printf("    TimeMax.WriteSingle_Us = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeMax.WriteSingle_Us);
    xil_printf("    TimeMax.WriteBuffer_Us = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeMax.WriteBuffer_Us);
    xil_printf("    TimeMax.EraseBlock_Ms = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeMax.EraseBlock_Ms);
    xil_printf("    TimeMax.EraseChip_Ms = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->TimeMax.EraseChip_Ms);
    xil_printf("    ProgCap.WriteBufferSize = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->ProgCap.WriteBufferSize);
    xil_printf("    ProgCap.WriteBufferAlignMask = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->ProgCap.WriteBufferAlignmentMask);
    xil_printf("    ProgCap.EraseQueueSize = 0x%x\n\r",
        parms.PropertiesParam.PropertiesPtr->ProgCap.EraseQueueSize);

    i = XFlash_DeviceControl(&f, XFL_DEVCTL_GET_GEOMETRY, &parms);
    if (i != XST_SUCCESS) {
        xil_printf("XFlash GET_GEOMETRY failed -- %d\r\n", i);
        return 0;
    }
    xil_printf("Flash Geometry\n\r");
    xil_printf("    BaseAddress = 0x%x\n\r",
                            parms.GeometryParam.GeometryPtr->BaseAddress);
    xil_printf("    MemoryLayout = 0x%x\n\r",
                            parms.GeometryParam.GeometryPtr->MemoryLayout);
    xil_printf("    DeviceSize = %d",
                            parms.GeometryParam.GeometryPtr->DeviceSize);
    if ((parms.GeometryParam.GeometryPtr->DeviceSize % (1024*1024)) == 0)
        xil_printf("  (%d MB)", parms.GeometryParam.GeometryPtr->DeviceSize/(1024*1024));
    xil_printf("\r\n");
    xil_printf("    NumEraseRegions = 0x%x\n\r",
                            parms.GeometryParam.GeometryPtr->NumEraseRegions);
    xil_printf("    NumBlocks = 0x%x\n\r",
                    parms.GeometryParam.GeometryPtr->NumBlocks);
    for(i = 0; i < parms.GeometryParam.GeometryPtr->NumEraseRegions; i++) {
        xil_printf("Erase region %d\n\r", i);
        xil_printf("    Absolute Offset = 0x%x\n\r",
            parms.GeometryParam.GeometryPtr->EraseRegion[i].AbsoluteOffset);
        xil_printf("    Absolute Block = 0x%x\n\r",
            parms.GeometryParam.GeometryPtr->EraseRegion[i].AbsoluteBlock);
        xil_printf("    Num Of Block = 0x%x\n\r",
            parms.GeometryParam.GeometryPtr->EraseRegion[i].Number);
        xil_printf("    Size Of Block = %d",
            parms.GeometryParam.GeometryPtr->EraseRegion[i].Size);
        if ((parms.GeometryParam.GeometryPtr->EraseRegion[i].Size % 1024) == 0)
            xil_printf("  (%d kB)", parms.GeometryParam.GeometryPtr->EraseRegion[i].Size / 1024);
        xil_printf("\r\n");
    }
    return 1;
}

int
linearFlashRead(unsigned int address, char *buf, unsigned int nBytes)
{
    int i;

    i = XFlash_Read(&f, address, nBytes, buf);
    if (i != XST_SUCCESS) {
        xil_printf("XFlash_Reade(0x%x,%d) failed: %d\r\n", address, nBytes, i);
        return -1;
    }
    return nBytes;
}

int
linearFlashWrite(unsigned int address, const char *buf, unsigned int nBytes)
{
    unsigned int loPage = address / PAGESIZE;
    unsigned int hiPage = (address + nBytes - 1) / PAGESIZE;
    int i;

    if (nBytes == 0)
        return 0;
    if (nBytes > PAGESIZE)
        return -1;
    if (((address % PAGESIZE) == 0) || (hiPage != loPage)) {
        i = XFlash_Unlock(&f, hiPage * PAGESIZE, PAGESIZE);
        if (i != XST_SUCCESS) {
            xil_printf("XFlash_Unlock page %d failed: %d\r\n", hiPage, i);
            return -1;
        }
        i = XFlash_Erase(&f, hiPage * PAGESIZE, PAGESIZE);
        if (i != XST_SUCCESS) {
            xil_printf("XFlash_Erase page %d failed: %d\r\n", hiPage, i);
            return -1;
        }
    }
    i = XFlash_Write(&f, address, nBytes, (char *)buf);
    if (i != XST_SUCCESS) {
        xil_printf("XFlash_Write(0x%x,%d) failed: %d\r\n", address, nBytes, i);
        return -1;
    }
    return nBytes;
}
