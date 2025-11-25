/*
Copyright 2022-2024 NXP

NXP Confidential. This software is owned or controlled by NXP and may only
be used strictly in accordance with the applicable license terms. By expressly accepting
such terms or by downloading, installing, activating and/or otherwise using
the software, you are agreeing that you have read, and that you agree to
comply with and are bound by, such license terms. If you do not agree to
be bound by the applicable license terms, then you may not retain,
install, activate or otherwise use the software.
*/

/**********************************************************
   This headfile provides APIs for host to drive VSPA DFE
   
   version: 2.0
************************************************************/

#ifndef HOST_VSPA_IF

#define HOST_VSPA_IF

/*********************************************************************
  Host VSPA Interface Init, call this API first before calling any other API
  modem_ccsr_base_phy:	host view of physical address of LA device CCSR base address
  vspa_dmem_base_phy: host view of base physical address of VSPA core0 DMEM
  ddr_phy_host_view:  host view of physical address of DDR region base address used for host-vspa interface
  ddr_phy_vspa_view:  VSPA view of the same DDR address. 
					  example: in la9310_modem_info log, the following info indicates the host and vspa view of IQ_FLOOD region:
                               IQ FLOOD phys     0x96400000    Modem phys:0xb0001000 Size:0xd000000
  return value:  num of vspa cores in the LA device. 1 or 8 for LA9310 or LA12xx
************************************************************/
uint32_t hvif_init(uint64_t modem_ccsr_base_phy, uint64_t vspa_dmem_base_phy, uint64_t ddr_phy_host_view, uint32_t ddr_phy_vspa_view);

// hvif_reset() should be called before hvif_init() is called the 2nd time
void hvif_reset();

/*********************************************************************
  mailbox msg receive and send
  core_id:			VSPA core ID, starting from 0.
  mbox_id:			mailbox ID, 0 or 1.
  msb32:			32 MSB of the 64bit mailbox message
  lsb32:			32 LSB of the 64bit mailbox message, see DFE Ref user guide for the msb and lsb definitions
  return vlaue:		received 64 bit message. If return value is 0, it means no message received.
                    hvif_mbox_send() will first send the message, and then receive a message from the same mailbox port. 
  
************************************************************/
uint64_t hvif_mbox_recv(uint32_t core_id, uint32_t mbox_id);
uint64_t hvif_mbox_send(uint32_t core_id, uint32_t mbox_id, uint32_t msb32, uint32_t lsb32);

void set_reverse_loopback(uint32_t tx_coreA_id, uint32_t rx_coreA_id, uint32_t addr, uint32_t size);

/*********************************************************************
  handshake used for host to send or receive a symbol to/from VSPA DFE
  core_id:		VSPA core ID, starting from 0.
  sym_idx:		symbol index of a symbol that host want to send or receive
  return value: tx_sym_buf_status(): 0-tx symbol buffer has no valid data or has been consumed by VSPA, host can write a new symbol to the buffer
                                     non zeor-tx symbol buffer has valid data and has not been consumed by VSPA, host can not update the buffer.
                rx_sym_buf_status(): 0-rx symbol buffer has no valid data, host should not do anything
				                     non zeor-rx symbol buffer has valid data, host can process iter_swap
************************************************************/
uint32_t hvif_tx_sym_buf_status(uint32_t core_id, uint32_t sym_idx);
void     hvif_tx_sym_buf_set_ready(uint32_t core_id, uint32_t sym_idx);
uint32_t hvif_rx_sym_buf_status(uint32_t core_id, uint32_t sym_idx);
void     hvif_rx_sym_buf_release(uint32_t core_id, uint32_t sym_idx);

/*********************************************************************
  Steps for host to drive VSPA DFE:
  1. Initialize the host-vspa interface by calling hvif_init().
     In this step, users should get familiar with the address mapping from BSP and configure the 
	 parameters passed to the hvif_init() function correctly.
  2. Send Symbol Buffer Struct Mailbox message by calling hvif_mbox_send().
     In this step, users should first create TX and RX symbol buffers in memory such as DDR. refer to 
	 DFE Ref user guide for the message definitions
  3. Send DFE mode message by calling hvif_mbox_send().
  4. (optional for LA12xx) For TDD, send TDD Pattern message by calling hvif_mbox_send().
  above steps are done only once.
  5. Start e200 for LA12xx, or start m4 for LA9310 to control DAC/ADC tx_allowed/rx_allowed to work in FDD or TDD mode.
  
  If bypass host interface handshake bits are not set, do the following repeatedly to send/recevie symbols:
  6. decide the TX symbol index, check tx symbol buffer status by calling hvif_tx_sym_buf_status().
  7. if buffer status is 0, send/update the data to tx symbol buffer, and set the buffer status to ready by calling hvif_tx_sym_buf_set_ready().
  8. decide the RX symbol index, check rx symbol buffer status by calling hvif_rx_sym_buf_status().
  9. if buffer status is 1, process the symbol, and release the buffer by calling hvif_rx_sym_buf_release().
  
  Host should check DFE underflow/overflow regularly
  10. Check errors by calling hvif_mbox_recv(), if the returned message is error message, it means error happens.
************************************************************/

/*********************************************************************
  core_id:  defined statically according to DFE architecture
            users can select the MACROs that fit their architecture
			The MACROs are defined for the VSPA images coming with fr1 fr2 test tool which are built
			using the default architecture header files, if users change the architeture, these MACROS may not be correct.
			tid or rid mean the TX path ID or RX path ID. Example, for 4T4R, there are 4 TX paths(tid=0,1,2,3) and 4 RX paths(rid=0,1,2,3) 
************************************************************/
#define TX_CORE_ID_FR1_4T4R_8CORES(tid)			((tid)+4)
#define RX_CORE_ID_FR1_4T4R_8CORES(rid)			(((rid)+4+2)%4)
#define TX_CORE_ID_FR1_4T4R_4CORES(tid)			(tid)
#define RX_CORE_ID_FR1_4T4R_4CORES(rid)			(rid)
#define TX_CORE_ID_FR1_1T2R_1CORES_9310(tid)	0
#define RX_CORE_ID_FR1_1T2R_1CORES_9310(rid)	0
#define TX_CORE_ID_FR2_2T2R_4CORES(tid)			((tid)+6)
#define RX_CORE_ID_FR2_2T2R_4CORES(rid)			((rid)+6)
#define TX_CORE_ID_FR2_2T2R_8CORES(tid)			((tid)*2)
#define RX_CORE_ID_FR2_2T2R_8CORES(rid)			((rid)*2+1)

/*********************************************************************
  mbox_id:  defined statically, mbox 0 is used by host, mbox 1 is used by e200 or m4
************************************************************/
#define MBOX_ID_HOST	0

/*********************************************************************
  qec_para_convert: convert the original QEC coeff struct to new optimized QEC para struct (starting from DFE Ref V5.0.1)
  original QEC para struct defined as qec_params_t, new struct defined as qec_params_opt_t
  p_qec_para_converted:  dest buffer for converted para struct
  p_qec_para: original struct.  p_qec_para_converted can be same as p_qec_para
************************************************************/
/*
typedef struct{
    cfloat32_t	FD_taps[QEC_MAX_FD_TAP_CNT];
    uint32_t 	int_del;
    uint32_t 	FD_tap_cnt;
    float32_t 	f1;
    float32_t 	f2;
    float32_t   f4;
    cfloat32_t	g;	
    cfloat32_t	dc;	
	cfloat32_t	fegain_ori_backup;
}qec_params_t;
typedef struct{
    float32_t 	f1;
    float32_t 	f4;
    float32_t 	pad0;    //set to 0
    float32_t 	f2;
    float32_t	dcoff_I;
    float32_t	dcoff_Q;
    float32_t 	f1_backup;
    float32_t 	f4_backup;
    float32_t 	pad1;    //set to 0
    float32_t 	f2_backup;
	float32_t	pad2[22];     //to make the struct size to 1 line
}qec_params_opt_t;
*/
void qec_para_convert(void* p_qec_para_converted, void* p_qec_para);

/*********************************************************************
  de-QEC: reverse of QEC. When QEC is integrated into DPD, DPD output can not be dumped out,
  users should dump QEC output and call this API to de-QEC and get DPD output for DPD training.
  
  the QEC parameters in the arguments are the QEC parameters being used by QEC algorithm.
************************************************************/
void deqec(void* buffer, unsigned int num_samples, float f1, float f2, float f4, float gain_I, float gain_Q, float dcoff_I, float dcoff_Q);

#endif