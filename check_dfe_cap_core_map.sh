#!/bin/bash
# Copyright 2022-2025 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

source ./config.dat

if ([ $0 != ./measure_dma_latency.sh ] && [ $0 != ./channels_start.sh ]);then
[ $flag_runtime_config = 0 ] && { echo -e "***ERROR: Channels not started, run ./channels_start.sh\n"; exit 1; }
fi

MAX_NUM_1R_IN_CORE=2

test_tool_env_tx_scaling_input=$((test_tool_env_rxdcs_sps_hs+4)) #size NUM_ANTS
test_tool_env_tx_scaling_output=$((test_tool_env_tx_scaling_input+NUM_ANTS*4)) #size NUM_ANTS
test_tool_env_rx_scaling=$((test_tool_env_tx_scaling_output+NUM_ANTS*4)) #size NUM_ANTS

#VSPA IP reg 
IP_DFE_MODE_HI=$((0x13C))
IP_DFE_MODE_LO=$((0x140))

OFFSET_DFE_MODE_HI=$((0x08))
DFE_MODE_OPTION8_IDX=8;					DFE_MODE_OPTION8=$((1<<DFE_MODE_OPTION8_IDX))
DFE_MODE_NO_RX_SYM_TO_HOST_IDX=11;		DFE_MODE_NO_RX_SYM_TO_HOST=$((1<<DFE_MODE_NO_RX_SYM_TO_HOST_IDX))
DFE_MODE_TX_HANDSHAKE_BYPASS_IDX=14;	DFE_MODE_TX_HANDSHAKE_BYPASS=$((1<<DFE_MODE_TX_HANDSHAKE_BYPASS_IDX))
DFE_MODE_RX_HANDSHAKE_BYPASS_IDX=15;	DFE_MODE_RX_HANDSHAKE_BYPASS=$((1<<DFE_MODE_RX_HANDSHAKE_BYPASS_IDX))
DFE_MODE_RESTART_TX_IDX=20;				DFE_MODE_RESTART_TX=$((1<<DFE_MODE_RESTART_TX_IDX))
DFE_MODE_RESTART_RX_IDX=21;				DFE_MODE_RESTART_RX=$((1<<DFE_MODE_RESTART_RX_IDX))
DFE_MODE_TX_DIS_IDX=22;					DFE_MODE_TX_DIS=$((1<<DFE_MODE_TX_DIS_IDX))
DFE_MODE_RX_DIS_IDX=23;					DFE_MODE_RX_DIS=$((1<<DFE_MODE_RX_DIS_IDX))


KERNELS_DISABLE=$((0x10))
KERNELS_DISABLE_BITMASK_CFR=$((1<<0))
KERNELS_DISABLE_BITMASK_DOWNSAMPLING=$((1<<10))
KERNELS_DISABLE_BITMASK_RX_LPF=$((1<<11))
KERNELS_DISABLE_BITMASK_RX_FFT=$((1<<12))
tx_mixer_freq_update=$((0x1c))
rx_mixer_freq_update=$((tx_mixer_freq_update+4))
tdd_pattern_entry=$((rx_mixer_freq_update+MAX_NUM_1R_IN_CORE*4))
num_patterns=$tdd_pattern_entry
tx_pattern_entry=$((num_patterns+4))  #total 4 entries
rx_pattern_entry=$((tx_pattern_entry+4*4))  #total 4 entries


COREA_STATUS_BASE=0x80
RXPATH_STATUS_OFFSET_FLAG_AtoB=$COREA_STATUS_BASE
FLAG_AtoB_OBS_DUMP_ENABLE=$((1<<3)) #must match vspa code
FLAG_AtoB_DOWNSAMPLEING_64TAPS=$((1<<6)) #must match vspa code

TXPATH_STATUS_OFFSET_CC_UPSAMPLING=$((COREA_STATUS_BASE+2))
TXPATH_STATUS_OFFSET_CC_DPD=$((TXPATH_STATUS_OFFSET_CC_UPSAMPLING+2))
TXPATH_STATUS_OFFSET_CC_QEC=$((TXPATH_STATUS_OFFSET_CC_DPD+2))
RXPATH_STATUS_OFFSET_CC_QEC=$((TXPATH_STATUS_OFFSET_CC_QEC+2))
RXPATH_STATUS_OFFSET_CC_DOWNSAMPLING=$((RXPATH_STATUS_OFFSET_CC_QEC+2))
TXPATH_STATUS_OFFSET_ADDR_UPSAMPLING_TAPS=$((RXPATH_STATUS_OFFSET_CC_DOWNSAMPLING+2))
RXPATH_STATUS_OFFSET_ADDR_DOWNSAMPLING_TAPS=$((TXPATH_STATUS_OFFSET_ADDR_UPSAMPLING_TAPS+2))
TXPATH_STATUS_OFFSET_TS_TXALLOWED_FIRST_ENABLED=$((RXPATH_STATUS_OFFSET_ADDR_DOWNSAMPLING_TAPS+2))
RXPATH_STATUS_OFFSET_TS_RXALLOWED_FIRST_ENABLED=$((TXPATH_STATUS_OFFSET_TS_TXALLOWED_FIRST_ENABLED+4))
CONFIG_RX_SINGLE_TONE_FREQ=$((RXPATH_STATUS_OFFSET_TS_RXALLOWED_FIRST_ENABLED+4))
CONFIG_RX_SINGLE_TONE_AMP=$((CONFIG_RX_SINGLE_TONE_FREQ+MAX_NUM_1R_IN_CORE*4))
MAX_NUM_SINGLE_TONE=4
CONFIG_TX_SINGLE_TONE_FREQ=$((CONFIG_RX_SINGLE_TONE_AMP+MAX_NUM_1R_IN_CORE*4))
CONFIG_TX_SINGLE_TONE_AMP=$((CONFIG_TX_SINGLE_TONE_FREQ+MAX_NUM_SINGLE_TONE*4))
addr_rx_fir_filter_taps=$((CONFIG_TX_SINGLE_TONE_AMP+MAX_NUM_SINGLE_TONE*4))
num_samples_sent=$((addr_rx_fir_filter_taps+4))
num_samples_received=$((num_samples_sent+4))


COREB_STATUS_BASE=0x100
STATUS_CC_DECOMP=$((COREB_STATUS_BASE+2))
STATUS_CC_IFFT=$((STATUS_CC_DECOMP+2))
STATUS_CC_IFFT_BITREV=$((STATUS_CC_IFFT+2))
STATUS_CC_CFR=$((STATUS_CC_IFFT_BITREV+2))
STATUS_CC_FFT=$((STATUS_CC_CFR+2))
STATUS_CC_FFT_BITREV=$((STATUS_CC_FFT+2))
STATUS_CC_COMP=$((STATUS_CC_FFT_BITREV+2))
STATUS_NUM_TX_SYM_FROM_HIPHY=$((STATUS_CC_COMP+2))
STATUS_NUM_RX_SYM_TO_HIPHY=$((STATUS_NUM_TX_SYM_FROM_HIPHY+4))
STATUS_CAP_HI=$((STATUS_NUM_RX_SYM_TO_HIPHY+4))
STATUS_CAP_LO=$((STATUS_CAP_HI+4))
STATUS_TX_SYM_DMA_SIZE_CYCLE_COUNT=$((STATUS_CAP_LO+4))
tx_sym_buf_base_inject=$((STATUS_TX_SYM_DMA_SIZE_CYCLE_COUNT+4))
tx_num_sym_in_buf_inject=$((tx_sym_buf_base_inject+4))
tx_sym_buff_size_inject=$((tx_num_sym_in_buf_inject+4))
rx_sym_buf_base_dump=$((tx_sym_buff_size_inject+4))
rx_num_sym_in_buff_dump=$((rx_sym_buf_base_dump+MAX_NUM_1R_IN_CORE*4))
rx_sym_buff_size_dump=$((rx_num_sym_in_buff_dump+MAX_NUM_1R_IN_CORE*4))
rx_sym_dumping_flag=$((rx_sym_buff_size_dump+4))
ext_log_buf_base=$((rx_sym_dumping_flag+4))
ext_log_buf_size=$((ext_log_buf_base+4))
ant_core_map_hi=$((ext_log_buf_size+4))
ant_core_map_lo=$((ant_core_map_hi+4))
addr_DFE_qec_params_opt_tx=$((COREB_STATUS_BASE+0x84))
rx_inject_addr=$((COREB_STATUS_BASE+0x9c))
rx_inject_size=$((COREB_STATUS_BASE+0xa0))
peak_cycle_count=$((COREB_STATUS_BASE+0xb8))
min_cycle_count=$((COREB_STATUS_BASE+0xba))
obs_dump_addr=$((COREB_STATUS_BASE+0xd4))

host_vspa_mbox_id=0
tag_tddfdd=(TDD FDD)
tag_UEMODE=("STOPPED" "CELL SEARCH MODE" "CELL ATTACH MODE" "NORMAL MODE" "ILLEGAL MODE")

get_counter() #get counter of vspa clock,tbgen master clock, API get_counter vspa|tbgen1|tbgen2 [vspa_core_id]
{
	if [ $1 = vspa ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + $2*0x4000 + 0x98 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
	elif [ $1 = tbgen1 ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + 0x1206F0 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
	elif [ $1 = tbgen2 ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + 0x1246F0 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
	else
		echo get_counter: Unsupported counter type $1; exit 1; 
	fi
	
	tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
	tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
	echo $(( ((tmr_msb&0xFFFF)<<32) + tmr_lsb ))
}

get_vspa_ip_reg_value() #$1=core $2=IP reg addr
{
	./utils/memrw r 32 $((modembase_phy+0x1000000+$1*0x4000+$2))
}

get_vspa_dmem_base()  #$1=core id
{
	echo $((VDRAMaddr_vir+$1*0x400000))
}
get_vspa_dmem_addr()  #$1=core id $2=dmem addr
{
	if [ $(($2)) -lt $((VCPUDMEM_SIZE)) ];then
		echo $((VDRAMaddr_vir+$1*0x400000+$2))
	else
		echo $((VDRAMaddr_vir+$1*0x400000+$2-VCPUDMEM_SIZE+0x100000))
	fi
}

get_flag_singletone() #$1=core id
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + CONFIG_TX_SINGLE_TONE_AMP))
	local flag=`./utils/memrw r 32 $addr_vir`
	echo $((flag&1))
}

get_flag_downsampling_64taps() #$1=core id
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + RXPATH_STATUS_OFFSET_FLAG_AtoB))
	local flag=`./utils/memrw r 32 $addr_vir`
	echo $((flag&FLAG_AtoB_DOWNSAMPLEING_64TAPS))   #0:8taps, non-zero:64taps
}
get_hwordvalue_from_vspa()  #$1=core id, $2=DMEM ADDR offset
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	./utils/memrw r 16 $addr_vir
}
get_wordvalue_from_vspa()  #$1=core id, $2=DMEM ADDR offset
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	./utils/memrw r 32 $addr_vir
}
set_hwordvalue_to_vspa()  #$1=core id, $2=DMEM ADDR offset, $3=value
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	./utils/memrw w 16 $addr_vir $3;
}
set_wordvalue_to_vspa()  #$1=core id, $2=DMEM ADDR offset, $3=value
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	./utils/memrw w 32 $addr_vir $3;
}
get_flag_from_vspa()  #$1=core id, $2=flag addr, $2=flag mask
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	local flag=`./utils/memrw r 16 $addr_vir`
	echo $((flag & $3))
}
set_flag16_to_vspa()  #$1=core id, $2=flag addr, $3=flag mask, $4=flag value
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $2))
	local flag=`./utils/memrw r 16 $addr_vir`
	flag=$(((flag&(~$3))|($3 & $4)))
	./utils/memrw w 16 $addr_vir $flag
}


vspa_mbox_ifsend()
{
	local msg=`./utils/vspa_mbox ifsend $modembase_phy $VDRAMaddr_vir $DDR_host_vspa_view_offset $@`
	echo ./utils/vspa_mbox send $@ >> ./command_list.sh
	if [ "$msg" = "" ]; then
		msg_recv_flag=0; msg_recv_msb32=0; msg_recv_lsb32=0; return 0;
	else
		llog=`echo "$msg" | grep ERROR`; [ $? = 0 ] && { msg_recv_flag=0; msg_recv_msb32=0; msg_recv_lsb32=0; echo "$msg"; return 1; }
		msg_recv_flag=1; msg_recv_msb32=${msg:34:10}; msg_recv_lsb32=${msg:50:10}
		local msg_type=$((msg_recv_msb32>>24))
		if ([ $msg_type -ge $((0x40)) ] && [ $msg_type -le $((0x44)) ]);then
			parse_error_msg $1 $msg_recv_msb32 $msg_recv_lsb32
			msg_recv_flag=0
		fi
		return 0;
	fi
}

vspa_mbox_ifrecv()   #recv multiple msg
{
	local msg=`./utils/vspa_mbox ifrecv $modembase_phy $VDRAMaddr_vir $DDR_host_vspa_view_offset $@`
	echo ./utils/vspa_mbox recv $@ >> ./command_list.sh
#	if [ "$msg" = "" ]; then
#		sleep 0.02
#		msg=`./utils/vspa_mbox ifrecv $modembase_phy $VDRAMaddr_vir $DDR_host_vspa_view_offset $@`
#	fi
	if [ "$msg" = "" ]; then
		msg_recv_flag=0; msg_recv_msb32=0; msg_recv_lsb32=0
	else
		msg_recv_flag=1; msg_recv_msb32=${msg:34:10}; msg_recv_lsb32=${msg:50:10}
		local msg_type=$((msg_recv_msb32>>24))
		if ([ $msg_type -ge $((0x40)) ] && [ $msg_type -le $((0x44)) ]);then
			parse_error_msg $1 $msg_recv_msb32 $msg_recv_lsb32
			msg_recv_flag=0
		fi
	fi
}

vspa_mbox_mpsend()
{
	vspa_mbox_ifsend $@
}

vspa_mbox_msend()   #send multiple msg
{
	vspa_mbox_ifsend $@
}
vspa_mbox_mrecv()   #recv multiple msg
{
	vspa_mbox_ifrecv $@
}

vspa_mbox()
{
	if [ $1 = send ];then
		vspa_mbox_ifsend $2 $3 $4 $5
	else
		vspa_mbox_ifrecv $2 $3
	fi
}


devmem()
{
	./utils/devmem $@
}

print_addr_mapping()
{
echo Address Mapping:
echo "ddr              $ddr_vir -- $ddr_phy, size $ddr_size"
echo "PEB              $PEBaddr_vir -- $PEBaddr_phy" 
echo "HRAM             $HRAMaddr_vir -- $HRAMaddr_phy" 
echo "FRAM             $FRAMaddr_vir -- $FRAMaddr_phy" 
echo "VSPA DMEM        $VDRAMaddr_vir -- $VDRAMaddr_phy"
echo "modembase_phy    $modembase_phy"
}

dpd_model_legal_check()
{
	local num_custom=${#dpd_model_id_para[@]}; 	local num_max_p=${#dpd_model_max_p[@]}; local i
	[ $num_custom != $num_max_p ] && { echo ***ERROR: Custom DPD model num of polynomials unexpected, current $((num_custom/3)) `print_dpd_model`, expected $((num_max_p/3)) `print_dpd_model_max`; echo; exit; }
	for ((i=0;i<$num_max_p;i=i+3))
	do
		([ ${dpd_model_id_para[i]} != ${dpd_model_max_p[i]} ] || [ ${dpd_model_id_para[i+1]} != ${dpd_model_max_p[i+1]} ]) && { echo ***ERROR: r q values changed in dpd_model_para_custom; echo; exit; }
		([ ${dpd_model_id_para[i+2]} != - ] && [ $((dpd_model_id_para[i+2])) -gt $((dpd_model_max_p[i+2])) ]) && { echo ***ERROR: p exceeds max value in dpd_model_para_custom; echo; exit; }
	done 

	local flag_updated=0
	local rflag=(0 0 0 0 0 0 0 0 0 0 0 0)  #r flag to indicate appeared.  max r = 11, big enough
	for ((i=0;i<${#dpd_model_id_para[@]};i=i+3)) #find all polynomials in which r first appeared, and clear p=0 to p=- for r repeated.
	do
		local r=${dpd_model_id_para[i]}; local q=${dpd_model_id_para[i+1]}; local p=${dpd_model_id_para[i+2]}
		if ([ ${rflag[r]} = 1 ] && [ $p = 0 ]);then dpd_model_id_para[i+2]=-; flag_updated=1;
		fi
		[ $p != - ] && rflag[r]=1; 
	done
	[ $flag_updated = 1 ] && echo Legal check has updated DPD model from illegal config to legal config, no negative impact.

	#rneq_flag=(0 0 0 0 0 0)  #if r -ne q, flag is set
	#for ((i=0;i<${#dpd_model_id_para[@]};i=i+3)) #find all polynomials in which r -ne q
	#do
	#	r=${dpd_model_id_para[i]}; q=${dpd_model_id_para[i+1]}; p=${dpd_model_id_para[i+2]}
	#	if ([ $r -ne $q ] && [ $p != - ]);then rneq_flag[$r]=1; [ $p = 0 ] && dpd_model_id_para[i+2]=-;
	#	fi
	#done
	#for ((i=0;i<${#dpd_model_id_para[@]};i=i+3)) #set polynomials in which r eq q if rneq_flag is set
	#do
	#	r=${dpd_model_id_para[i]}; q=${dpd_model_id_para[i+1]}; p=${dpd_model_id_para[i+2]}
	#	if ([ $r -eq $q ] && [ $p = - ] && [ ${rneq_flag[$r]} = 1 ]);then dpd_model_id_para[i+2]=0;
	#	fi
	#done
}

dpd_model_num_coeff()
{
	local num_coeff=0; local i
	for ((i=0;i<${#dpd_model_id_para[@]};i=i+3))
	do
		[ ${dpd_model_id_para[i+2]} != - ] && ((num_coeff=num_coeff+dpd_model_id_para[i+2]+1))
	done
	echo $num_coeff
}

dpd_model_est_load()
{
	echo $((25+$1*123/100))
}

dpd_model_get_para()
{
	if [ $((dpd_model_id)) -eq 7 ];then
		dpd_model_max_p=(0 0 5  1 0 4  2 0 1  0 1 5  1 1 2  2 2 3)
		dpd_model_id_para=(${dpd_model_max_p[@]})
	elif [ $((dpd_model_id)) -eq 5 ];then
		dpd_model_max_p=(0 0 6  1 1 6  2 2 6)
		dpd_model_id_para=(${dpd_model_max_p[@]})
	elif [ $((dpd_model_id)) -eq 4 ];then
		dpd_model_max_p=(0 0 5  1 0 2  0 1 4  1 1 4  0 2 4  2 2 3)
		dpd_model_id_para=(${dpd_model_max_p[@]})
	elif [ $((dpd_model_id)) -eq 3 ];then
		dpd_model_max_p=(0 0 6  1 0 3  0 1 5  1 1 5  0 2 5  2 2 5)
		dpd_model_id_para=(${dpd_model_max_p[@]})
	elif ([ $((dpd_model_id)) -eq 2 ] || [ $((dpd_model_id)) -eq 22 ]);then   #mixconfig 02
		dpd_model_max_p=(0 0 6  1 0 3  0 1 5  1 1 5)
		dpd_model_id_para=(${dpd_model_max_p[@]})
	elif [ $((dpd_model_id)) -eq 1 ];then   #mixconfig 01
		dpd_model_max_p=(0 0 6  1 0 5  2 0 5  0 1 5  1 1 6  2 1 5  0 2 5  1 2 5  2 2 6)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_01[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -eq 10 ];then   #mixconfig 11
		dpd_model_max_p=(0 0 6  1 0 5  2 0 5  3 0 5  4 0 5  5 0 5  0 1 5  1 1 6  2 1 5  3 1 5  4 1 5  5 1 5  0 2 5  1 2 5  2 2 6  3 2 5  4 2 5  5 2 5) #  3 3 0  4 4 0  5 5 0)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_10[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -eq 19 ];then
		dpd_model_max_p=(0 0 6  1 0 5  2 0 3  3 0 3  4 0 3  5 0 3  0 1 5  1 1 6  2 1 5  3 1 5  4 1 5  5 1 5  0 2 5  2 2 6  0 3 5  3 3 5  0 4 5  4 4 5  0 5 5  5 5 5)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_19[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -eq 39 ];then
		dpd_model_max_p=(0 0 6  1 0 3  2 0 3  3 0 3  4 0 3  5 0 3  0 1 5  1 1 5  0 2 5  2 2 5) #  3 3 0  4 4 0  5 5 0)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_39[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -eq 11 ];then   #mixconfig 11
		dpd_model_max_p=(0 0 4  1 0 3  2 0 3  3 0 3  4 0 3  5 0 3  0 1 5  1 1 5  0 2 5  2 2 5) #  3 3 0  4 4 0  5 5 0)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_11[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -eq 12 ];then
		dpd_model_max_p=(0 0 3  1 0 3  3 0 3  5 0 3  0 1 5) #  1 1 0  3 3 0  5 5 0)
		if [ $use_custom_dpd_model = 0 ];then
			dpd_model_id_para=(${dpd_model_max_p[@]})
		else
			dpd_model_id_para=(${dpd_model_para_custom_12[@]})
			dpd_model_legal_check
		fi
	elif [ $((dpd_model_id)) -ne 0 ];then
		echo ***ERROR: Undefined DPD model $dpd_model_id.; exit 1;
	else
		dpd_model_max_p=(0 0 -)  #DPD disabled, set para to disabled para.
		dpd_model_id_para=(${dpd_model_max_p[@]})
	fi
}

#API: get_chan_para <ant_id> <core_id>
#core_id can be TX or RX core ID. if core_id is higher than 16, the function will find TX core for this ant, if TX core doesn't exit, it will find RX core.
get_chan_para()
{
local ant_in=$1; local core=$2
if [ $((core)) -ge 16 ];then
core=${anttx[$ant_in]}
if [ $core -eq $((0xF)) ]; then
core=${antrx[$ant_in]}
fi
if [ $core -eq $((0xF)) ]; then
echo "*** ERROR: non-existing ant id $ant_in core $core passed to get_chan_para()."
echo
return 1
fi
fi

if [ $ant_in -lt 4 ];then
	fr1=1
	fr2=0
else
	fr2=1
	fr1=0
fi

#parsing capability info
cap_msb=`get_wordvalue_from_vspa $core $STATUS_CAP_HI`
cap_lsb=`get_wordvalue_from_vspa $core $STATUS_CAP_LO`
decom=$(($cap_lsb & 0x1))
ifft=$((($cap_lsb >> 1) & 0x1))
cfr_pass=$((($cap_lsb >> 2) & 0x3))
if [ $cfr_pass -ne 0 ];then
	((cfr_pass++))
fi
up1=$((($cap_lsb >> 4) & 0xF))
if [ $up1 -eq 0 ]; then				up1=128
elif [ $up1 -eq $((0xF)) ]; then	up1=64
elif [ $up1 -eq $((0xE)) ]; then	up1=32
elif [ $up1 -eq $((0xD)) ]; then	up1=48
elif [ $up1 -le $((0x5)) ]; then	up1=0
else								up1=$((($up1 + 2) * 2))
fi

dpd_model_id=$((($cap_lsb >> 8) & 0x1F))
block_size=$(((($cap_lsb >> 13) & 0x7F)*512))
txqec_timing_skew=$((($cap_lsb >> 22) & 0x1))
txqec_en=$((($cap_lsb >> 23) & 0x1))
rxqec_timing_skew=$((($cap_lsb >> 26) & 0x1))
rxqec_en=$((($cap_lsb >> 27) & 0x1))
fft=$((($cap_lsb >> 28) & 0x1))
comp=$((($cap_lsb >> 29) & 0x1))
cfo_disable=$(((cap_lsb >> 30) & 0x1))
phcom_disable=$(((cap_lsb >> 31) & 0x1))

sinad_enable=$((($cap_msb >> 0) & 0x1))
celltrack_enable=$((($cap_msb >> 1) & 0x1))
hwdcm_enable=$(((cap_msb >> 7) & 0x1))
dpd_enable=$(((cap_msb >> 8) & 0x1))
num_downsampling_taps=$(((cap_msb >> 9) & 0x1)); [ $num_downsampling_taps = 0 ] && num_downsampling_taps=8 || num_downsampling_taps=64
flag_obs=$(((cap_msb >> 10) & 0x1))
option8=$((option8_cfg|((cap_msb>>11)&1)))
dcsfdd=$(((cap_msb >> 12) & 0x1))
rx_lpf_63taps_enable=$(((cap_msb >> 13) & 0x1))
arch_1R_2cores=$((($cap_msb >> 21) & 0x1))
type_ru=$(((($cap_msb >> 22) & 0x1) | force_ru))
arch_1T_2cores=$((($cap_msb >> 23) & 0x1))




single_tone_stat=$((`get_wordvalue_from_vspa $core $CONFIG_TX_SINGLE_TONE_AMP` & 1))

pattern=(${pattern0[@]})
default_waveform_filename=(0 0)  #first is TDD, 2nd is FDD

if [ $fr1 = 1 ];then
	bandwidthT4x=`./utils/devmem $test_tool_env_bw_ls`
	scs=`./utils/devmem $test_tool_env_scs_ls`; scs=$((scs))
	txdcs=`./utils/devmem $test_tool_env_txdcs_sps_ls`; txdcs=$((txdcs))
	rxdcs=`./utils/devmem $test_tool_env_rxdcs_sps_ls`; rxdcs=$((rxdcs))
elif [ $fr2 = 1 ];then
	bandwidthT4x=`./utils/devmem $test_tool_env_bw_hs`
	scs=`./utils/devmem $test_tool_env_scs_hs`; scs=$((scs))
	txdcs=`./utils/devmem $test_tool_env_txdcs_sps_hs`; txdcs=$((txdcs))
	rxdcs=`./utils/devmem $test_tool_env_rxdcs_sps_hs`; rxdcs=$((rxdcs))
fi

bandwidth=$((bandwidthT4x&0x7FFF)); 
bandwidth_ori=$(((bandwidthT4x>>16)&0x7FFF)); 
T4x=$((bandwidthT4x>>31))
T2x=$(((bandwidthT4x>>15)&1))
baseband_upsampling_rate=1
[ $((T4x)) -eq 1 ] && baseband_upsampling_rate=4
[ $((T2x)) -eq 1 ] && baseband_upsampling_rate=2
bandwidth_tx=$((bandwidth*baseband_upsampling_rate))
baseband_txsps=$((1920*(1<<$(echo $bandwidth_tx | awk '{ printf("%d\n", log($1)/log(2)); }'))))
[ $((T4x|T2x)) -eq 1 ] && { bandwidth_rx=$((bandwidth_tx*rxdcs/txdcs)); baseband_rxsps=$((baseband_txsps*rxdcs/txdcs)); } || { bandwidth_rx=$bandwidth_tx; baseband_rxsps=$baseband_txsps; }
sym_num_1m=$((14*scs/15))
dpd_sps_ratio=$((txdcs/baseband_txsps))

if [ $scs -eq 15 ];then
	if [ $bandwidth -eq 50 ];then
		max_sym_size=3240; pattern=(${pattern1[@]});
	elif [ $bandwidth -eq 10 ];then
		max_sym_size=624;  pattern=(${pattern3[@]});
	else
		echo -e "Undefiend bandwidth $bandwidth\n"; exit 1;
	fi
elif [ $scs -eq 30 ];then
	if [ $bandwidth_ori -eq 100 ];then		max_sym_size_ori=3276
	elif [ $bandwidth_ori -eq 50 ];then		max_sym_size_ori=1596
	elif [ $bandwidth_ori -eq 25 ];then		max_sym_size_ori=780
	elif [ $bandwidth_ori -eq 10 ];then		max_sym_size_ori=288
	else echo -e "Undefiend bandwidth $bandwidth_ori\n"; exit 1;
	fi
	
	if [ $bandwidth -eq 100 ];then
		max_sym_size=3276
		[ $nrb -eq 24 ] && default_waveform_filename=(./test_vectors/TM3.3_10MHz_30kHz_TDD.bin ./test_vectors/TM3.3_10MHz_30kHz_FDD.bin)
		
	elif [ $bandwidth -eq 50 ];then
		max_sym_size=1596
		([ $nrb -eq 133 ] || [ $nrb -eq 0 ]) && default_waveform_filename[1]=./test_vectors/NR-FR1-TM3.3_50MHz_30kHz_FDD_fd_1600.bin

		
	elif [ $bandwidth -eq 25 ];then
		max_sym_size=780  
		[ $vspa_dev_type = LA9310 ] && { nrb=51; pattern=(${pattern2[@]}); }   #set default 20Mhz with specified pattern
		
		([ $nrb -eq 65 ] || [ $nrb -eq 0 ]) && default_waveform_filename[1]=./test_vectors/TM3.3_25MHz_30kHz_FDD.bin
		[ $nrb -eq 51 ] && default_waveform_filename=(./test_vectors/G-FR1-A1-5_20MHz_30kHz_TDD.bin ./test_vectors/TM3.3_20MHz_30kHz_FDD.bin)
		[ $nrb -eq 24 ] && default_waveform_filename=(./test_vectors/G-FR1-A1-2_10MHz_30kHz_TDD.bin ./test_vectors/TM3.3_10MHz_30kHz_FDD.bin)
		
		
	elif [ $bandwidth -eq 10 ];then
		max_sym_size=288  
		[ $vspa_dev_type = LA9310 ] && pattern=(${pattern2[@]})
		([ $nrb -eq 24 ] || [ $nrb -eq 0 ]) && default_waveform_filename=(./test_vectors/G-FR1-A1-2_10MHz_30kHz_TDD.bin ./test_vectors/TM3.3_10MHz_30kHz_FDD.bin)
	else
		echo -e "Undefiend bandwidth $bandwidth\n"; exit 1;
	fi
	
elif [ $scs -eq 60 ];then
	if [ $bandwidth_ori -eq 25 ];then		max_sym_size_ori=372
	elif [ $bandwidth_ori -eq 200 ];then	max_sym_size_ori=3168
	else echo -e "Undefiend bandwidth $bandwidth_ori\n"; exit 1;
	fi
	
	if [ $bandwidth -eq 200 ];then		max_sym_size=3168
	elif [ $bandwidth -eq 25 ];then
		max_sym_size=372; 
		[ $vspa_dev_type = LA9310 ] && { nrb=24; pattern=(${pattern2[@]}); }   #set default 20Mhz with specified pattern
		[ $nrb -eq 24 ] && [ $option8 = 0 ] && default_waveform_filename=(./test_vectors/G-FR1-A1-5_20MHz_60kHz_TDD.bin ./test_vectors/TM3.3_20MHz_60kHz_FDD.bin)
	elif [ $bandwidth -eq 20 ];then		max_sym_size=288
	elif [ $bandwidth -eq 15 ];then		max_sym_size=216
	elif [ $bandwidth -eq 10 ];then		max_sym_size=132
	else
		echo -e "Undefiend bandwidth $bandwidth\n"; exit 1;
	fi

elif [ $scs -eq 120 ];then
	if [ $bandwidth_ori -eq 800 ];then		max_sym_size_ori=$((3168*2))
	elif [ $bandwidth_ori -eq 400 ];then	max_sym_size_ori=3168
	fi
	
	if [ $bandwidth -eq 400 ];then
		max_sym_size=3168
	elif [ $bandwidth -eq 800 ];then
		max_sym_size=$((3168*2))
		default_waveform_filename[1]=./test_vectors/TM3.1_800MHz_480kHz_FDD_option8.bin
	else
		echo -e "Undefiend bandwidth $bandwidth\n"; exit 1;
	fi
fi

POINTS_FFT=$((2<<`echo $max_sym_size | awk '{ printf("%d\n",log($1-1)/log(2)); }'`))

local cell_state=`./utils/devmem $test_tool_env_cell_state`
[ $((cell_state)) = $CELL_STATE_SEARCH ] && pattern=(20 0 0 0 0 0)

if ([ $nrb -ne 0 ] && [ $nrb -lt $((max_sym_size/12)) ]);then
	sym_size=$((nrb*12))
else
	sym_size=$max_sym_size
	nrb=$((max_sym_size/12))
fi
if [ $nrb -ge $((max_sym_size_ori/12)) ];then	nrb=0
else [ $nrb -gt 255 ] && { echo -e "***ERROR: nrb $nrb exceeds limit of 255\n";  exit 1; }
fi

[ $use_specified_pattern = 1 ] && pattern=(${specified_pattern[@]})
default_waveform_len=${input_waveform_len[$tx_fdd]}
[ $default_waveform_len = 0.5 ] && default_waveform_len_double=1 || default_waveform_len_double=$((default_waveform_len*2))
sym_num=$((sym_num_1m*default_waveform_len_double/2))

txaxiq=$txdcs
([ $txaxiq = 1966080 ] && [ $((arg_hwdcm|arg_nhwdcm)) = 0 ] && [ $((bandwidth_ori)) -ne 800 ] && [ $sinad = 0 ]) && hwdcm=1
[ $fr2 = 0 ] && axiq_2G_mode=0 || axiq_2G_mode=$hwdcm

rxaxiq=$((rxdcs/(axiq_2G_mode+1)))
upsampling_ratio=$((txaxiq/baseband_txsps))
downsampling_ratio=$((rxaxiq/baseband_rxsps))

[ $option8 = 1 ] && invecsize=$((baseband_txsps*4*default_waveform_len_double/2)) || invecsize=$(( (sym_size*4+127)/128*128 * sym_num))

#error check
if [ $((option8)) -eq 1 ];then
	if [ $ecpri_comp_decomp_enable = 1 ];then
		echo
		echo "ERROR CONFIG: ant$ant_in core$core, option8 and ecpri_comp_decomp_enable can not be set together!"
		echo
		return 1
	fi
fi

[ $vspa_dev_type = LA9310 ] && option8rx=$(((cap_msb>>11)&1)) || option8rx=$option8

return 0
}

size_align()
{
	local size=$1
	local align=$2
	((size=(size+align-1)/align*align))
	echo $size
}

dmem2phy() #$1=core id, $2=vspa dmem addr in vspa view
{
	local vspa_dmem=$(($2)); local core_id=$(($1))
	if [ $vspa_dmem -ge $((VCPUDMEM_SIZE)) ];then
	echo $((VDRAMaddr_phy+core_id*0x400000+vspa_dmem-VCPUDMEM_SIZE+0x100000))
	else
	echo $((VDRAMaddr_phy+core_id*0x400000+vspa_dmem))
	fi
}

if [ $vspa_dev_type = LA9310 ];then
phy2vir()
{
	if ([ $(($1)) -ge $((ddr_phy)) ] && [ $(($1)) -lt $((ddr_phy+ddr_size)) ]);then #DDR
		echo `printf "0x%x" $((ddr_vir+($1-ddr_phy)))`
	else                                     #on chip memory
		echo `printf "0x%x" $((HRAMaddr_vir+($1-HRAMaddr_phy)))`
	fi
}
vir2phy()
{
	if ([ $(($1)) -ge $((ddr_vir)) ] && [ $(($1)) -lt $((ddr_vir+ddr_size)) ]);then #DDR
		echo `printf "0x%x" $(($1-DDR_host_vspa_view_offset))`
	else
		echo `printf "0x%x" $(($1-HRAM_host_vspa_view_offset))`
	fi
}

else
phy2vir()
{
	if ([ $(($1)) -ge $((ddr_phy)) ] && [ $(($1)) -lt $((ddr_phy+ddr_size)) ]);then #DDR
		echo `printf "0x%x" $((ddr_vir+($1-ddr_phy)))`
	elif ([ $(($1)) -ge $((ONCHIP_mem_phy)) ] && [ $(($1)) -lt $((ONCHIP_mem_phy+ONCHIP_mem_size)) ]);then #on chip memory
		echo `printf "0x%x" $((HRAMaddr_vir+($1-HRAMaddr_phy)))`
	else
		echo ***ERROR: phy2vir input address illegal $1
	fi
}
vir2phy()
{
	if ([ $(($1)) -ge $((ONCHIP_mem_vir)) ] && [ $(($1)) -lt $((ONCHIP_mem_vir+ONCHIP_mem_size)) ]);then #on-chip mem
		echo `printf "0x%x" $(($1-HRAM_host_vspa_view_offset))`
	elif ([ $(($1)) -ge $((ddr_vir)) ] && [ $(($1)) -lt $((ddr_vir+ddr_size)) ]);then #DDR
		echo `printf "0x%x" $(($1-DDR_host_vspa_view_offset))`
	else
		echo ***ERROR: vir2phy input address illegal $1
	fi
}
fi




msb20()
{
	printf "%05x" $(($1>>12))
}

keyin=0

malloc_for_dump()  #$1=size for dump
{
local size=`size_align $1 4096`
if [ $size_dump -lt $size ];then
	local inc=$((size-size_dump))
	end_ddr=$((end_ddr+inc))
	addr_inject=$((addr_inject+inc))
	size_dump=$size
	if [ $((end_ddr)) -gt $((ddr_phy+ddr_size)) ];then
		((num_warnings++))
		echo "***WARNING $num_warnings: DDR size larger than available. Size needed `printf "0x%x" $((end_ddr-ddr_phy))`, size available `printf "0x%x" $ddr_size`"
	fi
	echo "end_ddr=$end_ddr; addr_inject=$addr_inject; size_dump=$size_dump"  >> ./runtime_config.txt
fi
}

mem_addr_check_host_view() #check the addr range is legal or not, $1=addr, $2=size
{
	local start_addr=$(($1))
	local size=$(($2))
	local end_addr=$((start_addr+size-1))
	if ([ $start_addr -ge $(($ddr_vir)) ] && [ $end_addr -lt $(($ddr_vir+ddr_size)) ]);then
		return 0; #legal DDR Address
	fi
	if ([ $start_addr -ge $(($HRAMaddr_vir)) ] && [ $end_addr -lt $(($HRAMaddr_vir+HRAM_size)) ]);then
		return 0; #legal HRAM Address
	fi
	if ([ $start_addr -ge $(($VDRAMaddr_vir)) ] && [ $end_addr -lt $(($VDRAMaddr_vir+VDRAM_size)) ]);then
		return 0; #legal HRAM Address
	fi
	if ([ $start_addr -ge $(($FRAMaddr_vir)) ] && [ $end_addr -lt $(($FRAMaddr_vir+FRAM_size)) ]);then
		return 0; #legal HRAM Address
	fi
	echo -e "***ERROR: Address `HEX $1` with size $2 is out of valid range in host side view. Aborted\n"
	exit 1
}

loadfile() #$1 is address, $2 is filename, $3 is size (optional)
{
	if [ $# -lt 2 ]; then
		echo "arguments error, usage: loadfile <vir_addr> <filename> [size bytes]"
		return 1
	fi
	
	local filesize=$(stat --format=%s $2)
	
	if [ $# -gt 2 ];then
		local size_bytes=$(($3))
		[ $size_bytes -gt $filesize ] && size_bytes=$filesize
	else
		local size_bytes=$filesize
	fi
	
	mem_addr_check_host_view $1 $size_bytes
	./utils/loadfile $2 $1 $size_bytes
	return 0
}

dumpfile()
{
	#$1 is address, $2 is filename, $3 size
	if [ $# -ne 3 ]; then
		echo "arguments error, usage: dumpfile <vir_addr> <filename> <size>"
		exit
	fi
	
	mem_addr_check_host_view $1 $3
	
	local lsize=$(($3))
	if [ $(($lsize%1024)) -ne 0 ];then		arg_c="-c 4"
	else									arg_c=""
	fi
	
	if ([ $lsize -ne 0 ] && [ $lsize -le $((ddr_size)) ]);then     # 0<size<=128MB
		local log=`./utils/bin2mem -f $2 -a $1 $arg_c -r $lsize`
	else
		echo Dumping from address $1 size $lsize which is out of valid range. Continue dumping \(Y/N\)?
		read keyin
		if ([ $keyin = Y ] || [ $keyin = y ]);then
			local log=`./utils/bin2mem -f $2 -a $1 $arg_c -r $lsize`
		else
			echo Aborted.
			echo
			exit
		fi
	fi
}

clear_mem()
{
	local addr_start=$1
	local size=$2
	mem_addr_check_host_view $addr_start $size
	[ $((size/4)) -ne 0 ] && ./utils/memset $addr_start $((size/4)) 0
}


malloc_for_inject()  #$1=size for inject
{
local size=`size_align $1 4096`
if [ $size_inject -lt $size ];then
	local inc=$((size-size_inject))
	end_ddr=$((end_ddr+inc))
	size_inject=$size
	if [ $((end_ddr)) -gt $((ddr_phy+ddr_size)) ];then
		((num_warnings++))
		echo "***WARNING $num_warnings: DDR size larger than available. Size needed `printf "0x%x" $((end_ddr-ddr_phy))`, size available `printf "0x%x" $ddr_size`"
	fi
	echo "end_ddr=$end_ddr; size_inject=$size_inject"  >> ./runtime_config.txt
fi
}

print_ddr_usage()
{
echo
echo Test Tool memory usage:
echo "addr_test_tool_env           `phy2vir $test_tool_env_base_phy`, `printf "0x%x" $test_tool_env_base_phy`, size `printf "0x%x" $test_tool_env_size`"
echo "addr_trace_log               `phy2vir $trace_log_buf_base`, `printf "0x%x" $trace_log_buf_base`, size `printf "0x%x" $trace_log_buf_size`"
echo "addr_tx_sym_queue            `phy2vir $tx_sym_queue_base`, `printf "0x%x" $tx_sym_queue_base`, size `printf "0x%x" $tx_sym_queue_size`"
echo "addr_rx_sym_queue            `phy2vir $rx_sym_queue_base`, `printf "0x%x" $rx_sym_queue_base`, size `printf "0x%x" $rx_sym_queue_size`"
echo "addr_cell_tracking_extbuf    `phy2vir $celltrack_extbuf_base`, `printf "0x%x" $celltrack_extbuf_base`, size `printf "0x%x" $celltrack_extbuf_size`"
if [ $obs_buffer_phy != 0 ];then
echo "addr_obs_buffer              `phy2vir $obs_buffer_phy`, `printf "0x%x" $obs_buffer_phy`, size `printf "0x%x" $obs_buffer_size`"
fi
echo "addr_tx_test_vector          `phy2vir $addr_tx_test_vector`, `printf "0x%x" $addr_tx_test_vector`, size `printf "0x%x" $size_tx_test_vector`"
echo "addr_dump                    `phy2vir $addr_dump`, `printf "0x%x" $addr_dump`, size `printf "0x%x" $size_dump`"
echo "addr_inject                  `phy2vir $addr_inject`, `printf "0x%x" $addr_inject`, size `printf "0x%x" $size_inject`"
echo "End address                  `phy2vir $end_ddr`, `printf "0x%x" $end_ddr`"
echo "total size used              `printf "0x%x" $((end_ddr-ddr_phy))`, available size `printf "0x%x" $ddr_size`"
echo
}

check_running_status()   #API check_running_status <core_id> <trid>
{
	core=$1
	trid=$2
	
	num_sample_tx0=0; num_sample_rx0=0
	num_sample_rx=0; num_sample_rx=0
	if [ $((vspa_image_version)) -lt $((0x422)) ];then
	local cycle0=`get_counter vspa $core`
	vspa_mbox_ifsend $core $host_vspa_mbox_id $((0x46000000 + (trid<<15))) 0
	num_sym_tx0=$msg_recv_lsb32
	num_sym_rx0=0x00${msg_recv_msb32:4:6} #$((msg_recv_msb32&0xFFFFFF))
	sleep 0.005  #sleep 5ms in case there are some GP slots in which no symbols are sent or received
	local cycle1=`get_counter vspa $core`
	vspa_mbox_ifsend $core $host_vspa_mbox_id $((0x46000000 + (trid<<15))) 0
	num_sym_tx=$msg_recv_lsb32
	num_sym_rx=0x00${msg_recv_msb32:4:6} #$((msg_recv_msb32&0xFFFFFF))
	else
	local cycle0=`get_counter vspa $core`
	num_sym_tx0=`get_wordvalue_from_vspa $core $STATUS_NUM_TX_SYM_FROM_HIPHY`
	num_sample_tx0=$((`get_wordvalue_from_vspa $core $num_samples_sent` *1024/4))
	num_sym_rx0=`get_wordvalue_from_vspa $core $STATUS_NUM_RX_SYM_TO_HIPHY`
	num_sample_rx0=$((`get_wordvalue_from_vspa $core $num_samples_received` *1024/4))
	sleep 0.005  #sleep 5ms in case there are some GP slots in which no symbols are sent or received
	local cycle1=`get_counter vspa $core`
	num_sym_tx=`get_wordvalue_from_vspa $core $STATUS_NUM_TX_SYM_FROM_HIPHY`
	num_sample_tx=$((`get_wordvalue_from_vspa $core $num_samples_sent` *1024/4))
	num_sym_rx=`get_wordvalue_from_vspa $core $STATUS_NUM_RX_SYM_TO_HIPHY`
	num_sample_rx=$((`get_wordvalue_from_vspa $core $num_samples_received` *1024/4))
	fi
	
	cycle1=$((cycle1-cycle0))
	running_status_tx=$((num_sym_tx-num_sym_tx0))
	running_status_rx=$((num_sym_rx-num_sym_rx0))
	num_sym_tx_1ms=$(((running_status_tx*vspa_core_clock+cycle1/2)/cycle1))
	num_sym_rx_1ms=$(((running_status_rx*vspa_core_clock+cycle1/2)/cycle1))
	[ $running_status_tx != 0 ] && running_status_tx=1
	[ $running_status_rx != 0 ] && running_status_rx=1
	running_status_sample_tx=$((num_sample_tx-num_sample_tx0))
	running_status_sample_rx=$((num_sample_rx-num_sample_rx0))
	num_sample_tx_1ms=$(((running_status_sample_tx*vspa_core_clock+cycle1/2)/cycle1))
	num_sample_rx_1ms=$(((running_status_sample_rx*vspa_core_clock+cycle1/2)/cycle1))
	[ $running_status_sample_tx != 0 ] && running_status_sample_tx=1
	[ $running_status_sample_rx != 0 ] && running_status_sample_rx=1
}


get_ant_id_from_arg()
{
	local ant_id_list="0 1 2 3 4 5"
	local ant_id=null
	local arg=$1
	for tag in $ant_id_list
	do
		if [ $tag = $arg ];then
			ant_id=$arg
			[ $fr2_used = 0 ] && ant_id=$((ant_id%4))
			[ $fr1_used = 0 ] && ant_id=$(((ant_id%2)+4))
		fi
	done
	echo $ant_id
}

check_known_waveform()
{
	checksum=$1
	local i=0
	while [ $((1)) ]
	do
		#echo $checksum,${known_waveform_list[i]}
		if [ $checksum = ${known_waveform_list[i]} ];then
			echo Dump identified: ${known_waveform_list[i+1]}
			checksumpass=1
			return
		elif [ ${known_waveform_list[i]} = 0 ];then
			checksumpass=0
			return
		fi
		((i=i+2))
	done
}
 
HEX()
{
	printf "0x%08x" $(($1))
}

memcpy()    #memcpy source dest size
{
	local src=$1
	local dst=$2
	local size=$3
	local i=0;
	for ((i=0;i<size;i+=4))
	do
		./utils/devmem $((dst+i)) w `./utils/devmem $((src+i)) w`
	done
}

print_dpd_model()
{
	local i=0
	local str=""
	for ((i=0;i<${#dpd_model_id_para[@]};i=i+3))
	do
		if [ "${dpd_model_id_para[i+2]}" != - ];then
			str="$str[ ${dpd_model_id_para[i+0]} ${dpd_model_id_para[i+1]} ${dpd_model_id_para[i+2]} ]"
		else
			str="$str[ - - - ]"
		fi
	done
	echo $str
}
print_dpd_model_max()
{
	local i=0
	local str=""
	for ((i=0;i<${#dpd_model_max_p[@]};i=i+3))
	do
		if [ ${dpd_model_max_p[i+2]} != - ];then
			str="$str[ ${dpd_model_max_p[i+0]} ${dpd_model_max_p[i+1]} ${dpd_model_max_p[i+2]} ]"
		else
			str="$str[ - - - ]"
		fi
	done
	echo $str
}

dpd_model_spec_file_gen()
{
	str="1"
	for ((i=0;i<${#dpd_model_id_para[@]};i=i+3))
	do
		[ ${dpd_model_id_para[i+2]} != - ] && str="$str\n${dpd_model_id_para[i+0]} ${dpd_model_id_para[i+1]} ${dpd_model_id_para[i+2]}"
	done
	echo -e $str > $dpdpath/dpd_spec.cfg
}

check_ant_enable_tx()
{
	swverion_value=`./utils/memrw r 32 $((modembase_phy+0x1000000+$one_enabled_dfe_core*0x4000+4))`
	[ $((swverion_value&0xFFFF1000)) -ne $((0xdfef1000)) ] && { echo -e "*** ERROR from core $one_enabled_dfe_core: Channels not started. Next step: run ./channels_start.sh\n"; exit 1; }
	local ant=$1
	if [ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ];then
		echo -e "***ERROR: Current TX ant $ant is not enabled. Enabled TX ants are:\nant_id  dcsid   dcs"
		local i
		local counter=0
		for((i=0;i<NUM_ANTS;i++))
		do
			[ $((ant_enable[i]&BITMASK_ANT_ENABLE_TX)) != 0 ] && { echo "  $i       ${ant_map_tx[$i]}     ${TAG_TXDCSID[${ant_map_tx[$i]}]}"; counter=$((counter+1)); }
		done
		[ $counter = 0 ] && echo No TX antennas enabled.
		exit 1
	fi
}
check_ant_enable_rx()
{
	swverion_value=`./utils/memrw r 32 $((modembase_phy+0x1000000+$one_enabled_dfe_core*0x4000+4))`
	[ $((swverion_value&0xFFFF1000)) -ne $((0xdfef1000)) ] && { echo -e "*** ERROR from core $one_enabled_dfe_core: Channels not started. Next step: run ./channels_start.sh\n"; exit 1; }
	local ant=$1
	if [ $((ant_enable[ant]&BITMASK_ANT_ENABLE_RX)) = 0 ];then
		echo -e "***ERROR: Current RX ant $ant is not enabled. Enabled RX ants are:\nant_id  dcsid   dcs"
		local i
		local counter=0
		for((i=0;i<NUM_ANTS;i++))
		do
			[ $((ant_enable[i]&BITMASK_ANT_ENABLE_RX)) != 0 ] && { echo "  $i       ${ant_map_rx[$i]}     ${TAG_RXDCSID[${ant_map_rx[$i]}]}"; counter=$((counter+1)); }
		done
		[ $counter = 0 ] && echo No RX antennas enabled.
		exit 1
	fi
}

mailbox_msg_send_dpd_passthrough()  #$1=txcore, $2=tid
{
	vspa_mbox_ifsend $1 $host_vspa_mbox_id $((0x0A010000+($2<<15) + (1<<13))) 0
}


move_coeff()
{
	local addr=$1; srcLidx=$2; local srcCoefidx=$3; local dstLidx=$4; local destCoefidx=$5; 
	local a0i=`./utils/devmem $((addr+128*srcLidx+srcCoefidx*8))`;	local a0q=`./utils/devmem $((addr+128*srcLidx+srcCoefidx*8+4))`
	./utils/devmem $((addr+128*dstLidx+destCoefidx*8)) w $a0i;	./utils/devmem $((addr+128*dstLidx+destCoefidx*8+4)) w $a0q
	./utils/devmem $((addr+128*srcLidx+srcCoefidx*8)) w 0;		./utils/devmem $((addr+128*srcLidx+srcCoefidx*8+4)) w 0;
}

update_dpd_coeff()
{
	local i
	str1="${dpd_model_id_para[@]}"
	str2="${dpd_model_max_p[@]}"
	if [ "$str1" != "$str2" ];then
		echo Converting custom DPD model coeff to big model coeff...
		addr_vir_src=$addr_vir
		((addr_vir=addr_vir+0x1000))
		((addr_phy=addr_phy+0x1000))
		./utils/memset $addr_vir $((${#dpd_model_id_para[@]}/3*128/4)) 0  #clear dest coeff buffer
		Lidx=0
		for ((i=0;i<${#dpd_model_id_para[@]};i=i+3))
		do
			if [ ${dpd_model_id_para[i+2]} != - ];then
				((diff_k=dpd_model_max_p[i+2]-dpd_model_id_para[i+2]))
				#memcpy $((addr_vir_src+Lidx*128)) $((addr_vir+i/3*128+diff_k*8)) $(((dpd_model_max_p[i+2]+1-diff_k)*8))
				./utils/memcpy $((addr_vir_src+Lidx*128)) $((addr_vir+i/3*128+diff_k*8)) $(((dpd_model_max_p[i+2]+1-diff_k)*2))
				((Lidx++))
			fi
		done
	fi
	
	echo "Updating DPD coeff from file on antenna $ant from address `HEX $addr_vir` to vspa"
	echo Current DPD model $dpd_model_id: `print_dpd_model`
	vspa_mbox_ifsend $txcore $host_vspa_mbox_id $((0x0A010000+(tid<<15) + (dis<<13) + (ncvt<<12))) $((addr_phy>>7))
}

wait_for_flag_change() #$1 is the address, $2 is the flag value.this function waits until the flag value in the address is changed to any other value.
{
	flag_value=`./utils/devmem $1 w`
	counter=500
	while [ $((flag_value)) -eq $(($2)) ]
	do
		flag_value=`./utils/devmem $1 w`
		((counter--))
		[ $counter -eq 0 ] && { echo -e "***ERROR: VSPA timeout\n"; exit 1; }
	done
}
dump_time_domain_tx_1time() #$1=txcore, $2=tid, $3=addr LA view, $4=addr host view, $5=dump size, $6=dpdo $7=obs $8=offset
{
	local core=$1; local addr_la=$3; local addr_vir=$4; local dump_size=$5; local dpdo=$6; local obs=$7; local offset=$8
	local dump_type=0; [ $dpdo = 1 ] && dump_type=1; [ $((dpdo*obs)) -ne 0 ] && dump_type=3
	echo Using memory from $addr_vir size $dump_size as intermediate buffer for dumping...
	[ $tx_fdd = 0 ] && clear_mem $addr_vir $dump_size
	local flag_addr=$((addr_vir+dump_size-4))
	devmem $flag_addr w 0x1234abcd

	local msb=$((0x0A100000 + ((obs&1)<<22) + ($2<<15) + (dump_type<<12) + (1<<8) + offset ))
	local lsb=$((((dump_size/32768)<<20)|(addr_la>>12)))
	echo vspa_mbox_ifsend $1 $host_vspa_mbox_id `HEX $msb` `HEX $lsb`
	local log=`vspa_mbox_ifsend $1 $host_vspa_mbox_id $msb $lsb`
	wait_for_flag_change $flag_addr 0x1234abcd
	[ "${log:0:8}" = "***ERROR" ] && { echo $log; return 1; }
	return 0
}
dump_time_domain_rx_1time() #$1=txcore, $2=tid, $3=addr LA view, $4=addr host view, $5=dump size, $6=dcm, $7=offset
{
	local core=$1; local addr_la=$3; local addr_vir=$4; local dump_size=$5; local dcm=$6; local offset=$7
	echo Using memory from $addr_vir size $dump_size as intermediate buffer for dumping...
	[ $rx_fdd = 0 ] && clear_mem $addr_vir $dump_size
	local flag_addr=$((addr_vir+dump_size-4))
	devmem $flag_addr w 0x1234abcd

	local log=`vspa_mbox_ifsend $1 $host_vspa_mbox_id $((0x0A180000 + ($2<<15) + (dcm<<13) + (1<<8) + offset )) $((((dump_size/32768)<<20)|(addr_la>>12)))`

	wait_for_flag_change $flag_addr 0x1234abcd	
	[ "${log:0:8}" = "***ERROR" ] && { echo $log; return 1; }
	return 0
}
sync_dump_time_domain_1time() #using globles: sync_dump_txrx() sync_dump_ant() sync_dump_addr_la() sync_dump_size() sync_dump_offset() sync_dump_dpdout_dcm()
{
	local i; local core_id; local trid; local msb32   #size is total size for all synced dump antennas
	local str=""
	local flag_addr=(0 0 0 0 0 0 0 0)
	for ((i=0;i<${#sync_dump_txrx[@]};i++))
	do
		local addr_host=`phy2vir ${sync_dump_addr_la[i]}`
		[ $rx_fdd = 0 ] && clear_mem $addr_host ${sync_dump_size[i]}
		if [ ${sync_dump_txrx[i]} = 0 ];then
			core_id=${anttx[${sync_dump_ant[i]}]}; trid=${tidant[${sync_dump_ant[i]}]}
			msb32=$((0x0A100000 + (trid<<15) + sync_dump_dpdout_dcm[i]*(0x2000>>sync_dump_dpdout_dcm[i]) + (1<<8) + sync_dump_offset[i] ))
		else
			core_id=${antrx[${sync_dump_ant[i]}]}; trid=${ridant[${sync_dump_ant[i]}]}
			msb32=$((0x0A180000 + (trid<<15) + (sync_dump_dpdout_dcm[i]<<13) + (1<<8) + sync_dump_offset[i] ))
		fi
		local lsb32=$((((sync_dump_size[i]/32768)<<20)|(${sync_dump_addr_la[i]}>>12)))
		str="$str $core_id $host_vspa_mbox_id `HEX $msb32` `HEX $lsb32`"
		
		local flag_addr[i]=$((addr_host+sync_dump_size[i]-4))
		devmem $((flag_addr[i])) w 0x1234abcd
	done
	
	local log=`vspa_mbox_ifsend $str`; echo vspa_mbox_ifsend $str

	for ((i=0;i<${#sync_dump_txrx[@]};i++))
	do
		wait_for_flag_change $((flag_addr[i])) 0x1234abcd	
	done
	[ "${log:0:8}" = "***ERROR" ] && { echo $log; exit 1; }
}

percent_to_F16() #$1=percent number
{
	local factor=$1
	((factor=factor*65536/100))
	#find the leading 1 position
	for ((i=31;i>=1;i--))
	do
		if [ $(((1<<i)&factor)) -ne 0 ]; then
			break
		fi
	done

	((exp=i-16))
	if [ $i -gt 16 ];then
		((mant=factor>>exp))
	elif [ $i -lt 16 ];then
		((mant=factor<<(-exp)))
	else
		((mant=factor))
	fi
	((mant=(mant&0xFFFF)>>6))  #move mantisa to fraction part of F16
	((exp=(0xF+exp)<<10))
	((factor=exp+mant))
	echo $factor
}

output_turn_off()  #$1=txcore $2=tid
{
	local ant=${coretx_tr0[$1]}
	local factor=`./utils/memrw r 32 $((test_tool_env_tx_scaling_output+ant*4))`
	./utils/memrw w 32 $((test_tool_env_tx_scaling_output+ant*4)) $((factor|0x80000000))
	vspa_mbox_ifsend $1 $host_vspa_mbox_id $((0x0a030000+(tid<<15))) 0
}
output_turn_on()  #$1=txcore $2=tid
{
	local ant=${coretx_tr0[$1]}
	local factor=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_output+ant*4))` & 0x7FFFFFFF ))
	./utils/memrw w 32 $((test_tool_env_tx_scaling_output+ant*4)) $factor
	vspa_mbox_ifsend $1 $host_vspa_mbox_id $((0x0a030000+(tid<<15))) `percent_to_F16 $factor`
}

mem_test()
{
	local core=$1; test_addr=$2; local test_size=$(($3&0xFFFFFFFE))   #make it even, required by VSPA DMA
	local readwrite=$4   #0 read, 1 write
	[ $readwrite = 1 ] && { local vir=`phy2vir $test_addr`; ./utils/devmem $vir w 0; }

	vspa_mbox_ifsend $core $host_vspa_mbox_id $((0x60000000+(readwrite<<16)+(test_size&0xFFFF))) $((test_addr>>12))
	[ $msg_recv_flag = 0 ] && vspa_mbox_ifrecv $core $host_vspa_mbox_id
	([ $msg_recv_flag = 0 ] || [ $((msg_recv_msb32&0xFF000000)) -ne $((0x61000000)) ]) && return 1
	cycle2chan=$((msg_recv_msb32&0x00FFFFFF))
	cycle1chan=$((msg_recv_lsb32))
	#[ $vspa_dev_type = LA9310 ] && return 0 #only simple read/write test in LA9310, 1 msg from vspa
	
	vspa_mbox_ifrecv $core $host_vspa_mbox_id
	([ $msg_recv_flag = 0 ] || [ $((msg_recv_msb32&0xFF000000)) -ne $((0x61000000)) ]) && return 1
	cycle4chan=$((msg_recv_msb32&0x00FFFFFF))
	cycle3chan=$((msg_recv_lsb32))
	
	if [ $readwrite = 1 ];then
		local dma_data=`./utils/devmem $vir w`
		if [ $((dma_data)) -ne $((0x1234abcd)) ];then
			echo -e "***ERROR: DMA copy data wrong. Addr modem ivew = $test_addr, addr host view = $vir, data:$dma_data, expected data:0x1234abcd"
			echo -e "Please check address mapping, if it is wrong please update the address mapping in config.dat\n"
			exit 1
		fi
	fi
	return 0
}

pci_bw_test()
{
	local core=$1; ddr_address=$ddr_phy
	if [ $vspa_dev_type = LA9310 ];then	local test_size=2048
	else								local test_size=16384
	fi
	mem_test $core $ddr_address $test_size 0; [ $? -ne 0 ] && return 1
	ddr_read_cycle_2chan=$cycle2chan 
	ddr_read_cycle_1chan=$cycle1chan
	mem_test $core $ddr_address $test_size 1; [ $? -ne 0 ] && return 1
	ddr_write_cycle_2chan=$cycle2chan 
	ddr_write_cycle_1chan=$cycle1chan
	#ddr_write_cycle_back2=$cycle4chan
	#ddr_write_cycle_back1=$cycle3chan
	pci_bw_rd=0; pci_bw_wr=0;
	[ $ddr_read_cycle_1chan -ne 0 ]  && pci_bw_rd=$((test_size*8*vspa_core_clock/1000/ddr_read_cycle_1chan))
	[ $ddr_write_cycle_1chan -ne 0 ] && pci_bw_wr=$((test_size*8*vspa_core_clock/1000/ddr_write_cycle_1chan))
	[ $((pci_bw_rd*pci_bw_wr)) -ne 0 ] && return 0 || return 1
}

sample_hfix2int()
{
sample_v=$1
((v1=sample_v&0x7FFF0000))
((v2=sample_v&0x00007FFF))
[ $((v1)) -eq 0 ] && sign1=0 || ((sign1=sample_v&0x80000000))
[ $((v2)) -eq 0 ] && sign2=0 || ((sign2=sample_v&0x00008000))
[ $((sign1)) -eq 0 ] || ((v1=0x7FFF0000-v1+0x10000))
[ $((sign2)) -eq 0 ] || ((v2=0x00007FFF-v2+1))
((sample_v=sign1|sign2|v1|v2))
printf 0x%08x $sample_v
}

hexfloat2hfix()
{
	local vfloat=`./utils/hex2float $1`
	vhfix=$(echo $vfloat | awk '{printf("%d\n", $1 * 32768);}')
	[ $((vhfix)) -lt 0 ] && vhfix=$(( (0-vhfix) | 0x8000 ))
	echo $vhfix
}

mpy_hexfloat() #two hexfloat multiplication, output is hexfloat
{
	local vfloat1=`./utils/hex2float $1`
	local vfloat2=`./utils/hex2float $2`
	local vfloat=$(echo $vfloat1 $vfloat2 | awk '{printf("%f\n", $1 * $2);}')
	vfloat=`./utils/hex2float -r $vfloat`
	echo $vfloat 
}

parse_error() #$1=msg_hi $2=msg_lo
{
	local msg_hi=$1; local msg_lo=$2; local error_type=$(((msg_hi>>16)&0xFF)); local core=$3
	local i
	if [ $(($error_type)) -eq $((0xff)) ];then
		echo -n " Error from core $core: TX DCS started earlier than DFE started."
	elif [ $(($error_type)) -eq $((0xfe)) ];then
		echo -n " Error from core $core: RX DCS enabling error."
	elif [ $(($error_type)) -eq $((0xfd)) ];then
		echo -n " Error from core $core: TX DCS init state error."
	elif [ $(($error_type)) -eq $((0xfc)) ];then
		echo -n " Error from core $core: RX DCS init state error."
	elif [ $(($error_type)) -eq $((0x01)) ];then
		echo -n " Error from core $core: TX AXIQ underflow at sample index $msg_lo, num configured AXIQ DMA is $(((msg_hi>>14)&0x3))."
	elif [ $(($error_type)) -eq $((0x02)) ];then
		echo -n " Error from core $core: RX AXIQ overflow at sample index $msg_lo, num configured AXIQ DMA is $(((msg_hi>>14)&0x3))."
	elif [ $(($error_type)) -eq $((0x04)) ];then
		echo -n " Error from core $core: VSPA DMA config error in channel "
		for ((i=0;i<32;i++))
		do
			[ $((msg_lo&(1<<i))) -ne 0 ] && echo -n $i
		done
		echo -n .
	elif [ $(($error_type)) -eq $((0x05)) ];then
		echo -n " Error from core $core: VSPA DMA transfer error in channel "
		for ((i=0;i<32;i++))
		do
			[ $((msg_lo&(1<<i))) -ne 0 ] && echo -n $i
		done
		echo -n .
	elif [ $(($error_type)) -eq $((0x06)) ];then
		echo -n " Error from core $core: VSPA IPPU cmd error."
	elif [ $(($error_type)) -eq $((0x11)) ];then
		echo -n " Error from core $core: TX symbols deadline missed, sent to DFE by host too late."
	elif [ $(($error_type)) -eq $((0x12)) ];then
		echo -n " Error from core $core: RX symbols deadline missed, fetched from DFE by host too late."
	elif [ $(($error_type)) -eq $((0x21)) ];then
		echo -n " Error from core $core: TX ant data arrived at DCS too late, TX ant buffer empty."
	elif [ $(($error_type)) -eq $((0x22)) ];then
		echo -n " Error from core $core: RX ant data processed too later, RX ant buffer full."
	elif [ $(($error_type)) -eq $((0x31)) ];then
		echo -n " Error from core $core: Unexpected tx allowed falling edge."
	elif [ $(($error_type)) -eq $((0x32)) ];then
		echo -n " Error from core $core: Unexpected rx allowed falling edge."
	elif [ $(($error_type)) -eq $((0x34)) ];then
		echo -n " Error from core $core: Sample Check Error, sample value to AXIQ is `sample_hfix2int $error_data_lo`, timestamp ${error_data_hi}0000."
	else
		echo -n " undefined error."
	fi
	echo " Error info MSB:$msg_hi, LSB:$msg_lo"
}

get_vspa_reg_addr()
{
	echo $((modembase_phy+0x1000000+$1*0x4000+$2))
}

check_dma_error_core() #$1=core
{
	[ $((vspa_image_version)) -ge $((0x500)) ] && return;  #from v5.0, DMA error is checked by mailbox msg
	
	local error=0
	dma_error_reg_addr=`get_vspa_reg_addr $1 0xCC`
	dma_error=`./utils/memrw r 32 $dma_error_reg_addr`
	if [ $((dma_error)) -ne 0 ];then
		((error++))
		err_info="DMA transfer error in core $1, error reg value = $dma_error"; echo $err_info
		[ "$first_error" = 0 ] && { first_error="$err_info"; echo "first_error=\"$first_error\"" >> runtime_config.txt; }
		./utils/memrw w 32 $dma_error_reg_addr $dma_error #clear error
	fi
		
	dma_error_reg_addr=`get_vspa_reg_addr $1 0xD0`
	dma_error=`./utils/memrw r 32 $dma_error_reg_addr`
	if [ $((dma_error)) -ne 0 ];then
		((error++))
		err_info="DMA config error in core $1, error reg value = $dma_error"; echo $err_info
		[ "$first_error" = 0 ] && { first_error="$err_info"; echo "first_error=\"$first_error\"" >> runtime_config.txt; }
		./utils/memrw w 32 $dma_error_reg_addr $dma_error #clear error
	fi
	((num_errors+=error)); [ $num_errors -gt 255 ] && num_errors=255
	[ $error -ne 0 ] && echo "num_errors=$num_errors" >> runtime_config.txt
	if [ $num_errors -ne 0 ];then
		print_msg="***ERROR: Total errors $num_errors. You should stop and fix the errors first, your further test result is not reliable !\nFirst error=$first_error\n"
		[ "$total_error_print_msg" != "$print_msg" ] && { total_error_print_msg="$print_msg"; echo -e $print_msg; }
	fi
}

parse_error_msg() #S1=core $2=msg_msb $3=msg_lsb
{
	local error=0; local core=$1; local msg_recv_msb32=$2; local msg_recv_lsb32=$3

	msg_type=$((msg_recv_msb32>>24)) #${cap:36:2}
	if [ $msg_type -eq $((0x40)) ];then
		err_info="Unexpected message from core $core mbox 0. Error msg MSB:$msg_recv_msb32, LSB:$msg_recv_lsb32"
		echo $err_info
	elif [ $msg_type -eq $((0x42)) ];then
		err_info="***ERROR: Error message from core $core mbox 0. Error msg MSB:$msg_recv_msb32, LSB:$msg_recv_lsb32"
		echo $err_info
	elif [ $msg_type -eq $((0x43)) ];then
		err_info="***ERROR: Wrong slot patter msg from core $core mbox 0. Error msg MSB:$msg_recv_msb32, LSB:$msg_recv_lsb32"
		echo $err_info
	elif [ $msg_type -eq $((0x44)) ];then
		err_info=`parse_error $msg_recv_msb32 $msg_recv_lsb32 $core`
		echo $err_info
		[ "$first_error" = 0 ] && { first_error="$err_info"; echo "first_error=\"$first_error\"" >> runtime_config.txt; }
		error=1
	else
		echo "Msg from core $core mbox 0. MSB:$msg_recv_msb32, LSB:$msg_recv_lsb32"
	fi

	((num_errors+=error)); [ $num_errors -gt 255 ] && num_errors=255
	[ $error -ne 0 ] && echo "num_errors=$num_errors" >> runtime_config.txt
	if [ $num_errors -ne 0 ];then
		print_msg="***ERROR: Total errors $num_errors. You should stop and fix the errors first, your further test result is not reliable !\nFirst error=$first_error\n"
		[ "$total_error_print_msg" != "$print_msg" ] && { total_error_print_msg="$print_msg"; echo -e $print_msg; }
		[ $pci_bw_req_total -ge 25000000 ] && echo Possible Reason: Your PCI throughput $((pci_bw_req_total/1000000))Gbps is very high, data dumping may cause overflow or underflow. 
	fi
}

check_error_core()  #S1=core
{
	local error=0; local core=$1
	vspa_mbox_ifrecv $core $host_vspa_mbox_id
}

check_error_ant() #S1=ant
{
	local ant=$1
	local tx_core=${anttx[$ant]}; local rx_core=${antrx[$ant]};
	if [ $((tx_core)) -le $((NUM_CORES)) ];then
		check_error_core $tx_core; check_dma_error_core $tx_core
		local score=${slave_core[tx_core]}; 
		if [ $((score)) -ne $((tx_core)) ];then
			check_error_core $score
			check_dma_error_core $score
		fi
	fi
	if ([ $((rx_core)) -le $((NUM_CORES)) ] && [ $((rx_core)) -ne $((tx_core)) ]);then
		check_error_core $rx_core; check_dma_error_core $rx_core
		local score=${slave_core[rx_core]}; 
		if [ $((score)) -ne $((rx_core)) ];then
			check_error_core $score
			check_dma_error_core $score
		fi
	fi
	[ "$first_error" != 0 ] && echo First Error: $first_error
}

check_error()
{
	total_error_print_msg=0
	local i
	for ((i=0;i<$NUM_CORES;i++))
	do
		local tx_enable_ant0=0; local tx_enable_ant1=0; local rx_enable_ant0=0; local rx_enable_ant1=0; local ant
		local txant0=$((coretx_tr0[i])); [ $txant0 -ne $((0xf)) ] && { tx_enable_ant0=$((ant_enable[txant0]&BITMASK_ANT_ENABLE_TX)); ant=$txant0; }
		local txant1=$((coretx_tr1[i])); [ $txant1 -ne $((0xf)) ] && { tx_enable_ant1=$((ant_enable[txant1]&BITMASK_ANT_ENABLE_TX)); ant=$txant1; }
		local rxant0=$((corerx_tr0[i])); [ $rxant0 -ne $((0xf)) ] && { rx_enable_ant0=$((ant_enable[rxant0]&BITMASK_ANT_ENABLE_RX)); ant=$rxant0; }
		local rxant1=$((corerx_tr1[i])); [ $rxant1 -ne $((0xf)) ] && { rx_enable_ant1=$((ant_enable[rxant1]&BITMASK_ANT_ENABLE_RX)); ant=$rxant1; }
		if [ $((dfe_core[i])) = 1 ] && [ $((tx_enable_ant0|tx_enable_ant1|rx_enable_ant0|rx_enable_ant1)) -ne 0 ];then
			check_error_core $i
			check_dma_error_core $i
			local score=${slave_core[i]}
			if [ $score -ne $i ];then
				check_error_core $score
				check_dma_error_core $score
			fi
		fi
	done
	[ "$first_error" != 0 ] && echo First Error: $first_error
}

get_running_time()
{
	local core=$1
	local tmr_msb_addr=$(( modembase_phy + 0x01000000 + core*0x4000 + 0x98 ))
	local tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
	local tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
	local tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
	local tmr=$(( (((tmr_msb&0xFFFF)<<32) + tmr_lsb)/614400000 ))
	local hr=$((tmr/3600))
	local min=$(((tmr-hr*3600)/60))
	local sec=$((tmr%60))
	echo "$hr:$min:$sec"
}

cancel_buffer_mode()
{
	local ant
	for ((ant=0;ant<NUM_ANTS;ant++))
	do
		if [ ${buffer_mode_size_rx[ant]} != 0 ]; then
			vspa_mbox_ifsend ${anttx[ant]} $host_vspa_mbox_id 0x0a202000 0;
			local addr=`vir2phy ${buffer_mode_addr40_rx[ant]}`; addr=$((0x100000+(addr>>12)))
			vspa_mbox_ifsend ${antrx[ant]} $host_vspa_mbox_id 0x0a180000 $addr;
		fi
	done
	buffer_mode=0
	echo "buffer_mode=$buffer_mode" >> ./runtime_config.txt
}

hsdcs_loopback_enable()
{
	reg=`./utils/memrw r 32 $(( modembase_phy + 0x1E10000))`
	((reg=reg|1))
	./utils/memrw w 32 $((modembase_phy + 0x1E10000)) $reg
}
hsdcs_loopback_disable()
{
	reg=`./utils/memrw r 32 $(( modembase_phy + 0x1E10000))`
	((reg=reg&0xFFFFFFFE))
	./utils/memrw w 32 $((modembase_phy + 0x1E10000)) $reg
}

inject_freq_domain_tx() #$1=core, $2=mailbox, $3=msb, $4=lsb
{
	vspa_mbox_ifsend $1 $2 $3 $4
}

inject_freq_domain_tx_stop() #$1=core, $2=mailbox, $3=msb, $4=lsb
{
if ([ $((vspa_image_version)) -le $((0x450)) ] || [ $vspa_dev_type = LA12xx ]);then
	vspa_mbox_ifsend $1 $2 $3 $4
else
	#this is to restore TX sym buf struct
	local txcore=$1
	msb=`devmem $((test_tool_env_buf_struct_msg+txcore*8+0))`
	lsb=`devmem $((test_tool_env_buf_struct_msg+txcore*8+4))`
	[ $((vspa_image_version)) -ge $((0x500)) ] && msb=$((msb&0xFFF00000))
	vspa_mbox_ifsend $txcore $host_vspa_mbox_id $msb $lsb; [ $msg_recv_flag = 0 ] && vspa_mbox_ifrecv $txcore $host_vspa_mbox_id
fi
}

dump_freq_domain_rx() #$1=core, $2=mailbox, $3=msb, $4=lsb
{
	vspa_mbox_ifsend $1 $2 $3 $4
	sleep 0.1
	#this is to restore RX sym buf struct
	local rxcore=$1
	if [ $((vspa_image_version)) -ge $((0x500)) ];then
	msb=`devmem $((test_tool_env_buf_struct_msg+rxcore*8+0))`
	lsb=`devmem $((test_tool_env_buf_struct_msg+rxcore*8+4))`
	lsb=$((lsb&0xFFF00000))
	vspa_mbox_ifsend $rxcore $host_vspa_mbox_id $msb $lsb; [ $msg_recv_flag = 0 ] && vspa_mbox_ifrecv $rxcore $host_vspa_mbox_id
	fi
}

send_celltrack_cmd() #$1=core, $2=ssb_period, $3=ssb_sym_id, $4=ssb_re_offset, $5=NID2, $6=NID1
{
	local msb=$(( 0x19000000|($2<<22)|($5<<20)|($6<<11)|$3 ))
	local lsb=$(( ($4<<20)|(celltrack_extbuf_base>>12) ))
	vspa_mbox_ifsend $1 $host_vspa_mbox_id $msb $lsb		
}

send_timing_offset_cmd()  #$1=core.  $2=rx, 0:tx, 1:rx. $3=advance, 0:delay, 1:advance. $4=num samples. $5=dis
{
	vspa_mbox_ifsend $1 $host_vspa_mbox_id $((0x08000000+($2<<23)+($5<<21))) $((((1-$3*2)*$4)&0xFFFFFFFF))
}

dfe_mode_stop_rx2host()
{
	local msb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+0))`
	local lsb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+4))`
	msb=$((msb|DFE_MODE_NO_RX_SYM_TO_HOST))
	vspa_mbox_ifsend $txcore $host_vspa_mbox_id $msb $lsb; [ $msg_recv_flag = 0 ] && vspa_mbox_ifrecv $txcore $host_vspa_mbox_id
}
dfe_mode_restore()
{
	local msb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+0))`
	local lsb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+4))`
	vspa_mbox_ifsend $txcore $host_vspa_mbox_id $msb $lsb; [ $msg_recv_flag = 0 ] && vspa_mbox_ifrecv $txcore $host_vspa_mbox_id
}

pattern_detect() #$1-addr, $2-num_samples_in_sym_buf, $3-num_samples_in_sym, $4-cpe
{
	local addr=$1; local num_samples_in_sym_buf=$2; local num_samples_in_sym=$3; local uecpe=$4
	local num_tx_sym=0; local num_nontx_sym=0;
	detected_pattern=()
	local sym_idx=0
	[ $uecpe = 0 ] && local curr_is_txsym=1 || local curr_is_txsym=0
	while [ 1 ];
	do
		Prb2re11=`./utils/memrw r 64 $((addr+ (sym_idx*num_samples_in_sym_buf+num_samples_in_sym/2+5*12+10)*4 ))`
		Prb3re11=`./utils/memrw r 64 $((addr+ (sym_idx*num_samples_in_sym_buf+num_samples_in_sym/2+7*12+8)*4 ))`
		Nrb2re11=`./utils/memrw r 64 $((addr+ (sym_idx*num_samples_in_sym_buf+num_samples_in_sym/2-4*12+4)*4 ))`
		Nrb3re11=`./utils/memrw r 64 $((addr+ (sym_idx*num_samples_in_sym_buf+num_samples_in_sym/2-6*12+2)*4 ))`
		local sample_value=$((Prb2re11|Prb3re11|Nrb2re11|Nrb3re11))
		if [ $sample_value -ne 0 ];then
			if [ $curr_is_txsym = 1 ];then
				((num_tx_sym++))
			else
				detected_pattern=(${detected_pattern[@]} $num_nontx_sym)
				num_tx_sym=1
				curr_is_txsym=1
			fi
		else
			if [ $curr_is_txsym = 0 ];then
				((num_nontx_sym++))
			else
				detected_pattern=(${detected_pattern[@]} $num_tx_sym)
				num_nontx_sym=1
				curr_is_txsym=0
			fi
		fi
		if [ ${#detected_pattern[@]} -eq 4 ];then
			if [ $uecpe = 0 ];then
				local num_dl_slot0=$((detected_pattern[0]/14))
				local num_dl_sym0=$((detected_pattern[0]%14))
				local num_ul_slot0=$((detected_pattern[1]/14))
				local num_ul_sym0=$(((detected_pattern[1]%14)-2))  #assume two GP symbols
				local num_dl_slot1=$((detected_pattern[2]/14))
				local num_dl_sym1=$((detected_pattern[2]%14))
				local num_ul_slot1=$((detected_pattern[3]/14))
				local num_ul_sym1=$(((detected_pattern[3]%14)-2))  #assume two GP symbols
			else
				local num_ul_slot0=$((detected_pattern[1]/14))
				local num_ul_sym0=$((detected_pattern[1]%14))
				local num_dl_slot0=$((detected_pattern[0]/14))
				local num_dl_sym0=$(((detected_pattern[0]%14)-2))  #assume two GP symbols
				local num_ul_slot1=$((detected_pattern[3]/14))
				local num_ul_sym1=$((detected_pattern[3]%14))
				local num_dl_slot1=$((detected_pattern[2]/14))
				local num_dl_sym1=$(((detected_pattern[2]%14)-2))  #assume two GP symbols
			fi
			detected_pattern=($num_dl_slot0 $num_dl_sym0 $num_ul_slot0 $num_ul_sym0 0 0 $num_dl_slot1 $num_dl_sym1 $num_ul_slot1 $num_ul_sym1 0 0)
			break;
		fi
		([ $num_tx_sym -ge 140 ] || [ $num_nontx_sym -ge 140 ]) && { detected_pattern=(); break; }
		((sym_idx++))
	done
}

get_num_sym_in_pattern()  #return value (total_num num_tx_sym num_rx_sym)
{
	local i=0; local dl_num=0; local ul_num=0; local gp_num
	for((i=0;i<${#pattern[@]};i=i+6))
	do
		((dl_num += pattern[0+i]*14+pattern[1+i]))
		((ul_num += pattern[2+i]*14+pattern[3+i]))
		((gp_num += ((14-pattern[1+i]-pattern[3+i])%14) + pattern[4+i]*14 + pattern[5+i]*14 ))
	done
	if [ $cpe = 0 ];then
		echo "($((dl_num+ul_num+gp_num)) $dl_num $ul_num)"
	else
		echo "($((dl_num+ul_num+gp_num)) $ul_num $dl_num)"
	fi
}

kernel_disable() #$1=core, $2=disalbe_mask_bits, $3=disable_value_bits
{
	local disable_flag=`get_hwordvalue_from_vspa $1 $KERNELS_DISABLE`
	set_hwordvalue_to_vspa $1 $KERNELS_DISABLE $(((disable_flag & (0xFFFF-$2)) | $3))
}

rounding() #$1: data,  $2: value to round tto
{
	echo $(( ($1+$2/2)/$2*$2 ))
}

deqec() #$1:core #$2:addr $3:num samples
{
	local addr_qec_struct=`get_hwordvalue_from_vspa $1 $addr_DFE_qec_params_opt_tx`
	local addr_qec_struct=`get_vspa_dmem_addr $1 $((addr_qec_struct<<7))`
	local f1=`./utils/memrw r 32 $((addr_qec_struct+0*4))`
	local f4=`./utils/memrw r 32 $((addr_qec_struct+1*4))`
	local f2=`./utils/memrw r 32 $((addr_qec_struct+3*4))`
	local dci=`./utils/memrw r 32 $((addr_qec_struct+4*4))`
	local dcq=`./utils/memrw r 32 $((addr_qec_struct+5*4))`
	local gre=0x3f800000
	local gim=0x3f800000
	./utils/deqec $2 $3 $f1 $f2 $f4 $gre $gim $dci $dcq
}

check_sample_power() #$1:address, $2:num_samples
{
	local log=`./utils/power $1 0 $2`
	eval "$log"
	local v_tx_pow_acc=$power_IQ
	local v_tx_pow_num_samples=$num_samples_valid
	local sample_power=($(echo $v_tx_pow_acc $v_tx_pow_num_samples | awk '{ x=10*(log($1/$2)/log(10)); printf("%f %3.1f %d\n", $1/$2, x, x); }'))
	dbFS=${sample_power[1]}
	echo "  Sample power: ${sample_power[0]}/sample, ${sample_power[1]} dB, max I=$max_I, max Q=$max_Q, dc_I=$dc_I, dc_Q=$dc_Q"
	[ $((sample_power[2])) -lt -15 ] && echo "  ***WARNING: Sample power does not reach 10-15 dB, your test is not fully utilizing the DCS dynamic range!"
	[ $((sample_power[2])) -gt -8 ] && echo "  ***WARNING: Sample power is higher than -8 dB, be careful not to damage PA"
	local max_IQ100=`echo $max_IQ | awk '{ abs_val = ($1 >= 0) ? $1 : -$1; printf("%d\n", abs_val*100); }'`
	[ $max_IQ100 -ge 99 ] && echo "  ***WARNING: Sample may be saturated, max value $max_IQ"
}
#fi
