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

#usage: ./view_tbgen_phytimer.sh [reset|sync]
#	reset:	reset TBGEN and then view the register values, for LA12xx device only
#	sync:	check external SYNC, for LA12xx device only

modembase_phy=0xa048000000   #manually set the modem ccsr base.  if this script is used in fr1 fr2 rest tool directory, this value will be automatically updated.

if [ -f ./config.dat ];then
	use_with_test_tool=1; source ./config.dat; source ./rfg_ctrl.sh; echo Script runing with test tool, modem ccsr base updated to $modembase_phy
else
	use_with_test_tool=0
	read -p "Modem CCSR BASE is set to $modembase_phy, Press ENTER to continue or input new CCSR BASE: " yesno
	[ "$yesno" != "" ] && modembase_phy=$yesno
	echo modem ccsr base manually set to $modembase_phy
fi

if [ $vspa_dev_type = LA9310 ];then
	phytimer_base=$((modembase_phy+0x1020000))
	tx_allowed_reg_value=`./utils/memrw r 32 $((phytimer_base+0x5c))`
	rx0_allowed_reg_value=`./utils/memrw r 32 $((phytimer_base+0x0c))`
	rx1_allowed_reg_value=`./utils/memrw r 32 $((phytimer_base+0x14))`
	rx2_allowed_reg_value=`./utils/memrw r 32 $((phytimer_base+0x1c))`
	rx3_allowed_reg_value=`./utils/memrw r 32 $((phytimer_base+0x24))`
	highlow=("LOW " HIGH)
	((tx_high=tx_allowed_reg_value>>31))
	((rx0_high=rx0_allowed_reg_value>>31))
	((rx1_high=rx1_allowed_reg_value>>31))
	((rx2_high=rx2_allowed_reg_value>>31))
	((rx3_high=rx3_allowed_reg_value>>31))
	echo "TX  ALLOWED: ${highlow[tx_high]}, reg_value=$tx_allowed_reg_value"
	echo "RX0 ALLOWED: ${highlow[rx0_high]}, reg_value=$rx0_allowed_reg_value"
	echo "RX1 ALLOWED: ${highlow[rx1_high]}, reg_value=$rx1_allowed_reg_value"
	echo "RX2 ALLOWED: ${highlow[rx2_high]}, reg_value=$rx2_allowed_reg_value"
	echo "RX3 ALLOWED: ${highlow[rx3_high]}, reg_value=$rx3_allowed_reg_value"
	[ $((tx_high+rx0_high+rx1_high+rx2_high+rx3_high)) -eq 0 ] && echo -e "***WARNING: tx_allowed and all rx_allowed signals are LOW\n"
	exit 0
fi

tbgen_base=($((modembase_phy+0x1120000)) $((modembase_phy+0x1124000)))

tbgen_master_counter_read()
{
	echo tbgen1 master counter $(printf 0x%x `./utils/memrw r 32 $((tbgen_base[0]+0x6F0))`)$(printf %08x `./utils/memrw r 32 $((tbgen_base[0]+0x6F4))`)
	echo tbgen2 master counter $(printf 0x%x `./utils/memrw r 32 $((tbgen_base[1]+0x6F0))`)$(printf %08x `./utils/memrw r 32 $((tbgen_base[1]+0x6F4))`)
}

tbgen_reg_read()  #$1:0 or 1 for tbgen0/1
{
	for ((i=0;i<0x30;i+=4))
	do
		echo `printf %08x $((tbgen_base[$1]+i))`: $(printf %08x `./utils/memrw r 32 $((tbgen_base[$1]+i))`)
	done
}

if [ $# -ge 1 ] && [ $1 = reset ];then
./utils/memrw w 32 $((tbgen_base[0]+8)) 1
./utils/memrw w 32 $((tbgen_base[1]+8)) 1
fi
tbgen_master_counter_read
echo TBGEN1 REGISTERS:
tbgen_reg_read 0
echo TBGEN2 REGISTERS:
tbgen_reg_read 1

sleep 1

tbgen_master_counter_read
echo TBGEN1 REGISTERS:
tbgen_reg_read 0
echo TBGEN2 REGISTERS:
tbgen_reg_read 1

#get counter of vspa clock,tbgen master clock, API get_counter vspa|tbgen1|tbgen2 [vspa_core_id]
get_counter()
{
	if [ $1 = vspa ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + $2*0x4000 + 0x98 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
		tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
		tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
		if [ $((tmr_msb&0x80000000)) -eq 0 ];then
			./utils/memrw w 32 $tmr_msb_addr 0x80000000
			./utils/memrw w 32 $tmr_lsb_addr 0 #if timer not enabled, enable it
			tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
			tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
			[ $((tmr_msb&0x80000000)) -eq 0 ] && { echo ***ERROR: VSPA core $2 cycle count timer enabling failed.; exit 1; }
		fi
		tmr_msb=$((tmr_msb&0xFFFF))
	elif [ $1 = tbgen1 ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + 0x1206F0 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
		tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
		tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
	elif [ $1 = tbgen2 ]; then 
		tmr_msb_addr=$(( modembase_phy + 0x01000000 + 0x1246F0 ))
		tmr_lsb_addr=$(( tmr_msb_addr + 4 ))
		tmr_msb=`./utils/memrw r 32 $tmr_msb_addr`
		tmr_lsb=`./utils/memrw r 32 $tmr_lsb_addr`
	else
		echo get_counter: Unsupported counter type $1; exit 1; 
	fi
	
	echo $(( (tmr_msb<<32) + tmr_lsb ))
}

#measure tbgen clocks using vspa core clock. API measure_tbgen_clock_start/end vspa_core_id, call start first, after at least 1s, call end. result will be in tbgen1/2_freq
measure_tbgen_clock_start()
{
	vspa_core=$1
	vspa_tmr1=$(get_counter vspa $vspa_core)
	tbgen1_cnt1=$(get_counter tbgen1)
	tbgen2_cnt1=$(get_counter tbgen2)
}
measure_tbgen_clock_end()
{
	vspa_core=$1
	vspa_tmr2=$(get_counter vspa $vspa_core)
	tbgen1_cnt2=$(get_counter tbgen1)
	tbgen2_cnt2=$(get_counter tbgen2)
	
	vspa_tmr_inc=$((vspa_tmr2-vspa_tmr1))
	[ $vspa_tmr_inc = 0 ] && { echo ***ERROR: vspa core $vspa_core cycle counter is not enabled, failed to measure tbgen clock.; channels_start_fail; }
	vspa_tmr_inc_30720=$((vspa_tmr_inc/20))  #vspa cycle clock is 614.4Mhz, convert it to 30.72Mhz
	tbgen1_cnt_inc=$((tbgen1_cnt2-tbgen1_cnt1))
	tbgen2_cnt_inc=$((tbgen2_cnt2-tbgen2_cnt1))
	tbgen1_freq=$(((tbgen1_cnt_inc+vspa_tmr_inc_30720/2)/vspa_tmr_inc_30720*30720000))
	tbgen2_freq=$(((tbgen2_cnt_inc+vspa_tmr_inc_30720/2)/vspa_tmr_inc_30720*30720000))
}

measure_tbgen_clock_start 0
sleep 1
measure_tbgen_clock_end 0
echo -e "Measured TBGEN1 TBGEN2 frequencies: $tbgen1_freq $tbgen2_freq\n"

if ([ $# -lt 1 ] || [ $1 != sync ] || [ $use_with_test_tool = 0 ]);then 
	exit
fi

echo Starting RFG for LS...; start_rfg "LS"
echo Starting RFG for HS...; start_rfg "HS"

tbgen_master_counter_read
echo TBGEN1 REGISTERS:
tbgen_reg_read 0
echo TBGEN2 REGISTERS:
tbgen_reg_read 1

echo Waiting for SYNC on HS...; wait_for_pps "HS";
[ $? -ne 0 ] && echo ***WARNING: Waiting for SYNC on HS failed.
echo Waiting for SYNC on LS...; wait_for_pps "LS";
[ $? -ne 0 ] && echo ***WARNING: Waiting for SYNC on LS failed.

tbgen_master_counter_read
echo TBGEN1 REGISTERS:
tbgen_reg_read 0
echo TBGEN2 REGISTERS:
tbgen_reg_read 1
