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
echo "usage: ./update_fine_cfo_nco_freq.sh <ant id> <freq> [tx|rx]"
echo "ant id:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.  "
echo "freq: 	frequency in Hz"
echo "tx|rx:    TX or RX, if not specified, TX will be used"
}

source ./check_dfe_cap_core_map.sh

[ $# -lt 2 ] && { print_usage; exit 1; }

ant=0
freq=0
txrx=TX
num_counter=0

arg_parse()
{
	arg=$1
	if   [ $1 = rx ]; then 		txrx=RX
	elif [ $1 = tx ]; then 		txrx=TX
	else
		if [ $num_counter = 0 ];then	((num_counter++));	ant=$(get_ant_id_from_arg $1); [ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit 1; }
		elif [ $num_counter = 1 ];then	((num_counter++));	freq=$(($1))
		else							echo Wrong Argument: $1; print_usage; exit 1
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $cfo_disable = 1 ] && { echo -e "***ERROR: CFO feature is not enabled in current VSPA image, command failed\n"; exit 1; }

if [ $txrx = TX ];then	
	check_ant_enable_tx $ant; cmd=0x14000000; core=${anttx[$ant]}; trid=${tidant[$ant]}; sps=${axiqsps_tx[ant]}
else 					
	check_ant_enable_rx $ant; cmd=0x15000000; core=${antrx[$ant]}; trid=${ridant[$ant]}; sps=${axiqsps_rx[ant]}
fi

freq_hz=$freq
freq=$(echo $freq $sps | awk '{ freq=4294967296*$1/$2/1000; printf("%d",freq); }') #convert frequency in Hz to frequency value used by NCO
if [ $freq -lt 0 ];then
((freq=freq-1))    #the freq factor is 1's complement, equals to 2'complement plus 1
echo Negative frequency!
fi
((freq=freq&0xFFFFFFFF))  #get 32LSB

vspa_mbox send $core $host_vspa_mbox_id $((cmd+(trid<<23))) $freq
echo vspa_mbox send $core $host_vspa_mbox_id `HEX $((cmd+(trid<<23)))` `HEX $freq`
echo "$txrx fine CFO NCO frequency updated to $freq_hz with NCO freq value `HEX $freq` on antenna $ant"
check_error_ant $ant
