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

# usage: ./rx_dc_cl.sh  tx_ant    rx_ant

# tx_ant/rx_ant:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.
 

echo start RX DC Offset Calibration

source ./check_dfe_cap_core_map.sh
source ./qec_init.cfg
source $cmd_dir/qec_common.sh $tx_ant  $rx_ant


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

get_chan_para $rx_ant $rxcore

#Should have sent single tone at the beginning of CL-QEC
#./send_single_tone.sh $tx_ant  $(($tone_freq*1000000))  $amp 

dump_filename=$feedback_file
#dump_via_hram   > /dev/null
[ $verbose_en = 1 ] &&    echo ./dump_time_domain_rx.sh $rx_ant $((cap_size/32768))
./dump_time_domain_rx.sh $rx_ant $((cap_size/32768))            > /dev/null       #dump time domain RX 
[ -f $dump_filename ] || { echo File $dump_filename does not exist, command failed.; echo; exit; }


read -r dc_re_sig dc_im_sig << EOF
`$cmd_dir/tonelevel -i $dump_filename -f 0 -l -c -q`
EOF

echo "Detected DC offset: ($dc_re_sig) + 1j*($dc_im_sig)"

dc_re_corr=$(echo "-1*$dc_re_sig" | bc -l)
dc_im_corr=$(echo "-1*$dc_im_sig" | bc -l)

echo "Applying Rx DC correction:"
echo "	--dre $dc_re_corr"
echo "	--dim $dc_im_corr"

/bin/bash    $cmd_dir/imb2qec_apply.sh -p rx -a $rx_ant    --dre $dc_re_corr --dim $dc_im_corr   -s  # > /dev/null
sleep 0.01


#echo QEC Close Loop RX DC Offset Calibration Done
