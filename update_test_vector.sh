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
	echo
	echo "Usage: ./update_test_vector.sh [ant_id] [user_vec_filename|sample] [-lh|-rh] [idx=a:b]"
	echo "  ant_id:            0-5, test vector only updated on specified antenna. If ant_id not specified, update on all antennas"
	echo "  user_vec_filename: User vector file to be loaded, user_vec_filename is the filename. If filename is not specified, default frequency domain input vector file will be loaded"
	echo "  sample:            A sample is a HEX format 32-bit IQ value with leading 0x. If sample is specified, the value of all the waveform will be set to this sample value"
	echo "  -lh:               only send left half of the total bandwidth."
	echo "  -rh:               only send right half of the total bandwidth."
	echo "  idx=a:b:           only keep specified range of REs, other REs cleared to 0"
	echo "example:  ./update_test_vector.sh 0 a.bin                will update test vector to a.bin on ant 0"
	echo "example:  ./update_test_vector.sh 0 a.bin idx=-120:119   will update test vector to a.bin on ant 0 and only keep 240 REs"
	echo
}

source ./check_dfe_cap_core_map.sh

arg_file=0
lh=0
rh=0
ant=all
send_fixed_sample_flag=0
flag_idx=0
num_counter=0

arg_parse()
{
	local arg=$1
	if 		[ $1 = help ]; 	then		print_usage; exit;
	elif 	[ $1 = -lh ]; 	then		lh=1
	elif 	[ $1 = -rh ]; 	then		rh=1
	elif 	[ ${arg:0:4} = "idx=" ]; then 		
		arg=${arg:4}; arg=(${arg//:/ }); [ ${#arg[@]} != 2 ] && { echo -e "***ERROR: wrong idx parameters\n"; exit 1; }
		flag_idx=1; idx_start=${arg[0]}; idx_end=${arg[1]}
	elif 	[ $1 = 0 ]; 	then		ant=0
	elif 	[ $1 = 1 ]; 	then		ant=1
	elif 	[ $1 = 2 ]; 	then		ant=2
	elif 	[ $1 = 3 ]; 	then		ant=3
	elif 	[ $1 = 4 ]; 	then		ant=4
	elif 	[ $1 = 5 ]; 	then		ant=5
	elif 	[ ${arg:0:2} = 0x ];then	send_fixed_sample_flag=1; send_fixed_sample_value=$((arg))
	else								arg_file=$1; [ -f $arg_file ] || { echo "File $arg_file doesn't exist, command failed"; exit; }
	fi
}

for i in "$@"
do
	arg_parse $i
done

if [ $ant = all ];then
	ant_start=0; ant_end=5
else
	ant_start=$ant; ant_end=$ant;
fi

prach=0
num_ant_updated=0
for ((ant=ant_start;ant<=ant_end;ant++))
do
[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && continue

txcore=${anttx[$ant]}
get_chan_para $ant $txcore;

if [ $((vspa_image_version)) -ge $((0x457)) ];then
	tx_sym_base=`get_wordvalue_from_vspa $txcore $tx_sym_buf_base_inject`
	tx_num_sym=`get_wordvalue_from_vspa $txcore $tx_num_sym_in_buf_inject`
	if [ $((tx_sym_base)) -eq $((tx_sym_queue_base)) ];then
		echo "Updating PRACH waveform to $tx_num_sym TX symbols buffer..."
		[ $arg_file = 0 ] && { echo ***ERROR: PRACH waveform file not specified; exit 1; }
		filesize=$(stat --format=%s $arg_file)
		filesize_exp=$((bbsps_tx[ant]*4*tx_num_sym/sym_num_1m));
		[ $filesize -ne $filesize_exp ] && { echo ***ERROR: PRACH waveform file size $filesize is not expected $filesize_exp; exit 1; }
		tx_sym_base_vir=`phy2vir $tx_sym_base`
		echo Loading PRACH waveform $arg_file to address $tx_sym_base_vir for ant$ant
		loadfile $tx_sym_base_vir $arg_file $filesize_exp
		echo prach_wv=$arg_file >> ./runtime_config.txt
		((num_ant_updated++))
		prach=1
		continue
	fi
fi




if [ $arg_file = 0 ];then 
	vec_file=${invecfile_ori[$ant]}; 
	[ $vec_file = 0 ] && { echo Default waveform does not exist for ant $ant; continue; }
	tag="default waveform file"
else 
	vec_file=$arg_file
	tag="user specified waveform file"
fi
filesize=$(stat --format=%s $vec_file)
filesize_exp=${invecsize_exp[$ant]}

addr_phy=${addr_tx_wv[$ant]}
addr_vir=`phy2vir $addr_phy`
((sym_buf_size=(sym_size+31)/32*32))   #aligned to 32 sample 128B.

invecfile_cur[$ant]=$vec_file

if [ $send_fixed_sample_flag = 0 ];then
	([ $((filesize%filesize_exp)) -ne 0 ] && [ $((filesize_exp%filesize)) -ne 0 ]) && { echo -e "***ERROR: Input waveform file size $filesize is not expected ${input_waveform_len[$tx_fdd]}ms $filesize_exp.\n"; exit 1; }
	echo Loading $tag $vec_file to address $addr_vir with size $filesize_exp for ant$ant
	loadfile $addr_vir $vec_file $filesize_exp
	./utils/memrw w 32 $((test_tool_env_tx_scaling_input+ant*4)) 100 #input sacling restored to 100% as new waveform loaded
	if [ $filesize -lt $filesize_exp ];then
		numload=$((filesize_exp/filesize)); [ $numload -gt 40 ] && { echo -e "***ERROR: Input waveform file size $filesize is too small than expected ${input_waveform_len[$tx_fdd]}ms $filesize_exp.\n"; exit 1; }
		echo -e "***WARNING: Ant $ant waveform size $filesize is smaller than expected ${input_waveform_len[$tx_fdd]}ms $filesize_exp, repeating/concatenating $numload times.\n"
		for((i=0;i<numload-1;i++))
		do
			./utils/memcpy $addr_vir $((addr_vir+(i+1)*filesize)) $((filesize/4))
		done
	elif [ $filesize -gt $filesize_exp ];then
		echo -e "***WARNING: Ant $ant waveform size $filesize is larger than expected ${input_waveform_len[$tx_fdd]}ms $filesize_exp, tail part will be removed.\n"
	fi
else
	./utils/memset $addr_vir $((filesize_exp/4)) $send_fixed_sample_value
	echo Setting ant $ant waveform to fixed sample value $send_fixed_sample_value
fi

((num_ant_updated++))

[ $((lh+rh+flag_idx)) -ne 0 ] && [ $((option8_tx[ant])) = 1 ] && { echo ***WARNING: -lh,-rh,idx= are not supported in option8. ignored.; continue; }

if [ $lh = 1 ];then #only send left half, clearing righ half
	((clr_start=sym_size/2))
	((clr_end=sym_size-1))
	echo Sending only LEFT half of total bandwidth...
elif [ $rh = 1 ];then #only send right half, clearing left half
	((clr_start=0))
	((clr_end=sym_size/2-1))
	echo Sending only RIGHT half of total bandwidth...
elif [ $flag_idx = 1 ];then
	((keep_start=sym_size/2+idx_start))
	((keep_end=sym_size/2+idx_end))
	echo Sending specified range of subcarriers...
fi

if [ $((lh+rh)) -eq 1 ];then
for ((i=0;i<sym_num;i++))
do
	((addr=addr_vir+(i*sym_buf_size+clr_start)*4))
	clear_mem $addr $((sym_size/2*4))
done

elif [ $flag_idx = 1 ];then
	if [ $((keep_start)) -gt 0 ];then
		for ((i=0;i<sym_num;i++))
		do
			((addr=addr_vir+(i*sym_buf_size+0)*4))
			clear_mem $addr $((keep_start*4))
		done
	fi
	if [ $((keep_end)) -lt $((sym_size-1)) ];then
		for ((i=0;i<sym_num;i++))
		do
			((addr=addr_vir+(i*sym_buf_size+keep_end+1)*4))
			clear_mem $addr $(((sym_size-1-keep_end)*4))
		done
	fi
fi

done
[ $prach = 0 ] && echo "invecfile_cur=(${invecfile_cur[@]}); " >> ./runtime_config.txt
echo Num of antennas updated: $num_ant_updated
echo
