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

source ./config.dat

chan=0
txrx=0; tagtxrx=(TX RX)
addr=0
mask=0
arg_parse()
{
	arg=$1
	if 		[ $1 = 0 ]; 	then		chan=0
	elif 	[ $1 = 1 ]; 	then		chan=1
	elif 	[ $1 = 2 ]; 	then		chan=2
	elif 	[ $1 = 3 ]; 	then		chan=3
	elif 	[ $1 = 4 ]; 	then		chan=4
	elif 	[ $1 = 5 ]; 	then		chan=5
	elif 	[ $1 = tx ]; 	then		txrx=0
	elif 	[ $1 = rx ]; 	then		txrx=1
	elif 	[ $1 = rxhshake ];	then		addr=`printf 0x%x $((modembase_phy+0x1000000+0x18))`; mask=0x0FFFFFFF
	elif 	[ $1 = imbox0 ];	then		addr=`printf 0x%x $((modembase_phy+0x1000000+0x650))`; mask=0xFFFFFFFF
	elif 	[ $1 = imbox1 ];	then		addr=`printf 0x%x $((modembase_phy+0x1000000+0x658))`; mask=0xFFFFFFFF
	elif 	[ ${arg:0:5} = addr= ];	then		addr=${arg:5}
	elif 	[ ${arg:0:5} = mask= ];	then		mask=${arg:5}
	else	echo ***ERROR: Wrong channel $1; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done


if [ $mask = 0 ];then
	if [ $vspa_dev_type = LA9310 ];then
		if [ $txrx = 0 ];then
			txrx_allowed_addr=$((modembase_phy+0x102005c))    #PHYtimer register 11
		else
			txrx_allowed_addr=$((modembase_phy+0x102000c+8*chan))    #PHYtimer register
		fi
		txrx_allowed_bitmask=0x80000000
	else
		if [ $chan = 0 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+0x500+(9-txrx)*4))    #GPI9 bit 2
			txrx_allowed_bitmask=0x4
		elif [ $chan = 1 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+0x500+(9-txrx)*4))    #GPI9 bit 2
			txrx_allowed_bitmask=0x400
		elif [ $chan = 2 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+0x500+(12-txrx)*4))    #GPI9 bit 2
			txrx_allowed_bitmask=0x4
		elif [ $chan = 3 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+0x500+(12-txrx)*4))    #GPI9 bit 2
			txrx_allowed_bitmask=0x400
		elif [ $chan = 4 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+4*0x4000+0x500+15*4))    #GPI9 bit 2
			txrx_allowed_bitmask=$((1<<(10-txrx*8)))
		elif [ $chan = 5 ];then
			txrx_allowed_addr=$((modembase_phy+0x1000000+4*0x4000+0x500+15*4))    #GPI9 bit 2
			txrx_allowed_bitmask=$((1<<(26-txrx*8)))
		else
			echo ***ERROR: Wrong TX channel $chan; exit 1;
		fi
	fi
	txrx_allowed_addr=`printf 0x%x $txrx_allowed_addr`
	echo Measuring ${tagtxrx[txrx]}_allowed signal length for channel $chan
	addr=$txrx_allowed_addr; mask=$txrx_allowed_bitmask
else
	echo Measuring value change on address $addr with bit mask $mask
fi

vspa_ccnt_msb_addr=`printf 0x%x $((modembase_phy+0x1000000+0x98))`
[ $vspa_dev_type = LA9310 ] && vspa_core_clock_rate=491520000 || vspa_core_clock_rate=614400000

echo ./utils/mea_sig_len $addr $mask $vspa_ccnt_msb_addr $vspa_core_clock_rate
./utils/mea_sig_len $addr $mask $vspa_ccnt_msb_addr $vspa_core_clock_rate
