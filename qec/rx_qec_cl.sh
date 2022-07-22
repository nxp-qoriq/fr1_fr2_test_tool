# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

# usage: ./rx_qec_cl.sh  tx_ant    rx_ant

# tx_ant/rx_ant:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.
 
#cmd_dir=./qec
source ./check_dfe_cap_core_map.sh
echo start QEC RX 

feedback_size=128	# unit: KB , RX dump file size
source ./qec_init.cfg
source $cmd_dir/qec_common.sh $tx_ant  $rx_ant


#tone_freq=3000000	# in Hz
#tone_freq=24000000	# in Hz
#tone_freq=24      	# in MHz

#amp=80				# percentage of full scale

#dump_len=4			# num of 32KB(or 8K IQ samples)

#verbose enable
#verbose_en=0


if [ $# -lt 2 ];then
	echo Wrong arguments
	#print_usage
	echo
	exit
fi
if [ $# -ge 2 ];then
	((tx_ant=$1%6))
	((rx_ant=$2%6))
fi
rxcore=${antrx[$rx_ant]}

#Should have sent single tone at the beginning of CL-QEC
#./send_single_tone.sh $tx_ant  $(($tone_freq*1000000))  $amp 
#sleep 0.1

[ $verbose_en = 1 ] &&    echo ./dump_time_domain_rx.sh $rx_ant $((feedback_size/32))
./dump_time_domain_rx.sh $rx_ant $((feedback_size/32))            > /dev/null       #dump time domain RX 
#./dump_time_domain_rx.sh $rx_ant $((feedback_size/32))    HRAM   > /dev/null       #dump time domain RX 
#dump_filename=$feedback_file
#dump_via_hram   > /dev/null

get_chan_para $rx_ant $rxcore
feedback_sps=$rxaxiq

[ $verbose_en = 1 ] &&    echo feedback_sps: $feedback_sps
feedback_file=rx_timedomain_$feedback_size\KB_$feedback_sps\ksps_dump_ant$rx_ant.bin
[ -f $feedback_file ] || { echo File $feedback_file does not exist, command failed.; echo; exit; }

#debug
#feedback_file=3MHz_td_245p76Msps_GainImb1p1.bin
$cmd_dir/fr12_rx_iqimb_api.sh    $tone_freq  $feedback_file  $rx_ant 

#echo QEC Close Loop RX Calibration Done
