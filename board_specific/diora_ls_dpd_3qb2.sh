#!/bin/bash
# Copyright 2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.
#

# For DPD LS closed-loop training
# usage:
# 	./diora_ls_dpd_3qb2.sh <slot> <freq>
#
# Input Parameters:
#	slot	: slot selection
#	freq	: TrxPll frequency = freq*500 Hz
#
# example: ( slot-0 3.5GHz )
# 	./diora_ls_dpd_3qb2.sh 0 7000000

echo 3 >/proc/sys/kernel/printk

[ $# -lt 2 ] && { echo "***ERROR: ./diora_ls_dpd_3qb2.sh <slot> <freq>"; exit 1; }

slot=$1
freq=$2
CFreq=$(( $freq * 500 ))
tx_gain=19
rx_gain=7
bsp_ver=$(grep -o -P '\d+\.\d+' /lib/firmware/bsp_version)

if [ $(echo "$bsp_ver < 3.0" | bc) -eq 1 ]
then
	cmd="gul_refapp"
else
	cmd="gul_cli"
fi

print_preset()
{
echo
echo Initialize RF sequence for DPD closed-loop training...
echo
echo Slot = $slot
echo TRXPLL frequency = $CFreq
echo Tx_gain = $tx_gain
echo Rx_gain = $rx_gain
echo
}

function dio () {
	         gul_cli -c "$@"  >/dev/null 2>&1
		 echo $cmd: $@
		 sleep 0.5
		}

print_preset;		
dio "diora-close"
dio "diora-open 0 0";
dio "diora-version";
dio "diora-setls ${slot}";
dio "diora-resetn 0";
dio "diora-txrxsw 1";
dio "diora-resetn 1";
dio "diora-setpa 3 0";
dio "diora-setdpd 3 0";
dio "diora-setlna 3 0";
dio "diora-txrxsw 1";
dio "diora-txrxsw2 1";

echo Diora load
dio "diora-load";
dio "diora-getsysstatus"

dio "diora-calresistor 8";
dio "diora-calregulator";
dio "diora-setrxbw 11 4 0";
dio "diora-settxbw 3 0 1";
dio "diora-settrxpll 1 ${freq}";
dio "diora-setpath 15 2 0 5 11 3";
dio "diora-setgain 12 1 0 1 ${tx_gain}";
dio "diora-setgain 3 1 0 1 ${rx_gain}";
dio "diora-setactive 1 3";
dio "diora-txrxsw 0";
dio "diora-txrxsw2 0";
dio "diora-setpa 3 1";
dio "diora-setlna 3 0";
dio "diora-setdpd 3 1";
dio "diora-getsysstatus"
dio "diora-accpll ${freq}"
