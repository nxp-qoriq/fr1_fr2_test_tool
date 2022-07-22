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
	echo "Usage: ./inject_freq_domain_tx.sh <ant_id> [file] [stop] [nsym=n] [addr=x"
	echo "    ant_id: 0,1,2,3,4,5.   injected waveform file is default file, users can use ./update_test_vector.sh to update injected file."
	echo "    stop: stop injecting"
	echo "    file: waveform file to be injected"
	echo "    nsym=n: specify num of symbols to inject, n can be any number from 1 and 20ms must be multiple of n"
	echo "    addr=x: specify address from where the waveform will be loaded by VSPA, x must be in VSPA view and can be any address that VSPA can access, must be 4KB aligned"
	echo "Example: ./inject_freq_domain_tx.sh 0           will inject waveform for ant 0, assuming waveform file already loaded to specified address"
	echo "Example: ./inject_freq_domain_tx.sh 0 f.bin     will load f.bin to specified address and inject waveform for ant 0"
	echo "Example: ./inject_freq_domain_tx.sh 0 stop      will stop injecting"
	echo
}

source ./check_dfe_cap_core_map.sh
#[ $sinad = 1 ] && { echo Current VSPA images do not support freq domain injection.; exit; }

stop_inject=0
ant=0
vec_file=0
nsym=0; addr=""
HRAM=0

arg_parse()
{
	arg=$1
	if 		[ $1 = stop ]; 	then		stop_inject=1
	elif 	[ $1 = 0 ]; 	then		ant=0
	elif 	[ $1 = 1 ]; 	then		ant=1
	elif 	[ $1 = 2 ]; then			ant=2
	elif 	[ $1 = 3 ]; then			ant=3
	elif 	[ $1 = 4 ]; then			ant=4
	elif 	[ $1 = 5 ]; then			ant=5
	elif 	[ $1 = fast ]; then			fast=1
	elif 	[ $1 = HRAM ]; then			HRAM=1
	elif 	[ ${arg:0:5} = nsym= ]; then			nsym=$(echo $arg | cut -d "=" -f2)
	elif 	[ ${arg:0:5} = addr= ]; then			addr=$(echo $arg | cut -d "=" -f2)
	else                                vec_file=$1
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

txcore=${anttx[$ant]}
tid=${tidant[$ant]}

if [ $stop_inject = 1 ];then
if [ $((vspa_image_version)) -le $((0x456)) ];then
	msb=`printf "0x%08x" $((0x0A112000 + (tid<<15)))`
	inject_freq_domain_tx_stop $txcore $host_vspa_mbox_id $msb 0
else
	msb=`devmem $((test_tool_env_buf_struct_msg+txcore*8+0))`
	lsb=`devmem $((test_tool_env_buf_struct_msg+txcore*8+4))`
	vspa_mbox_ifsend $txcore $host_vspa_mbox_id $msb $lsb  #send buf struct msg to restore tx symbol buffer
fi
echo -e "Injecting freq domain waveform on ant $ant has stopped. Sending from TX symbol buffers.\n"
exit 1
fi

get_chan_para $ant $txcore
size_1sym=`size_align $((sym_size*4)) 128`
[ $((nsym)) -eq 0 ] && nsym=$sym_num

if [ $HRAM = 0 ];then
	[ "$addr" = "" ] && addr=${addr_tx_wv[$ant]}
	[ $vec_file != 0 ] && ./update_test_vector.sh $ant $vec_file
else
	end_hram=`size_align $next_HRAMaddr_phy 4096`
	available_hram=$((HRAMaddr_phy+HRAM_size-end_hram))
	[ $available_hram -lt $((size_1sym*nsym)) ] && { echo -e "***ERROR: HRAM or TCM available size $available_hram is smaller than required $((size_1sym*nsym))\n"; exit 1; }
	addr=$end_hram
	if [ $vec_file != 0 ];then
		if [ -f $vec_file ];then
			filesize=$(stat --format=%s $vec_file)
			[ $((filesize)) -gt $available_hram ] && { echo -e "***ERROR: Input waveform file size $filesize is larger than available HRAM/TCM size $available_hram, file not loaded.\n"; exit 1; }
			addr_vir=`phy2vir $addr`
			loadfile $addr_vir $vec_file
			echo Loading file $vec_file to address $addr_vir
		else
			echo -e "***ERROR: Input waveform file $vec_file does not exist, file not loaded.\n"; exit 1;
		fi
	fi
fi

inject_msb=`printf "0x%08x" $((0x0A110000 + (size_1sym/128) + (tid<<15)))`
inject_lsb=`printf "0x%08x" $(((nsym<<20)+(addr>>12)))`
inject_freq_domain_tx $txcore $host_vspa_mbox_id $inject_msb $inject_lsb
echo Injecting freq domain waveform on antenna $ant done, nsym=$nsym, addr=`HEX $addr`
echo
./check_error.sh
