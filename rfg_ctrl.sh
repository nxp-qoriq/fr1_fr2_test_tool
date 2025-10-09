#!/bin/bash
# Copyright 2022-2025 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

TBGEN_CCSR_OFFSET=0
TBGEN_FREQ=0
# TBGEN registers
TBGEN_BASE=0
TBGEN_REG_CNTRL0=0
TBGEN_REG_TS10MSHI=0
TBGEN_REG_TS10MSLO=0
TBGEN_REG_TDD0_CTRL=0
TBGEN_REG_TDD2_CTRL=0
TBGEN_RFG_REG_CTRL=0
TBGEN_RFG_REG_REFCLKS_PER_10MS=0
TBGEN_REG_MSTRCNTLO=0
TBGEN_REG_MSTRCNTHI=0

set_tbgen_ccsr_offset()
{
    if [[ "$1" == "LS" ]];then
        TBGEN_CCSR_OFFSET=0x1120000
    elif [[ "$1" == "HS" ]];then
        TBGEN_CCSR_OFFSET=0x1124000
    fi
    # TBGEN registers
    TBGEN_BASE=$((modembase_phy + TBGEN_CCSR_OFFSET))
    TBGEN_REG_CNTRL0=$((TBGEN_BASE + 0x8))
    TBGEN_REG_TS10MSHI=$((TBGEN_BASE + 0x1c))
    TBGEN_REG_TS10MSLO=$((TBGEN_BASE + 0x20))
    TBGEN_REG_TDD0_CTRL=$((TBGEN_BASE + 0x450))
    TBGEN_REG_TDD2_CTRL=$((TBGEN_BASE + 0x4F0))
    TBGEN_RFG_REG_CTRL=$((TBGEN_BASE + 0x0))
    TBGEN_RFG_REG_REFCLKS_PER_10MS=$((TBGEN_BASE + 0x2C))
    TBGEN_REG_MSTRCNTHI=$((TBGEN_BASE + 0x6F0))
    TBGEN_REG_MSTRCNTLO=$((TBGEN_BASE + 0x6F4))
}

wait_for_pps()
{
	if [[ "$1" == "LS" ]];then
		set_tbgen_ccsr_offset "LS"
	elif [[ "$1" == "HS" ]];then
		set_tbgen_ccsr_offset "HS"
	fi

	local TS10MSLO=$(./utils/memrw r 32 $TBGEN_REG_TS10MSLO)
	sleep 2
	local TS10MSLO_comp=$(./utils/memrw r 32 $TBGEN_REG_TS10MSLO)

	if [ $((TS10MSLO_comp)) -eq $((TS10MSLO)) ];then
		return 1
	else
		return 0
	fi
}

wait_till_tbgen_tick()
{
	if [[ "$1" == "LS" ]];then
		set_tbgen_ccsr_offset "LS"
	elif [[ "$1" == "HS" ]];then
		set_tbgen_ccsr_offset "HS"
	fi

	local MSTRCNTHI=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTHI)
	local MSTRCNTLO=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTLO)
	MCTR=$(((MSTRCNTHI << 32) | MSTRCNTLO))

	if [[ $2 -gt $MCTR ]]; then
		while [ $2 -gt $MCTR ]; do
			MSTRCNTHI=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTHI)
			MSTRCNTLO=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTLO)
			MCTR=$(((MSTRCNTHI << 32) | MSTRCNTLO))
		done
	else
		echo Current: $MCTR Target: $2
		echo "Target already passed. Fix tbgen_init_time"
	fi
}

# start reference tngem output
# $1 LS or HS
start_rfg()
{
    set_tbgen_ccsr_offset $@
    if [[ "$1" == "LS" ]];then
	TBGEN_FREQ=$tbgen1_freq
    elif [[ "$1" == "HS" ]];then
	TBGEN_FREQ=$tbgen2_freq
    fi
	
    ./utils/memrw w 32 $TBGEN_RFG_REG_REFCLKS_PER_10MS $(($TBGEN_FREQ / 100))
	
    # Radio Frame Generator output is used as the source for the 10ms Frame SYNC signal
    local rfgcr=$(./utils/memrw r 32 $TBGEN_RFG_REG_CTRL)
    rfgcr=$((rfgcr & ~0x4))
    rfgcr=$((rfgcr | 0x40003))
    ./utils/memrw w 32 $TBGEN_RFG_REG_CTRL $rfgcr
    rfgcr=$((rfgcr & ~0x2))
    sleep 1
    ./utils/memrw w 32 $TBGEN_RFG_REG_CTRL $rfgcr
}

# stop reference tngem output
# $1 LS or HS
stop_rfg()
{
    set_tbgen_ccsr_offset $@
    local rfgcr=$(./utils/memrw r 32 $TBGEN_RFG_REG_CTRL)
    rfgcr=$((rfgcr | 0x4))
    rfgcr=$((rfgcr & ~0x3))
    ./utils/memrw w 32 $TBGEN_RFG_REG_CTRL $rfgcr
}

get_tdd_ctrl()
{
    set_tbgen_ccsr_offset $1
    local val=$2
    echo $((TBGEN_REG_TDD0_CTRL + $(( 0x50 * val)) ))
}

get_tdd1_ctrl()
{
    set_tbgen_ccsr_offset $1
    local val=$2
    echo $((TBGEN_REG_TDD1_CTRL + $(( 0x50 * val)) ))
}

get_tbgen_mode()
{
    case $1 in
        "rx")
            echo 1
            ;;
        "tx")
            echo 2
            ;;
        "trx")
            echo 3
            ;;
    esac
}

# get current tbgen counter value
# $1 LS or HS
get_tbgen_counter()
{
    set_tbgen_ccsr_offset $1
    local ts10mshi=$(./utils/memrw r 32 $TBGEN_REG_TS10MSHI)
    local ts10mslo=$(./utils/memrw r 32 $TBGEN_REG_TS10MSLO)
    local ts10ms=$(( $((ts10mshi << 32)) | ts10mslo ))
    echo $ts10ms
}
get_tbgen_master_counter()
{
    set_tbgen_ccsr_offset $1
    local ts10mshi=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTHI)
    local ts10mslo=$(./utils/memrw r 32 $TBGEN_REG_MSTRCNTLO)
    local ts10ms=$(( $((ts10mshi << 32)) | ts10mslo ))
    echo $ts10ms
}

# antenna specific trigger configurations
# $1 LS or HS
# $2 antenna index
# $3 tbgen mode (tx, rx, trx)
# $4 offset value to set
set_tbgen_offset()
{
    set_tbgen_ccsr_offset $1
    local tdd_REG_CTRL=$(get_tdd_ctrl $1 $2)
    local tdd_REG_OSETHI=$((tdd_REG_CTRL + 4))
    local tdd_REG_OSETLO=$((tdd_REG_CTRL + 8))
    local tdd_REG_MODE=$((tdd_REG_CTRL + 0xC))
    local tdd_REG_DURATION=$((tdd_REG_CTRL + 0x10))

    ./utils/memrw w 32 $tdd_REG_DURATION 0x0

    local tbgen_mode=$(get_tbgen_mode $3)
    ./utils/memrw w 32 $tdd_REG_MODE $tbgen_mode

    offset=$4
    ./utils/memrw w 32 $tdd_REG_OSETHI $((offset >> 32))
    ./utils/memrw w 32 $tdd_REG_OSETLO $((offset & 0xffffffff))

    ./utils/memrw w 32 $tdd_REG_CTRL 0x3
}

get_pulse_length()
{
	local pulse_divider=$(($hsadc_sps / $tbgen2_freq))
	local pulse_length=$(($OBS_PULSE_LEN / $pulse_divider))
	echo $pulse_length
}

# antenna specific trigger configurations
# $1 ADC index
# $2 offset value to set
enable_dpd_hsadc()
{
    set_tbgen_ccsr_offset "HS"
    local tdd_REG_CTRL=$(get_tdd_ctrl "HS" $1)
    local tdd_REG_OSETHI=$((tdd_REG_CTRL + 4))
    local tdd_REG_OSETLO=$((tdd_REG_CTRL + 8))

    local tdd_REG_MODE=$((tdd_REG_CTRL + 0xC))

    local tdd_REG_DURATION0=$((tdd_REG_CTRL + 0x10))
    local tdd_REG_DURATION1=$((tdd_REG_CTRL + 0x14))

	high_pusle_len=$(get_pulse_length)		 #set number of tbgen clocks for 8K samples
    ./utils/memrw w 32 $tdd_REG_DURATION0 $high_pusle_len
    ./utils/memrw w 32 $tdd_REG_DURATION1 $((($tbgen2_freq * OBS_PULSE_PERIOD / 1000) - high_pusle_len))		#Idle period = (10 sec - high_pulse_length)
    echo ./utils/memrw w 32 $tdd_REG_DURATION0 $high_pusle_len
    echo ./utils/memrw w 32 $tdd_REG_DURATION1 $((($tbgen2_freq * OBS_PULSE_PERIOD / 1000) - high_pusle_len))		#Idle period = (10 sec - high_pulse_length)

    local tbgen_mode=$(get_tbgen_mode "rx")
    ./utils/memrw w 32 $tdd_REG_MODE $tbgen_mode

    offset=$2
    ./utils/memrw w 32 $tdd_REG_OSETHI $((offset >> 32))
    ./utils/memrw w 32 $tdd_REG_OSETLO $((offset & 0xffffffff))

    ./utils/memrw w 32 $tdd_REG_CTRL 0x13
    echo 'configured hsadc'
}

put_hsadc_in_low_power_mode()
{
	tdd_REG_CTRL=`printf 0x%x $(get_tdd_ctrl "HS" 2)`
	./utils/memrw w 32 $tdd_REG_CTRL 0x100
	echo Put HSADC0 in low-power mode, ./utils/memrw w 32 $tdd_REG_CTRL 0x100

	tdd_REG_CTRL=`printf 0x%x $(get_tdd_ctrl "HS" 3)`
	./utils/memrw w 32 $tdd_REG_CTRL 0x100
	echo Put HSADC1 in low-power mode, ./utils/memrw w 32 $tdd_REG_CTRL 0x100
}

get_hsadc_outof_low_power_mode()
{
	tdd_REG_CTRL=`printf 0x%x $(get_tdd_ctrl "HS" 2)`
	echo Bring HSADC0 out of low power mode, ./utils/memrw w 32 $tdd_REG_CTRL 0x0
	./utils/memrw w 32 $tdd_REG_CTRL 0x0

	tdd_REG_CTRL=`printf 0x%x $(get_tdd_ctrl "HS" 3)`
	echo Bring HSADC1 out of low power mode, ./utils/memrw w 32 $tdd_REG_CTRL 0x0
	./utils/memrw w 32 $tdd_REG_CTRL 0x0
}
