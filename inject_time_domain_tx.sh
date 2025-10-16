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

inject_tx_time_file=(0 0 0 0 0 0)
inject_tx_time_addr=(0 0 0 0 0 0)
inject_tx_time_size=(0 0 0 0 0 0)
inject_tx_time_tag=(0 0 0 0 0 0)

print_usage()
{
	echo
	echo "Usage: ./inject_time_domain_tx.sh [ant_id] [<user_vec_file>] [HRAM]" 
	echo "Usage: ./inject_time_domain_tx.sh [ant_id] [stop]"
	echo "    ant_id:        0,1,2,3,4,5"
	echo "    stop:          stop injecting"
	echo "    user_vec_file: User vector file will be loaded, user_vec_file is the filename."
	echo "    HRAM:          inject from HRAM."
	echo "Example: ./inject_time_domain_tx.sh 0 <filename> : load specified file to DDR and send it to DAC antenna 0"
	echo "Example: ./inject_time_domain_tx.sh 0 stop : stop sending timedomain vector for memory, go back to send normal DFE signal"
	echo
}

source ./check_dfe_cap_core_map.sh

stop_inject=0
via_hram=0
ant=0
vec_file=0

arg_parse()
{
	if 		([ $1 = stop ] || [ $1 = dis ]); 	then		stop_inject=1
	elif 	([ $1 = HRAM ] || [ $1 = hram ]); 	then		via_hram=1
	elif 	[ $1 = 0 ]; 	then		ant=0
	elif 	[ $1 = 1 ]; 	then		ant=1
	elif 	[ $1 = 2 ]; then			ant=2
	elif 	[ $1 = 3 ]; then			ant=3
	elif 	[ $1 = 4 ]; then			ant=4
	elif 	[ $1 = 5 ]; then			ant=5
	elif 	[ $1 = fast ]; then			fast=1
	else                                vec_file=$1
	fi
}

for i in "$@"
do
	arg_parse $i
done

#[ $buffer_mode = 1 ] && { echo -e "***ERROR: Current mode is buffer mode. Should not run this script before buffer mode is stopped.\n"; exit 1; }
check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }
txcore=${anttx[$ant]}; txscore=${slave_core[txcore]}
tid=${tidant[$ant]}


get_chan_para $ant $txcore
#[ $tx_timedomain_dump_inject_enable = 0 ] && { echo "***ERROR: Current version of VSPA image doesn't support this feature."; echo; exit 1; }

msb=`printf "0x%08x" $((0x0A200000 + (tid<<15)))`
status=`get_wordvalue_from_vspa $txscore $tx_timedomain_inject_size`

if [ $stop_inject = 1 ];then
	#msb=`printf "0x%08x" $((0x0A202000 + (tid<<15)))`
	#vspa_mbox send $txcore 1 $msb 0
	#echo vspa_mbox send $txcore 1 $msb 0
	if [ $((status)) = 0 ];then
		echo -e "***ERROR: Current ant $ant time domain inject not enabled, unable to stop it.\n"
		exit 1
	else
		set_wordvalue_to_vspa $txscore $tx_timedomain_inject_size 0
		echo Time domain inject on ant $ant successfully stopped.
		exit 1
	fi
else
	if [ $((status)) != 0 ];then
		echo -e "***ERROR: Current ant $ant time domain inject already enabled, unable to enable it again.\n"
		exit 1
	fi
fi

sps=${axiqsps_tx[ant]}
blocksize=$((block_size_per_ant[ant]*(sps/${bbsps_tx[ant]})))
((size_half_ms=sps*2)); ((size_40ms=size_half_ms*80))

if [ $vec_file != 0 ];then
	[ -f $vec_file ] || { echo -e "\n***ERROR: File $vec_file does not exist, command failed\n"; echo; print_usage; exit 1; }
	filesize=$(stat --format=%s $vec_file)
	[ $((filesize)) -lt $blocksize ] && { echo -e "\n***ERROR: File size is less then block size $blocksize\n"; exit 1; } 
else
	#filesize=$size_half_ms  #if filename not specified, use 0.5ms length as default
	filesize=$((blocksize*4))  #if filename not specified, use 4 blocks buffer for shortest delay
fi

if [ $filesize -ge $size_half_ms ];then
	if [ $((filesize%size_half_ms)) -ne 0 ];then
		echo WARNING: File size $filesize is not multiple of 0.5ms. 
		((filesize=filesize/size_half_ms*size_half_ms))
	fi
	((num_half_ms=filesize/size_half_ms))
	tag=$num_half_ms*0.5ms
else
	[ $((size_40ms%filesize)) -ne 0 ] && { echo -e "\n***ERROR: 40ms is not mutiple of File size, users must make sure 40ms%filesize = 0\n"; exit 1; } 
	[ $((filesize % $blocksize)) -ne 0 ] && { echo -e "\n***ERROR: File size is not mutiple of block size $blocksize\n"; exit 1; } 
	num_half_ms=0
	tag=$filesize
fi

available_hram_size=$((HRAMaddr_phy+HRAM_size-next_HRAMaddr_phy))
([ $fr2 = 1 ] || [ $filesize -le $available_hram_size ]) && via_hram=1

if [ $((inject_tx_time_size[ant])) -eq 0 ];then #new inject, allocate address
if [ $via_hram = 0 ];then
	if [ $num_half_ms -gt 80 ];then
		echo
		echo WARNING: File size $filesize which is $num_half_ms\ms, too large, maximum allowed is 40ms.
		echo
		num_half_ms=80
		((filesize=num_half_ms*size_half_ms))
	fi
	malloc_for_inject $filesize
	addr_phy=$malloced_addr
	addr_vir=`phy2vir $addr_phy`
	echo TX time domain inject size is set to $filesize, $tag from DDR.
else
	addr_phy=$next_HRAMaddr_phy
	addr_vir=$((HRAMaddr_vir+next_HRAMaddr_phy-HRAMaddr_phy))
	if [ $filesize -gt $available_hram_size ];then
		echo "***WARNING: Injection length exceeds available HRAM size $available_hram_size. Will reduce inject length."
		num_half_ms=$((available_hram_size/size_half_ms)); tag=$num_half_ms*0.5ms
		[ $num_half_ms = 0 ] && { echo -e "\n***ERROR: Available HRAM size $available_hram_size is too small to hold 0.5ms size $size_half_ms.\n"; exit 1; } 
		((filesize=num_half_ms*size_half_ms))
		echo TX time domain inject size is set to $filesize, $num_half_ms*0.5ms from HRAM.
	else
		echo TX time domain inject size is set to $filesize, $tag from HRAM.
	fi
	
	next_HRAMaddr_phy=$(printf 0x%x $((addr_phy+filesize)))
fi
inject_tx_time_file[ant]=$vec_file
inject_tx_time_addr[ant]=$addr_phy
inject_tx_time_size[ant]=$filesize
inject_tx_time_tag[ant]=$tag
echo "inject_tx_time_tag=(${inject_tx_time_tag[@]}); inject_tx_time_file=(${inject_tx_time_file[@]}); inject_tx_time_addr=(${inject_tx_time_addr[@]}); inject_tx_time_size=(${inject_tx_time_size[@]}); next_HRAMaddr_phy=$next_HRAMaddr_phy" >> runtime_config.txt

else #previously injected, reuse address
	addr_phy=${inject_tx_time_addr[ant]}
	filesize_pre=${inject_tx_time_size[ant]}
	if [ $filesize -gt $filesize_pre ];then
		echo -e "***ERROR: Current inject size $filesize is bigger than previously injected size $filesize_pre\n"
		exit 1
	elif [ $filesize -lt $filesize_pre ];then
		tag=$filesize
	else
		tag=${inject_tx_time_tag[ant]}
	fi
	addr_vir=`phy2vir $addr_phy`
	echo "Re-use previous inject buffer from address $addr_phy size $filesize_pre for current inject size $filesize"
fi

#((size32KB=$filesize/32768))
#((lsb=(size32KB<<20)+(addr_phy>>12)))

#lsb=`printf "0x%08x" $lsb`

#vspa_mbox send $txcore 1 $msb $lsb
#echo vspa_mbox send $txcore 1 $msb $lsb

[ $vec_file != 0 ] && { echo Loading waveform file $vec_file from address $addr_vir; loadfile $addr_vir $vec_file $filesize; } || { echo File not provided, source data from address $addr_vir size $filesize initialized to all 0.; ./utils/memset $addr_vir $((filesize/4)) 0; }

set_wordvalue_to_vspa $txscore $tx_timedomain_inject_addr $addr_phy
set_wordvalue_to_vspa $txscore $tx_timedomain_inject_size $filesize

check_error_ant $ant
if [ $((num_errors)) -ne 0 ];then
	echo Time domain injection incurred high bandwidth on PCI and caused errors, if you are running more than 1 channels, change to 1 channel.
	echo option1: boot VSPA and run the following script to enable TX only, and then run this script again.
	echo ./channels_start.sh txonly
	echo option2: boot VSPA and run the following script to enable 1 antenna only, and then run this script again.
	echo ./channels_start.sh [ant_id]
	echo And remember to stop injecting previous antenna before injecting another antenna!!!
	exit 1
else
	if [ $rloopback_time = 0 ];then
		echo -e "SUCCESS! TX time domain inject $tag for antenna $ant from address `HEX $addr_vir` size $filesize\n"
	else
		echo -e "SUCCESS! Reverse loopback time domain for antenna $ant from address `HEX $addr_vir` size $filesize"
		echo -e "The loopback delay is $((filesize/4)) sample at ${axiqsps_tx[ant]} Ksps, ~$((filesize/4*1000/axiqsps_tx[ant])) us\n"
	fi
fi
exit 0
