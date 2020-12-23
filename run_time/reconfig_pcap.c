/*
 * reconfig_pcap.c
 *
 *  Created on: 09/04/2014
 *      Author: Alfonso
 *  Modified on: 06/03/2018
 *  	Author: Rafa
 */


/***************************** Include Files ********************************/
#include "reconfig_pcap.h"
#include "ff.h"
#include "string.h"
#include "xtime_l.h"
#include "xstatus.h"
#include "xil_assert.h"
#include "xil_cache.h"

// FPGA description file
#include "xc7z020.h"
#include "series7.h"


/************************** Constant Definitions ****************************/
#define READ_BLOCK_SIZE 512  // Block size in bytes when reading from file
#define READ_FRAME_SIZE 256  // Buffer size to store configuration header and tail

// SLCR registers
#define SLCR_LOCK   0xF8000004        // SLCR Write Protection Lock
#define SLCR_UNLOCK 0xF8000008        // SLCR Write Protection Unlock
#define SLCR_PCAP_CLK_CTRL 0xF8000168 // SLCR PCAP clock control register

#define SLCR_LOCK_VAL   0x767B
#define SLCR_UNLOCK_VAL 0xDF0D

#define PCAP_CLK_RW                 // If defined, PCAP has different divisor in reading and writing processes
#define PCAP_CLK_DIVISOR_READ 0x0A  // PCAP clock divisor when reading (6bits)
#define PCAP_CLK_DIVISOR_WRITE 0x05 // PCAP clock divisor when writing (6bits)
#define PCAP_CLK_DIVISOR 0x0A       // PCAP clock divisor (6bits)
#define PCAP_CLK_SOURCE 0x0         // PCAP clock source (0b00 -> IO PLL@1000Hz; 0b10 -> ARM PLL@1333Hz; 0b11 -> DDR PLL@1067Hz)

//#define PCAP_TIMING // If defined, elapsed times will be computed
#ifdef PCAP_TIMING
#include "stdio.h" // Include printf(...) function
#endif // #ifdef PCAP_TIMING


/************************** Function Prototypes *****************************/

/****************************************************************************/
/**
*
* Loads a partial bitstream file from the external SD card to the on-board RAM
*
* @param file_name is the name of the PBS file stored in the SD card
* @param addr_start is the initial position of the PBS in the RAM
*
* @return final position of the PBS in the RAM
*
*****************************************************************************/
u32 load_bitstream_from_SD_to_RAM(const char *file_name, u32 *addr_start) 
{
  // Local variables
    u32 Index;
    UINT bytes;		  // Byte count (memory positions)
    u32 *buffer;      // Pointer to memory region in which PBS is to be stored
    FATFS fatfs;      // FAT file system
    FIL file;         // Partial bitstream file
    FRESULT rc;       // File management status
    int i;            // Loop variable
    u32 aux;          // Intermediate variable to perform swapping operations

#ifdef PCAP_TIMING
    XTime time;       // Elapsed time local variable
    XTime_SetTime(0); // Initialize time count
#endif // #ifdef PCAP_TIMING

    // Mount FAT file system
    rc = f_mount (&fatfs, "", 1); //We open the default drive
    if(rc)
    {
        xil_printf("ERROR %02d: FAT file system not mounted\n", rc);
        return 0;
    }

    // Open input file
    rc = f_open(&file, file_name, FA_READ);
    if(rc)
    {
        xil_printf("ERROR %02d: File %s not opened\n", rc, file_name);
        return 0;
    }

    // Initialize variables
    Index = (u32)addr_start;
    buffer = addr_start;

    // Load partial bitstream into memory
    while(!f_eof(&file))
    {
        // Read block from file
        f_read(&file, buffer, READ_BLOCK_SIZE, &bytes);
        // Increment index
        Index += bytes;
        // Move buffer pointer
        buffer += (bytes/sizeof(u32));
    }

    // Reorder wrong byte endianness
    buffer = addr_start;
    for(i = 0; i < ((Index - (int)addr_start)/sizeof(u32)); i++)
    {
        aux = ((buffer[i] & 0xFF) << 24) + ((buffer[i] & 0xFF00) << 8) + ((buffer[i] & 0xFF0000) >> 8) + ((buffer[i] & 0xFF000000) >> 24);
        buffer[i] = aux;
    }

    // Close input file
    rc = f_close(&file);
    if(rc)
    {
        xil_printf("ERROR %02d: File %s not closed\n", rc, file_name);
        return 0;
    }

    // Unmount FAT file system
    rc = f_mount(0, "", 0);
    if(rc)
    {
        xil_printf("ERROR %02d: FAT file system not unmounted\n", rc);
        return 0;
    }

#ifdef PCAP_TIMING
    XTime_GetTime(&time); // Get time count
    printf("SD2RAM elapsed time:              %12.3f us (%10.0f cycles @ %7.3f MHz)\n", ((float)time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)time, (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
#endif // #ifdef PCAP_TIMING

    // Return number of bytes that has been read
    return Index;
}

/****************************************************************************/
/**
*
* Stores a partial bitstream file from the on-board RAM to the external SD card
*
* @param file_name is the name of the PBS file to be stored in the SD card
* @param addr_start is the initial position of the PBS in the RAM
* @param TotalWords is the amount of configuration words that the PBS contains
*
* @return final position of the PBS in the RAM
*
*****************************************************************************/
u32 load_bitstream_from_RAM_to_SD(const char *file_name, u32 *addr_start, u32 TotalWords)
{
  // Local variables
UINT bytes;        // Byte count (memory positions)
  u32 *buffer;      // Pointer to memory region in which PBS is to be stored
  FATFS fatfs;      // FAT file system
  FIL file;         // Partial bitstream file
  FRESULT rc;       // File management status
  int i;            // Loop variable
  u32 aux;          // Intermediate variable to perform swapping operations


#ifdef PCAP_TIMING
  XTime time;       // Elapsed time local variable
  XTime_SetTime(0); // Initialize time count
#endif // #ifdef PCAP_TIMING

  // Mount FAT file system
  rc = f_mount (&fatfs, "", 1); //We open the default drive
  if(rc)
  {
      xil_printf("ERROR %02d: FAT file system not mounted\n", rc);
      return 0;
  }

  // Open output file
  rc = f_open(&file, file_name, FA_CREATE_ALWAYS | FA_WRITE);
  if(rc)
  {
      xil_printf("ERROR %02d: File %s not opened\n", rc, file_name);
      return 0;
  }

  // Initialize variables
  buffer = addr_start;

  // Write partial bitstream to SD
  for(i = 0; i < TotalWords; i++)
  {
      // Reorder wrong byte endianness
      aux = ((buffer[i] & 0xFF) << 24) + ((buffer[i] & 0xFF00) << 8) + ((buffer[i] & 0xFF0000) >> 8) + ((buffer[i] & 0xFF000000) >> 24);
      // Write to file
      rc = f_write(&file, &aux, sizeof(u32), &bytes);
      if(rc)
  {
    xil_printf("ERROR %02d: data %s not written\n", rc, file_name);
    return 0;
  }
  }

  // Close input file
  rc = f_close(&file);
  if(rc)
  {
      xil_printf("ERROR %02d: File %s not closed\n", rc, file_name);
      return 0;
  }

  // Unmount FAT file system
  rc = f_mount(0, "", 0);
  if(rc)
  {
      xil_printf("ERROR %02d: FAT file system not unmounted\n", rc);
      return 0;
  }

#ifdef PCAP_TIMING
  XTime_GetTime(&time); // Get time count
  printf("RAM2SD elapsed time:              %12.3f us (%10.0f cycles @ %7.3f MHz)\n", ((float)time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)time, (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
#endif // #ifdef PCAP_TIMING

  return 1;
}

/****************************************************************************/
/**
*
* Initializes PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance to be configured
* @param DeviceId is the ID of the DEVCFG device
*
* @return   XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_Initialize(XDcfg *InstancePtr, u16 DeviceId)
{
    int Status;
    u32 StatusReg;

    XDcfg_Config *ConfigPtr;

    // Initialize the Device Configuration Interface driver
    ConfigPtr = XDcfg_LookupConfig(DeviceId);

    // This is where the virtual address would be used, this example uses physical address
    Status = XDcfg_CfgInitialize(InstancePtr, ConfigPtr, ConfigPtr->BaseAddr);
    if (Status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    Status = XDcfg_SelfTest(InstancePtr);
    if (Status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }

    // Select PCAP interface for partial reconfiguration
    XDcfg_EnablePCAP(InstancePtr);
    XDcfg_SetControlRegister(InstancePtr, XDCFG_CTRL_PCAP_PR_MASK);

    // Clear the interrupt status bits
    //XDcfg_IntrDisable(InstancePtr, XDCFG_IXR_ALL_MASK);
    XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

    // Check if DMA command queue is full
    StatusReg = XDcfg_ReadReg(InstancePtr->Config.BaseAddr, XDCFG_STATUS_OFFSET);
    if ((StatusReg & XDCFG_STATUS_DMA_CMD_Q_F_MASK) == XDCFG_STATUS_DMA_CMD_Q_F_MASK)
    {
        return XST_FAILURE;
    }

#ifndef PCAP_CLK_RW
    // Change PCAP clock configuration
    *(volatile u32*)(SLCR_UNLOCK) = SLCR_UNLOCK_VAL;
    *(volatile u32*)(SLCR_PCAP_CLK_CTRL) = ((PCAP_CLK_DIVISOR & 0x3F) << 8) | ((PCAP_CLK_SOURCE & 0x3) << 4) | 0x1;
    *(volatile u32*)(SLCR_LOCK) = SLCR_LOCK_VAL;
#endif // #ifndef PCAP_CLK_RW

    return XST_SUCCESS;
}

/****************************************************************************/
/**
*
* Writes PBS file using PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance.
* @param addr_ini is a pointer to the frame that is to be written to the device
* @param addr_end is the value of the last memory position of the PBS
* @param x0, y0, xf, yf are the coordinates of the region to be reconfigured
*
* @return   XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_RAM_write(XDcfg *InstancePtr, u32 *addr_start, u32 addr_end, u32 x0, u32 y0, u32 xf, u32 yf, u32 erase_bram)
{
	u32 Index =0;
	u32 Packet;
    u32 Data;
    u32 TotalWords;
    int Status;
    static u32 WriteBuffer[READ_FRAME_SIZE];
    volatile u32 IntrStsReg = 0;

#ifdef PCAP_TIMING
    XTime time, transfer; // Elapsed time local variable
    XTime_SetTime(0);     // Initialize time count
#endif // #ifdef PCAP_TIMING

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
    Xil_AssertNonvoid(addr_start != NULL);

#ifdef PCAP_CLK_RW
    // Change PCAP clock configuration
    *(volatile u32*)(SLCR_UNLOCK) = SLCR_UNLOCK_VAL;
    *(volatile u32*)(SLCR_PCAP_CLK_CTRL) = ((PCAP_CLK_DIVISOR_WRITE & 0x3F) << 8) | ((PCAP_CLK_SOURCE & 0x3) << 4) | 0x1;
    *(volatile u32*)(SLCR_LOCK) = SLCR_LOCK_VAL;
#endif // #ifdef PCAP_CLK_RW

    // Bus Width, DUMMY and SYNC
    WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
    WriteBuffer[Index++] = PCAP_BW_SYNC;
    WriteBuffer[Index++] = PCAP_BW_DETECT;
    WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
    WriteBuffer[Index++] = PCAP_SYNC_PACKET;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;

    // Reset CRC
    Packet = PCAP_Type1Write(PCAP_CMD) | 1;
    Data = PCAP_CMD_RCRC;
    WriteBuffer[Index++] = Packet;
    WriteBuffer[Index++] = Data;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;

    // ID register
    Packet = PCAP_Type1Write(PCAP_IDCODE) | 1;
    Data = PCAP_IDCODE_NUMBER;
    WriteBuffer[Index++] = Packet;
    WriteBuffer[Index++] = Data;

    // Repeat for each clock region
    u32 *addr_send = addr_start;
    int x, y;
    for(y = y0; y <= yf; y++)
    {
        // Setup CMD register - write configuration
        Packet = PCAP_Type1Write(PCAP_CMD) | 1;
        Data = PCAP_CMD_WCFG;
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = Data;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Setup FAR
        Packet = PCAP_Type1Write(PCAP_FAR) | 1;
        Data = PCAP_SetupFar7S((fpga[y][x0][0] & (0xFF << 24))>>24, PCAP_FAR_CLB_BLOCK, (fpga[y][x0][0] & (0xFF << 16))>>16, x0, 0);
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = Data;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Setup Packet header
        TotalWords = 0;
        for(x = x0; x <= xf; x++)
        {
            TotalWords += (fpga[y][x][0] & 0xFFFF) * NUM_FRAME_WORDS;
        }
        TotalWords += NUM_FRAME_WORDS;//We add a padding frame

        if (TotalWords < PCAP_TYPE_1_PACKET_MAX_WORDS)
        {
            // Create Type 1 Packet
            Packet = PCAP_Type1Write(PCAP_FDRI) | TotalWords;
            WriteBuffer[Index++] = Packet;
        }
        else
        {
            // Create Type 2 Packet
            Packet = PCAP_Type1Write(PCAP_FDRI);
            WriteBuffer[Index++] = Packet;

            Packet = PCAP_TYPE_2_WRITE | TotalWords;
            WriteBuffer[Index++] = Packet;
        }

#ifdef PCAP_TIMING
        XTime_GetTime(&time); // Get time count
#endif // #ifdef PCAP_TIMING

        // Write header data.
        Xil_DCacheFlushRange(WriteBuffer, Index*4);
        Status = XDcfg_Transfer(InstancePtr, WriteBuffer, Index, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
        if (Status != XST_SUCCESS)
        {
            return XST_FAILURE;
        }
        // Poll IXR_DMA_DONE
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
        {
            IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }
        // Poll IXR_D_P_DONE
        while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
        {
            IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }

#ifdef PCAP_TIMING
        XTime_GetTime(&transfer); // Get time count
        printf("Write header elapsed time:        %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
        printf("PCAP Bandwidth:                   %12.3f MB/s\n", ((float)Index*4)/((float)(transfer-time)*1000000/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)));
#endif // #ifdef PCAP_TIMING

        // Clear the interrupt status bits
        XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

#ifdef PCAP_TIMING
        XTime_GetTime(&time); // Get time count
#endif // #ifdef PCAP_TIMING

        // Write the frame data.
        Xil_DCacheFlushRange(addr_send, TotalWords*4);
        Status = XDcfg_Transfer(InstancePtr, addr_send, TotalWords, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
        if (Status != XST_SUCCESS)
        {
            return XST_FAILURE;
        }
        // Poll IXR_DMA_DONE
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
        {
            IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }
        // Poll IXR_D_P_DONE
        while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
        {
            IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }

#ifdef PCAP_TIMING
        XTime_GetTime(&transfer); // Get time count
        printf("Write frame data elapsed time:    %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
        printf("PCAP Bandwidth:                   %12.3f MB/s\n", ((float)TotalWords*4)/((float)(transfer-time)*1000000/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)));
#endif // #ifdef PCAP_TIMING

        // Clear the interrupt status bits
        XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

        // Reset command buffer index
        Index = 0;

        // Increment initial address
        addr_send = (u32*) ((u32) addr_send + (TotalWords  * BYTES_PER_WORD_OF_FRAME));

        // Security check. We add a padding frame to the addr end
        if((u32)addr_send > (addr_end + NUM_FRAME_WORDS*BYTES_PER_WORD_OF_FRAME))
        {
        	return XST_FAILURE;
        }
    }

    // Erase BRAM contents if required
    if (erase_bram == PCAP_BRAM_ERASE) {
        u32 null_frame[128*NUM_FRAME_WORDS];
        for (Index = 0; Index < 128; Index++) null_frame[Index] = 0;
        Index = 0;
        // Repeat for each clock region
        for (y = y0; y <= yf; y++)
        {
            // Repeat for each column
            for (x = x0; x <= xf; x++)
            {
                // Check if the column is a BRAM column
                if (((fpga_bram[y][x] & 0xFFFF0000)>>16) == BRAM_CONTENT) {
                    // Setup CMD register - write configuration
                    Packet = PCAP_Type1Write(PCAP_CMD) | 1;
                    Data = PCAP_CMD_WCFG;
                    WriteBuffer[Index++] = Packet;
                    WriteBuffer[Index++] = Data;
                    WriteBuffer[Index++] = PCAP_NOOP_PACKET;

                    // Setup FAR
                    Packet = PCAP_Type1Write(PCAP_FAR) | 1;
                    Data = PCAP_SetupFar7S((fpga[y][x][0] & (0xFF << 24))>>24, PCAP_FAR_BRAM_BLOCK, (fpga[y][x][0] & (0xFF << 16))>>16, fpga_bram[y][x] & 0xFFFF, 0);
                    WriteBuffer[Index++] = Packet;
                    WriteBuffer[Index++] = Data;
                    WriteBuffer[Index++] = PCAP_NOOP_PACKET;

                    // Setup Packet header
                    TotalWords = 128 * NUM_FRAME_WORDS;
                    if (TotalWords < PCAP_TYPE_1_PACKET_MAX_WORDS)
                    {
                        // Create Type 1 Packet
                        Packet = PCAP_Type1Write(PCAP_FDRI) | TotalWords;
                        WriteBuffer[Index++] = Packet;
                    }
                    else
                    {
                        // Create Type 2 Packet
                        Packet = PCAP_Type1Write(PCAP_FDRI);
                        WriteBuffer[Index++] = Packet;

                        Packet = PCAP_TYPE_2_WRITE | TotalWords;
                        WriteBuffer[Index++] = Packet;
                    }

                    // Write header data.
                    Xil_DCacheFlushRange(WriteBuffer, Index*4);
                    Status = XDcfg_Transfer(InstancePtr, WriteBuffer, Index, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
                    if (Status != XST_SUCCESS)
                    {
                        return XST_FAILURE;
                    }
                    // Poll IXR_DMA_DONE
                    IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
                    {
                        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    }
                    // Poll IXR_D_P_DONE
                    while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
                    {
                        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    }

                    // Clear the interrupt status bits
                    XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

                    // Write the frame data.
                    Xil_DCacheFlushRange(null_frame, TotalWords*4);
                    Status = XDcfg_Transfer(InstancePtr, null_frame, TotalWords, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
                    if (Status != XST_SUCCESS)
                    {
                        return XST_FAILURE;
                    }
                    // Poll IXR_DMA_DONE
                    IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
                    {
                        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    }
                    // Poll IXR_D_P_DONE
                    while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
                    {
                        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
                    }

                    // Clear the interrupt status bits
                    XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

                    // Reset command buffer index
                    Index = 0;
                }
            }
        }
    }

    // Add CRC
    Packet = PCAP_Type1Write(PCAP_CMD) | 1;
    Data = PCAP_CMD_RCRC;
    WriteBuffer[Index++] = Packet;
    WriteBuffer[Index++] = Data;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;
    WriteBuffer[Index++] = PCAP_NOOP_PACKET;

    // DESYNC
    Packet = (PCAP_Type1Write(PCAP_CMD) | 1);
    Data = PCAP_CMD_DESYNCH;
    WriteBuffer[Index++] = Packet;
    WriteBuffer[Index++] = Data;
    WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
    WriteBuffer[Index++] = PCAP_DUMMY_PACKET;

#ifdef PCAP_TIMING
    XTime_GetTime(&time); // Get time count
#endif // #ifdef PCAP_TIMING

    // Write the frame data.
    Xil_DCacheFlushRange(WriteBuffer, Index*4);
    Status = XDcfg_Transfer(InstancePtr, WriteBuffer, Index, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
    if (Status != XST_SUCCESS)
    {
        return XST_FAILURE;
    }
    // Poll IXR_DMA_DONE
    IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
    while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
    {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
    }
    // Poll IXR_D_P_DONE
    while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
    {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
    }

#ifdef PCAP_TIMING
    XTime_GetTime(&transfer); // Get time count
    printf("Write tail elapsed time:          %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
    printf("PCAP Bandwidth:                   %12.3f MB/s\n", ((float)Index*4)/((float)(transfer-time)*1000000/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)));
#endif // #ifdef PCAP_TIMING

    // Clear the interrupt status bits
    XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

#ifdef PCAP_TIMING
    XTime_GetTime(&time); // Get time count
    printf("PCAP_DeviceWritePBS elapsed time: %12.3f us (%10.0f cycles @ %7.3f MHz)\n", ((float)time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)time, (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
#endif // #ifdef PCAP_TIMING

    return XST_SUCCESS;
}

/****************************************************************************/
/**
*
* Reads PBS file using PCAP interface
*
* @param InstancePtr is a pointer to the PCAP instance.
* @param addr_ini is a pointer to the memory addres that will store data read from the device
* @param TotalWords is total amount of words that the PCAP has to read
* @param x0, y0, xf, yf are the coordinates of the region to be reconfigured
*
* @return   XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int PCAP_RAM_read(XDcfg *InstancePtr, u32 **addr_start, u32 x0, u32 y0, u32 xf, u32 yf)
{
    u32 Packet;
    u32 Data;
    int Status;
    static u32 WriteBuffer[READ_FRAME_SIZE];
    u32 Index = 0;
    volatile u32 IntrStsReg = 0;
    u32 TotalWords = 0;

#ifdef PCAP_TIMING
    XTime time, transfer; // Elapsed time local variable
    XTime_SetTime(0);     // Initialize time count
#endif // #ifdef PCAP_TIMING

    Xil_AssertNonvoid(InstancePtr != NULL);
    Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
    Xil_AssertNonvoid(*addr_start != NULL);

#ifdef PCAP_CLK_RW
    // Change PCAP clock configuration
    *(volatile u32*)(SLCR_UNLOCK) = SLCR_UNLOCK_VAL;
    *(volatile u32*)(SLCR_PCAP_CLK_CTRL) = ((PCAP_CLK_DIVISOR_READ & 0x3F) << 8) | ((PCAP_CLK_SOURCE & 0x3) << 4) | 0x1;
    *(volatile u32*)(SLCR_LOCK) = SLCR_LOCK_VAL;
#endif // #ifdef PCAP_CLK_RW

    // Repeat for each clock region
    int x, y;
    for(y = y0; y <= yf; y++)
    {
        // Bus Width, DUMMY and SYNC
        WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
        WriteBuffer[Index++] = PCAP_BW_SYNC;
        WriteBuffer[Index++] = PCAP_BW_DETECT;
        WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
        WriteBuffer[Index++] = PCAP_SYNC_PACKET;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Reset CRC
        Packet = PCAP_Type1Write(PCAP_CMD) | 1;
        Data = PCAP_CMD_RCRC;
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = Data;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Setup CMD register to read configuration
        Packet = PCAP_Type1Write(PCAP_CMD) | 1;
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = PCAP_CMD_RCFG;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Setup FAR register
        Packet = PCAP_Type1Write(PCAP_FAR) | 1;
        Data = PCAP_SetupFar7S((fpga[y][x0][0] & (0xFF << 24))>>24, PCAP_FAR_CLB_BLOCK, (fpga[y][x0][0] & (0xFF << 16))>>16, x0, 0);
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = Data;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // Set up packet header
        TotalWords = NUM_FRAME_WORDS;
        for(x = x0; x <= xf; x++)
        {
            TotalWords += (fpga[y][x][0] & 0xFFFF) * NUM_FRAME_WORDS;
        }
        if (TotalWords < PCAP_TYPE_1_PACKET_MAX_WORDS)
        {
            // Create Type 1 Packet
            Packet = PCAP_Type1Read(PCAP_FDRO) | TotalWords;
            WriteBuffer[Index++] = Packet;
        }
        else
        {
            // Create Type 2 Packet
            Packet = PCAP_Type1Read(PCAP_FDRO);
            WriteBuffer[Index++] = Packet;

            Packet = PCAP_TYPE_2_READ | TotalWords;
            WriteBuffer[Index++] = Packet;
        }
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;
        WriteBuffer[Index++] = PCAP_NOOP_PACKET;

        // DESYNC
        Packet = (PCAP_Type1Write(PCAP_CMD) | 1);
        Data = PCAP_CMD_DESYNCH;
        WriteBuffer[Index++] = Packet;
        WriteBuffer[Index++] = Data;
        WriteBuffer[Index++] = PCAP_DUMMY_PACKET;
        WriteBuffer[Index++] = PCAP_DUMMY_PACKET;

        /* 2 explicit DMA transfers */

#ifdef PCAP_TIMING
        XTime_GetTime(&time); // Get time count
#endif // #ifdef PCAP_TIMING

        Xil_DCacheFlushRange(WriteBuffer, Index*4);
        Status = XDcfg_Transfer(InstancePtr, WriteBuffer, Index, (u32*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
        //Status = XDcfg_Transfer(InstancePtr, WriteBuffer, Index, (u8*) XDCFG_DMA_INVALID_ADDRESS, 0, XDCFG_NON_SECURE_PCAP_WRITE);
        if (Status != XST_SUCCESS)
        {
        return XST_FAILURE;
        }
        // Poll IXR_DMA_DONE
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
        {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }
        // Poll IXR_D_P_DONE
        while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
        {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }

#ifdef PCAP_TIMING
        XTime_GetTime(&transfer); // Get time count
        printf("DMA write transfer elapsed time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
        printf("PCAP Bandwidth:                   %12.3f MB/s\n", ((float)Index*4)/((float)(transfer-time)*1000000/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)));
        XTime_GetTime(&time); // Get time count
#endif // #ifdef PCAP_TIMING

        // Clear the interrupt status bits
        XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));




        Status = XDcfg_Transfer(InstancePtr, (u32*) XDCFG_DMA_INVALID_ADDRESS, TotalWords, *addr_start, TotalWords, XDCFG_NON_SECURE_PCAP_WRITE);
        //Status = XDcfg_Transfer(InstancePtr, (u8*) XDCFG_DMA_INVALID_ADDRESS, TotalWords, 0, TotalWords, XDCFG_NON_SECURE_PCAP_WRITE);
        Xil_DCacheInvalidateRange(*addr_start, TotalWords*4);
        if (Status != XST_SUCCESS)
        {
        return XST_FAILURE;
        }
        // Poll IXR_DMA_DONE
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);

        while ((IntrStsReg & XDCFG_IXR_DMA_DONE_MASK) != XDCFG_IXR_DMA_DONE_MASK)
        {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }
        // Poll IXR_D_P_DONE
        while ((IntrStsReg & XDCFG_IXR_D_P_DONE_MASK) != XDCFG_IXR_D_P_DONE_MASK)
        {
        IntrStsReg = XDcfg_IntrGetStatus(InstancePtr);
        }

#ifdef PCAP_TIMING
        XTime_GetTime(&transfer); // Get time count
        printf("DMA read transfer elapsed time:   %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
        printf("PCAP Bandwidth:                   %12.3f MB/s\n", ((float)TotalWords*4)/((float)(transfer-time)*1000000/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)));
#endif // #ifdef PCAP_TIMING


        // Clear the interrupt status bits
        XDcfg_IntrClear(InstancePtr, (XDCFG_IXR_PCFG_DONE_MASK | XDCFG_IXR_D_P_DONE_MASK | XDCFG_IXR_DMA_DONE_MASK));

        /* 2 explicit DMA transfers */

        // Erase NULL frame
        memmove(*addr_start, *addr_start+NUM_FRAME_WORDS, (TotalWords-NUM_FRAME_WORDS)*BYTES_PER_WORD_OF_FRAME);
        // Reset command buffer index
        Index = 0;
        // Increment initial address
        *addr_start = (u32*) ((u32) *addr_start + (TotalWords- (u32) NUM_FRAME_WORDS) * BYTES_PER_WORD_OF_FRAME);
    }

#ifdef PCAP_TIMING
    XTime_GetTime(&time); // Get time count
    printf("PCAP_DeviceReadPBS elapsed time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", ((float)time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)time, (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
#endif // #ifdef PCAP_TIMING

    return XST_SUCCESS;
}



/****************************************************************************/
/**
*
* Writes a bitstream in a region defined as an array of rectangular pblocks
* defined by the structs pblock which contains X0, Y0, Xf and Yf coordinates.
* The heigh of the region to allocate the bitstream can be less than a clock
* region height.
*
* NOTE: Although the resulting region to reconfigure can be non rectangular
* it is necessary that each pblock that compone the area is rectangular
* i.e. it has to contain whole RAM and DSP tiles
*
* @param InstancePtr: is a pointer to the PCAP instance.
* @param addr_start: is a pointer to free memory address. NOTE This memory needs
* to be big enough to read the partial bitstream of the region to reallocate
* (with the whole frame height) and to write on top of that the new partial
* bitstream
* @param file_name: name of the bitstream file located in the SD wich will be
* reconfigured
* @param pblock_list[] array with the pblock where the bitstream will be
* reconfigured
* @param num_pblocks total number of pblocks in the array.
* @param erase_bram boolean. Erase BRAM contents if required.
* @param stacked_modules : this value can be used when reconfiguring several
* modules that are stacked in the same columns. If this parameter is set to 0
* then the RE has its normal behaviour. If set to 1, then only the readback and
* bitstream combination is performed. If set to 2 then, only the combination is
* performed. Lastly, if set to 3 only the combination and the write operation
* are performed.
*
*
* @return XST_SUCCESS else XST_FAILURE.
*
*****************************************************************************/
int write_subclock_region_PBS(XDcfg *InstancePtr, u32 *addr_start, const char *file_name, pblock pblock_list[], u32 num_pblocks, u32 erase_bram, u8 stacked_modules) {
	int initial_clock_region_row, final_clock_region_row, words_per_half_clock_region_without_clock;
	int first_rows_not_used, first_words_not_used, last_rows_not_used, last_words_not_used;
	int first_half_bytes_to_move, first_half_first_unused_bytes, last_half_bytes_to_move, last_half_first_unused_bytes;
	int num_frames, extra_frames, reconfigurable_regions;
	int i, y, x, frame; //iterable for variables
	int x0, y0, xf, yf;
	u32 *previous_PBS_first_addr, *new_PBS_first_addr, *new_PBS_last_addr;
	u32 *pblock_addr[MAX_RECONFIGURABLE_CLOCK_REGIONS];
	int status;
	static u32 *previous_PBS_last_addr;

	Xil_AssertNonvoid(InstancePtr != NULL);
	Xil_AssertNonvoid(InstancePtr->IsReady == XIL_COMPONENT_IS_READY);
	Xil_AssertNonvoid(addr_start != NULL);
	Xil_AssertNonvoid(num_pblocks);
	Xil_AssertNonvoid(stacked_modules <= 3);

	// XTime time, transfer; // Elapsed time local variable
	// XTime_SetTime(0);     // Initialize time count
  // 
	// XTime_GetTime(&time); // Get time count

	//The first thing we do is copying the previous PBS of all the pblocks into the RAM memory
	previous_PBS_first_addr = addr_start;
	reconfigurable_regions = 0;
	if (stacked_modules <= 1){
		previous_PBS_last_addr = addr_start;
		for (i = 0; i < num_pblocks; i++) {
			x0 = pblock_list[i].X0;
			y0 = pblock_list[i].Y0;
			xf = pblock_list[i].Xf;
			yf = pblock_list[i].Yf;


			initial_clock_region_row = (int) y0 / (int) ROWS_PER_CLOCK_REGION;
			final_clock_region_row = (int) yf / (int) ROWS_PER_CLOCK_REGION;

			for(y = initial_clock_region_row; y <= final_clock_region_row; y++) {
			  pblock_addr[reconfigurable_regions++] = previous_PBS_last_addr;
			  if (reconfigurable_regions >= MAX_RECONFIGURABLE_CLOCK_REGIONS) {
				return XST_FAILURE;
			  }
			  //We read the actual content on the FPGA and save it on the RAM memory
			  status = PCAP_RAM_read(InstancePtr, &previous_PBS_last_addr, x0, y, xf, y);
			  if (status != XST_SUCCESS) {
				return XST_FAILURE;
			  }
			}
		}
	} else {
		pblock_addr[reconfigurable_regions++] = addr_start;
	}

	// XTime_GetTime(&transfer); // Get time count
	// printf("readback time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
	// XTime_GetTime(&time); // Get time count

	pblock_addr[reconfigurable_regions] = previous_PBS_last_addr;
	if (reconfigurable_regions >= MAX_RECONFIGURABLE_CLOCK_REGIONS) {
		return XST_FAILURE;
	}
	new_PBS_first_addr = previous_PBS_last_addr;
	//Now we copy the new PBS above the address of the previous PBS
	new_PBS_last_addr = (u32*) load_bitstream_from_SD_to_RAM(file_name, previous_PBS_last_addr);
	if (new_PBS_last_addr == 0) {
		return XST_FAILURE;
	}

	// XTime_GetTime(&transfer); // Get time count
	// printf("SD to RAM time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
	// XTime_GetTime(&time); // Get time count


	/**
	* Now we combine the previous bitstream and the new bitstream. The PBS that we are going to
	* reconfigure does not contain the clock word. Therefore the clock word must not be changed.
	* This means that there may be vertical clock lines that do not have any load, thus creating
	* net antennas that can increase the radiation emited by the FPGA. In the future it could
	* be helpful to control the vertical clock lines enabling and disabling them on run-time
	*/

	words_per_half_clock_region_without_clock = (NUM_FRAME_WORDS - CLOCK_WORDS) / 2;

	for (i = 0; i < num_pblocks; i++) {
		x0 = pblock_list[i].X0;
		y0 = pblock_list[i].Y0;
		xf = pblock_list[i].Xf;
		yf = pblock_list[i].Yf;

		initial_clock_region_row = (int) y0 / (int) ROWS_PER_CLOCK_REGION;
		final_clock_region_row = (int) yf / (int) ROWS_PER_CLOCK_REGION;

		for(y = initial_clock_region_row; y <= final_clock_region_row; y++) {
		  first_words_not_used = 0;
		  last_words_not_used = 0;
		  if(y == initial_clock_region_row) {
			first_rows_not_used = y0 - (initial_clock_region_row * ROWS_PER_CLOCK_REGION);
			first_words_not_used = first_rows_not_used * WORDS_PER_ROW_IN_CLOCK_REGION;
		  }
		  if(y == final_clock_region_row) {
			last_rows_not_used = (((final_clock_region_row + 1) * ROWS_PER_CLOCK_REGION) - 1) - yf;
			last_words_not_used = last_rows_not_used * WORDS_PER_ROW_IN_CLOCK_REGION;
		  }
		  /**
		  * We move the contents of the new PBS (located in the upper part of the RAM) to the lower part
		  * in order to compose it with the previous bitstream.
		  */
		  if(first_words_not_used < words_per_half_clock_region_without_clock && last_words_not_used < words_per_half_clock_region_without_clock) {
			  // The region crosses the middle of the clock region
			  first_half_first_unused_bytes = first_words_not_used * BYTES_PER_WORD_OF_FRAME;
			  first_half_bytes_to_move = (words_per_half_clock_region_without_clock - first_words_not_used) * BYTES_PER_WORD_OF_FRAME;
//			  last_half_first_unused_bytes = 0;
			  last_half_bytes_to_move = (words_per_half_clock_region_without_clock - last_words_not_used) * BYTES_PER_WORD_OF_FRAME;
			  for(x = x0; x <= xf; x++) {
				  num_frames = fpga[y][x][0] & 0xFFFF;
				  extra_frames = 0;
				  if (fpga[y][x][1] == CLK_TYPE) {
					  extra_frames = num_frames - FRAMES_CLK_INTERCONNECT;
					  num_frames = FRAMES_CLK_INTERCONNECT;
				  } else if (fpga[y][x][1] == CFG_TYPE) {
					  extra_frames = num_frames;
					  num_frames = 0;
				  }
				  for(frame = 0; frame < num_frames; frame++) {
					  memmove((u32*) ((u32) previous_PBS_first_addr + first_half_first_unused_bytes), new_PBS_first_addr, first_half_bytes_to_move);
					  new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + first_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + (words_per_half_clock_region_without_clock + CLOCK_WORDS) * BYTES_PER_WORD_OF_FRAME);
					  memmove((u32*) ((u32) previous_PBS_first_addr), new_PBS_first_addr, last_half_bytes_to_move);
					  new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + last_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + words_per_half_clock_region_without_clock * BYTES_PER_WORD_OF_FRAME);

				  }
				  for (frame = 0; frame < extra_frames; frame++) {
					  new_PBS_first_addr =  (u32*) ((u32) new_PBS_first_addr + first_half_bytes_to_move + last_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + NUM_FRAME_BYTES);
				  }
			  }

		  } else if(first_words_not_used >= words_per_half_clock_region_without_clock && last_words_not_used < words_per_half_clock_region_without_clock) {
			  // Region on the top half of the clock region
//			  first_half_first_unused_bytes =0; //In this case we don't care about this value
//			  first_half_bytes_to_move = 0;
			  last_half_first_unused_bytes = (first_words_not_used - words_per_half_clock_region_without_clock) * BYTES_PER_WORD_OF_FRAME;
			  last_half_bytes_to_move = ((words_per_half_clock_region_without_clock - last_words_not_used) * BYTES_PER_WORD_OF_FRAME) - last_half_first_unused_bytes;
			  for(x = x0; x <= xf; x++) {
				  num_frames = fpga[y][x][0] & 0xFFFF;
				  extra_frames = 0;
				  if (fpga[y][x][1] == CLK_TYPE) {
					  extra_frames = num_frames - FRAMES_CLK_INTERCONNECT;
					  num_frames = FRAMES_CLK_INTERCONNECT;
				  } else if (fpga[y][x][1] == CFG_TYPE) {
					  extra_frames = num_frames;
					  num_frames = 0;
				  }
				  for(frame = 0; frame < num_frames; frame++) {
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + (words_per_half_clock_region_without_clock + CLOCK_WORDS) * BYTES_PER_WORD_OF_FRAME);
					  memmove((u32*) ((u32) previous_PBS_first_addr + last_half_first_unused_bytes), new_PBS_first_addr, last_half_bytes_to_move);
					  new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + last_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + words_per_half_clock_region_without_clock * BYTES_PER_WORD_OF_FRAME);
				  }
				  for (frame = 0; frame < extra_frames; frame++) {
					  new_PBS_first_addr =  (u32*) ((u32) new_PBS_first_addr + last_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + NUM_FRAME_BYTES);
				  }
			  }


		  } else if(first_words_not_used < words_per_half_clock_region_without_clock && last_words_not_used >= words_per_half_clock_region_without_clock) {
			  // Region on the bottom half of tyhe clock region
			  first_half_first_unused_bytes = first_words_not_used * BYTES_PER_WORD_OF_FRAME;
			  first_half_bytes_to_move = (2*words_per_half_clock_region_without_clock - first_words_not_used - last_words_not_used) * BYTES_PER_WORD_OF_FRAME;
//			  last_half_first_unused_bytes = 0; //In this case we don't care about this value
//			  last_half_bytes_to_move = 0;
			  for(x = x0; x <= xf; x++) {
				  num_frames = fpga[y][x][0] & 0xFFFF;
				  extra_frames = 0;
				  if (fpga[y][x][1] == CLK_TYPE) {
					  extra_frames = num_frames - FRAMES_CLK_INTERCONNECT;
					  num_frames = FRAMES_CLK_INTERCONNECT;
				  } else if (fpga[y][x][1] == CFG_TYPE) {
					  extra_frames = num_frames;
					  num_frames = 0;
				  }
				  for(frame = 0; frame < num_frames; frame++) {
					  memmove((u32*) ((u32) previous_PBS_first_addr + first_half_first_unused_bytes), new_PBS_first_addr, first_half_bytes_to_move);
					  new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + first_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + NUM_FRAME_BYTES);

				  }
				  for (frame = 0; frame < extra_frames; frame++) {
					  new_PBS_first_addr =  (u32*) ((u32) new_PBS_first_addr + first_half_bytes_to_move);
					  previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + NUM_FRAME_BYTES);
				  }
			  }
		  } else {
			  //The other cases are not possible
			  return XST_FAILURE;
		  }
//		  for(x = x0; x <= xf; x++) {
//			num_frames = fpga[y][x][0] & 0xFFFF;
//			for(frame = 0; frame < num_frames; frame++) {
//				memmove((u32*) ((u32) previous_PBS_first_addr + first_half_first_unused_bytes), new_PBS_first_addr, first_half_bytes_to_move);
//				new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + first_half_bytes_to_move);
//				previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + (words_per_half_clock_region_without_clock + CLOCK_WORDS) * BYTES_PER_WORD_OF_FRAME);
//				memmove((u32*) ((u32) previous_PBS_first_addr + last_half_first_unused_bytes), new_PBS_first_addr, last_half_bytes_to_move);
//				new_PBS_first_addr = (u32*) ((u32) new_PBS_first_addr + last_half_bytes_to_move);
//				previous_PBS_first_addr = (u32*) ((u32) previous_PBS_first_addr + words_per_half_clock_region_without_clock * BYTES_PER_WORD_OF_FRAME);
//
//			}
//		}
		}
	}

	//We check that the size of the region to reconfigure and the new PBS are compatible
	if(( (u32) previous_PBS_first_addr != (u32) previous_PBS_last_addr ) || ((u32) new_PBS_first_addr != (u32) new_PBS_last_addr) ) {
		return XST_FAILURE;
	}

	// XTime_GetTime(&transfer); // Get time count
	// printf("recombination time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
	// XTime_GetTime(&time); // Get time count

	if (stacked_modules == 0 || stacked_modules == 3){
		//We write the bitstream for each region
		reconfigurable_regions = 0;
		for (i = 0; i < num_pblocks; i++) {
			x0 = pblock_list[i].X0;
			y0 = pblock_list[i].Y0;
			xf = pblock_list[i].Xf;
			yf = pblock_list[i].Yf;

			initial_clock_region_row = (int) y0 / (int) ROWS_PER_CLOCK_REGION;
			final_clock_region_row = (int) yf / (int) ROWS_PER_CLOCK_REGION;

			for(y = initial_clock_region_row; y <= final_clock_region_row; y++) {
			  status = PCAP_RAM_write(InstancePtr, pblock_addr[reconfigurable_regions], (u32) (pblock_addr[reconfigurable_regions + 1]), x0, y, xf, y, erase_bram);
			  if (status != XST_SUCCESS) {
				return XST_FAILURE;
			  }
			  reconfigurable_regions++;
			}
		}
	}

	// XTime_GetTime(&transfer); // Get time count
	// printf("Write time:  %12.3f us (%10.0f cycles @ %7.3f MHz)\n", (float)(transfer-time)/(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)*1000000, (float)(transfer-time), (float)(XPAR_PS7_CORTEXA9_0_CPU_CLK_FREQ_HZ/2)/1000000);
	// XTime_GetTime(&time); // Get time count


	return XST_SUCCESS;
}
