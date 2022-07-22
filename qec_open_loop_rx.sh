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

function wait_here() 
{
	printf "Press ENTER to continue ...\n"
	read tmp
	echo
}
[ $# -lt 2 ] && { echo "***ERROR: ./qec_open_loop_rx.sh <tx_ant_id> <rx_ant_id>"; exit 1; }
tx_ant_id=$(($1%6))
rx_ant_id=$(($2%6))

cmd_dir=($PWD/qec)

source ./check_dfe_cap_core_map.sh

check_ant_enable_rx $rx_ant_id

rxcore=${antrx[$rx_ant_id]}
get_chan_para $rx_ant_id $rxcore
feedback_sps=$rxaxiq
#echo feedback_sps=$feedback_sps

rx_dump_size=1
rx_dump_file_size=32

rx_file=rx_timedomain_$rx_dump_file_size\KB_$feedback_sps\ksps_dump_ant$rx_ant_id.bin
echo Calulate IQ imbalance ...
./dump_time_domain_rx.sh $rx_ant_id $rx_dump_size > /dev/null 2>&1
x=`python3 utils/iq_imb.py -i $rx_file`
list=($(echo $x | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$'))
phase_error=${list[0]}
gain_error=${list[1]}
#echo "phase_error=$phase_error; gain_error=$gain_error" > $cmd_dir/qec_rx_ant$rx_ant_id.txt
declare -p gain_error phase_error >> qec/qec_rx_ant${rx_ant_id}.cfg
echo Phase_error = $phase_error
echo Gain_error = $gain_error
echo ./update_qec_coeff_rx.sh $rx_ant_id imb=$gain_error:$phase_error
./update_qec_coeff_rx.sh $rx_ant_id imb=$gain_error:$phase_error
cp ./qec/qec_coeff_rx_ant$rx_ant_id.bin ./qec/qec_open_loop_coeff_rx_ant$rx_ant_id.bin
