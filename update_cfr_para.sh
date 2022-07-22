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

#usage: ./update_cfr_para.sh [ant id] [dis]
#usage: ./update_cfr_para.sh [ant id] [filename] [cpulse]
#all the arguments are optional, by default the script will update cfr para with user para defined below in this script.
#ant id:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.
#dis: 		disable cfr, set cfr back to pass through mode
#filename: 	update cfr para from a file. The data struct in the file must be as same struct as in this script.
#           If filename not specified, defalut parameters will be used which is well tuned and embeded in VSPA images.
#example: ./update_cfr_para.sh     will update cfr with user para defined in this script to ant 0
#example: ./update_cfr_para.sh 1   will update cfr with user para defined in this script to ant 1
#example: ./update_cfr_para.sh 0 dis   will set cfr back to pass through mode.
#example: ./update_cfr_para.sh 0 f.bin   will load the para from f.bin and update it to cfr, data in the file should be little endian, bin format
#example: ./update_cfr_para.sh 0 f.bin cpulse  will load the cpulse struct from f.bin and update it to cfr, data in the file should be little endian, bin format

#cfr para struct:
#each PASS uses a different para struct defined as below, each struct occupies 128 bytes, starting address aligned to 128
#typedef struct struct_cfr_para_s
#{
#	__fp16 coef_fir[16];
#	__fp16 coef_interp8x[20+8+8];   //must be in interleaved order
#	__fp16 threshold_p;		//threshold for peak search, only the peak samples with power higher than threshold can be picked for cancellation
#	__fp16 reserved1;
#	__fp16 threshold_c;		//threshold for peak-canceled power, the new peak power will be no higher than this threshold.
#	__fp16 reserved2;
#	short Nskip;			//can be any integer.
#} struct_cfr_para;

#cfr cpulse struct (cpulse file should contain 8 such struct for 8 cpulses):
#typedef struct struct_cpulse_s
#{
#	__fp16	zero_pad0[32];		//must be set to 0's
#	__fp16	cpulse[LEN_CPULSE];
#	__fp16	zero_pad1[31];		//must be set to 0's
#} struct_cpulse;


source ./check_dfe_cap_core_map.sh

ant=0
dis=0
filename=0
cpulse=0
if [ $# -ge 1 ]; then
	if [ $1 = 0 ]; then 		ant=$1
	elif [ $1 = 1 ]; then 		ant=$1
	elif [ $1 = 2 ]; then 		ant=$1
	elif [ $1 = 3 ]; then 		ant=$1
	elif [ $1 = 4 ]; then 		ant=$1
	elif [ $1 = 5 ]; then 		ant=$1
	elif [ $1 = dis ]; then 	dis=1
	else						
		filename=$1
		[ -f $filename ] || { echo "File $filename doesn't exist, command failed"; exit; }
	fi
fi
	
if [ $# -ge 2 ]; then
	if [ $2 = dis ];then
		dis=1
	elif [ $2 = cpulse ];then
		cpulse=1
	else
		filename=$2
		[ -f $filename ] || { echo "File $filename doesn't exist, command failed"; exit; }
	fi
fi

if [ $# -ge 3 ]; then
	cpulse=1
fi

check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

txcore=${anttx[$ant]}
tid=${tidant[$ant]}
get_chan_para $ant $txcore

if [ $((cfr_pass)) = 0 ];then
	echo -e "***ERROR: CFR is disabled in current version of test tool. command failed.\n"
	exit 1
fi

addr_vir=`phy2vir $addr_dump`
if [ $dis = 1 ];then 
	echo CFR set to passthrough on ant $ant.
	./utils/memset $addr_vir $((cfr_pass*128/4)) 0
	for ((i=0;i<cfr_pass;i++))
	do
		./utils/memset $((addr_vir+i*128+52*2)) 1 0x4000   #set threshold to 2.0 to avoid CFR 
		./utils/memset $((addr_vir+i*128+54*2)) 1 0x4000   #set threshold to 2.0 to avoid CFR 
	done
	cpulse=0
else
	[ $filename = 0 ] && { echo -e "***ERROR: Filename not specified, command failed.\n"; exit 1; }
	loadfile $addr_vir $filename
	echo CFR ${tag_cpulse[cpulse]} updated from file $filename on antenna $ant.

fi


tag_cpulse=(para cpulse)
((msb=0x0A060000+(cpulse<<14)+(tid<<15)))
((lsb=addr_dump>>7))
msb=`printf "0x%08x" $msb`
lsb=`printf "0x%08x" $lsb`
vspa_mbox send $txcore $host_vspa_mbox_id $msb $lsb
echo vspa_mbox send $txcore $host_vspa_mbox_id $msb $lsb

check_error_ant $ant
