#!/bin/bash
# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only be used strictly
# in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

# Call dedicated command to apply the DC corrections
# parameters:
# 			$1 : option , 1 - BB Correction ; 2 - IceWings Correction 
# 			$2 : tx or rx
# 			$3 : $tx_ant , tx_ant id
#				$4 : DC real
#				$5 : DC imag
#				$6 : s , save dc correction value into bin. This is for baseband QEC.

# example:
#				./dc_offset_apply.sh  1  tx  $tx_ant   $tx_corr_dc_re   $tx_corr_dc_im   s

source ./check_dfe_cap_core_map.sh
source qec_init.cfg


option=$1	 # 1 - BB Correction ; 2 - IceWings Correction 

tx_ant=$3

if [[ $option == 1 ]]; then
    [ $verbose_en = 1 ] && echo "Using default BB correction"
   	#[ $verbose_en = 1 ] && echo  $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre  $dc_i_tmp  --dim $dc_q_tmp  in  `basename $0` line:${LINENO}
   	if [[ $6 == 's' ]]; then
			$cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre  $4  --dim $5   -s   > /dev/null
		else
			$cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre  $4  --dim $5        > /dev/null
		fi
elif [[ $option == 2 ]]; then
    echo "Using default IceWings correction"

    if ([ ${dcs_enable[0]} == 3 ] && [ $tx_ant == 0 ]); then
        icewings_path=1
    elif ([ ${dcs_enable[1]} == 3 ] && [ $tx_ant == 0 ]); then		#single dcs enabled
        icewings_path=2	
    elif ([ ${dcs_enable[1]} == 3 ] && [ $tx_ant == 1 ]); then		#multiple dcs enabled
        icewings_path=2
    else
        echo "Error: wrong DCS path configuration. No value applied!"
        exit
    fi

    gul_refapp -c "txdc a $icewings_path $4 $5"  > /dev/null

    sleep 0.01
else
    echo "Error: wrong option. No value applied!"
    exit
fi
