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

#include <stdio.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <string.h>
#include <stdlib.h>

#include "antman_axiq.h"

#define DUMP_INJECT_STOPPED						0x0000
#define DUMP_INJECT_WAIT_MASK					0x0001
#define DUMP_DONE_MASK							0x0001
#define DUMP_INJECT_ONCE						0x0002
#define DUMP_INJECT_FOREVER						0x0004
//#define DUMP_INJECT_COMPACT						0x0008
#define DUMP_INJECT_MODE_ONCE					0x0020
#define DUMP_INJECT_MODE_FOREVER				0x0040
//#define DUMP_INJECT_MODE_COMPACT				0x0080
#define DUMP_INJECT_MODE_SHIFT					4

#define SWVERSION           0x004
#define VCPU_HOST_FLAGS0    0x014
#define VCPU_HOST_FLAGS1    0x018
#define HOST_VCPU_FLAGS0    0x01C
#define HOST_VCPU_FLAGS1    0x020
#define IP_IDX_FAST_FLAGS	0x714
#define IP_IDX_NSC			0x138
#define IP_DFE_MODE_HI 		0x13C
#define IP_DFE_MODE_LO 		0x140


// Trigger options:
#define DMAC_TRIG_IPPU          (0b1 << 12)     //!< Trigger IPPU on transfer completion.
#define DMAC_TRIG_VCPU          (0b1 << 13)     //!< Trigger VCPU on transfer completion.
#define DMAC_TRIG_IRQ           (0b1 << 14)     //!< Trigger IRQ  on transfer completion.
#define DMAC_TRIG_FECU          (0b1 << 22)     //!< Trigger FECU on transfer completion.

// Pending options:
#define DMAC_PEND_EXT           (0b1 << 16)     //!< Transfer pending on external trigger.
#define DMAC_PEND_IPPU          (0b1 << 17)     //!< Transfer pending on IPPU procedure completion.
#define DMAC_PEND_FECU          (0b1 << 23)     //!< Transfer pending on FECU operation completion.

// Pointer reset request:
#define DMAC_PRST_REQ           (0b1 << 15)

// FIFO mode:
#define DMAC_FIFO_HS            ((0b1 << 11))
#define DMAC_FIFO               ((0b1 << 11) | DMAC_PEND_EXT)
#define DMAC_FIFO_RESET         ((0b1 << 11) | DMAC_PRST_REQ)

// Program memory access:
#define DMAC_VPRAM              (0b010 << 8)    //!< Transfer to VCPU program memory.
#define DMAC_IPRAM              (0b011 << 8)    //!< Transfer to IPPU program memory.

// Turbo read:
#define DMAC_MBRE               (0b1 << 7)      //!< Enable multi-burst read.

// Transfer modes:
#define DMAC_RD                 ((0b000 << 8) | DMAC_MBRE)      //!< Read from AXI (use multi-burst)
#define DMAC_RDC                (0b001 << 8)                    //!< Read from AXI and convert to sign-magnitude.
#define DMAC_WR                 (0b110 << 8)                    //!< Write to AXI.
#define DMAC_WRC                (0b111 << 8)                    //!< Write to AXI and convert to 2's complement.
#define DMAC_DI8                ((0b100 << 8) | (0b001 << 18))  //!<  8-bit write to AXI.
#define DMAC_DI4_MSB0           ((0b100 << 8) | (0b010 << 18))  //!<  4-bit write to AXI.
#define DMAC_DI4_MSB1           ((0b100 << 8) | (0b011 << 18))  //!<  4-bit write to AXI.
#define DMAC_DI16               ((0b100 << 8) | (0b100 << 18))  //!< 16-bit write to AXI.
#define DMAC_DI32               ((0b100 << 8) | (0b101 << 18))  //!< 32-bit write to AXI.
#define DMA_TRIG				DMAC_PEND_EXT

#define DMA_DMEM_PRAM_ADDR              (0x0B0)
#define DMA_AXI_ADDRESS                 (0x0B4)
#define DMA_AXI_BYTE_CNT                (0x0B8)
#define DMA_XFR_CTRL                    (0x0BC)
#define DMA_STAT_ABORT                  (0x0C0)
#define DMA_IRQ_STAT                    (0x0C4)
#define DMA_COMP_STAT                   (0x0C8)
#define DMA_XFRERR_STAT                 (0x0CC)
#define DMA_CFGERR_STAT                 (0x0D0)
#define DMA_XRUN_STAT                   (0x0D4)
#define DMA_GO_STAT                     (0x0D8)
#define DMA_FIFO_STAT                   (0x0DC)

#define IPPUCONTROL                     (0x700)
#define IPPUSTATUS                      (0x704)
#define IPPURC                          (0x708)
#define IPPUARGBASEADDR                 (0x70C)
#define IPPUHWVER                       (0x710)
#define IPPUSWVER                       (0x714)


#define LA9310

#define MAX_NUM_1R_IN_CORE	2

#define MAX_NUM_PATTERN_ENTRIES					4	//expanding the patterns to 20 slots, a common period for FR1 and FR2
#define NUM_SLOTS_COMMON_PERIOD					20
#define PATTERN_SIZE_SYMBOL_MASK				0xFF
#define PATTERN_SIZE_SYMBOL_SKIP0_BITIDX		0
#define PATTERN_SIZE_SYMBOL_BITIDX				8
#define PATTERN_SIZE_SYMBOL_SKIP1_BITIDX		16
#define PATTERN_SIZE_SYMBOL_SKIP1_MASK			(PATTERN_SIZE_SYMBOL_MASK<<PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)
//#define PATTERN_SIZE_STOP_BITIDX				30
//#define PATTERN_SIZE_STOP_MASK					(1<<PATTERN_SIZE_STOP_BITIDX)
#define PATTERN_SIZE_VALID_BITIDX				31
#define PATTERN_SIZE_VALID_MASK					(1<<PATTERN_SIZE_VALID_BITIDX)
#define GET_SKIP0(x)		(((x)>>PATTERN_SIZE_SYMBOL_SKIP0_BITIDX)&PATTERN_SIZE_SYMBOL_MASK)
#define GET_NUM_SYMBOLS(x)	(((x)>>PATTERN_SIZE_SYMBOL_BITIDX)&PATTERN_SIZE_SYMBOL_MASK)
#define GET_SKIP1(x)		(((x)>>PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)&PATTERN_SIZE_SYMBOL_MASK)


typedef struct tdd_pattern_entry_s
{
	unsigned short 	num_patterns;
	unsigned short 	num_patterns_onetime;
	unsigned int	tx_entry[MAX_NUM_PATTERN_ENTRIES];
	unsigned int	ts_txallowed[MAX_NUM_PATTERN_ENTRIES];
	unsigned int	rx_entry[MAX_NUM_PATTERN_ENTRIES];
} struct_tdd_pattern_entry;


#define KERNELS_DISABLE						((0x10))
#define KERNELS_DISABLE_BITMASK_CFR			((1<<0))
#define tx_mixer_freq_update				((0x1c))
#define rx_mixer_freq_update				((tx_mixer_freq_update+4))
#define tdd_pattern_entry					((rx_mixer_freq_update+MAX_NUM_1R_IN_CORE*4))
//#define num_patterns						tdd_pattern_entry
//#define tx_pattern_entry					((num_patterns+4))  //total 4 entries
//#define rx_pattern_entry					((tx_pattern_entry+4*4))  //total 4 entries
#define tx_timing_offset_total				0x64
#define rx_timing_offset_total				0x68



#define COREA_STATUS_BASE        0x80
#define RXPATH_STATUS_OFFSET_FLAG_AtoB                COREA_STATUS_BASE
#define FLAG_AtoB_OBS_DUMP_ENABLE                ((1<<3)) #must match vspa code
#define FLAG_AtoB_DOWNSAMPLEING_64TAPS                ((1<<6)) #must match vspa code
#define TXPATH_STATUS_OFFSET_CC_UPSAMPLING                ((COREA_STATUS_BASE+2))
#define TXPATH_STATUS_OFFSET_CC_DPD                ((TXPATH_STATUS_OFFSET_CC_UPSAMPLING+2))
#define TXPATH_STATUS_OFFSET_CC_QEC                ((TXPATH_STATUS_OFFSET_CC_DPD+2))
#define RXPATH_STATUS_OFFSET_CC_QEC                ((TXPATH_STATUS_OFFSET_CC_QEC+2))
#define RXPATH_STATUS_OFFSET_CC_DOWNSAMPLING                ((RXPATH_STATUS_OFFSET_CC_QEC+2))
#define TXPATH_STATUS_OFFSET_ADDR_UPSAMPLING_TAPS                ((RXPATH_STATUS_OFFSET_CC_DOWNSAMPLING+2))
#define RXPATH_STATUS_OFFSET_ADDR_DOWNSAMPLING_TAPS                ((TXPATH_STATUS_OFFSET_ADDR_UPSAMPLING_TAPS+2))
#define TXPATH_STATUS_OFFSET_TS_TXALLOWED_FIRST_ENABLED                ((RXPATH_STATUS_OFFSET_ADDR_DOWNSAMPLING_TAPS+2))
#define RXPATH_STATUS_OFFSET_TS_RXALLOWED_FIRST_ENABLED                ((TXPATH_STATUS_OFFSET_TS_TXALLOWED_FIRST_ENABLED+4))
#define CONFIG_RX_SINGLE_TONE_FREQ                ((RXPATH_STATUS_OFFSET_TS_RXALLOWED_FIRST_ENABLED+4))
#define CONFIG_RX_SINGLE_TONE_AMP                ((CONFIG_RX_SINGLE_TONE_FREQ+MAX_NUM_1R_IN_CORE*4))
#define MAX_NUM_SINGLE_TONE        4
#define CONFIG_TX_SINGLE_TONE_FREQ                ((CONFIG_RX_SINGLE_TONE_AMP+MAX_NUM_1R_IN_CORE*4))
#define CONFIG_TX_SINGLE_TONE_AMP                ((CONFIG_TX_SINGLE_TONE_FREQ+MAX_NUM_SINGLE_TONE*4))


#define COREB_STATUS_BASE       		0x100
#define STATUS_CC_DECOMP       			((COREB_STATUS_BASE+2))
#define STATUS_CC_IFFT       			((STATUS_CC_DECOMP+2))
#define STATUS_CC_IFFT_BITREV      		((STATUS_CC_IFFT+2))
#define STATUS_CC_CFR      			 ((STATUS_CC_IFFT_BITREV+2))
#define STATUS_CC_FFT      			 ((STATUS_CC_CFR+2))
#define STATUS_CC_FFT_BITREV      	 ((STATUS_CC_FFT+2))
#define STATUS_CC_COMP       		((STATUS_CC_FFT_BITREV+2))
#define STATUS_NUM_TX_SYM_FROM_HIPHY       ((STATUS_CC_COMP+2))
#define STATUS_NUM_RX_SYM_TO_HIPHY       ((STATUS_NUM_TX_SYM_FROM_HIPHY+4))
#define STATUS_CAP_HI      				 ((STATUS_NUM_RX_SYM_TO_HIPHY+4))
#define STATUS_CAP_LO      				 ((STATUS_CAP_HI+4))
#define STATUS_TX_SYM_DMA_SIZE_CYCLE_COUNT       ((STATUS_CAP_LO+4))
#define tx_sym_buf_base       		((STATUS_TX_SYM_DMA_SIZE_CYCLE_COUNT+4))
#define tx_num_sym_in_buf       ((tx_sym_buf_base+4))
#define tx_sym_buff_size       ((tx_num_sym_in_buf+4))
#define rx_sym_buf_base       ((tx_sym_buff_size+4))
#define rx_num_sym_in_buff       ((rx_sym_buf_base+MAX_NUM_1R_IN_CORE*4))
#define rx_sym_buff_size       ((rx_num_sym_in_buff+MAX_NUM_1R_IN_CORE*4))
#define rx_sym_dumping_flag       ((rx_sym_buff_size+4))
#define ext_log_buf_base       ((rx_sym_dumping_flag+4))
#define ext_log_buf_size       ((ext_log_buf_base+4))
#define ant_core_map_hi       ((ext_log_buf_size+4))
#define ant_core_map_lo       ((ant_core_map_hi+4))
#define celltrack_config_hi       ((ant_core_map_lo+4))
#define celltrack_config_lo       ((celltrack_config_hi+4))

#define tx_circ_base			0x160
#define rx_circ_base			0x170
#define addr_antman_tx			0x16c
#define addr_antman_rx			0x17c
#define addr_phcom_coeff_tx		0x180
#define addr_phcom_coeff_rx		((addr_phcom_coeff_tx+2))
#define addr_DFE_qec_params_opt_tx		((addr_phcom_coeff_rx+2))
#define addr_DFE_qec_params_opt_rx		((addr_DFE_qec_params_opt_tx+2))
#define addr_ant_tx_dump				((addr_DFE_qec_params_opt_rx+2))
#define addr_ant_rx_dump				((addr_ant_tx_dump+4))
#define	tx_timing_offset							((addr_ant_rx_dump+4))
#define	rx_timing_offset							((tx_timing_offset+4))
#define	tx_circ_total_write_size							((rx_timing_offset+4))
#define	rx_inject_addr							((tx_circ_total_write_size+4))
#define	rx_inject_size							((rx_inject_addr+4))
#define	tx_freq_dump_flag							((rx_inject_size+4))
#define	tx_freq_dump_num_sym							((tx_freq_dump_flag+2))
#define	tx_freq_dump_addr							((tx_freq_dump_num_sym+2))
#define	tx_freq_dump_sym_size							((tx_freq_dump_addr+4))
#define	error_info									((tx_freq_dump_sym_size+4))
#define rx_dumping_sym_buf_base			0x1bc
#define rx_dumping_num_sym_in_buff		0x1c4
#define rx_dumping_num_sym_in_buff		0x1c4
#define rx_dumping_sym_buff_size		0x1c8

#define GET_CONTROL0(msg32msb)							(((msg32msb)>>22)&0x3)
#define GET_CONTROL1(msg32msb)							(((msg32msb)>>14)&0x1)
#define GET_CONTROL2(msg32msb)							(((msg32msb)>>13)&0x1)
#define GET_CONTROL3(msg32msb)							(((msg32msb)>>12)&0x1)
#define GET_TEST_PARA_HI(msg32msb)						((msg32msb)&0xFFF)
#define GET_CFO_TRID(x)									(((x)>>23)&1)
#define GET_INJECT_SYM_BUF_SIZE(msg32msb)				(((msg32msb)&0xFF)*128)
#define GET_INJECT_NUM_SYMBOLS(msg32lsb)				(((msg32lsb)>>20)&0xFFF)
#define GET_INJECT_ADDR(msg32lsb)						(((msg32lsb)&0xFFFFF)<<12)
#define MSG_TXRX_IDX									22
#define GET_DUMP_ADDR(msg32lsb)							(((msg32lsb)&0xFFFFF)<<12)
#define GET_SIZE_NUM32KB_TO_DUMP(msg32lsb)				(((msg32lsb)>>20)&0xFFF)
#define GET_CONTROL0(msg32msb)							(((msg32msb)>>22)&0x3)
#define GET_CONTROL1(msg32msb)							(((msg32msb)>>14)&0x1)
#define GET_CONTROL2(msg32msb)							(((msg32msb)>>13)&0x1)
#define GET_CONTROL3(msg32msb)							(((msg32msb)>>12)&0x1)
#define GET_CONTROL(msg32msb)							(((msg32msb)>>12)&0x7)
#define GET_CONTROL23(msg32msb)							(((msg32msb)>>12)&0x3)
#define GET_NUM_ONETIME_PATTERN(msg32lsb)				(((msg32lsb)>>30))		//change for special pattern
#define NUM_SYM_PER_SLOT								14
#define GET_SEQ_ID_MASK(msg32lsb)						((msg32lsb)&(3<<28))

#define SINGLE_TONE_VALID_FLAG	1

#define MSG_ID_MASK								0xFF000000
#define MSG_ID_TEST_MSG							0x0A000000
#define MSG_ID_DFE_MODE_CONFIG					0x0E000000
#define MSG_ID_DFE_MODE_CONFIG_ACK				0x0F000000
#define MSG_ID_SYMBOL_BUFFER_STRUCT				0x10000000
#define MSG_ID_SYMBOL_BUFFER_STRUCT_ACK			0x11000000
#define MSG_ID_SYMBOL_BUFFER_STRUCT2			0x20000000
#define MSG_ID_SYMBOL_BUFFER_STRUCT2_ACK		0x21000000
#define MSG_ID_STATIC_SLOT_FORMAT				0x12000000
#define MSG_ID_STATIC_SLOT_FORMAT_ACK			0x13000000
#define MSG_ID_FLEXIBLE_SLOT_FORMAT_TX			0x03000000
#define MSG_ID_FLEXIBLE_SLOT_FORMAT_RX			0x04000000
#define MSG_ID_FLEXIBLE_SLOT_FORMAT				0x03000000
#define MSG_ID_TIMING_OFFSET					0x08000000
#define MSG_ID_FDD_START						0x02000000
#define MSG_ID_FDD_STOP							0x00000000
#define MSG_ID_FINE_CFO_NCO_FREQ_UPDATE_TX		0x14000000
#define MSG_ID_FINE_CFO_NCO_FREQ_UPDATE_RX		0x15000000
#define MSG_ID_STAT_REQ_TX_POWER				0x16000000
#define MSG_ID_UPDATE_PHCOM_COEFF				0x18000000
#define MSG_ID_CELLTRACK_REQUEST				0x19000000

#define MSG_ID_ERROR_REPORT_MSG					0x44000000
#define ERROR_REPORT_MSG_ERROR_TYPE_DMA_CONFIG_ERR		4	
#define ERROR_REPORT_MSG_ERROR_TYPE_DMA_TRANSFER_ERR	5	
#define ERROR_REPORT_MSG_ERROR_TYPE_IPPU_ERR			6

#define GET_DFE_MODE_RX_IQSWAP(msg32lsb)				(((msg32lsb)>>23)&1)
#define GET_DFE_MODE_TX_IQSWAP(msg32lsb)				(((msg32lsb)>>19)&1)
#define GET_DFE_MODE_ANT_MAP_RX(msg32lsb)				(((msg32lsb)>>20)&0x7)
#define GET_DFE_MODE_ANT_MAP_TX(msg32lsb)				(((msg32lsb)>>16)&0x7)
#define GET_DFE_MODE_RX2_IQSWAP(msg32lsb)				(((msg32lsb)>>7)&1)
#define GET_DFE_MODE_TX2_IQSWAP(msg32lsb)				(((msg32lsb)>>3)&1)
#define GET_DFE_MODE_ANT_MAP_RX2(msg32lsb)				(((msg32lsb)>>4)&0x7)
#define GET_DFE_MODE_ANT_MAP_TX2(msg32lsb)				(((msg32lsb)>>0)&0x7)
#define GET_DFE_MODE_CFR_CTRRL(msg32lsb)				(((msg32lsb)>>8)&0xFF)
#define GET_DFE_MODE_RXEXT(msg32lsb)					(((msg32lsb)>>12)&0xF)
#define GET_DFE_MODE_TXEXT(msg32lsb)					(((msg32lsb)>>8)&0xF)

#define DFE_MODE_LSDIV2_BITIDX			2
#define DFE_MODE_LSDIV2_BITMASK			(1<<DFE_MODE_LSDIV2_BITIDX)
#define DFE_MODE_HSDIV2_BITIDX			3
#define DFE_MODE_HSDIV2_BITMASK			(1<<DFE_MODE_HSDIV2_BITIDX)
#define DFE_MODE_BWDIV_BITIDX			4
#define DFE_MODE_BWDIV_MASK				0x3
#define DFE_MODE_BWDIV_BITMASK			(DFE_MODE_BWDIV_MASK<<DFE_MODE_BWDIV_BITIDX)
#define DFE_MODE_HWDCM_BITIDX			6
#define DFE_MODE_HWDCM_BITMASK			(1<<DFE_MODE_HWDCM_BITIDX)
#define DFE_MODE_COMP_DIS				(1<<7)
#define DFE_MODE_OPTION8				(1<<8)
#define DFE_MODE_LOWPHYONLY				(1<<9)
#define DFE_MODE_CPE					(1<<10)
#define DFE_MODE_NO_RX_SYM_TO_HOST		(1<<11)
#define DFE_MODE_TX_FDD					(1<<12)
#define DFE_MODE_RX_FDD					(1<<13)
#define DFE_MODE_TX_HANDSHAKE_BYPASS	(1<<14)
#define DFE_MODE_RX_HANDSHAKE_BYPASS	(1<<15)
#define DFE_MODE_RESTART_TX				(1<<20)
#define DFE_MODE_RESTART_RX				(1<<21)
#define DFE_MODE_TX_DIS					(1<<22)
#define DFE_MODE_RX_DIS					(1<<23)
#define DFE_MODE_TX_ANT_MASK(trid)		(7<<(0+(1-trid)*16))
#define DFE_MODE_RX_ANT_MASK(trid)		(7<<(4+(1-trid)*16))

//these globals are needed. 
uint32_t g_dev_la9310;
uint32_t g_num_cores;
uint32_t g_dfe_ref_la9310;
uint32_t g_devmem_fd;						//demem_fd from external (g_devmem_fd = open("/dev/mem", O_RDWR);)
uint64_t g_vspa_ccsr_vir;				//vspa register base virtual (mem mapped)
uint64_t g_vspa_dmem_base_phy;         //vspa dmem base from host view
uint64_t g_ddr_host_vspa_view_offset;  //DDR address host vspa view offset (DDR scratch buffer physical address host view minus vspa view)

//user configurable
//test result: 3 will get underflow easier than 2 on LA9310 at 61Msps (TX AXIQ DMA + RX AXIQ DMA + RX sym DMA from TCM, cauing TX AXIQ underflow with config 3. changing to 2 works)
#define FIFO_THRESHOLD_CONFIG_TX			0   //0,1,2,3: stands for 256/128/64/32 bytes.
#define FIFO_THRESHOLD_CONFIG_RX			0   //0,1,2,3: stands for 256/128/64/32 bytes.

#ifdef LA9310
#define SIZE_AXIQ_FIFO						512
#define SIZE_FOR_FLUSH_MODE					0               //LA9310 FLush mode doesn't work, size must be 0
#else
#define SIZE_AXIQ_FIFO						2048
#define SIZE_FOR_FLUSH_MODE					(SIZE_AXIQ_FIFO/2)	//must be a size to feed Flush mode. multiple of 512-bit burst.
#endif

#define AXIQFIFO_WIN_SIZE					4096
#define SIZE_AXIQ_THRESHOLD					(SIZE_AXIQ_FIFO/2)    // default AXIQ THRESHOLD is half of AXIQ BUFFER SIZE
#define AXIQFIFO_OFFSET_THRESHOLD_TX		(AXIQFIFO_WIN_SIZE-(SIZE_AXIQ_THRESHOLD>>FIFO_THRESHOLD_CONFIG_TX))
#define AXIQFIFO_OFFSET_THRESHOLD_RX		(AXIQFIFO_WIN_SIZE-(SIZE_AXIQ_THRESHOLD>>FIFO_THRESHOLD_CONFIG_RX))

#ifdef LA9310
	#define AXIQDMA_ID_TX0					11
	#define AXIQDMA_ID_TX1					11
	#define AXIQDMA_ID_TX2					11
	#define AXIQDMA_ID_TX3					11
	#define AXIQDMA_ID_TX4					11
	#define AXIQDMA_ID_TX5					11
	#define AXIQDMA_ID_TX(x)				11
	#define AXIQDMA_ID_RX0					1
	#define AXIQDMA_ID_RX1					2
	#define AXIQDMA_ID_RX2					3
	#define AXIQDMA_ID_RX3					4
	#define AXIQDMA_ID_RX4					5
	#define AXIQDMA_ID_RX5					6
	#define AXIQDMA_ID_RX(x)				((x)+1)
	#define AXIQFIFO_ADDR_BASE				0x44000000
	#define AXIQFIFO_ADDR_TX0				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX1				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX2				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX3				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX4				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX5				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_TX(x)				(AXIQFIFO_ADDR_BASE+0xB000)
	#define AXIQFIFO_ADDR_RX0				(AXIQFIFO_ADDR_BASE+0x1000)
	#define AXIQFIFO_ADDR_RX1				(AXIQFIFO_ADDR_BASE+0x2000)
	#define AXIQFIFO_ADDR_RX2				(AXIQFIFO_ADDR_BASE+0x3000)
	#define AXIQFIFO_ADDR_RX3				(AXIQFIFO_ADDR_BASE+0x4000)
	#define AXIQFIFO_ADDR_RX4				(AXIQFIFO_ADDR_BASE+0x5000)
	#define AXIQFIFO_ADDR_RX5				(AXIQFIFO_ADDR_BASE+0x6000)
	#define AXIQFIFO_ADDR_RX(x)				(AXIQFIFO_ADDR_BASE+((x)+1)*0x1000)
	#define AXIQ_GPO_TX0					7
	#define AXIQ_GPI_TX0					1
	#define AXIQ_STATUS_ENABLE_BITFIELD_TX0	(1<<16)
	#define AXIQ_STATUS_UNDERF_BITFIELD_TX0	((1<<18)|(1<<19))

#else
	#define AXIQDMA_ID_TX0					4
	#define AXIQDMA_ID_TX1					5
	#define AXIQDMA_ID_TX2					9
	#define AXIQDMA_ID_TX3					10
	#define AXIQDMA_ID_TX4					14
	#define AXIQDMA_ID_TX5					15
	#define AXIQDMA_ID_TX(x)				((x)/2*5+4+((x)%2))
	#define AXIQDMA_ID_RX0					1
	#define AXIQDMA_ID_RX1					2
	#define AXIQDMA_ID_RX2					6
	#define AXIQDMA_ID_RX3					7
	#define AXIQDMA_ID_RX4					11
	#define AXIQDMA_ID_RX5					12
	#define AXIQDMA_ID_RX(x)				((x)/2*5+1+((x)%2))
	#define AXIQFIFO_ADDR_BASE				0xD2000000
	#define AXIQFIFO_ADDR_TX0				(AXIQFIFO_ADDR_BASE+0x10000)
	#define AXIQFIFO_ADDR_TX1				(AXIQFIFO_ADDR_BASE+0x11000)
	#define AXIQFIFO_ADDR_TX2				(AXIQFIFO_ADDR_BASE+0x20000)
	#define AXIQFIFO_ADDR_TX3				(AXIQFIFO_ADDR_BASE+0x21000)
	#define AXIQFIFO_ADDR_TX4				(AXIQFIFO_ADDR_BASE+0x00000)
	#define AXIQFIFO_ADDR_TX5				(AXIQFIFO_ADDR_BASE+0x08000)
	#define AXIQFIFO_ADDR_RX0				(AXIQFIFO_ADDR_BASE+0x10000)
	#define AXIQFIFO_ADDR_RX1				(AXIQFIFO_ADDR_BASE+0x11000)
	#define AXIQFIFO_ADDR_RX2				(AXIQFIFO_ADDR_BASE+0x20000)
	#define AXIQFIFO_ADDR_RX3				(AXIQFIFO_ADDR_BASE+0x21000)
	#define AXIQFIFO_ADDR_RX4				(AXIQFIFO_ADDR_BASE+0x00000)
	#define AXIQFIFO_ADDR_RX5				(AXIQFIFO_ADDR_BASE+0x08000)
	#define AXIQFIFO_ADDR_TX(x)				(AXIQFIFO_ADDR_BASE+0x10000+(x)/2*0x10000+((x)%2)*0x1000)
	#define AXIQFIFO_ADDR_RX(x)				AXIQFIFO_ADDR_TX(x)
	#define HS_AXIQFIFO_ADDR_TX(x)			(AXIQFIFO_ADDR_BASE+0x08000*(x))
	#define HS_AXIQFIFO_ADDR_RX(x)			HS_AXIQFIFO_ADDR_TX(x)
	#define AXIQ_GPO_TX0					AXIQ0_LS_CONTROL1_GPOUT
	#define AXIQ_GPI_TX0					AXIQ0_LS_STATUS1_GPIN
	#define AXIQ_STATUS_ENABLE_BITFIELD_TX0	LS_AXIQ_STS_TX0_CH_EN_MASK
	#define AXIQ_STATUS_UNDERF_BITFIELD_TX0	(LS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK)
#endif

#define IQSWAP_BITIDX(trid)			(0x0+(trid))
#define HWDCM_BITIDX				31
#define HWDCM_MASK					(1<<HWDCM_BITIDX)
#define ANT_ID_BITIDX(trid)			(0x0+(trid)*4)


#define GPOUT0                          (0x580 >> 2)
#define GPO(x)      (GPOUT0 + (x))
#define GPIN0                           (0x500 >> 2)
#define GPI(x)      (GPIN0 + (x))

#define TCM_BASE	0x20000000
#define VCPU_DMEM_SIZE_LA12xx		0x20000
#define VCPU_DMEM_SIZE_LA9310		0x4000

#define NUM_ANT_BUFFERS	2

typedef struct buf_stat_td_s
{
	unsigned int buf_stat_size;
	unsigned int buf_addr[MAX_NUM_1R_IN_CORE];
	unsigned int offset_in_sframe;
//	unsigned int sym_idx;
} struct_buf_stat_td;

typedef struct struct_antman_ctrl_tx_s
{
	unsigned short	dcs_id;     //the highest dcs id in all dcs id
	unsigned short	num_buffers;
	unsigned short	num_DMA_in_progress;
	unsigned short 	axiq_dma_chan;
	unsigned short	num_valid_buffers;
	unsigned short	num_empty_buffers;
	unsigned int 	axiq_fifo_addr;
	unsigned short 	axiq_control_gpo;
	unsigned short	axiq_status_gpi;
	unsigned int 	axiq_control_enable_bitfield;
	unsigned int 	axiq_control_fifo_rst_clr_err_bitfield;
	unsigned int 	axiq_status_enable_bitfield;
	unsigned int 	axiq_status_rst_complete_bitfield;
	unsigned int 	axiq_status_err_bitfield;
	unsigned int 	axiq_underflow_overflow_bitfield;
	unsigned int 	tx_allowed_bitfield;
	struct_buf_stat_td	buf_stat_ant_tx[NUM_ANT_BUFFERS];
	struct_buf_stat_td*	wr_ptr_buf_stat_ant_tx;
	struct_buf_stat_td*	rd_ptr_buf_stat_ant_tx;
	struct_buf_stat_td*	chk_ptr_buf_stat_ant_tx;
} struct_antman_ctrl_tx; 

typedef struct struct_antman_ctrl_rx_s
{
	unsigned short	dcs_id;
	unsigned short	num_buffers;
	unsigned short	num_DMA_in_progress;
	unsigned short 	axiq_dma_chan;
	unsigned short 	num_valid_buffers;
	unsigned short	sps_div;
	unsigned int 	axiq_fifo_addr;
	unsigned short 	axiq_control_gpo;
	unsigned short 	axiq_status_gpi;
	unsigned int 	axiq_control_enable_bitfield;
	unsigned int 	axiq_control_fifo_rst_clr_err_bitfield;
	unsigned int 	axiq_status_err_bitfield;
	unsigned int 	axiq_status_rst_complete_bitfield;
	unsigned int 	axiq_status_enable_bitfield;
	unsigned int 	axiq_underflow_overflow_bitfield;
	unsigned int 	rx_allowed_bitfield;
	struct_buf_stat_td	buf_stat_ant_rx[NUM_ANT_BUFFERS];
	struct_buf_stat_td*	wr_ptr_buf_stat_ant_rx;
	struct_buf_stat_td*	rd_ptr_buf_stat_ant_rx;
	unsigned short	ant_buf_size;
	unsigned short	sym_idx;
	unsigned int	offset_in_sframe;
	unsigned int	rxext_size;
//	unsigned int	rxext_size_remainder;
	unsigned int	skip1;
	unsigned int	rx_size;//feed_block_counter;
} struct_antman_ctrl_rx;


//#include "eDMA_la9310.h"



#define dsb(opt) asm volatile("dsb " #opt : : : "memory")
#define dmb(opt) asm volatile("dmb " #opt : : : "memory")

static inline uint32_t ioread32(const volatile void *addr)
{
    uint32_t val;

    asm volatile(
            "ldr %w[val], [%x[addr]]"
            : [val] "=r" (val)
            : [addr] "r" (addr));

    dsb(ld);
    return val;
}

static inline uint64_t ioread64(const volatile void *addr)
{
    uint64_t val;

    asm volatile(
            "ldr %x[val], [%x[addr]]"
            : [val] "=r" (val)
            : [addr] "r" (addr));

    dsb(ld);
    return val;
}

static inline void iowrite32(uint32_t val, volatile void *addr)
{
    dsb(st);
    asm volatile(
            "str %w[val], [%x[addr]]"
            :
            : [val] "r" (val), [addr] "r" (addr));
}

static inline void iowrite64(uint64_t val, volatile void *addr)
{
    dsb(st);
    asm volatile(
            "str %x[val], [%x[addr]]"
            :
            : [val] "r" (val), [addr] "r" (addr));
}


//convert float16 to float 32.  float 16 has 1 sign bit + 5 shift bit + 10 fractional bit. float 32 has 1 sign bit + 8 shift bit + 23 fractinal bit
int float16_to_float32(short data16)
{
	unsigned int sign, data;
	unsigned int data32;
	sign = data16 & 0x8000;
	data = data16 & 0x7FFF;
	
#if 1     //use 0 for input data range is within valid range
	if(data>=0x7c00)  //infinity or not representable
	{
		data32 =  (sign << 16) | 0x7F800000 ;      // presented with infinity
	}
	else if(data<=0x03FF)  //0
	{
		data32 = (sign << 16) | 0;
	}
	else
		data32 = (sign << 16) | ((data<<(16-3))+(0x70<<23));   //change from EXP from (EXP field-15) to (EXP field-127), need compensate 127-15 = 112 = 0x70,
#else
	data32 = (sign << 16) | ((data << (16 - 3)) + (0x70 << 23));   //change from EXP from (EXP field-15) to (EXP field-127), need compensate 127-15 = 112 = 0x70,
#endif
	return (int)data32;
}

uint32_t get_vspa_dmem_addr_offset_host_view(uint32_t vspa_dmem_addr_vspa_view)
{
	uint32_t vcpu_dmem_size;
	if(g_dfe_ref_la9310)
		vcpu_dmem_size = VCPU_DMEM_SIZE_LA9310;
	else
		vcpu_dmem_size = VCPU_DMEM_SIZE_LA12xx;
	
	if(vspa_dmem_addr_vspa_view >= vcpu_dmem_size)
		return vspa_dmem_addr_vspa_view - vcpu_dmem_size + 0x100000;
	else
		return vspa_dmem_addr_vspa_view;
}

void qec_para_convert(void* p_qec_para_converted, void* p_qec_para)
{
	uint64_t  addr_qec_para = (uint64_t)p_qec_para;
	float f1=*(float*)((addr_qec_para+128+4*2));
	float f2=*(float*)((addr_qec_para+128+4*3));
	float f4=*(float*)((addr_qec_para+128+4*4));
	float gre=*(float*)((addr_qec_para+128+4*5));
	float gim=*(float*)((addr_qec_para+128+4*6));
	float dcre=*(float*)((addr_qec_para+128+4*7));
	float dcim=*(float*)((addr_qec_para+128+4*8));
	
		
	//convert to struct for optimized QEC
	uint64_t  addr_qec_para_converted = (uint64_t)p_qec_para_converted;
		
	if (gim == 0) gim = gre;
	
	f1 *= gre;
	f2 *= gim;
	f4 *= gim;
	
	*(float*)(addr_qec_para_converted+4*0) = f1;
	*(float*)(addr_qec_para_converted+4*1) = f4;
	*(float*)(addr_qec_para_converted+4*2) = 0;
	*(float*)(addr_qec_para_converted+4*3) = f2;
	*(float*)(addr_qec_para_converted+4*4) = dcre;
	*(float*)(addr_qec_para_converted+4*5) = dcim;
	*(float*)(addr_qec_para_converted+4*6) = f1;
	*(float*)(addr_qec_para_converted+4*7) = f4;
	*(float*)(addr_qec_para_converted+4*8) = 0;
	*(float*)(addr_qec_para_converted+4*9) = f2;
	*(float*)(addr_qec_para_converted+4*10) = dcre;
	*(float*)(addr_qec_para_converted+4*11) = dcim;
}


uint64_t check_error_core(uint32_t core)
{
	//check DMA error
	uint32_t config_error = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_CFGERR_STAT);
	if(config_error)
	{
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_CFGERR_STAT) = config_error; //clear config error status bits
		return (((uint64_t)(MSG_ID_ERROR_REPORT_MSG|(ERROR_REPORT_MSG_ERROR_TYPE_DMA_CONFIG_ERR<<16)))<<32)|config_error;
	}
	uint32_t transfer_error = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_XFRERR_STAT);
	if(transfer_error)
	{
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_XFRERR_STAT) = transfer_error;
		return (((uint64_t)(MSG_ID_ERROR_REPORT_MSG|(ERROR_REPORT_MSG_ERROR_TYPE_DMA_TRANSFER_ERR<<16)))<<32)|transfer_error;
	}
	uint32_t ippu_error = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IPPUSTATUS);
	if(ippu_error&(1<<27)) //cmd error
	{
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IPPURC) = 0x80000000;  //clear cmd error status bit
		return (((uint64_t)(MSG_ID_ERROR_REPORT_MSG|(ERROR_REPORT_MSG_ERROR_TYPE_IPPU_ERR<<16)))<<32)|ippu_error;
	}
	uint64_t vspa_dmem_base_vir = (uint64_t)mmap(NULL, 0x400000*8, PROT_READ | PROT_WRITE,	MAP_SHARED, g_devmem_fd, g_vspa_dmem_base_phy);
	uint64_t dcs_error = *(uint64_t*)(vspa_dmem_base_vir+core*0x400000+error_info);
	if(dcs_error)
	{
		*(uint64_t*)(vspa_dmem_base_vir+core*0x400000+error_info) = 0; //clear the error
	}
	return dcs_error;
}	

void dmac_enable(unsigned int ctrl, unsigned int size, unsigned int axi_addr, unsigned int dmem_addr)
{
	unsigned int core = 0;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_DMEM_PRAM_ADDR) = dmem_addr;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_AXI_ADDRESS) = axi_addr;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_AXI_BYTE_CNT) = size;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_XFR_CTRL) = ctrl;
}
#ifdef LA9310
#define UNIT2BYTE(x)	((x)*2)
#else
#define UNIT2BYTE(x)	((x)*1)
#endif

volatile unsigned int counter;
void delay_cycles(unsigned int cycles)
{
	for(unsigned int i = 0; i<cycles; i++)
	{
		counter++;
	}
}

void dmac_abort(unsigned int mask)
{
	unsigned int core = 0;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+DMA_STAT_ABORT) = mask;
}

void Ant_buffer_tx_axiq_reset(unsigned int dcs_id, uint64_t vspa_dmem_base_vir)
{
	unsigned int core = 0;
	struct_antman_ctrl_tx antman_ctrl_tx;
	antman_ctrl_tx.axiq_dma_chan = AXIQDMA_ID_TX0;
	antman_ctrl_tx.axiq_fifo_addr = AXIQFIFO_ADDR_TX0+AXIQFIFO_OFFSET_THRESHOLD_TX;
	antman_ctrl_tx.axiq_control_gpo = GPO(AXIQ_GPO_TX0);
	antman_ctrl_tx.axiq_status_gpi = GPI(AXIQ_GPI_TX0);
	antman_ctrl_tx.axiq_control_enable_bitfield = LS_AXIQ_CTL_TX0_CH_EN_MASK;
	antman_ctrl_tx.axiq_status_enable_bitfield = AXIQ_STATUS_ENABLE_BITFIELD_TX0;
	antman_ctrl_tx.axiq_underflow_overflow_bitfield = AXIQ_STATUS_UNDERF_BITFIELD_TX0;
	antman_ctrl_tx.axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX0_CLEAR_ERROR_MASK;		
	antman_ctrl_tx.buf_stat_ant_tx[0].buf_addr[0] = 0;
	unsigned int addr_temp = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_circ_base);  //used for temp addr for vspa DMA VCPU addr

	unsigned int axiq_dma_chan = antman_ctrl_tx.axiq_dma_chan;

	dmac_abort(1<<axiq_dma_chan);
	
	#ifdef LA9310
	//configure a short DMA with PTR_RST to reset AXIQ, 9310 AXIQ can only reset by ptr_rst
	dmac_enable(DMAC_PRST_REQ | DMA_TRIG | DMAC_WRC | DMAC_FIFO_HS | axiq_dma_chan, 64, antman_ctrl_tx.axiq_fifo_addr, addr_temp);
	delay_cycles(1000);
	//if AXIQ is in normal state, this DMA will be pending there, then abort it.
	//if AXIQ is in Flush mode, this DMA will be consumed and Flush mode will be ended, then this abort will take no effect.
	dmac_abort(1<<axiq_dma_chan);
	#endif

	//disable AXIQ, reset AXIQ(LA12xx only), clr errors
	//__ip_write(antman_ctrl_tx->axiq_control_gpo, antman_ctrl_tx->axiq_control_enable_bitfield|antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield, antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield);
	unsigned int gpo = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_tx.axiq_control_gpo*4);
	gpo &= ~(antman_ctrl_tx.axiq_control_enable_bitfield|antman_ctrl_tx.axiq_control_fifo_rst_clr_err_bitfield);
	gpo |= antman_ctrl_tx.axiq_control_fifo_rst_clr_err_bitfield;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_tx.axiq_control_gpo*4) = gpo;
	delay_cycles(32); //wait at least 8 clocks for reset to complete
	//__ip_write(antman_ctrl_tx->axiq_control_gpo, antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield, 0);
	gpo &= ~antman_ctrl_tx.axiq_control_fifo_rst_clr_err_bitfield;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_tx.axiq_control_gpo*4) = gpo;
}
void Ant_buffer_rx_axiq_reset(unsigned int dcs_id, uint64_t vspa_dmem_base_vir)
{
	unsigned int core = 0;
	struct_antman_ctrl_rx antman_ctrl_rx;
	antman_ctrl_rx.axiq_fifo_addr = AXIQFIFO_ADDR_RX0 + dcs_id * 0x1000 +AXIQFIFO_OFFSET_THRESHOLD_RX;
	antman_ctrl_rx.axiq_dma_chan = (AXIQDMA_ID_RX0+dcs_id);		
	antman_ctrl_rx.dcs_id = dcs_id;
	antman_ctrl_rx.axiq_control_gpo = GPO(4);
	antman_ctrl_rx.axiq_status_gpi = GPI(0);
	antman_ctrl_rx.axiq_control_enable_bitfield = LS_AXIQ_CTL_RX0_CH_EN_MASK<<(dcs_id*8);
	antman_ctrl_rx.axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX0_CLEAR_ERROR_MASK<<(dcs_id*8);
	antman_ctrl_rx.axiq_status_err_bitfield = 0xc<<(dcs_id*4);
	antman_ctrl_rx.axiq_status_enable_bitfield = LS_AXIQ_STS_RX0_CH_EN_MASK<<(dcs_id*4);
	antman_ctrl_rx.axiq_underflow_overflow_bitfield = 0xc<<(dcs_id*4);
	unsigned int addr_temp = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_circ_base);  //used for temp addr for vspa DMA VCPU addr

	unsigned int axiq_dma_chan = antman_ctrl_rx.axiq_dma_chan;
	dmac_abort(1<<axiq_dma_chan);

	#ifdef LA9310
	//configure a short DMA with PTR_RST to reset AXIQ, 9310 AXIQ can only reset by ptr_rst
	dmac_enable(DMAC_PRST_REQ | DMA_TRIG | DMAC_RDC | DMAC_FIFO_HS | axiq_dma_chan, 64, antman_ctrl_rx.axiq_fifo_addr, addr_temp);
	delay_cycles(1000);
	//if AXIQ is in normal state, this DMA will be pending there, then abort it.
	//if AXIQ is in Flush mode, this DMA will be consumed and Flush mode will be ended, then this abort will take no effect.
	dmac_abort(1<<axiq_dma_chan);
	#endif

	//disable AXIQ, reset AXIQ(LA12xx only), clr errors
	//__ip_write(antman_ctrl_rx->axiq_control_gpo, antman_ctrl_rx->axiq_control_enable_bitfield|antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield, antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield);
	unsigned int gpo = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_rx.axiq_control_gpo*4);
	gpo &= ~(antman_ctrl_rx.axiq_control_enable_bitfield|antman_ctrl_rx.axiq_control_fifo_rst_clr_err_bitfield);
	gpo |= antman_ctrl_rx.axiq_control_fifo_rst_clr_err_bitfield;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_rx.axiq_control_gpo*4) = gpo;
	delay_cycles(32); //wait at least 8 clocks for reset to complete
	//__ip_write(antman_ctrl_rx->axiq_control_gpo, antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield, 0);
	gpo &= ~antman_ctrl_rx.axiq_control_fifo_rst_clr_err_bitfield;
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_rx.axiq_control_gpo*4) = gpo;
}
int Ant_buffer_tx_init(unsigned int dcs_id, unsigned int iq_swap, uint64_t vspa_dmem_base_vir)
{
	unsigned int core = 0;
	unsigned int reg_value, reg_mask;
	unsigned int v_addr_antman_tx = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+addr_antman_tx);
	struct_antman_ctrl_tx* antman_ctrl_tx = (struct_antman_ctrl_tx*)(vspa_dmem_base_vir+core*0x400000+v_addr_antman_tx);
#ifdef LA9310
	antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX0;
	antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX0+AXIQFIFO_OFFSET_THRESHOLD_TX;
//	antman_ctrl_tx->dcs_id = 0;
	antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ_GPO_TX0);
	antman_ctrl_tx->axiq_status_gpi = GPI(AXIQ_GPI_TX0);
	antman_ctrl_tx->axiq_control_enable_bitfield = LS_AXIQ_CTL_TX0_CH_EN_MASK;
	antman_ctrl_tx->axiq_status_enable_bitfield = AXIQ_STATUS_ENABLE_BITFIELD_TX0;
	antman_ctrl_tx->axiq_underflow_overflow_bitfield = AXIQ_STATUS_UNDERF_BITFIELD_TX0;
	antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX0_CLEAR_ERROR_MASK;		
	reg_value = LS_AXIQ_CTL_TX0_CH_EN_MASK | (FIFO_THRESHOLD_CONFIG_TX << LS_AXIQ_CTL_TX0_FIFO_THRESH_LSB) | (iq_swap<<LS_AXIQ_CTL_TX0_SWAP_B);
	reg_mask = LS_AXIQ_CTL_TX0_CH_EN_MASK | LS_AXIQ_CTL_TX0_FIFO_THRESH_MASK | LS_AXIQ_CTL_TX0_SWAP_MASK;

#else
	antman_ctrl_tx->dcs_id = dcs_id;
	if(dcs_id == 0)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX0;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX0;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ_GPO_TX0);
		antman_ctrl_tx->axiq_status_gpi = GPI(AXIQ_GPI_TX0);
		antman_ctrl_tx->axiq_control_enable_bitfield = LS_AXIQ_CTL_TX0_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = AXIQ_STATUS_ENABLE_BITFIELD_TX0;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = AXIQ_STATUS_UNDERF_BITFIELD_TX0;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX0_RESET_FIFO_MASK | LS_AXIQ_CTL_TX0_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = LS_AXIQ_STS_TX0_FIFO_RST_ERR_MASK | LS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_TX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = LS_AXIQ_STS_TX0_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_TX0_CH_EN_MASK | LS_AXIQ_CTL_TX0_COMPLEX_MODE_MASK | (iq_swap<<LS_AXIQ_CTL_TX0_SWAP_B);
		reg_mask = LS_AXIQ_CTL_TX0_CH_EN_MASK | LS_AXIQ_CTL_TX0_COMPLEX_MODE_MASK | LS_AXIQ_CTL_TX0_SWAP_MASK;
	}
	else if(dcs_id == 1)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX1;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX1;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ0_LS_CONTROL1_GPOUT);
		antman_ctrl_tx->axiq_control_enable_bitfield = LS_AXIQ_CTL_TX1_CH_EN_MASK;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX1_RESET_FIFO_MASK | LS_AXIQ_CTL_TX1_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = LS_AXIQ_STS_TX1_FIFO_RST_ERR_MASK | LS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_TX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = LS_AXIQ_STS_TX1_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_gpi = GPI(0) + AXIQ0_LS_STATUS1_GPIN;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = LS_AXIQ_STS_TX1_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_TX1_CH_EN_MASK | LS_AXIQ_CTL_TX1_COMPLEX_MODE_MASK | (iq_swap<<LS_AXIQ_CTL_TX1_SWAP_B);
		reg_mask = LS_AXIQ_CTL_TX1_CH_EN_MASK | LS_AXIQ_CTL_TX1_COMPLEX_MODE_MASK | LS_AXIQ_CTL_TX1_SWAP_MASK;
	}
	else if(dcs_id == 2)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX2;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX2;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ1_LS_CONTROL1_GPOUT);
		antman_ctrl_tx->axiq_control_enable_bitfield = LS_AXIQ_CTL_TX0_CH_EN_MASK;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX0_RESET_FIFO_MASK | LS_AXIQ_CTL_TX0_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = LS_AXIQ_STS_TX0_FIFO_RST_ERR_MASK | LS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_TX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = LS_AXIQ_STS_TX0_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_gpi = GPI(0) + AXIQ1_LS_STATUS1_GPIN;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = LS_AXIQ_STS_TX0_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_TX0_CH_EN_MASK | LS_AXIQ_CTL_TX0_COMPLEX_MODE_MASK | (iq_swap<<LS_AXIQ_CTL_TX0_SWAP_B);
		reg_mask = LS_AXIQ_CTL_TX0_CH_EN_MASK | LS_AXIQ_CTL_TX0_COMPLEX_MODE_MASK | LS_AXIQ_CTL_TX0_SWAP_MASK;
	}
	else if(dcs_id == 3)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX3;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX3;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ1_LS_CONTROL1_GPOUT);
		antman_ctrl_tx->axiq_control_enable_bitfield = LS_AXIQ_CTL_TX1_CH_EN_MASK;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_TX1_RESET_FIFO_MASK | LS_AXIQ_CTL_TX1_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = LS_AXIQ_STS_TX1_FIFO_RST_ERR_MASK | LS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_TX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = LS_AXIQ_STS_TX1_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_gpi = GPI(0) + AXIQ1_LS_STATUS1_GPIN;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = LS_AXIQ_STS_TX1_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_TX1_CH_EN_MASK | LS_AXIQ_CTL_TX1_COMPLEX_MODE_MASK | (iq_swap<<LS_AXIQ_CTL_TX1_SWAP_B);
		reg_mask = LS_AXIQ_CTL_TX1_CH_EN_MASK | LS_AXIQ_CTL_TX1_COMPLEX_MODE_MASK | LS_AXIQ_CTL_TX1_SWAP_MASK;
	}
	else if(dcs_id == 4)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX4;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX4;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ_HS_CONTROL0_GPOUT);
		antman_ctrl_tx->axiq_control_enable_bitfield = HS_AXIQ_CTL_TX_CH_EN_MASK;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = HS_AXIQ_CTL_TX_RESET_FIFO_MASK | HS_AXIQ_CTL_TX_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = HS_AXIQ_STS_TX0_FIFO_RST_ERR_MASK | HS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = HS_AXIQ_STS_TX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = HS_AXIQ_STS_TX0_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_gpi = GPI(0) + AXIQ_HS_STATUS1_GPIN;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = HS_AXIQ_STS_TX0_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_TX0_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = HS_AXIQ_STS_TX0_CH_ALLOWED_MASK;
		reg_value = HS_AXIQ_CTL_TX_CH_EN_MASK | (iq_swap<<HS_AXIQ_CTL_TX_SWAP_B);
		reg_mask = HS_AXIQ_CTL_TX_CH_EN_MASK | HS_AXIQ_CTL_TX_SWAP_MASK;
	}
	else if(dcs_id == 5)
	{
		antman_ctrl_tx->axiq_dma_chan = AXIQDMA_ID_TX5;
		antman_ctrl_tx->axiq_fifo_addr = AXIQFIFO_ADDR_TX5;
		antman_ctrl_tx->axiq_control_gpo = GPO(AXIQ_HS_CONTROL1_GPOUT);
		antman_ctrl_tx->axiq_control_enable_bitfield = HS_AXIQ_CTL_TX_CH_EN_MASK;
		antman_ctrl_tx->axiq_control_fifo_rst_clr_err_bitfield = HS_AXIQ_CTL_TX_RESET_FIFO_MASK | HS_AXIQ_CTL_TX_CLEAR_ERROR_MASK;
		antman_ctrl_tx->axiq_status_err_bitfield = HS_AXIQ_STS_TX1_FIFO_RST_ERR_MASK | HS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->axiq_status_rst_complete_bitfield = HS_AXIQ_STS_TX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_tx->axiq_status_enable_bitfield = HS_AXIQ_STS_TX1_CH_EN_MASK;
		antman_ctrl_tx->axiq_status_gpi = GPI(0) + AXIQ_HS_STATUS1_GPIN;
		antman_ctrl_tx->axiq_underflow_overflow_bitfield = HS_AXIQ_STS_TX1_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_TX1_OVERFLOW_ERR_MASK;
		antman_ctrl_tx->tx_allowed_bitfield = HS_AXIQ_STS_TX1_CH_ALLOWED_MASK;
		reg_value = HS_AXIQ_CTL_TX_CH_EN_MASK | (iq_swap<<HS_AXIQ_CTL_TX_SWAP_B);
		reg_mask = HS_AXIQ_CTL_TX_CH_EN_MASK | HS_AXIQ_CTL_TX_SWAP_MASK;
	}
#endif

	//__ip_write(antman_ctrl_tx->axiq_control_gpo, reg_mask, 0);  //disable AXIQ if it's enabled before initialization
	//delay_cycles(32);
	//start a short DMA to reset FIFO
	//dmac_enable(DMAC_WRC|DMAC_PRST_REQ|antman_ctrl_tx->axiq_dma_chan, 64, antman_ctrl_tx->axiq_fifo_addr, UNIT2BYTE(antman_ctrl_tx->buf_stat_ant_tx[0].buf_addr[0]));
	
	
	//Ant_buffer_tx_axiq_reset();  //clr potential errors before starting to work
	
	#ifdef LA9310
	//for LA9310, enable status bit will not be set until tx_allowed is asserted, so no need to check enable status
	//__ip_write(antman_ctrl_tx->axiq_control_gpo, reg_mask, reg_value);
	unsigned int axiq_control = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_tx->axiq_control_gpo*4);
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_tx->axiq_control_gpo*4) = (axiq_control & (~reg_mask)) | reg_value;
	#else
	//for LA12xx, enable status is set right after enable control bit is set. As the same register is used by multiple DCS channels
	//and multiple core may write to the same control register, failure may happen when multiple core write at the same time.
	//need to check enable bit status to confirm channle is enabled.
	unsigned int counter=5;
	do
	{
		__ip_write(antman_ctrl_tx->axiq_control_gpo, reg_mask, reg_value);
		counter--;
		if(counter==0)
		{
			mailbox_send_msg(MAILBOX_USED_FOR_ERROR_REPORT,SET_ERROR_TYPE(ERROR_REPORT_MSG_ERROR_TYPE_TXAXIQ_ENABLING_ERROR)|SET_ERROR_ANT_ID(dcs_id)|0xFFF, 0xFFFFFFFF);
			break;
		}
		delay_cycles(32);
	} while (!__ip_read(antman_ctrl_tx->axiq_status_gpi, antman_ctrl_tx->axiq_status_enable_bitfield));
	#endif
	
	
	#ifdef LOG_TYPE_INIT_TX_ANTMAN
	log_2int(LOG_TYPE_INIT_TX_ANTMAN|antman_ctrl_tx->dcs_id, __ip_read(antman_ctrl_tx->axiq_status_gpi));
	#endif
	
//	unsigned int error = __ip_read(antman_ctrl_tx->axiq_status_gpi, antman_ctrl_tx->axiq_underflow_overflow_bitfield);
//#ifndef LA9310
//	error |= get_tx_allowed_status(tid);
//#endif
//	if(error)
//		mailbox_send_error_msg(SET_ERROR_TYPE(ERROR_REPORT_MSG_ERROR_TYPE_TXAXIQ_INIT_STATE_ERROR)|SET_ERROR_TR_ID(tid)|SET_ERROR_ANT_ID(dcs_id)|0xFFF, error);
//	
//	//check AXIQ status, return error.
//	return error;
	return 0;  //error just cleared, no need to check error here.  if there is error, it will be checked at runtime.
}
int Ant_buffer_rx_init(unsigned int dcs_ids, unsigned int ctrl_iqswap, uint64_t vspa_dmem_base_vir)
{
	unsigned int core = 0;
	unsigned int v_addr_antman_rx = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+addr_antman_rx);
	struct_antman_ctrl_rx* antman_ctrl_rx = (struct_antman_ctrl_rx*)(vspa_dmem_base_vir+core*0x400000+v_addr_antman_rx);

	unsigned int iq_swap = (ctrl_iqswap>>IQSWAP_BITIDX(0))&1;
	unsigned int iq_swap2 = (ctrl_iqswap>>IQSWAP_BITIDX(1))&1;
	unsigned int hw2xdecim = ctrl_iqswap >> HWDCM_BITIDX;
	unsigned int reg_value, reg_mask;
	unsigned int dcs_id2 = (dcs_ids >> ANT_ID_BITIDX(1)) & 0x7;
	unsigned int dcs_id = (dcs_ids >> ANT_ID_BITIDX(0)) & 0x7;

#ifdef LA9310
	antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX0 + dcs_id * 0x1000 +AXIQFIFO_OFFSET_THRESHOLD_RX;
	antman_ctrl_rx->axiq_dma_chan = (AXIQDMA_ID_RX0+dcs_id);		
	antman_ctrl_rx->dcs_id = dcs_ids;
	antman_ctrl_rx->axiq_control_gpo = GPO(4);
	antman_ctrl_rx->axiq_status_gpi = GPI(0);
	antman_ctrl_rx->axiq_control_enable_bitfield = LS_AXIQ_CTL_RX0_CH_EN_MASK<<(dcs_id*8);
	antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX0_CLEAR_ERROR_MASK<<(dcs_id*8);
	antman_ctrl_rx->axiq_status_err_bitfield = 0xc<<(dcs_id*4);
//	antman_ctrl_rx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_RX0_FIFO_RST_COMPL_MASK;
	antman_ctrl_rx->axiq_status_enable_bitfield = LS_AXIQ_STS_RX0_CH_EN_MASK<<(dcs_id*4);
	antman_ctrl_rx->axiq_underflow_overflow_bitfield = 0xc<<(dcs_id*4);
//	antman_ctrl_rx->rx_allowed_bitfield = LS_AXIQ_STS_RX0_CH_ALLOWED_MASK;
	reg_value = (LS_AXIQ_CTL_RX0_CH_EN_MASK | (FIFO_THRESHOLD_CONFIG_RX<<LS_AXIQ_CTL_RX0_FIFO_THRESH_LSB) | (iq_swap<<LS_AXIQ_CTL_RX0_SWAP_B))<<(dcs_id*8);
	reg_mask = (LS_AXIQ_CTL_RX0_CH_EN_MASK | LS_AXIQ_CTL_RX0_FIFO_THRESH_MASK | LS_AXIQ_CTL_RX0_SWAP_MASK)<<(dcs_id*8);
	if(dcs_id2 != 0x7)
	{
		reg_value |= (LS_AXIQ_CTL_RX0_CH_EN_MASK | (FIFO_THRESHOLD_CONFIG_RX<<LS_AXIQ_CTL_RX0_FIFO_THRESH_LSB) | (iq_swap2<<LS_AXIQ_CTL_RX0_SWAP_B))<<(dcs_id2*8);
		reg_mask |= (LS_AXIQ_CTL_RX0_CH_EN_MASK | LS_AXIQ_CTL_RX0_FIFO_THRESH_MASK | LS_AXIQ_CTL_RX0_SWAP_MASK)<<(dcs_id2*8);
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_IDX_FAST_FLAGS) |= 1;
	}

#else
	antman_ctrl_rx->dcs_id = dcs_ids;
	if(dcs_id == 0)
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX0;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX0;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ0_LS_CONTROL0_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = LS_AXIQ_CTL_RX0_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX0_RESET_FIFO_MASK | LS_AXIQ_CTL_RX0_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = LS_AXIQ_STS_RX0_FIFO_RST_ERR_MASK | LS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_RX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = LS_AXIQ_STS_RX0_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ0_LS_STATUS0_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = LS_AXIQ_STS_RX0_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_RX0_CH_EN_MASK | (iq_swap<<LS_AXIQ_CTL_RX0_SWAP_B);
		reg_mask = LS_AXIQ_CTL_RX0_CH_EN_MASK | LS_AXIQ_CTL_RX0_SWAP_MASK;
	}
	else if(dcs_id == 1)
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX1;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX1;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ0_LS_CONTROL0_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = LS_AXIQ_CTL_RX1_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX1_RESET_FIFO_MASK | LS_AXIQ_CTL_RX1_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = LS_AXIQ_STS_RX1_FIFO_RST_ERR_MASK | LS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_RX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = LS_AXIQ_STS_RX1_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ0_LS_STATUS0_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = LS_AXIQ_STS_RX1_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_RX1_CH_EN_MASK | (iq_swap<<LS_AXIQ_CTL_RX1_SWAP_B);
		reg_mask = LS_AXIQ_CTL_RX1_CH_EN_MASK | LS_AXIQ_CTL_RX1_SWAP_MASK;
	}
	else if(dcs_id == 2)
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX2;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX2;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ1_LS_CONTROL0_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = LS_AXIQ_CTL_RX0_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX0_RESET_FIFO_MASK | LS_AXIQ_CTL_RX0_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = LS_AXIQ_STS_RX0_FIFO_RST_ERR_MASK | LS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_RX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = LS_AXIQ_STS_RX0_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ1_LS_STATUS0_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = LS_AXIQ_STS_RX0_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_RX0_CH_EN_MASK | (iq_swap<<LS_AXIQ_CTL_RX0_SWAP_B);
		reg_mask = LS_AXIQ_CTL_RX0_CH_EN_MASK | LS_AXIQ_CTL_RX0_SWAP_MASK;
	}
	else if(dcs_id == 3)
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX3;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX3;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ1_LS_CONTROL0_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = LS_AXIQ_CTL_RX1_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = LS_AXIQ_CTL_RX1_RESET_FIFO_MASK | LS_AXIQ_CTL_RX1_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = LS_AXIQ_STS_RX1_FIFO_RST_ERR_MASK | LS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = LS_AXIQ_STS_RX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = LS_AXIQ_STS_RX1_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ1_LS_STATUS0_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = LS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | LS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = LS_AXIQ_STS_RX1_CH_ALLOWED_MASK;
		reg_value = LS_AXIQ_CTL_RX1_CH_EN_MASK | (iq_swap<<LS_AXIQ_CTL_RX1_SWAP_B);
		reg_mask = LS_AXIQ_CTL_RX1_CH_EN_MASK | LS_AXIQ_CTL_RX1_SWAP_MASK;
	}
	else if(dcs_id == 4)
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX4;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX4;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ_HS_CONTROL0_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = HS_AXIQ_CTL_RX_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = HS_AXIQ_CTL_RX_RESET_FIFO_MASK | HS_AXIQ_CTL_RX_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = HS_AXIQ_STS_RX0_FIFO_RST_ERR_MASK | HS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = HS_AXIQ_STS_RX0_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = HS_AXIQ_STS_RX0_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ_HS_STATUS1_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = HS_AXIQ_STS_RX0_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_RX0_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = HS_AXIQ_STS_RX0_CH_ALLOWED_MASK;
		reg_value = HS_AXIQ_CTL_RX_CH_EN_MASK | (iq_swap<<HS_AXIQ_CTL_RX_SWAP_B) | (hw2xdecim<<HS_AXIQ_CTL_RX_2G_MODE_B);
		reg_mask = HS_AXIQ_CTL_RX_CH_EN_MASK | HS_AXIQ_CTL_RX_SWAP_MASK | HS_AXIQ_CTL_RX_2G_MODE_MASK;
	}
	else
	{
		antman_ctrl_rx->axiq_dma_chan = AXIQDMA_ID_RX5;
		antman_ctrl_rx->axiq_fifo_addr = AXIQFIFO_ADDR_RX5;
		antman_ctrl_rx->axiq_control_gpo = GPO(AXIQ_HS_CONTROL1_GPOUT);
		antman_ctrl_rx->axiq_control_enable_bitfield = HS_AXIQ_CTL_RX_CH_EN_MASK;
		antman_ctrl_rx->axiq_control_fifo_rst_clr_err_bitfield = HS_AXIQ_CTL_RX_RESET_FIFO_MASK | HS_AXIQ_CTL_RX_CLEAR_ERROR_MASK;
		antman_ctrl_rx->axiq_status_err_bitfield = HS_AXIQ_STS_RX1_FIFO_RST_ERR_MASK | HS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->axiq_status_rst_complete_bitfield = HS_AXIQ_STS_RX1_FIFO_RST_COMPL_MASK;
		antman_ctrl_rx->axiq_status_enable_bitfield = HS_AXIQ_STS_RX1_CH_EN_MASK;
		antman_ctrl_rx->axiq_status_gpi = GPI(0) + AXIQ_HS_STATUS1_GPIN;
		antman_ctrl_rx->axiq_underflow_overflow_bitfield = HS_AXIQ_STS_RX1_UNDERFLOW_ERR_MASK | HS_AXIQ_STS_RX1_OVERFLOW_ERR_MASK;
		antman_ctrl_rx->rx_allowed_bitfield = HS_AXIQ_STS_RX1_CH_ALLOWED_MASK;
		reg_value = HS_AXIQ_CTL_RX_CH_EN_MASK | (iq_swap<<HS_AXIQ_CTL_RX_SWAP_B) | (hw2xdecim<<HS_AXIQ_CTL_RX_2G_MODE_B);
		reg_mask = HS_AXIQ_CTL_RX_CH_EN_MASK | HS_AXIQ_CTL_RX_SWAP_MASK | HS_AXIQ_CTL_RX_2G_MODE_MASK;
	}
#endif

	//__ip_write(antman_ctrl_rx->axiq_control_gpo, reg_mask, 0);
	//delay_cycles(32);

	//start a short DMA to reset FIFO
	//dmac_enable(DMAC_RDC|DMAC_PRST_REQ|antman_ctrl_rx->axiq_dma_chan, 64, antman_ctrl_rx->axiq_fifo_addr, UNIT2BYTE(antman_ctrl_rx->buf_stat_ant_rx[0].buf_addr[0]));
	
	//Ant_buffer_rx_axiq_reset();  //clr potential errors before initializing AXIQ
		                               
	#ifdef LA9310
	//antman_ctrl_rx->offset_in_sframe = SIZE_PER_SYSPERIOD(RX_AXIQ_SPS);
	//for LA9310, enable status bit will not be set until tx_allowed is asserted, so no need to check enable status
	//__ip_write(antman_ctrl_rx->axiq_control_gpo, reg_mask, reg_value);
	unsigned int axiq_control = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_rx->axiq_control_gpo*4);
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+antman_ctrl_rx->axiq_control_gpo*4) = (axiq_control & (~reg_mask)) | reg_value;

	#else
	antman_ctrl_rx->offset_in_sframe = SIZE_PER_SYSPERIOD(RX_AXIQ_SPS)>>antman_ctrl_rx->sps_div;
	//for LA12xx, enable status is set right after enable control bit is set. As the same register is used by multiple DCS channels
	//and multiple core may write to the same control register, failure may happen when multiple core write at the same time.
	//need to check enable bit status to confirm channle is enabled.
	unsigned int counter=5;
	do
	{
		__ip_write(antman_ctrl_rx->axiq_control_gpo, reg_mask, reg_value);
		counter--;
		if(counter==0)
		{
			mailbox_send_msg(MAILBOX_USED_FOR_ERROR_REPORT,SET_ERROR_TYPE(ERROR_REPORT_MSG_ERROR_TYPE_RXAXIQ_ENABLING_ERROR)|SET_ERROR_ANT_ID(dcs_id)|0xFFF, 0xFFFFFFFF);
			break;
		}
		delay_cycles(32);
	} while (!__ip_read(antman_ctrl_rx->axiq_status_gpi, antman_ctrl_rx->axiq_status_enable_bitfield));
	#endif
	
	
	#ifdef LOG_TYPE_INIT_RX_ANTMAN
	log_2int(LOG_TYPE_INIT_RX_ANTMAN|antman_ctrl_rx->dcs_id, __ip_read(antman_ctrl_rx->axiq_status_gpi));
	#endif


	
//	//check AXIQ status, return error.
//	unsigned int error = __ip_read(antman_ctrl_rx->axiq_status_gpi, antman_ctrl_rx->axiq_underflow_overflow_bitfield);
//#ifndef LA9310
//	error |= get_rx_allowed_status(rid);
//#endif
//	if(error)
//		mailbox_send_error_msg(SET_ERROR_TYPE(ERROR_REPORT_MSG_ERROR_TYPE_RXAXIQ_INIT_STATE_ERROR)|SET_ERROR_TR_ID(rid)|SET_ERROR_ANT_ID(dcs_id)|0xFFF, error);
//
//	//check AXIQ status, return error.
//	return error;
	return 0;  //error just cleared, no need to check error here.  if there is error, it will be checked at runtime.
}

void add_a_pattern(unsigned int pattern_word, struct_tdd_pattern_entry* p_tdd_pattern, unsigned int UE_mask)
{
	unsigned int n_dl_slots          = pattern_word & 0xF;
	unsigned int n_gp_slots_after_dl = (pattern_word>>4) & 0xF;
	unsigned int n_dl_symbols        = (pattern_word>>8) & 0xF;
	unsigned int n_ul_slots          = (pattern_word>>12) & 0xF;
	unsigned int n_gp_slots_after_ul = (pattern_word>>16) & 0xF;
	unsigned int n_ul_symbols        = (pattern_word>>20) & 0xF;
	
	unsigned int num_dl_symbols          = n_dl_slots*NUM_SYM_PER_SLOT + n_dl_symbols;
	unsigned int num_gp_symbols_after_dl = ((NUM_SYM_PER_SLOT-n_dl_symbols-n_ul_symbols)%NUM_SYM_PER_SLOT) + n_gp_slots_after_dl*NUM_SYM_PER_SLOT;
	unsigned int num_ul_symbols          = n_ul_slots*NUM_SYM_PER_SLOT + n_ul_symbols;
	unsigned int num_gp_symbols_after_ul = n_gp_slots_after_ul*NUM_SYM_PER_SLOT;
	
	unsigned int pattern_idx = p_tdd_pattern->num_patterns;
	if(!UE_mask)
	{
		p_tdd_pattern->tx_entry[pattern_idx] = (num_dl_symbols<<PATTERN_SIZE_SYMBOL_BITIDX)|((num_ul_symbols+num_gp_symbols_after_dl+num_gp_symbols_after_ul)<<PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)|(1<<PATTERN_SIZE_VALID_BITIDX);
		p_tdd_pattern->rx_entry[pattern_idx] = (num_ul_symbols<<PATTERN_SIZE_SYMBOL_BITIDX)|((num_dl_symbols+num_gp_symbols_after_dl)<<PATTERN_SIZE_SYMBOL_SKIP0_BITIDX)|((num_gp_symbols_after_ul)<<PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)|(1<<PATTERN_SIZE_VALID_BITIDX);
	}
	else
	{
		p_tdd_pattern->rx_entry[pattern_idx] = (num_dl_symbols<<PATTERN_SIZE_SYMBOL_BITIDX)|((num_ul_symbols+num_gp_symbols_after_dl+num_gp_symbols_after_ul)<<PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)|(1<<PATTERN_SIZE_VALID_BITIDX);
		p_tdd_pattern->tx_entry[pattern_idx] = (num_ul_symbols<<PATTERN_SIZE_SYMBOL_BITIDX)|((num_dl_symbols+num_gp_symbols_after_dl)<<PATTERN_SIZE_SYMBOL_SKIP0_BITIDX)|((num_gp_symbols_after_ul)<<PATTERN_SIZE_SYMBOL_SKIP1_BITIDX)|(1<<PATTERN_SIZE_VALID_BITIDX);
	}
	p_tdd_pattern->num_patterns = pattern_idx+1;
}

unsigned int convert_2implement(unsigned int data)
{
	if(data > 0x80000000)
		data = ((~data)+1) | 0x80000000;
	return data;
}


unsigned int get_max(unsigned int a, unsigned int b)
{
	if(a>=b)	return a;
	else		return b;
}
unsigned int get_min(unsigned int a, unsigned int b)
{
	if(a<=b)	return a;
	else		return b;
}

#define DFE_INITIALIZED					(1<<12)

//return value: 0-success,  -1 fail (the msg not sent)
uint64_t la9310_la12xx_dmem_write_for_mbox(unsigned int core, unsigned int mbox_id, unsigned int msb, unsigned int lsb)
{
	if((msb&0xFF3F0000)==0x0A030000)   //signal scaling
	{
		uint64_t dest;
		unsigned int trid = (msb>>15)&1;
		unsigned int rx = msb & (1<<14);
		uint64_t vspa_dmem_base_vir = (uint64_t)mmap(NULL, 0x2000000, PROT_READ | PROT_WRITE,	MAP_SHARED, g_devmem_fd, g_vspa_dmem_base_phy);
		core = ((*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+SWVERSION))>>13) & 7;	//signal scaling is on core A.

		if(rx)
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_DFE_qec_params_opt_rx))<<7;
		else
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_DFE_qec_params_opt_tx))<<7;

		dest = (vspa_dmem_base_vir+core*0x400000+get_vspa_dmem_addr_offset_host_view(dest)+trid*128);
		
		short temp=lsb&0xFFFF;
		int temp1 = float16_to_float32(temp);
		float scaling_factor = *(float*)&temp1;
		
		unsigned int cap_lo = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+STATUS_CAP_LO);
		unsigned int timing_skew_flag = (cap_lo >> 22) & 0x1;

		if(timing_skew_flag == 0)
		{
			float f1 = *(float*)(dest+4*6);
			float f4 = *(float*)(dest+4*7);
			float f2 = *(float*)(dest+4*9);
			if((f1 == 0) && (f4 == 0) && (f2 == 0) )
			{
				f1 = 1; 
				f4 = 1; 
			}
			f1 *= scaling_factor;
			f2 *= scaling_factor;
			f4 *= scaling_factor;
			
			*(float*)(dest+4*0) = f1;
			*(float*)(dest+4*1) = f4;
			*(float*)(dest+4*3) = f2;
			
			if(rx)
			{
				float dc_I_ori = *(float*)(dest+4*10);
				float dc_Q_ori = *(float*)(dest+4*11);
				if(dc_I_ori==0 && dc_Q_ori==0)
				{
					dc_I_ori = *(float*)(dest+4*4);
					dc_Q_ori = *(float*)(dest+4*5);
					*(float*)(dest+4*10) = dc_I_ori;
					*(float*)(dest+4*11) = dc_Q_ori;
				}
				*(float*)(dest+4*4) = dc_I_ori * scaling_factor;
				*(float*)(dest+4*5) = dc_Q_ori * scaling_factor;
			}
		}
		else
		{
			float gain_I_ori = *(float*)(dest+128+4*9);
			float gain_Q_ori = *(float*)(dest+128+4*10);
			gain_I_ori *= scaling_factor;
			gain_Q_ori *= scaling_factor;
			*(float*)(dest+128+4*5) = gain_I_ori;
			*(float*)(dest+128+4*6) = gain_Q_ori;
			
			if(rx)
			{
				float dc_I_ori = *(float*)(dest+128+4*11);
				float dc_Q_ori = *(float*)(dest+128+4*12);
				if(dc_I_ori==0 && dc_Q_ori==0)
				{
					dc_I_ori = *(float*)(dest+128+4*7);
					dc_Q_ori = *(float*)(dest+128+4*8);
					*(float*)(dest+128+4*11) = dc_I_ori;
					*(float*)(dest+128+4*12) = dc_Q_ori;
				}
				*(float*)(dest+128+4*7) = dc_I_ori * scaling_factor;
				*(float*)(dest+128+4*8) = dc_Q_ori * scaling_factor;
			}
		}
		return 0;
	}
	return -1;
}


//due to LA9310 code size limitation, mailbox msg will be converted to direct memory access by this API.
//return value: 0-success,  -1 fail (the msg not sent)
uint64_t la9310_dmem_write_for_mbox(unsigned int core, unsigned int mbox_id, unsigned int msb, unsigned int lsb)
{
	uint64_t vspa_dmem_base_vir = (uint64_t)mmap(NULL, 0x2000000, PROT_READ | PROT_WRITE,	MAP_SHARED, g_devmem_fd, g_vspa_dmem_base_phy);
	if( ((msb&0xFF000000)==MSG_ID_SYMBOL_BUFFER_STRUCT) || ((msb&0xFF000000)==MSG_ID_SYMBOL_BUFFER_STRUCT2) )   //buffer struct msg
	{
		unsigned int tx_sym_base, rx_sym_base, ack_msg;
		if((msb&0xFF000000)==MSG_ID_SYMBOL_BUFFER_STRUCT)
		{
			tx_sym_base = (lsb&0xFFFFF)<<12;
			rx_sym_base = (msb&0xFFFFF)<<12; 
			ack_msg = MSG_ID_SYMBOL_BUFFER_STRUCT_ACK;
		}
		else
		{
			tx_sym_base = ((lsb&0xFFFFF)<<7)|TCM_BASE;
			rx_sym_base = ((msb&0xFFFFF)<<7)|TCM_BASE;
			ack_msg = MSG_ID_SYMBOL_BUFFER_STRUCT2_ACK;
		}
		
		if(tx_sym_base)
		{
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_num_sym_in_buf) = get_max(1, ((lsb>>20)&0xF)*2);
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_sym_buf_base) = tx_sym_base;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_sym_buff_size) = ((lsb>>24)&0xFF)*128;
		}
		
		if(rx_sym_base)
		{
			unsigned int rx_sym_num=get_max(1, ((msb>>20)&0xF)*2); 
			unsigned int rx_sym_size=((lsb>>24)&0xFF)*128;

			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_num_sym_in_buff) = rx_sym_num;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_sym_buf_base) = rx_sym_base;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_sym_buff_size) = rx_sym_size;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_num_sym_in_buff+4) = rx_sym_num;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_sym_buf_base+4) = rx_sym_base+rx_sym_num*rx_sym_size;
		}
		//printf("Received from VSPA:%d, MBox:%d, MSB:0x%08x, LSB:0x%08x.\n", core, mbox_id, ack_msg, 0);  //simulate an ACK
		return ((uint64_t)ack_msg)<<32;
	}
	else if((msb&0xFF000000)==MSG_ID_DFE_MODE_CONFIG)   //DFE MODE msg
	{
		unsigned int dfe_mode_hi_pre = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_HI);
		if(dfe_mode_hi_pre)  //update DFE mode bits only
		{
			unsigned int dfe_mode_lo_pre = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_LO);
			unsigned int ant_map_tx_pre = GET_DFE_MODE_ANT_MAP_TX(dfe_mode_lo_pre);
			unsigned int ant_map_rx_pre = GET_DFE_MODE_ANT_MAP_RX(dfe_mode_lo_pre);
			unsigned int ant_map_rx2_pre = GET_DFE_MODE_ANT_MAP_RX2(dfe_mode_lo_pre);
			
			*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_LO) = lsb;
			*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_HI) = msb;
			
			if(msb&(DFE_MODE_RESTART_TX|DFE_MODE_RESTART_RX))
			{
				//restart, wait until vspa retart ready and cleared the restart bit
				unsigned int dfe_mode_cur;
				do
				{
					dfe_mode_cur = *(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_HI);
				}while(dfe_mode_cur & DFE_MODE_RESTART_TX);
				
				delay_cycles(1000000); //delay 1ms to make sure vspa has restarted
				
				//reset AXIQ only when FDD mode,  TDD mode doesn't need reset AXIQ for restart.
				if( ((msb&DFE_MODE_TX_DIS)==0) && (dfe_mode_hi_pre&DFE_MODE_TX_FDD) )
				{
					Ant_buffer_tx_axiq_reset(ant_map_tx_pre, vspa_dmem_base_vir);
				}
				if( ((msb&DFE_MODE_RX_DIS)==0) && (dfe_mode_hi_pre&DFE_MODE_RX_FDD) )
				{
					Ant_buffer_rx_axiq_reset(ant_map_rx_pre, vspa_dmem_base_vir);
					if(ant_map_rx2_pre != 0x7)
						Ant_buffer_rx_axiq_reset(ant_map_rx2_pre, vspa_dmem_base_vir);
				}
			}
			return ((uint64_t)MSG_ID_DFE_MODE_CONFIG_ACK)<<32;
		}
		//first time DFE mode configuration after reset
		//before DFE mode is configured, init DCS
		unsigned int ant_map_tx = GET_DFE_MODE_ANT_MAP_TX(lsb);
		if(!(msb&DFE_MODE_TX_DIS))
			Ant_buffer_tx_init(ant_map_tx, GET_DFE_MODE_TX_IQSWAP(lsb), vspa_dmem_base_vir);
		
		unsigned int ant_map_rx = GET_DFE_MODE_ANT_MAP_RX(lsb);
		unsigned int ant_map_rx2 = GET_DFE_MODE_ANT_MAP_RX2(lsb);
		unsigned int ctrl_iqswap = (GET_DFE_MODE_RX_IQSWAP(lsb)<<IQSWAP_BITIDX(0)) | (GET_DFE_MODE_RX2_IQSWAP(lsb)<<IQSWAP_BITIDX(1));
		unsigned int dcs_id = (ant_map_rx<<ANT_ID_BITIDX(0)) | (ant_map_rx2<<ANT_ID_BITIDX(1));
		if(!(msb&DFE_MODE_RX_DIS))
			Ant_buffer_rx_init(dcs_id, ctrl_iqswap, vspa_dmem_base_vir);

//		iEdmaInit();
//		iEdmaChanInit(VSPA_eDMA_CHANNEL);
		
		unsigned short num_rb_in_a_sym = ((lsb)>>24)&0xFF;
		unsigned int num_sc_in_a_sym = num_rb_in_a_sym*12;

		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_IDX_NSC) = num_sc_in_a_sym;
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_LO) = lsb;
		*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_HI) = msb;  //must write lsb first, msb last, as msb will trigger vspa to start.
		//printf("Received from VSPA:%d, MBox:%d, MSB:0x%08x, LSB:0x%08x.\n", core, mbox_id, MSG_ID_DFE_MODE_CONFIG_ACK, 0);  //simulate an ACK
		return ((uint64_t)MSG_ID_DFE_MODE_CONFIG_ACK)<<32;
	}
	else if((msb&0xFF000000)==MSG_ID_STATIC_SLOT_FORMAT)  //static TDD pattern
	{
       	struct_tdd_pattern_entry* p_tdd_pattern = (struct_tdd_pattern_entry*)(vspa_dmem_base_vir+core*0x400000+tdd_pattern_entry);
		unsigned int UE_mask = (*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+IP_DFE_MODE_HI)) & (1<<10);
       	unsigned int seq_id_mask = GET_SEQ_ID_MASK(lsb);
		if(seq_id_mask == 0)
			p_tdd_pattern->num_patterns = 0;  //clear num of entry if this is the first msg
		add_a_pattern(lsb, p_tdd_pattern, UE_mask);
       	if(msb&0xFFFFFF)
           	add_a_pattern(msb, p_tdd_pattern, UE_mask);

        p_tdd_pattern->num_patterns_onetime = GET_NUM_ONETIME_PATTERN(lsb);
		//printf("Received from VSPA:%d, MBox:%d, MSB:0x%08x, LSB:0x%08x.\n", core, mbox_id, MSG_ID_STATIC_SLOT_FORMAT_ACK, 0);  //simulate an ACK
		return ((uint64_t)MSG_ID_STATIC_SLOT_FORMAT_ACK)<<32;
	}
	else if((msb&0xFF000000)==MSG_ID_UPDATE_PHCOM_COEFF)
	{
		uint64_t dest;
		unsigned int trid = (msb>>23)&1;
		unsigned int num_coeff = msb & 0xFF;
		unsigned int ddr_vspa_view = lsb;
		uint64_t ddr_host_view = ddr_vspa_view + g_ddr_host_vspa_view_offset;
		ddr_host_view = (uint64_t)mmap(NULL, 0x1000, PROT_READ | PROT_WRITE,	MAP_SHARED, g_devmem_fd, ddr_host_view);
		
		if(msb & (1<<MSG_TXRX_IDX))  //TXRX
		{
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_phcom_coeff_rx))<<7;
		}
		else
		{
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_phcom_coeff_tx))<<7;
		}
		dest = (vspa_dmem_base_vir+core*0x400000+dest);
		for(int i=0;i<num_coeff;i++)
			*(uint64_t*)(dest+i*8) = *(uint64_t*)(ddr_host_view+i*8);
		return 0;
	}
	else if((msb&0xFF000000)==MSG_ID_TIMING_OFFSET)
	{
		unsigned int rx = msb & (1 << 23);
    	unsigned int dis = msb & (1 << 21);
		if(rx)
		{
    		if(dis)
    			*(int*)(vspa_dmem_base_vir+core*0x400000+rx_timing_offset) = 0x80000000;
			else
				*(int*)(vspa_dmem_base_vir+core*0x400000+rx_timing_offset) = lsb;
		}
		else
		{
    		if(dis)
    			*(int*)(vspa_dmem_base_vir+core*0x400000+tx_timing_offset) = 0x80000000;
			else
				*(int*)(vspa_dmem_base_vir+core*0x400000+tx_timing_offset) = lsb;
		}
		return 0;
	}
	else if((msb&0xFF000000)==MSG_ID_FINE_CFO_NCO_FREQ_UPDATE_TX)
	{
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_mixer_freq_update) = lsb;
		return 0;
	}
	else if((msb&0xFF000000)==MSG_ID_FINE_CFO_NCO_FREQ_UPDATE_RX)
	{
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_mixer_freq_update+GET_CFO_TRID(msb)*4) = lsb;
		return 0;
	}
	else if((msb&0xFF000000)==MSG_ID_CELLTRACK_REQUEST)
	{
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+celltrack_config_lo) = lsb;
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+celltrack_config_hi) = msb;
		return 0;
	}
	else if((msb&0xFF000000)==0x4e000000)   //core map
	{
		uint32_t core_map_hi = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+ant_core_map_hi);
		uint32_t core_map_lo = *(unsigned int*)(vspa_dmem_base_vir+core*0x400000+ant_core_map_lo);
		//printf("Received from VSPA:%d, MBox:%d, MSB:0x%08x, LSB:0x%08x.\n", core, mbox_id, core_map_hi, core_map_lo);  //simulate an ACK
		return (((uint64_t)core_map_hi)<<32)|core_map_lo;
	}
	else if((msb&0xFF3F0000)==0x0a0e0000)   //tx single tone
	{
		unsigned int para_hi = GET_TEST_PARA_HI(msb);
		if(GET_CONTROL2(msb))
		{
			for(int i=0; i<MAX_NUM_SINGLE_TONE; i++)
				*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_AMP+i*4) = 0;	//stop single tone
		}
		else
		{
			unsigned int single_tone_amplitude = ((para_hi<<4)*(1-GET_CONTROL1(msb))) | ((para_hi<<20)*(1-GET_CONTROL3(msb))) | SINGLE_TONE_VALID_FLAG;
			if(GET_CONTROL0(msb) == 0)  //first single tone
			{
				*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_FREQ+0*4) = lsb;
				*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_AMP+0*4) = single_tone_amplitude;
				for(int i=1; i<MAX_NUM_SINGLE_TONE; i++)
					*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_AMP+i*4) = 0;  //set the rest single tone invalid
			}
			else
			{
				for(int i=0; i<MAX_NUM_SINGLE_TONE; i++)
				{
					if(*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_AMP+i*4) == 0)
					{
						*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_FREQ+i*4) = lsb;
						*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_TX_SINGLE_TONE_AMP+i*4) = single_tone_amplitude;
						break;
					}
				}
			}
		}
		return 0;
	}
	else if((msb&0xFF370000)==0x0a100000)  //dump time domain tx and rx, bit 19 indicates TX or RX
	{
		unsigned int rx = (msb>>19)&1;
		unsigned int trid = (msb>>15)&1;
		uint64_t dest;
		unsigned int dcm = 0;
		if(rx)
		{
			dest = (*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+addr_ant_rx_dump));
			dcm = GET_CONTROL2(msb);
		}
		else
			dest = (*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+addr_ant_tx_dump));
		dest = (vspa_dmem_base_vir+core*0x400000+dest+trid*9*4);
		unsigned int para_hi = GET_TEST_PARA_HI(msb);
		unsigned int control = GET_CONTROL(msb);
		unsigned int control1 = control>>2;
		control = control & 0x3;
		unsigned int dump_granul = 32768 << (control1<<1);
		unsigned int granul = (para_hi>>8);
		if(granul == 0)
			granul = 6*1024*1024;
		else
			granul = (32*1024)<<granul;
		unsigned int offset = granul * (para_hi&0x3F);
		//if(control==0)
		//{
			*(unsigned int*)(dest+8) = offset;
			*(unsigned int*)(dest+12) = GET_DUMP_ADDR(lsb);
			*(unsigned int*)(dest+16) = GET_SIZE_NUM32KB_TO_DUMP(lsb)*dump_granul;
			*(unsigned int*)(dest+20) = 0;
			*(unsigned int*)(dest+32) = dcm<<31;
			*(unsigned int*)(dest+0) = 0x21;
		//}
		return 0;
	}
	else if((msb&0xFF3F0000)==0x0a1e0000)   //rx single tone
	{
		unsigned int para_hi = GET_TEST_PARA_HI(msb);
		unsigned int trid = (msb & 0x00008000)>>15;
		if(GET_CONTROL2(msb))
		{
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_RX_SINGLE_TONE_AMP+trid*4) = 0;	//stop single tone
		}
		else
		{
			unsigned int single_tone_amplitude = ((para_hi<<4)*(1-GET_CONTROL1(msb))) | ((para_hi<<20)*(1-GET_CONTROL3(msb))) | SINGLE_TONE_VALID_FLAG;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_RX_SINGLE_TONE_FREQ+trid*4) = lsb;
			*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+CONFIG_RX_SINGLE_TONE_AMP+trid*4) = single_tone_amplitude;
		}
		return 0;
	}
	else if((msb&0xFF3F0000)==0x0a110000)   //ijnect freq tx
	{
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_sym_buf_base) = GET_INJECT_ADDR(lsb);
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_num_sym_in_buf) = GET_INJECT_NUM_SYMBOLS(lsb);
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_sym_buff_size) = GET_INJECT_SYM_BUF_SIZE(msb);
		return 0;
	}
	else if((msb&0xFF3F0000)==0x0a0f0000)   //dump freq tx
	{
		//unsigned int rid=(( ( msb >> 15) & 1 ));
		unsigned int dump_addr = GET_INJECT_ADDR(lsb);
		unsigned int dump_num_sym = GET_INJECT_NUM_SYMBOLS(lsb);
		unsigned int dump_sym_size =  GET_INJECT_SYM_BUF_SIZE(msb);
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_freq_dump_addr) = dump_addr;
		*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+tx_freq_dump_num_sym) = dump_num_sym;
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+tx_freq_dump_sym_size) = dump_sym_size;
		*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+tx_freq_dump_flag) = DUMP_INJECT_WAIT_MASK|DUMP_INJECT_ONCE;
		return 0;
	}
	else if((msb&0xFF3F0000)==0x0a1c0000)   //dump freq rx
	{
		unsigned int rid=(( ( msb >> 15) & 1 ));
		unsigned int dump_addr = GET_INJECT_ADDR(lsb);
		unsigned int dump_num_sym = GET_INJECT_NUM_SYMBOLS(lsb);
		unsigned int dump_sym_size =  GET_INJECT_SYM_BUF_SIZE(msb);
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_dumping_sym_buf_base+rid*4) = dump_addr;
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_dumping_num_sym_in_buff) = dump_num_sym;
		*(unsigned int*)(vspa_dmem_base_vir+core*0x400000+rx_dumping_sym_buff_size) = dump_sym_size;
		*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+rx_sym_dumping_flag+rid*2) = 1;
		return 0;
	}
	else if((msb&0xFF3F0000)==0x0A020000)   //QEC
	{
		uint64_t dest;
		unsigned int trid = (msb>>15)&1;
		unsigned int ddr_vspa_view = lsb<<7;
		uint64_t ddr_host_view = ddr_vspa_view + g_ddr_host_vspa_view_offset;
		ddr_host_view = (uint64_t)mmap(NULL, 0x1000, PROT_READ | PROT_WRITE,	MAP_SHARED, g_devmem_fd, ddr_host_view);
		
		if(msb & (1<<14))  //TXRX
		{
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_DFE_qec_params_opt_rx))<<7;
		}
		else
		{
			dest = (*(unsigned short*)(vspa_dmem_base_vir+core*0x400000+addr_DFE_qec_params_opt_tx))<<7;
		}
		dest = (vspa_dmem_base_vir+core*0x400000+dest+trid*128);
		
		//convert to struct for optimized QEC
		qec_para_convert((void*)dest, (void*)ddr_host_view);

		return 0;
	}
	return -1;
}

#define MAILBOX_ADDR(mbox, direction, core_idx) \
    (g_vspa_ccsr_vir + 0x680 + direction * 0x10 + mbox * 8 + 0x4000 * core_idx)
/* Assumption: msg is 4 32bit words. */


uint32_t hvif_init(uint64_t modem_ccsr_base_phy, uint64_t vspa_dmem_base_phy, uint64_t ddr_phy_host_view, uint32_t ddr_phy_vspa_view)
{
	g_devmem_fd = open("/dev/mem", O_RDWR);
    g_vspa_ccsr_vir = (uint64_t)mmap(NULL, 0x4000000, PROT_READ | PROT_WRITE, MAP_SHARED, g_devmem_fd, modem_ccsr_base_phy) + 0x1000000;
	g_vspa_dmem_base_phy = vspa_dmem_base_phy;
	g_ddr_host_vspa_view_offset = ddr_phy_host_view - ddr_phy_vspa_view;

	unsigned int vspa_hw_ver = *(unsigned int *)(g_vspa_ccsr_vir);
	if((vspa_hw_ver&0xFFFF0000) == 0x02010000)
	{
		g_dev_la9310 = 1;
		g_num_cores = 1;
	}
	else
	{
		g_dev_la9310 = 0;
		g_num_cores = 8;
	}

	unsigned int vspa_sw_ver = *(unsigned int *)(g_vspa_ccsr_vir+4);
	if((g_dev_la9310) && ((vspa_sw_ver&0xFFFF0000) == 0xDFEF0000))
		g_dfe_ref_la9310 = 1;
	else
		g_dfe_ref_la9310 = 0;
	
	return g_num_cores;
}
void hvif_reset()
{
	close(g_devmem_fd);
}

uint64_t hvif_mbox_recv_1msg(uint32_t core_id, uint32_t mbox_id, uint32_t timeout)
{
	uint64_t addr = g_vspa_ccsr_vir + 0x6A0 + 0x4000 * core_id;
	uint32_t msb, lsb;

	while (timeout && !(ioread32((void*)addr) & (1<<(mbox_id + 2))))
		timeout--;

	if (!timeout) {
		//if(!(ioread32((void*)addr_flag) & (1<<(30+mbox_id)) ))
			return 0;		
	}
	//iowrite32(1<<(30+mbox_id), (void*)addr_flag); //clear vcpu_host_flag1 bit 30 and 31 which are used specifically for vcpu2host mbox valid flag
	
	addr = MAILBOX_ADDR(mbox_id, 1, core_id);
	msb = ioread32((void*)addr);
	lsb = ioread32((void*)addr+4);
	return (((uint64_t)msb)<<32)|lsb;
}


uint64_t hvif_mbox_recv(uint32_t core_id, uint32_t mbox_id)
{
	uint64_t msg = hvif_mbox_recv_1msg(core_id, mbox_id, 1);
	
	if(msg)
		return msg;
	else
		return check_error_core(core_id);  //if no msg, check error.
}

uint64_t hvif_mbox_send(uint32_t core_id, uint32_t mbox_id, uint32_t msb32, uint32_t lsb32)
{
	if((msb32&MSG_ID_MASK) == MSG_ID_ERROR_REPORT_MSG)
		return check_error_core(core_id);
	
	uint64_t addr = MAILBOX_ADDR(mbox_id, 0, core_id);
	
	//for specific messages, use direct mem write instead of mbox due to vspa code size limitation or mbox msg not implemeted in vspa
	uint64_t ret = la9310_la12xx_dmem_write_for_mbox(core_id, mbox_id, msb32, lsb32);
	if(ret == -1) 
	{
		if(g_dfe_ref_la9310)
		{
			//la9310 fr1 fr2 test tool doesn't support some mbox msgs due to code size limitation, write to dmem
			ret = la9310_dmem_write_for_mbox(core_id, mbox_id, msb32, lsb32);
		}
	}

	//send all mbox messages.
	iowrite32(msb32, (void*)addr);
	iowrite32(lsb32, (void*)(addr+4));
	uint64_t ret1 = hvif_mbox_recv_1msg(core_id, mbox_id, 1);          //recv ack after a send
	
	if(ret == -1) 
		return ret1;
	else
		return ret;
}

uint32_t hvif_tx_sym_buf_status(uint32_t core, uint32_t sym_idx)
{
	return (*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+HOST_VCPU_FLAGS1)) & (1<<sym_idx);
}
void hvif_tx_sym_buf_set_ready(uint32_t core, uint32_t sym_idx)
{
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+HOST_VCPU_FLAGS1) = (1<<sym_idx);
}

uint32_t hvif_rx_sym_buf_status(uint32_t core, uint32_t sym_idx)
{
	return (*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+VCPU_HOST_FLAGS1)) & (1<<sym_idx);
}
void hvif_rx_sym_buf_release(uint32_t core, uint32_t sym_idx)
{
	*(unsigned int*)(g_vspa_ccsr_vir+core*0x4000+VCPU_HOST_FLAGS1) = (1<<sym_idx);
}

void deqec(void* buffer, unsigned int num_samples, float f1, float f2, float f4, float gain_I, float gain_Q, float dcoff_I, float dcoff_Q)
{
	short* sample = (short*)buffer;

	for (int i = 0;i < num_samples;i++)
	{
		float SI = sample[i * 2] / 32768.0;
		float SQ = sample[i * 2 + 1] / 32768.0;
		float OI = SI - dcoff_I;  //remove dcoffset
		float OQ = SQ - dcoff_Q;
		//complex_div(OI, OQ, gain_I, gain_Q, &OI, &OQ);   //remove gain
		OI /= gain_I; OQ /= gain_Q;
		
		OI = OI / f1;   //divide by f1
		OQ = (OQ - OI * f2) / f4;
		sample[i * 2] = OI * 32768.0;
		sample[i * 2 + 1] = OQ * 32768.0;
	}
}
