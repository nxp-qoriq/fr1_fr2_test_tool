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

#usage
#./check_all.sh [ant_id} [fast|nfast]
#   ant_id: 0-5, print channel status for specified ant_id. if not specified, print status for all antennas
#   fast|nfast:  fast-speed first, print less info.  nfast-print all info which takes much time.

source ./check_dfe_cap_core_map.sh

get_kernel_load() #$1=core id $2=KSPS $3=addr_offset $4=num_samples
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + $3))
	local cc=`./utils/memrw r 16 $addr_vir`
	echo $((100*cc*$2/vspa_core_clock/$4)) #core load percent
}
get_ts_txallowed_first_enabled() #$1=core id
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + TXPATH_STATUS_OFFSET_TS_TXALLOWED_FIRST_ENABLED))
	local ts=`./utils/memrw r 32 $addr_vir`
	echo $ts
}
get_ts_rxallowed_first_enabled() #$1=core id
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + RXPATH_STATUS_OFFSET_TS_RXALLOWED_FIRST_ENABLED))
	local ts=`./utils/memrw r 32 $addr_vir`
	echo $ts
}
#printing capability and core mapping info
prodtype=("Vspa-Vspa symbol interface with 2 Symbols Buffer on VSPA DMEM" "Host-Vspa symbol interface with up to 28 Symbols Buffer") #(ISC RU)
tag_running=("STOPPED     " "RUNNING     " "UN-CHECKED  " "RUNNING-IDLE")
tag_idle=("" IDLE)
ant_running_tx=(2 2 2 2 2 2)
ant_running_rx=(2 2 2 2 2 2)
num_running_chan_tx=0
num_running_chan_rx=0
dcs_used_tx=(0 0 0 0 0 0 0 0)
dcs_used_rx=(0 0 0 0 0 0 0 0)
LSHS=(LS HS)
onoff=(OFF ON ON ON ON ON ON ON)
enabled=(DISABLED ENABLED)
supported=("NOT-SUPPORTED" "SUPPORTED")
error_list=""
warning_list=""

print_capability()
{
echo "*****************************************************************************************************"
echo "***                  DFE capability "
for ((i=0;i<2;i++))
do
ant=$((i*NUM_ANTS_LS))
([ $((anttx[ant])) -ge $NUM_CORES ] && [ $((antrx[ant])) -ge $NUM_CORES ]) && continue
get_chan_para $ant 0xFF; [ $? != 0 ] && { echo -e "***ERROR: Failure Getting channel parameters\n"; exit 1; }
echo "***                     FR$((i+1)) capabilities:"
echo "***        Interface Type:   ${prodtype[$type_ru]}"
[ $cfr_pass = 0 ] && status=NOT-SUPPORTED || status="SUPPORTED, num of PASS = $cfr_pass"
echo "***                   CFR:   $status"

if [ $dpd_model_id -ne 0 ];then		
dpd_model_get_para
dpd=`dpd_model_num_coeff`
echo "***                   DPD:   SUPPORTED @$((baseband_txsps*dpd_sps_ratio)) KSPS, DPD CONFIG ID = $dpd_model_id, num coeff = $dpd" 
echo "***             DPD model:   `print_dpd_model`" 
else
echo "***                   DPD:   NOT-SUPPORTED"
fi

interp_ratio=("" "" "2x interpolation" "" "4x interpolation")
if [ $up1 -ne 0 ];then
echo "***    up-sampling filter:   $up1 taps, ${interp_ratio[txaxiq/baseband_txsps]}"
else
echo "***    up-sampling filter:   NOT-SUPPORTED"
fi


rxcore=${antrx[$ant]}
downsampling_ratio=$((rxaxiq/baseband_rxsps))

if [ $downsampling_ratio -gt 1 ];then
echo "***  down-sampling filter:   $num_downsampling_taps taps, ${downsampling_ratio}x demcimation"
else
echo "***  down-sampling filter:   NOT-SUPPORTED"
fi

if [ $rx_lpf_63taps_enable = 1 ];then
echo "***    RX LOW PASS filter:   63 taps, following down-sampling filter"
fi

echo "***                 TXQEC:   ${supported[$txqec_en]}, timing skew filter is ${supported[txqec_timing_skew]}"
echo "***                 RXQEC:   ${supported[$rxqec_en]}, timing skew filter is ${supported[rxqec_timing_skew]}"
echo "***                  iFFT:   ${supported[$ifft]}, ${POINTS_FFT}-point"
echo "***                   FFT:   ${supported[$fft]}, ${POINTS_FFT}-point"
echo "***          eCPRI Decomp:   ${supported[$decom]}"
echo "***            eCPRI Comp:   ${supported[$comp]}"

if [ $phcom_disable = 0 ];then
echo "***    Phase Compensation:   TX: SUPPORTED, RX: SUPPORTED. Num of Coeff: $((sym_num_1m/2)). Frequency Domain"
else
echo "***    Phase Compensation:   TX: NOT-SUPPORTED, RX: NOT-SUPPORTED."
fi
if [ $cfo_disable = 0 ];then
echo "***                   CFO:   TX: SUPPORTED, RX: SUPPORTED. Between QEC and Up/Down Sampling"
else
echo "***                   CFO:   TX: NOT-SUPPORTED, RX: NOT-SUPPORTED."
fi

echo "***         CELL TRACKING:   ${supported[$celltrack_enable]}"
echo "***     SINAD measurement:   ${supported[${sinad_enable_arr[ant]}]}"
done

echo "*** Channels running time:   hh:mm:ss `get_running_time $core`" #Current time: $(date "+%Y.%m.%d %H:%M")

echo "*****************************************************************************************************"
}


show_status()
{
if [ $tag = TX+RX ]; then
	echo "$1 TX: $2, RX: $3"
elif [ $tag = TX ]; then
	[ "$2" = "" ] || echo "$1 TX: $2"
else
	[ "$3" = "" ] || echo "$1 RX: $3"
fi
}

print_status()
{
local core=$1; local trid=$2; local tag=$3; local ant=$4
get_chan_para $ant $core; [ $? != 0 ] && { echo -e "***ERROR: Failure Getting channel parameters\n"; exit 1; }

check_running_status $core $trid

local score=${slave_core[core]}
local tag_score="&$score"
[ $score = $core ] && tag_score=""
dfe_mode_hi=`get_vspa_ip_reg_value $core $IP_DFE_MODE_HI`
dfe_mode_hi_option8=$(((dfe_mode_hi>>DFE_MODE_OPTION8_IDX)&1))
tagoption8=(OPTION7-2 OPTION8)

echo "***************  ANT ID $ant: $tag on CORE$core$tag_score  ***********************************************"

local dcs_id_tx=${ant_map_tx[$ant]}; 
local dcs_id_rx=${ant_map_rx[$ant]};
bw_curr=`size_align $((sym_size*scs/1000)) 5`

if [ $dfe_mode_hi_option8 -ne 0 ];then
echo "***             Bandwidth:   Max $((bandwidth_tx/baseband_upsampling_rate)) Mhz"
else
echo "***             Bandwidth:   Max $((bandwidth_tx/baseband_upsampling_rate)) Mhz, Current $bw_curr Mhz, num RE $((sym_size)), SCS $scs Khz"
fi

tag_iqswap=("" "IQSWAPPED")
[ $((vspa_image_version)) -ge $((0x500)) ] && { tag_pnswap_I=("" "PNSWAPPED_on_I");tag_pnswap_Q=("" "PNSWAPPED_on_Q"); } || { tag_pnswap_I=("" "");tag_pnswap_Q=("" ""); }

if [ $tag = TX+RX ]; then
tx_sym_base=`get_wordvalue_from_vspa $core $tx_sym_buf_base_inject`; tx_sym_base_vir=`phy2vir $tx_sym_base`
tx_num_sym=`get_wordvalue_from_vspa $core $tx_num_sym_in_buf_inject`
tx_sym_buf_size=`get_wordvalue_from_vspa $core $tx_sym_buff_size_inject`
end_tx_sym_buf=`size_align $((tx_sym_base+tx_num_sym*tx_sym_buf_size)) 4096`
[ $((end_tx_sym_buf)) -gt $((next_HRAMaddr_phy)) ] && [ $((end_tx_sym_buf)) -lt $((HRAMaddr_phy+HRAM_size)) ] && { next_HRAMaddr_phy=$end_tx_sym_buf; echo "next_HRAMaddr_phy=$end_tx_sym_buf" >> ./runtime_config.txt; }
rx_sym_base=`get_wordvalue_from_vspa $core $((rx_sym_buf_base_dump+trid*4))`; rx_sym_base_vir=`phy2vir $tx_sym_base`
rx_num_sym=`get_wordvalue_from_vspa $core $((rx_num_sym_in_buff_dump+trid*4))`
rx_sym_buf_size=`get_wordvalue_from_vspa $core $rx_sym_buff_size_dump`
end_rx_sym_buf=`size_align $((rx_sym_base+rx_num_sym*rx_sym_buf_size)) 4096`
[ $((end_rx_sym_buf)) -gt $((next_HRAMaddr_phy)) ] && [ $((end_rx_sym_buf)) -lt $((HRAMaddr_phy+HRAM_size)) ] && { next_HRAMaddr_phy=$end_rx_sym_buf; echo "next_HRAMaddr_phy=$end_rx_sym_buf" >> ./runtime_config.txt; }
((dcs_used_tx[$dcs_id_tx]++))
((dcs_used_rx[$dcs_id_rx]++))
echo "***      DCS channel used:   TX: "${tag_tddfdd[$tx_fdd]} ${TAG_TXDCSID[$dcs_id_tx]} $txdcs KSPS ${tag_iqswap[iqswap_tx[dcs_id_tx]]} ${tag_pnswap_I[pnswap_tx_I[dcs_id_tx]]} ${tag_pnswap_Q[pnswap_tx_Q[dcs_id_tx]]},   RX: ${tag_tddfdd[$rx_fdd]} ${TAG_RXDCSID[$dcs_id_rx]} $rxdcs KSPS ${tag_iqswap[iqswap_rx[dcs_id_rx]]} ${tag_pnswap_I[pnswap_rx_I[dcs_id_rx]]} ${tag_pnswap_Q[pnswap_rx_Q[dcs_id_rx]]}, HW_2x_Decimation ${onoff[axiq_2G_mode]}

if [ $dfe_only = 0 ];then
echo "***      Symbols sent    :   TX: $num_sym_tx ~$num_sym_tx_1ms/ms from addr $tx_sym_base num_symbols $((tx_num_sym))"
echo "***      Symbols received:   RX: $num_sym_rx ~$num_sym_rx_1ms/ms from addr $rx_sym_base num_symbols $((rx_num_sym))"
[ $((num_sym_tx_1ms)) -gt $((sym_num_1m*12/10)) ] && { str="***WARNING: TX sent more symbols than expected on ant $ant, sent $num_sym_tx_1ms/ms, expected $sym_num_1m/ms. Check TX DAC sampling rate\n"; error_list="$error_list$str"; }
[ $((num_sym_rx_1ms)) -gt $((sym_num_1m*12/10)) ] && { str="***WARNING: RX received more symbols than expected on ant $ant, received $num_sym_rx_1ms/ms, expected $sym_num_1m/ms. Check RX ADC sampling rate\n"; error_list="$error_list$str"; }
else
echo "***      Samples sent    :   TX: $num_sample_tx ~`rounding $num_sample_tx_1ms 15360` KSPS from addr $tx_sym_base num_symbols $((tx_num_sym))"
echo "***      Samples received:   RX: $num_sample_rx ~`rounding $num_sample_rx_1ms 15360` KSPS from addr $rx_sym_base num_symbols $((rx_num_sym))"
fi

elif [ $tag = TX ]; then
tx_sym_base=`get_wordvalue_from_vspa $core $tx_sym_buf_base_inject`; tx_sym_base_vir=`phy2vir $tx_sym_base`
tx_num_sym=`get_wordvalue_from_vspa $core $tx_num_sym_in_buf_inject`
tx_sym_buf_size=`get_wordvalue_from_vspa $core $tx_sym_buff_size_inject`
end_tx_sym_buf=`size_align $((tx_sym_base+tx_num_sym*tx_sym_buf_size)) 4096`
[ $((end_tx_sym_buf)) -gt $((next_HRAMaddr_phy)) ] && [ $((end_tx_sym_buf)) -lt $((HRAMaddr_phy+HRAM_size)) ] && { next_HRAMaddr_phy=$end_tx_sym_buf; echo "next_HRAMaddr_phy=$end_tx_sym_buf" >> ./runtime_config.txt; }
((dcs_used_tx[$dcs_id_tx]++))
echo "***      DCS channel used:   "${tag_tddfdd[$tx_fdd]} ${TAG_TXDCSID[$dcs_id_tx]} $txdcs KSPS ${tag_iqswap[iqswap_tx[dcs_id_tx]]} ${tag_pnswap_I[pnswap_tx_I[dcs_id_tx]]} ${tag_pnswap_Q[pnswap_tx_Q[dcs_id_tx]]}
if [ $dfe_only = 0 ];then
echo "***          Symbols sent:   $num_sym_tx ~$num_sym_tx_1ms/ms from addr $tx_sym_base num_symbols $((tx_num_sym))"
[ $((num_sym_tx_1ms)) -gt $((sym_num_1m*12/10)) ] && { str="***WARNING: TX sent more symbols than expected on ant $ant, sent $num_sym_tx_1ms/ms, expected $sym_num_1m/ms. Check TX DAC sampling rate\n"; error_list="$error_list$str"; }
else
echo "***          Samples sent:   $num_sample_tx ~`rounding $num_sample_tx_1ms 15360` KSPS from addr $tx_sym_base num_symbols $((tx_num_sym))"
fi

else
rx_sym_base=`get_wordvalue_from_vspa $core $((rx_sym_buf_base_dump+trid*4))`; rx_sym_base_vir=`phy2vir $tx_sym_base`
rx_num_sym=`get_wordvalue_from_vspa $core $((rx_num_sym_in_buff_dump+trid*4))`
rx_sym_buf_size=`get_wordvalue_from_vspa $core $rx_sym_buff_size_dump`
end_rx_sym_buf=`size_align $((rx_sym_base+rx_num_sym*rx_sym_buf_size)) 4096`
[ $((end_rx_sym_buf)) -gt $((next_HRAMaddr_phy)) ] && [ $((end_rx_sym_buf)) -lt $((HRAMaddr_phy+HRAM_size)) ] && { next_HRAMaddr_phy=$end_rx_sym_buf; echo "next_HRAMaddr_phy=$end_rx_sym_buf" >> ./runtime_config.txt; }
((dcs_used_rx[$dcs_id_rx]++))
echo "***      DCS channel used:   "${tag_tddfdd[$rx_fdd]} ${TAG_RXDCSID[$dcs_id_rx]} $rxdcs KSPS ${tag_iqswap[iqswap_rx[dcs_id_rx]]} ${tag_pnswap_I[pnswap_rx_I[dcs_id_rx]]} ${tag_pnswap_Q[pnswap_rx_Q[dcs_id_rx]]}, HW_2x_Decimation ${onoff[axiq_2G_mode]}
if [ $dfe_only = 0 ];then
echo "***      Symbols received:   $num_sym_rx ~$num_sym_rx_1ms/ms from addr $rx_sym_base num_symbols $((rx_num_sym))"
[ $((num_sym_rx_1ms)) -gt $((sym_num_1m*12/10)) ] && { str="***WARNING: RX received more symbols than expected on ant $ant, received $num_sym_rx_1ms/ms, expected $sym_num_1m/ms. Check RX ADC sampling rate\n"; error_list="$error_list$str"; }
else
echo "***      Samples received:   $num_sample_rx ~`rounding $num_sample_rx_1ms 15360` KSPS from addr $rx_sym_base num_symbols $((rx_num_sym))"
fi
fi

show_status "***           Symbol Type:  " "${tagoption8[dfe_mode_hi_option8]}" "${tagoption8[option8_rx[ant]]}"
show_status "***        Running Status:  " "${tag_running[running_status_tx|running_status_sample_tx]}" "${tag_running[running_status_rx|running_status_sample_rx]}"
                    
if [ ${tag:0:1} = T ]; then
	if ([ $sinad = 0 ] && [ $fr1 = 1 ] && [ $pow_cal_en = 1 ]);then  
	if [ $running_status_tx = 1 ];then
	#calculate power from tx dump
	dump_size=$((10*15*POINTS_FFT*4*axiqsps_tx[ant]/bbsps_tx[ant]/32768*32768)) #10 slots
	host_addr=`phy2vir $addr_dump`
	log=`dump_time_domain_tx_1time $core $trid $addr_dump $host_addr $dump_size 0 0 0`
	if [ $? = 0 ];then
		log=`./utils/power $host_addr 0 $((dump_size/4))`
		eval "$log"
		max_IQ100=`echo $max_IQ | awk '{ abs_val = ($1 >= 0) ? $1 : -$1; printf("%d\n", abs_val*100); }'`
		[ $max_IQ100 -ge 97 ] && warning_list="${warning_list}***WARNING: TX ant $ant DAC output is saturated, max value $max_IQ\n"
		
		v_tx_pow_acc=$power_IQ
		v_tx_pow_num_samples=$num_samples_valid
		
		if [ $v_tx_pow_num_samples -ne 0 ];then
		sample_power=($(echo $v_tx_pow_acc $v_tx_pow_num_samples | awk '{ x=10*(log($1/$2)/log(10)); printf("%f %3.1f %d\n", $1/$2, x, x); }'))
		[ ${sample_power[1]} = -inf ] && { sample_power[1]=-99999; sample_power[2]=-99999; }  #negative infinite
		echo "***   Sample power at DAC:   TX: ${sample_power[0]}/sample, ${sample_power[1]} dB, max I=$max_I, max Q=$max_Q"
		[ $((sample_power[2])) -lt -15 ] && warning_list="${warning_list}***WARNING: TX ant $ant DAC output power does not reach 10-15 dB, your test is not fully utilizing the DAC dynamic range!\n            To scale the power to appropriate level, run ./scale_percent.sh auto\n"
		[ $((sample_power[2])) -gt -8 ] && warning_list="${warning_list}***WARNING: TX ant $ant DAC output power is higher than -8 dB, be careful not to damage PA\n"
		fi
	fi
	fi
	fi

((num_running_chan_tx=num_running_chan_tx+(running_status_tx|running_status_sample_tx)))
ant_running_tx[$ant]=$((running_status_tx|running_status_sample_tx))
fi

if [ $tag != TX ]; then
	if ([ $sinad = 0 ] && [ $fr1 = 1 ] && [ $pow_cal_en = 1 ]);then  
	if [ $running_status_rx = 1 ];then
	#calculate power from rx dump
	dump_size=$((10*15*POINTS_FFT*4*axiqsps_rx[ant]/bbsps_rx[ant]/32768*32768)) #10 slots
	host_addr=`phy2vir $addr_dump`
	log=`dump_time_domain_rx_1time $core $trid $addr_dump $host_addr $dump_size 0 0`
	if [ $? = 0 ];then
		log=`./utils/power $host_addr 0 $((dump_size/4))`
		eval "$log"
		max_IQ100=`echo $max_IQ | awk '{ abs_val = ($1 >= 0) ? $1 : -$1; printf("%d\n", abs_val*100); }'`
		[ $max_IQ100 -ge 97 ] && warning_list="${warning_list}***WARNING: RX ant $ant ADC input is saturated, max value $max_IQ\n"

		v_rx_pow_acc=$power_IQ
		v_rx_pow_num_samples=$num_samples_valid
		
		sample_power=($(echo $v_rx_pow_acc $v_rx_pow_num_samples | awk '{ x=10*(log($1/$2)/log(10)); printf("%f %3.1f %d\n", $1/$2, x, x); }'))
		[ ${sample_power[1]} = -inf ] && { sample_power[1]=-99999; sample_power[2]=-99999; }  #negative infinite
		if [ $v_rx_pow_num_samples -ne 0 ];then
		echo "***   Sample power at ADC:   RX: ${sample_power[0]}/sample, ${sample_power[1]} dB, max I=$max_I, max Q=$max_Q"
		[ $((sample_power[2])) -lt -15 ] && warning_list="${warning_list}***WARNING: RX ant $ant ADC input  power does not reach 10-15dB, your test is not fully utilizing the ADC dynamic range!\n"
		fi
	fi
	fi
	fi
	
	((num_running_chan_rx=num_running_chan_rx+(running_status_rx|running_status_sample_rx)))
	ant_running_rx[$ant]=$((running_status_rx|running_status_sample_rx))
fi

if [ ${tag:0:1} = T ]; then


if [ $type_ru = 1 ];then
	if [ $dfe_only = 1 ];then
		tag_from_file="from TX circular buffer"
	else
		if [ $((tx_sym_base)) -eq $((tx_sym_queue_base)) ];then
			if [ $prach_wv = 0 ];then
			tag_from_file="from $((tx_num_sym)) TX symbol buffers at address $tx_sym_base_vir but waveform not loaded"
			else
			tag_from_file="from $((tx_num_sym)) TX symbol buffers at address $tx_sym_base_vir \n***                                        loaded from file $prach_wv"
			fi
		else
			if [ ${invecfile_cur[ant]} = 0 ];then
			tag_from_file="but waveform not loaded"
			else
			tag_from_file="from file ${invecfile_cur[ant]}\n***                          loaded at address `phy2vir ${addr_tx_wv[ant]}`"
			fi
		fi
	fi
else
	tag_from_file="from HighPHY"
fi

if [ $single_tone_stat = 1 ];then
echo "***               TX MODE:   Single Tone"
elif [ $((`get_vspa_ip_reg_value $core $IP_DFE_MODE_HI` & DFE_MODE_OPTION8)) -ne 0 ];then
echo -e "***               TX MODE:   Time Domain waveform $baseband_txsps KSPS $tag_from_file"
else
echo -e "***               TX MODE:   Freq domain waveform $tag_from_file"
fi

fi




if [ $vspa_dev_type = LA12xx ];then
show_status "*** DCS enabled timestamp:  " "tx_allowed `get_ts_txallowed_first_enabled $core`" "rx_allowed `get_ts_rxallowed_first_enabled $core`"
fi

if [ $disable_coreload = '0' ]; then
	cld_ifft=`get_kernel_load $core $baseband_txsps $STATUS_CC_IFFT $((POINTS_FFT))`
	cld_ifft_bitrev=`get_kernel_load $core $baseband_txsps $STATUS_CC_IFFT_BITREV $((POINTS_FFT))`
	cld_fft=`get_kernel_load $core $baseband_rxsps $STATUS_CC_FFT $((POINTS_FFT))`
	cld_fft_bitrev=`get_kernel_load $core $baseband_rxsps $STATUS_CC_FFT_BITREV $((POINTS_FFT))`
	cld_cfr=`get_kernel_load $core $baseband_txsps $STATUS_CC_CFR $((1024))`
	cld_upsampling=`get_kernel_load $core $baseband_txsps $TXPATH_STATUS_OFFSET_CC_UPSAMPLING $((block_size/4))`
	ld_dpd=`get_kernel_load $core $txdcs $TXPATH_STATUS_OFFSET_CC_DPD $((block_size/4*upsampling_ratio))`
	cld_downsampling=`get_kernel_load $core $rxaxiq $RXPATH_STATUS_OFFSET_CC_DOWNSAMPLING $((block_size/4*downsampling_ratio))`
	cld_qec_tx=`get_kernel_load $core $txdcs $TXPATH_STATUS_OFFSET_CC_QEC $((block_size/4*upsampling_ratio))`
	cld_qec_rx=`get_kernel_load $core $rxaxiq $RXPATH_STATUS_OFFSET_CC_QEC $((block_size/4*downsampling_ratio))`

[ $((cld_ifft+cld_fft)) -ne 0 ] && show_status "***           Kernel load:   ifft/fft" $((cld_ifft+cld_ifft_bitrev))% $((cld_fft+cld_fft_bitrev))%
[ $((cld_upsampling+cld_downsampling)) -ne 0 ] && show_status "***           Kernel load:   UP/DownSampling" $cld_upsampling% $cld_downsampling%

((ld_dpd=ld_dpd*dpd_enable))
if [ ${tag:0:1} = T ]; then
if [ $baseband_txsps -eq $txaxiq ];then
	dpd_model_get_para
	dpd=`dpd_model_num_coeff`	
	#ld_dpd=$((ld_dpd*2)) #dpd split into 2 cores, load doubled
	estimated_ld_dpd=`dpd_model_est_load $dpd`; ((estimated_ld_dpd=estimated_ld_dpd*dpd_enable))
	#[ $((dpd_model_id)) -ge 20 ] && ((estimated_ld_dpd=estimated_ld_dpd*2))
	[ $ld_dpd -ne 0 ] && echo "***           Kernel load:   DPD Estimated $estimated_ld_dpd% big_model $ld_dpd%"
else
	[ $ld_dpd -ne 0 ] && echo "***           Kernel load:   CFR $((cld_cfr))%, DPD $((ld_dpd))%"
fi
fi

[ $((cld_qec_tx+cld_qec_rx)) -ne 0 ] && show_status "***           Kernel load:   QEC " $cld_qec_tx% $cld_qec_rx%

if [ $((vspa_image_version)) -ge $((0x500)) ];then
cld_peak=`get_kernel_load $score $txdcs $peak_cycle_count $((block_size/4*upsampling_ratio))`
cld_min=`get_kernel_load $score $txdcs $min_cycle_count $((block_size/4*upsampling_ratio))`
[ $cld_peak -ne 0 ] && echo "***           Core A load:   Peak $cld_peak%, Control $cld_min%"
fi

fi




if [ ${tag:0:1} = T ]; then
if [ $((cld_cfr)) -le 5 ];then
[ $cfr_pass -ne 0 ] && echo "***            CFR status:   OFF"
else
[ $cfr_pass -ne 0 ] && echo "***            CFR status:   ON"
fi
if [ $((ld_dpd)) -le 5 ];then
[ $dpd_model_id -ne 0 ] && echo "***            DPD status:   OFF"
else
[ $dpd_model_id -ne 0 ] && echo "***            DPD status:   ON"
fi
fi

echo "*****************************************************************************************************"
}

pow_cal_en=0
ant_start=0
ant_end=$((NUM_ANTS-1))

arg_parse()
{
	arg=$1
	if [ $arg = 0 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = 1 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = 2 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = 3 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = 4 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = 5 ]; then								ant_start=$arg;ant_end=$arg
	elif [ $arg = fast ]; then							fast=1
	elif [ $arg = nfast ]; then							fast=0
	elif [ $arg = pow ]; then							pow_cal_en=1
	fi
}

for i in "$@"
do
	arg_parse $i
done

if [ $fast = 0 ];then
[ $((one_enabled_dfe_core)) -ge $((NUM_CORES)) ] && one_enabled_dfe_core=0
swverion_value=`./utils/memrw r 32 $((modembase_phy+0x1000000+$((one_enabled_dfe_core))*0x4000+4))`
[ $((swverion_value>>16)) -ne $((0xdfef)) ] && { echo -e "*** ERROR: VSPA images are not FR1 FR2 Test Tool VSPA images.\n"; exit 1; }
[ $((swverion_value&0x00001000)) -eq 0    ] && { echo -e "*** ERROR: Channels not started on core $one_enabled_dfe_core. Next step: run ./channels_start.sh\n"; exit 1; }

print_addr_mapping
print_ddr_usage
print_capability

[ $vspa_dev_type = LA12xx ] && disable_coreload=0 || disable_coreload=1

for ((ant=ant_start;ant<=ant_end;ant++))
do

[ $((ant_enable[ant])) = 0 ] && continue

txcore=${anttx[$ant]}
rxcore=${antrx[$ant]}
tid=${tidant[$ant]}
rid=${ridant[$ant]}

rx_printed_flag=0
if [ $((ant_enable[ant] & BITMASK_ANT_ENABLE_TX)) -ne 0 ]; then 
	if ([ $txcore -eq $rxcore ] && [ $((ant_enable[ant] & BITMASK_ANT_ENABLE_RX)) -ne 0 ]); then 
		print_status $txcore $tid "TX+RX" $ant
		rx_printed_flag=1
	else
		print_status $txcore $tid "TX" $ant
	fi
fi
if ([ $((ant_enable[ant] & BITMASK_ANT_ENABLE_RX)) -ne 0 ] && [ $rx_printed_flag -eq 0 ]); then 
	print_status $rxcore $rid "RX" $ant
fi

done

else #fast = 1
for((i=0;i<NUM_ANTS;i++))
do
	txcore=${anttx[$i]}
	rxcore=${antrx[$i]}
	tid=${tidant[$i]}
	rid=${ridant[$i]}

	if [ $((ant_enable[i] & BITMASK_ANT_ENABLE_TX)) -ne 0 ]; then 
	check_running_status $txcore $tid
	ant_running_tx[$i]=$((running_status_tx|running_status_sample_tx))
	((num_running_chan_tx=num_running_chan_tx+ant_running_tx[$i]))
	fi
	if [ $((ant_enable[i] & BITMASK_ANT_ENABLE_RX)) -ne 0 ]; then 
	check_running_status $rxcore $rid
	ant_running_rx[$i]=$((running_status_rx|running_status_sample_rx))
	((num_running_chan_rx=num_running_chan_rx+ant_running_rx[$i]))
	fi
done
fi



echo -e "\n****************************************************************************\nTest Tool name          :   $test_tool_name"
echo "Test Tool script Version:   $test_tool_version"
echo "VSPA image Version      :   $ver_maj.$ver_min.$revision"
read board_name < /proc/device-tree/model
echo "Board Name              :  " "$board_name"

	dfe_txcore=$INVALID_CORE
	for ((i=0;i<NUM_ANTS;i++))
	do
		[ $((ant_enable[i] & BITMASK_ANT_ENABLE_TX)) -ne 0 ] && { dfe_txcore=${anttx[i]}; break; }
	done
	if [ $((dfe_txcore)) -lt $((NUM_CORES)) ];then
		[ $vspa_dev_type = LA12xx ] && dma_size_cycle=`get_wordvalue_from_vspa $dfe_txcore $STATUS_TX_SYM_DMA_SIZE_CYCLE_COUNT` || dma_size_cycle=0
		dma_size=$((dma_size_cycle>>16)); dma_cycle_count=$((dma_size_cycle&0xFFFF))
		if [ $((dma_size|dma_size_cycle)) -eq 0 ];then
			echo "PCI bandwidth unknown, required PCI bandwidth read=$((pci_bw_req_total/1000)) Mbps"
		else
			pci_bw_rd=$((dma_size*8*vspa_core_clock/1000/dma_cycle_count))
			echo "Measured PCI bandwidth read=$pci_bw_rd Mbps, required PCI bandwidth read=$((pci_bw_req_total/1000)) Mbps"
		fi
	else
		echo "Measured PCI bandwidth unkonwn due to unavailable TX channel, required PCI bandwidth read=$((pci_bw_req_total/1000)) Mbps"
	fi

echo "Number of enabled channels TX: $((num_T_LS_enabled+num_T_HS_enabled)),  RX: $((num_R_LS_enabled+num_R_HS_enabled))"
echo "Number of Running channels TX: $num_running_chan_tx,  RX: $num_running_chan_rx "
tagCPE=("BaseStation" "UE/CPE"); DUTRtag=("DL=TX UL=RX" "DL=RX UL=TX"); tagLPHY=("" "LowPHY Only"); tagDFE=("" "DFE only")
cell_state=`./utils/devmem $test_tool_env_cell_state`
echo "MODE: TX ${tag_tddfdd[tx_fdd]}, RX ${tag_tddfdd[rx_fdd]}, ${tagLPHY[lphy]} ${tagDFE[dfe_only]}  ${tagCPE[cpe]} (${DUTRtag[cpe]}), ${tag_UEMODE[$((cell_state))]}"
if [ $((tx_fdd&rx_fdd)) = 0 ];then
	echo -n "TDD PATTERN: "
	
	if [ $((${#pattern[@]} % 6)) -eq 0 ];then
	patternstr=""
	for ((i=0;i<${#pattern[@]};i+=6))
	do
		echo -n "(${pattern[i+0]} ${pattern[i+1]} ${pattern[i+2]} ${pattern[i+3]} ${pattern[i+4]} ${pattern[i+5]}) "
		for ((nd=0;nd<pattern[i+0];nd++))
		do
			patternstr="${patternstr}D"
		done
		for ((ng=0;ng<pattern[i+4];ng++))
		do
			patternstr="${patternstr}G"
		done
		[ $((pattern[i+1] + pattern[i+3])) -ne 0 ] && patternstr="${patternstr}S"
		for ((nu=0;nu<pattern[i+2];nu++))
		do
			patternstr="${patternstr}U"
		done
		for ((ng=0;ng<pattern[i+5];ng++))
		do
			patternstr="${patternstr}G"
		done
	done
	echo -n =
	for ((i=0;i<${#patternstr};i+=5))
	do
		echo -n " ${patternstr:i:5}"
	done
	
	elif [ $((${#pattern[@]} % 4)) -eq 0 ];then
		echo -n pattern="(${pattern[@]})  "
	fi
	
	[ $dcsfdd = 1 ] && echo -n " [TDD in FDD] mode"
	echo
fi

TAG_IQSWAP=("         " "IQSWAPPED")
if [ $((num_T_LS_enabled+num_T_HS_enabled)) -ne 0 ];then
echo -e "\nAnt Mapping TX:\nant_id dcs_id                status            scaling_factor(input/ouput)"
for((i=0;i<$NUM_ANTS;i++))
do
	if [ $((ant_enable[$i]&BITMASK_ANT_ENABLE_TX)) != 0 ];then
		tag0="${ant_map_tx[$i]}"
		dcsid=${ant_map_tx[$i]}
		tag1=${TAG_TXDCSID[dcsid]}
		scaling_factor_input=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_input+i*4))`))
		scaling_factor_output=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_output+i*4))`))
		scaling_off=$((scaling_factor_output>>31)); scaling_factor_output=$((scaling_factor_output&0x7FFFFFFF))
		idle_flag=`get_wordvalue_from_vspa ${anttx[$i]} $CONFIG_TX_SINGLE_TONE_AMP`
		[ $((idle_flag)) -eq 1 ] && ant_running_tx[i]=3 || idle_flag=0
		[ $((scaling_off|idle_flag)) = 1 ] && tag_scaling=OFF || tag_scaling="$scaling_factor_input/$scaling_factor_output"
		echo "$i      $tag0 $tag1 ${TAG_IQSWAP[iqswap_tx[dcsid]]}  ${tag_running[ant_running_tx[i]]}      $tag_scaling"
	fi
done
fi

if [ $((num_R_LS_enabled+num_R_HS_enabled)) -ne 0 ];then
echo -e "\nAnt Mapping RX:\nant_id dcs_id                status            scaling_factor"
for((i=0;i<$NUM_ANTS;i++))
do
	if [ $((ant_enable[$i]&BITMASK_ANT_ENABLE_RX)) != 0 ];then
		scaling_factor=$((`./utils/memrw r 32 $((test_tool_env_rx_scaling+i*4))`))
		tag0="${ant_map_rx[$i]}"
		dcsid=${ant_map_rx[$i]}
		tag1=${TAG_RXDCSID[dcsid]}
		echo "$i      $tag0 $tag1 ${TAG_IQSWAP[iqswap_rx[dcsid]]}  ${tag_running[ant_running_rx[i]]}      $scaling_factor"
	fi
done
fi
echo

[ $((num_running_chan_tx+num_running_chan_rx)) -eq 0 ] && [ $vspa_dev_type = LA9310 ] && ./utils/view_tbgen_phytimer.sh

if [ $fast = 0 ];then
for ((i=0;i<NUM_ANTS;i++))
do
	[ $((dcs_used_tx[$i])) -gt 1 ] && { echo ERROR: TX ${TAG_TXDCSID[$i]} is re-mapped to multiple antenna ID. Please fix it in config.dat and reboot VSPA.; echo; exit; }
	[ $((dcs_used_rx[$i])) -gt 1 ] && { echo ERROR: RX ${TAG_RXDCSID[$i]} is re-mapped to multiple antenna ID. Please fix it in config.dat and reboot VSPA.; echo; exit; }
done

echo -e "$warning_list"
echo -e "$error_list"
[ $sinad = 1 ] && echo -e "CAUTION: Current VSPA image is only for SINAD test, run ./send_single_tone.sh and then ./sinad_test.sh\n"
check_error
fi
