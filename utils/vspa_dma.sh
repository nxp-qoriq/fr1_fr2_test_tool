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

#vspa_dma.sh <core_id> <src_addr> <dst_addr> <size> [dma_chan] [conv]
#src_addr and dst_addr must be: one on VSPA DMEM(addr range 0-DMEM size in vspa view), another is not on VSPA DMEM(in LA side view).
#size must be no more than 65536
#dma_chan: 0-15 for LA93xx, 0-31 for LA12xx. 
#conv: enable DMA to convert from half fix to 2's complement or vise versa.

source ./check_dfe_cap_core_map.sh

[ $# -lt 4 ] && { echo -e "***ERROR: Wrong arguments. usage: ./vspa_dma.sh <core_id> <src_addr> <dst_addr> <size> [dma_chan] [conv]\n"; exit 1; }
core_id=$(($1)); src=$(($2)); dst=$(($3)); size=$(($4))
[ $core_id -ge $NUM_CORES ] && { echo -e "***ERROR: Wrong core_id. core_id must be smaller than $NUM_CORES\n"; exit 1; }
[ $size -gt 65536 ] && { echo -e "***ERROR: Wrong size. size must be no more than 65536\n"; exit 1; }
if ([ $src -gt $((VCPUDMEM_SIZE+IPPUDMEM_SIZE)) ] && [ $dst -lt $((VCPUDMEM_SIZE+IPPUDMEM_SIZE)) ]);then
	dma_mode=0x080
	axi_addr=$src
	dmem_addr=$dst
elif ([ $src -lt $((VCPUDMEM_SIZE+IPPUDMEM_SIZE)) ] && [ $dst -gt $((VCPUDMEM_SIZE+IPPUDMEM_SIZE)) ]);then
	dma_mode=0x600
	axi_addr=$dst
	dmem_addr=$src
else
	echo -e "***ERROR: Wrong src and dst addr. one addr must be on VSPA DMEM, the other must be not on VSPA DMEM\n"; exit 1;
fi

dma_chan=15  #using chan 15 by default
conv=0

if [ $# -ge 5 ];then
	arg=$5
	[ ${arg:0:4} = conv ] && conv=1 || dma_chan=$((arg))
fi
if [ $# -ge 6 ];then
	arg=$6
	[ ${arg:0:4} = conv ] && conv=1 || dma_chan=$((arg))
fi

#mem_addr_check_host_view $axi_addr $size

dma_mode=$((dma_mode+(conv*0x100)+dma_chan)) #VCPU GO set
./utils/memrw w 32 $((modembase_phy+0x1000000+$core_id*0x4000+0xB0)) $dmem_addr
#./utils/memrw w 32 $((modembase_phy+0x1000000+$core_id*0x4000+0xB4)) `vir2phy $axi_addr`
./utils/memrw w 32 $((modembase_phy+0x1000000+$core_id*0x4000+0xB4)) $axi_addr
./utils/memrw w 32 $((modembase_phy+0x1000000+$core_id*0x4000+0xB8)) $size
./utils/memrw w 32 $((modembase_phy+0x1000000+$core_id*0x4000+0xBC)) $dma_mode
echo -e "VSPA DMA command finished: DMEM_ADDR(VSPA view)=`HEX $dmem_addr`, AXI_ADDR(VSPA view)=`HEX $axi_addr`, SIZE=$size, MODE=`HEX $dma_mode`, Channel=$dma_chan\n"
check_error
