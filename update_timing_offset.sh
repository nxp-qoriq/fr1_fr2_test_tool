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
echo "usage: ./update_timing_offset.sh <ant id> <num_samples> [delay|advance] [tx|rx] [dis]"
echo "  ant id:        antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.  "
echo "  num_samples:   number of samples at FFT/iFFT to delay or advance"
echo "  delay|advance: delay or advance。 if not specified, delay will be used"
echo "  tx|rx:         TX or RX, if not specified, TX will be used"
echo "  dis:           Cancel all previous accumulated timing offset valude"
}

source ./check_dfe_cap_core_map.sh

txrx=0; advance=0; num_samples=0; ant=0; dis=0
num_counter=0

arg_parse()
{
	arg=$1
	if ([ $1 = help ] || [ $1 = -help ]); then		print_usage; exit 1
	elif [ $1 = rx ]; then 		txrx=1
	elif [ $1 = tx ]; then 		txrx=0
	elif [ $1 = delay ]; then 	advance=0
	elif [ $1 = advance ]; then advance=1
	elif [ $1 = dis ]; then 	dis=1
	else 						
		if [ $num_counter = 0 ];then	((num_counter++));	ant=$(get_ant_id_from_arg $1); [ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit 1; }
		elif [ $num_counter = 1 ];then	((num_counter++));	num_samples=$(($1))
		else							echo Wrong Argument: $1; print_usage; exit 1
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done


if [ $txrx = 0 ];then	
	check_ant_enable_tx $ant; core=${anttx[$ant]}; trid=${tidant[$ant]}
else 					
	check_ant_enable_rx $ant; core=${antrx[$ant]}; trid=${ridant[$ant]}
fi

send_timing_offset_cmd $core $txrx $advance $num_samples $dis
TXRX=(TX RX); DLY_ADV=(Delayed Advanced)
echo -e "${TXRX[txrx]} timing is ${DLY_ADV[advance]} by $num_samples samples at FFT/iFFT on antenna $ant\n"
check_error_ant $ant
