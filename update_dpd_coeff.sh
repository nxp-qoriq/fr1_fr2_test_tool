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
echo "usage: ./update_dpd_coeff.sh [ant id] [filename]"
echo "usage: ./update_dpd_coeff.sh [ant id] [dis]"
echo "ant id:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels."
echo "dis: 		disable dpd, set dpd back to pass through mode"
echo "filename: 	update dpd coeff from a file. The data struct in the file must be as same struct as in this script."
echo "example: ./update_dpd_coeff.sh 0 dis     will set dpd back to pass through mode."
echo "example: ./update_dpd_coeff.sh 0 f.bin   will load the coeff from f.bin and update it to dpd, data in the file should be little endian, bin format"
echo
}

source ./check_dfe_cap_core_map.sh

ant=0
filename=0
dis=0
ncvt=0
num_counter=0

arg_parse()
{
	if ([ $1 = stop ] || [ $1 = dis ]); then		dis=1
	elif [ $1 = ncvt ]; then						ncvt=1
	else
		if [ $num_counter = 0 ];then
			ant=$(get_ant_id_from_arg $1)
			[ $ant = null ] && { echo Wrong Argument; print_usage; exit; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			filename=$1
			[ -f $filename ] || { echo "File $filename doesn't exist, command failed"; exit; }
			num_counter=$((num_counter+1))
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

txcore=${anttx[$ant]}
tid=${tidant[$ant]}

get_chan_para $ant $txcore
[ $((dpd_model_id)) -eq 0 ] && { echo DPD is disabled in current VSPA image, command failed.; echo; exit 1; }

dpd_model_get_para
dpd=`dpd_model_num_coeff`	

addr_phy=$addr_dump
addr_vir=`phy2vir $addr_phy`

if [ $dis = 1 ];then
	echo "Setting DPD to Passthrough on ant $ant..."
	mailbox_msg_send_dpd_passthrough $txcore $tid

elif [ $filename != 0 ];then
	#filesize=$(stat --format=%s $filename)
	loadfile $addr_vir $filename
	update_dpd_coeff

else
	echo Wrong Argument; print_usage; exit 1;
fi
