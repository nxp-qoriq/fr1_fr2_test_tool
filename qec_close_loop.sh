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

# usage ./qec_closeloop.sh   tx_ant     rx_ant    [bb_dc]
# bb_dc(baseband dc offset) : optional
#                             1=enable Baseband DC correction  , default
#                             0=disable Baseband DC correction

source ./check_dfe_cap_core_map.sh
source qec_init.cfg
bb_dc=1		# enable Baseband DC correction

echo "*************************************************"
echo "* Close Loop QEC Calibration Version v$VERSION  *"
echo "*************************************************"
echo
if [ $# -lt 2 ];then
	echo Wrong arguments
	#print_usage
	echo
	exit
else
	((tx_ant=$1%6))
	((rx_ant=$2%6))
	[ $# -eq 3  ] &&  ((bb_dc=$3%6))
fi

if [[ ! -d $cmd_dir ]]; then
	echo  folder $cmd_dir is not existing
#	mkdir $cmd_dir
fi

function wait_here() 
{
	printf "Press ENTER to continue ...\n"
	read tmp
	echo
} 

find $cmd_dir -type f -name '*.cfg' -delete
echo "deleting previous *.cfg done"
sleep 0.5

echo send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 
./send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 

$cmd_dir/imb2qec_apply.sh -p tx --pt -a $tx_ant  ;
$cmd_dir/imb2qec_apply.sh -p rx --pt -a $rx_ant  ;

#
#if [ "${bb_dc}" -eq 0 ];then
#  $cmd_dir/dc_offset_apply.sh  2  tx  $tx_ant  $( printf "%x" "$( printf "%.0f" 0)" )   $( printf "%x" "$( printf "%.0f" 0)" )     > /dev/null
#fi 

# Perform Rx QEC
echo
time $cmd_dir/rx_qec_cl.sh   $tx_ant    $rx_ant
echo  rx_qec_cl.sh done
#wait_here


if [ "${bb_dc}" -eq 1 ];then
  # Perform RX DC offset correction
  $cmd_dir/rx_dc_offset_cl.sh     $tx_ant   $rx_ant
  echo  rx_dc_offset_cl.sh done

  # Perform Baseband DC offset correction
  echo
  time $cmd_dir/tx_dc_offset_cl.sh     $tx_ant   $rx_ant
  if [[ $? == $repeat ]]; then
	echo "re-do TX DC Offset Calibration ..."
	time $cmd_dir/tx_dc_offset_cl.sh      $tx_ant   $rx_ant
  fi
  echo  tx_dc_offset_cl.sh done
  #wait_here
fi

# Perform Tx QEC
echo
time $cmd_dir/tx_qec_cl.sh       $tx_ant   $rx_ant
if [[ $? == $repeat ]]; then
	echo "re-do TX QEC Calibration ..."
	time $cmd_dir/tx_qec_cl.sh       $tx_ant   $rx_ant
fi

echo  tx_qec_cl.sh  done

./send_single_tone.sh  $tx_ant dis
echo  Close Loop QEC Completed !

