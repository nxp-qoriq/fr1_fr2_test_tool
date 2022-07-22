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
echo "usage ./kernels_disable_tx.sh [ant_id] [kernel_name]"
echo "  Disable the specified kernel, all other kernels will remain in previous state. if -r is speicified, enable the kernel."
echo "  ant_id: 		0-5, antenna ID. if not specified, ant 0 will be used"
echo "  kernel_name: 	can be one of the followign names, required:"
echo "    2xup1: if disabled, 2x upsampling stage 1 will be replaced by 2x duplicate, each sample duplicated to 2 samples"
echo "    2xup2: if disabled, 2x upsampling stage 2 will be replaced by 2x duplicate, each sample duplicated to 2 samples"
echo "    4xup:  if disabled, 4x upsampling will be replaced by 4x duplicate, each sample duplicated to 4 samples"
echo "    dpd:   if disabled, DPD will be in pass through mode"
echo "    qec:   if disabled, QEC will be in pass through mode"
echo "    cfr :  if disabled, All CFR PASS will be in pass through mode"
echo "    -r:    reverse operation which means to enable the kernel"
echo "  Example: ./kernels_disable_tx.sh 0 2xup2  	will disable the 2nd 2x up sampling for antenna 0"
echo "  Example: ./kernels_disable_tx.sh 0 cfr -r  	will enable CFR"
echo 
}

source ./check_dfe_cap_core_map.sh

ant=0
kernel_name=0
reverse=0
arg_parse()
{
	if [ $1 = 2xup2 ]; then			kernel_name=2xup2
	elif [ $1 = 2xup1 ]; then		kernel_name=2xup1
	elif [ $1 = 4xup ]; then		kernel_name=4xup
	elif [ $1 = cfr ]; then			kernel_name=cfr
	elif [ $1 = dpd ]; then			kernel_name=dpd
	elif [ $1 = qec ]; then			kernel_name=qec
	elif [ $1 = 0 ]; then			ant=0
	elif [ $1 = 1 ]; then			ant=1
	elif [ $1 = 2 ]; then			ant=2
	elif [ $1 = 3 ]; then			ant=3
	elif [ $1 = 4 ]; then			ant=4
	elif [ $1 = 5 ]; then			ant=5
	elif [ $1 = -r ]; then			reverse=1
	else							echo Argument $1 undefined; print_usage; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done

if [ $((vspa_image_version)) -lt $((0x425)) ];then 
echo -e "***ERROR: The script is not supported in VSPA image version earlier than V4.2.4.\n"; exit 1
fi

enabled=(DISABLED ENABLED)

if [ $kernel_name = 2xup2 ]; then		./update_filter_coeff.sh $ant 2xup2 dis
elif [ $kernel_name = 2xup1 ]; then		./update_filter_coeff.sh $ant 2xup1 dis
elif [ $kernel_name = 4xup ]; then		./update_filter_coeff.sh $ant 4xup dis
elif [ $kernel_name = cfr ]; then		
	check_ant_enable_tx $ant
	txcore=${anttx[$ant]}
	
	if ([ $((tx_fdd|rx_fdd)) -ne 0 ] && [ $((num_T_LS_enabled*num_R_LS_enabled)) -ne 0 ] && ([ $num_T_LS_enabled -gt 2 ] || [ $num_R_LS_enabled -gt 2 ]) && [ $reverse = 1 ] && [ $option8 = 0 ]);then
		echo -e "***WARNING: When CFR is enabled, only 2T2R/4T0R/0T4R are supported for FDD in option7-2 mode. Enabling CFR with more than 2T2R will cause errors.\n            Suggestion is to run 4T4R in option8 FDD mode.\n"
	fi

	set_flag16_to_vspa $txcore $KERNELS_DISABLE $KERNELS_DISABLE_BITMASK_CFR $((0xFFFFFFFF*(1-reverse))) #./update_cfr_para.sh $ant dis
	echo -e "CFR ${enabled[reverse]} on ant $ant\n"
	
elif [ $kernel_name = dpd ]; then		./update_dpd_coeff.sh $ant dis
elif [ $kernel_name = qec ]; then		./update_qec_coeff_tx.sh $ant dis
else									echo -e "***ERROR: Kernel name not specified, command failed.\n"; exit 1
fi

check_error_ant $ant
