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
echo "usage ./kernels_disable_rx.sh [ant_id] [kernel_name] [-r]"
echo "  Disable the specified kernel, all other kernels will be enabled. if -r is speicified, enable the kernel."
echo "  ant_id: 		0-5, antenna ID. if not specified, ant 0 will be used"
echo "  kernel_name: 	can be one of the followign names, required:"
echo "    fft:    if disabled, FFT will be bypassed, freq domain symbol data will be dirty data"
echo "    lpf:    if disabled, low pass filter will be disabled"
echo "    2xdown: if disabled, 2x downsamplng will be replaced by 2x decimation by picking even numbered samples, removing odd numbered samples"
echo "    -r:     reverse operation, meaning to enable kernels."
echo "  Example: ./kernels_disable_rx.sh 0 2xdown  		will disable the 2x down sampling for antenna 0"
echo 
}

source ./check_dfe_cap_core_map.sh

ant=0
kernel_name=0
reverse=0

arg_parse()
{
	if [ $1 = 0 ]; then					ant=0
	elif [ $1 = 1 ]; then				ant=1
	elif [ $1 = 2 ]; then				ant=2
	elif [ $1 = 3 ]; then				ant=3
	elif [ $1 = 4 ]; then				ant=4
	elif [ $1 = 5 ]; then				ant=5
	elif [ $1 = lpf ]; then				kernel_name=lpf
	elif ([ $1 = 2xdown ] || [ $1 = down ]); then			kernel_name=2xdown
	elif [ $1 = fft ]; then				kernel_name=fft
	elif [ $1 = -r ]; then				reverse=1
	else								echo Wrong Argument; print_usage; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done

rxcore=${antrx[ant]}
TAG_ENABLED=("disabled or bypassed" enabled)

if [ $kernel_name = fft ]; then			kernel_disable $rxcore $KERNELS_DISABLE_BITMASK_RX_FFT $((KERNELS_DISABLE_BITMASK_RX_FFT*(1-reverse)))
										echo -e "FFT in core $rxcore for ant $ant is ${TAG_ENABLED[reverse]}.\n"
elif [ $kernel_name = lpf ]; then		kernel_disable $rxcore $KERNELS_DISABLE_BITMASK_RX_LPF $((KERNELS_DISABLE_BITMASK_RX_LPF*(1-reverse)))
										echo -e "Low pass filter in core $rxcore for ant $ant is ${TAG_ENABLED[reverse]}.\n"
elif [ $kernel_name = 2xdown ]; then	kernel_disable $rxcore $KERNELS_DISABLE_BITMASK_DOWNSAMPLING $((KERNELS_DISABLE_BITMASK_DOWNSAMPLING*(1-reverse)))
										echo -e "Down sampling filter in core $rxcore for ant $ant is ${TAG_ENABLED[reverse]}.\n"
else									echo -e "***ERROR: Kernel name not specified, command failed.\n"; exit 1
fi

check_error_ant $ant
