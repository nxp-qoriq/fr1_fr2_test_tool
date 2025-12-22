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
echo "usage ./channels_act_tx.sh [ant_id_list]"
echo "  Set TX channels active. Specified channels will be set active to send user waveform, other channels will be set idle and no signal will be sent"
echo "  ant_id_list: 	list of ant id to set active, each id is 0-5. the list can be any combination of num from 0 to 5, all stands for all antennas"
echo "  Example: ./channels_act_tx.sh 0   	        will set channel 0 active to send user waveform, other channels set idle"
echo "  Example: ./channels_act_tx.sh 0 1  		    will set channel 0 and 1 active to send user waveform, other channels set idle"
echo "  Example: ./channels_act_tx.sh all  		    will set or enabled channels active to send user waveform"
echo 
}

source ./check_dfe_cap_core_map.sh

ant_list=(0 0 0 0 0 0)

arg_parse()
{
	if [ $1 = 0 ]; then				ant_list[$1]=1
	elif [ $1 = 1 ]; then			ant_list[$1]=1
	elif [ $1 = 2 ]; then			ant_list[$1]=1
	elif [ $1 = 3 ]; then			ant_list[$1]=1
	elif [ $1 = 4 ]; then			ant_list[$1]=1
	elif [ $1 = 5 ]; then			ant_list[$1]=1
	elif [ $1 = all ]; then			ant_list=(1 1 1 1 1 1)
	else							echo Argument $1 undefined; print_usage; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done

for ((i=0;i<NUM_ANTS;i++))
do
	if [ $((ant_enable[i]&BITMASK_ANT_ENABLE_TX)) = 0 ];then
		[ $((ant_list[i])) -eq 1 ] && echo Ant $i is in disabled state.
		continue
	fi
	txcore=${anttx[$i]}
	if [ $((ant_list[i])) -eq 1 ];then	
		log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e21ff 0x00040000`; 
		echo Ant $i is set active.
	else	
		log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e0000 0x00040000`; 
		echo Ant $i is set idle;
	fi
done
