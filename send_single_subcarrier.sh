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
	echo "usage: ./send_single_subcarrier.sh <ant id> <subcarrier_index> [subcarrier_sample_value] [add]"
	echo "usage: ./send_single_subcarrier.sh <ant id> stop"
	echo "for SCS 30Khz, the lowest subcarrier is 30Khz. for SCS 120, the lowest is 120Khz."
	echo "ant id:  antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels."
	echo "subcarrier_index: index of the subcarrier, -1638 to 1637 for 3276 sub-carriers."
	echo "sample_value: format: 0xQQQQIIII,  each sample is a complex with 16bit I in the lower 32bit word and 16-bit Q in the higher 32-bit word. 2'complement."
	echo "add: 	send current singe sub-carrier on top of previous singe sub-carriers"
	echo "stop: stop sending single subcarrier"
	echo "example: ./send_single_subcarrier.sh 0 1 0x30002000  will send 1*(15/30/60/120)Khz subcarrier with subcarrier sample value 0x30002000 on ant 0"
	echo "example: ./send_single_subcarrier.sh 2 100 0x30002000  will send 100*(15/30/60/120)Khz subcarrier for SCS15/30/60/120 with subcarrier sample value 0x30002000 on ant 2"
	echo "example: ./send_single_subcarrier.sh 2 stop  will stop sending single subcarrier on antenna 2"
	echo "To send multiple single sub-carriers, the first command must not have 'add' option, subsequent commands should have 'add' option."
	echo "	Example to send 2 single carriers at 15Khz and 30Khz (assume SCS is 15Khz)"
	echo "   ./send_single_subcarrier.sh 0 1 0x3FFF3FFF; ./send_single_subcarrier.sh 0 2 0x3FFF3FFF add"
	echo
}

source ./check_dfe_cap_core_map.sh

index=1
value=0x3FFF3FFF  #indicator of using fetched sample value
ant=0
stopping=0
add=0
num_counter=0
arg_parse()
{
	arg=$1
	if [ "${arg: -4}" = help ]; then				print_usage; exit 1;
	elif ([ $1 = stop ] || [ $1 = dis ]); then		stopping=1
	elif [ $1 = add ]; then							add=1
	else
		if [ $num_counter = 0 ];then
			ant=$(get_ant_id_from_arg $1)
			[ $ant = null ] && { echo Wrong Argument; print_usage; exit 1; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			index=$(($1))
			num_counter=$((num_counter+1))
		elif [ $num_counter = 2 ];then
			value=`HEX $(($1))`
			num_counter=$((num_counter+1))
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

check_ant_enable_tx $ant

txcore=${anttx[$ant]}
get_chan_para $ant $txcore
[ $((index+sym_size/2)) -lt 0 ] || [ $((index+sym_size/2)) -ge $sym_size ] && { echo -e "\n***ERROR: illegal sub-carrier index. Legal index from -$((sym_size/2)) to $((sym_size/2-1))\n"; exit 1; }

addr_vir=`phy2vir ${addr_tx_wv[$ant]}`
if [ $add = 1 ];then
	./utils/devmem $((addr_vir + (sym_size/2+index)*4 )) w $value
	echo "Sending multiple single sub carriers, adding new subcarrier $index * $scs Khz with specified sample value $value on antenna $ant"
	exit 0;
fi

if [ $stopping = 0 ]; then
	log=`./inject_freq_domain_tx.sh $ant nsym=1`   #sending 1 symbol repeatedly
	./utils/memset $addr_vir $sym_size 0  #clear the symbol to all 0
	./utils/devmem $((addr_vir + (sym_size/2+index)*4 )) w $value
	echo "Sending single sub carrier $index * $scs Khz with specified sample value $value on antenna $ant"
else
	./update_test_vector.sh $ant
	./inject_freq_domain_tx.sh $ant
	echo Stopped sending single sub carrier on antenna $ant, resume sending TM signal.
fi

check_error_ant $ant
