#!/bin/bash
# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

print_usage()
{
echo "usage: ./scale_percent.sh [ant_id] [per_cent] [-y] [input [auto] [dis] [offset=x len=y]]"
echo "  the arguments are optional, with no arguments the script will scale up antenna 0 by 10%."
echo "  ant_id:   antenna ID, values could be 0,1,2,3,4,5 representing a logic channel."
echo "  per_cent：percentage number without %. As too high amplitude may damage PA, when per_cent is 200 or higher, a warning will be prompted to ask users to confirm the scaling is safe to PA."
echo "     -y：   confirm the scaling is safe to PA, and test tool will not prompt with a warning."
echo "  input:    scaling the input data fetched from HighPHY/DU. if not specified, scaling the QEC output."
echo "   auto:    auto scaling both input and output to fully utilize the DAC dynamic range"
echo "    dis:    disable scaling on both input and output, restore to original state"
echo "example:  ./scale_percent.sh 0 105                will scale antenna 0 signal amplitude up 5%"
echo "example:  ./scale_percent.sh 0 90                 will scale antenna 0 signal amplitude down 10%"
echo "example:  ./scale_percent.sh 0 25 input           will scale input data down to 25% of original data"
echo
}

source ./check_dfe_cap_core_map.sh

TARGET_INPUT_SCALING_LEVEL=50      #for auto scaling, after input scaling the sample level reaches this level at DAC, the rest is reserved for output scaling. percent
TARGET_DAC_SAMPLE_SCALE=85         #for auto scaling, the target highest sample scale reaches this level after input and output scaling. percent of full scale.
ant=0
factor=110
input_scaling=0; output_scaling=1; on=0; off=0; auto=0; dis=0
yesno=0
num_counter=0
offset=0
len=0
txrx=0 #0=tx 1=rx
arg_parse()
{
	arg=$1
	if [ $1 = input ]; then		input_scaling=1; output_scaling=0
	elif [ $1 = fast ]; then	fast=1
	elif [ $1 = -y ]; then		yesno=1
	elif [ $1 = on ]; then		on=1
	elif [ $1 = auto ]; then	auto=1
	elif [ $1 = dis ]; then		dis=1
	elif [ $1 = off ]; then		off=1
	elif [ $1 = tx ]; then		txrx=0
	elif [ $1 = rx ]; then		txrx=1
	elif [ ${arg:0:7} = offset= ]; then		offset=${arg:7}
	elif [ ${arg:0:4} = len= ]; then		len=${arg:4}
	else
		if [ $num_counter = 0 ];then
			ant=$(($1)); [ $ant != $1 ] && { echo -e "***ERROR: Wrong Argument $1\n"; print_usage; exit 1; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			factor=$(($1)); [ $factor != $1 ] && { echo -e "***ERROR: Wrong Argument $1\n"; print_usage; exit 1; }
			num_counter=$((num_counter+1))
		else
			echo -e "***ERROR: Wrong Argument $1\n"; print_usage; exit 1
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

if [ $txrx = 1 ];then
	check_ant_enable_rx $ant
	echo "Scaling digital signal amplitude at RX ADC output for antenna $ant to $factor%..."
	./utils/memrw w 32 $((test_tool_env_rx_scaling+ant*4)) $factor
	rxcore=${antrx[$ant]}
	rid=${ridant[$ant]}
	if [ $((factor)) -ne 0 ];then
		factor=`percent_to_F16 $((factor))`
	fi

	msb=`printf "0x%08x" $((0x0a030000 | (1 << 14) | (rid<<15)))`
	vspa_mbox send $rxcore $host_vspa_mbox_id $msb $factor;
	echo vspa_mbox send $rxcore $host_vspa_mbox_id $msb $factor;
	echo -e "RX signal scaling done. Run ./check_all.sh to check scaling result\n"
	check_error $ant
	exit 0
fi


check_ant_enable_tx $ant

if ([ $((factor)) -ge 200 ] && [ $yesno = 0 ]);then
	echo "***WARNING: High amplitude may damage PA. The scaling you set is $factor%."
	echo -n "Are you sure the scaling you set is safe?  Input Y to Continue, N to Abort: "
	read yesno
	([ "$yesno" != Y ] && [ "$yesno" != y ]) &&  { echo Command Aborted; exit 1; }
fi	

txcore=${anttx[$ant]}
tid=${tidant[$ant]}
get_chan_para $ant $txcore

if [ $dis = 1 ];then
	input_scaling=1; input_scaling_factor=100
	output_scaling=1; output_scaling_factor=100
elif [ $auto = 1 ];then
	factor_hist=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_output+ant*4))`))
	[ $((factor_hist&0x80000000)) -ne 0 ] && { echo -e "***ERROR: Output signal is turned off, please turn on first\n"; exit 1; }
	[ $((factor_hist&0x7FFFFFFF)) -ne 100 ] && { echo -e "***ERROR: Output signal is scaled, please scale it back to 100% first\n"; exit 1; }
	factor_hist=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_input+ant*4))`))
	[ $((factor_hist)) -ne 100 ] && { echo -e "***ERROR: Input signal is scaled, please scale it back to 100% first\n"; exit 1; }
	[ $((single_tone_stat)) -ne 0 ] && { echo -e "***ERROR: Single tone mode does not support auto scaling\n"; exit 1; }
	if [ $phcom_disable = 1 ];then
	tx_sym_base=`get_wordvalue_from_vspa $txcore $tx_sym_buf_base_inject`
	[ $((tx_sym_base)) -eq $((tx_sym_queue_base)) ] && { echo -e "***ERROR: VSPA is fetching TX symbols from TX symbol buffers, auto scaling not supported\n"; exit 1; }
	fi
	
	#calculate power from tx dump
	dump_size=$((axiqsps_tx[ant]*4*20)) ; host_addr=`phy2vir $addr_dump`
	log=`dump_time_domain_tx_1time $txcore $tid $addr_dump $host_addr $dump_size 0 0 0`
	log=`./utils/power $host_addr 0 $((dump_size/4))`
	eval "$log"
	
	v_rx_pow_acc=$power_IQ
	v_rx_pow_num_samples=$((dump_size/4))
	if [ $tx_fdd = 0 ];then
		eval trx_num_sym_in_pattern=`get_num_sym_in_pattern`
		v_rx_pow_num_samples=$((v_rx_pow_num_samples*trx_num_sym_in_pattern[1]/trx_num_sym_in_pattern[0]))
	fi
	sample_power=($(echo $v_rx_pow_acc $v_rx_pow_num_samples | awk '{ x=10*(log($1/$2)/log(10)); printf("%f %3.1f\n", $1/$2, x); }'))
	
	power_IQ_dB=`echo ${sample_power[1]} | awk '{ printf("%d\n",$1); }'`
	[ $power_IQ_dB -ge -10 ] && { echo -e "***ERROR: Power $power_IQ_dB already reached -10 dB level, not need for scaling\n"; exit 1; }
	expected_scaling_factor=`echo $((-10 - $power_IQ_dB)) | awk '{ printf("%d\n",2^($1/6)*100); }'`
	
	input_scaling=1; input_scaling_factor=100
	output_scaling=1; output_scaling_factor=100
	max_IQ100=`echo $max_IQ | awk '{ abs_val = ($1 >= 0) ? $1 : -$1; printf("%d\n", abs_val*100); }'`
	[ $max_IQ100 -lt 1 ] && { echo -e "***WARNING: Signal is too weak, max_IQ $max_IQ. Do not use auto scaling\n"; exit 1; }
	[ $max_IQ100 -lt $TARGET_INPUT_SCALING_LEVEL ] && { input_scaling_factor=$((TARGET_INPUT_SCALING_LEVEL*100/max_IQ100)); max_IQ100=$TARGET_INPUT_SCALING_LEVEL; }
	output_scaling_factor=$((TARGET_DAC_SAMPLE_SCALE*100/max_IQ100))
	
	total_scaling_factor=$((input_scaling_factor*output_scaling_factor/100))
	if [ $total_scaling_factor -gt $expected_scaling_factor ];then
		output_scaling_factor=$((output_scaling_factor*expected_scaling_factor/total_scaling_factor))
	fi
	echo Max scaling factor to 10dB $expected_scaling_factor, Max scaling factor to $TARGET_DAC_SAMPLE_SCALE% scale $total_scaling_factor, executed $((output_scaling_factor*input_scaling_factor/100))
	
else
	[ $input_scaling = 1 ] && input_scaling_factor=$factor || output_scaling_factor=$factor
fi


if [ $input_scaling = 1 ];then
	if ([ $phcom_disable = 1 ] || [ $((option8_tx[ant])) -eq 1 ]);then #when phcom is disabled or time domain, scale input waveform
	filename=${invecfile_cur[$ant]}; [ $filename = 0 ] && { echo -e "Waveform file not loaded\n"; exit 1; }
	echo Scaling TX input waveform amplitude for antenna $ant to $input_scaling_factor%...
	log=`./update_test_vector.sh $ant $filename`  #restore test vector
	[ $((len)) -eq 0 ] && len=$((invecsize_exp[$ant]/4))
	if [ $input_scaling_factor -ne 100 ];then
		addr_phy=${addr_tx_wv[$ant]}
		addr_vir=`phy2vir $addr_phy`
		./utils/scale $((addr_vir+offset*4)) $((addr_vir+offset*4)) $len $input_scaling_factor
	fi
	./utils/memrw w 32 $((test_tool_env_tx_scaling_input+ant*4)) $input_scaling_factor 
	else
	echo Scaling TX input RE amplitude by scaling phase compensation coeff for antenna $ant to $input_scaling_factor%...
	./update_phase_compensation_coeff.sh $ant scale=$input_scaling_factor
	fi
fi


if [ $output_scaling = 1 ];then
	factor_hist=$((`./utils/memrw r 32 $((test_tool_env_tx_scaling_output+ant*4))` & 0x7FFFFFFF ))
	if [ $off = 1 ];then	
		output_scaling_factor=0
		./utils/memrw w 32 $((test_tool_env_tx_scaling_output+ant*4)) $((factor_hist|0x80000000))  #set OFF bit
	elif [ $on = 1 ];then	
		((output_scaling_factor=factor_hist))
		./utils/memrw w 32 $((test_tool_env_tx_scaling_output+ant*4)) $factor_hist  #clear OFF bit
	else
		./utils/memrw w 32 $((test_tool_env_tx_scaling_output+ant*4)) $output_scaling_factor 
	fi

	echo "Scaling digital signal amplitude at TX DAC input for antenna $ant to $output_scaling_factor%..."

	if [ $((output_scaling_factor)) -ne 0 ];then
		output_scaling_factor=`percent_to_F16 $output_scaling_factor`
	fi

	msb=`printf "0x%08x" $((0x0a030000 | (tid<<15)))`
	vspa_mbox send $txcore $host_vspa_mbox_id $msb $output_scaling_factor;
	echo vspa_mbox send $txcore $host_vspa_mbox_id $msb $output_scaling_factor;

fi
echo -e "TX signal scaling done. Run ./check_all.sh to check scaling result\n"
check_error $ant
exit 0
