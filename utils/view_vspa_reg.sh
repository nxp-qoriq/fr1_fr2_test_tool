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

show_bits() #$1=32 bit value, $2=start bit idx, $3=num bits 
{
	echo $((($1>>$2)&(0xFFFFFFFF>>(32-$3))))
}

if ([ $# -ne 3 ] && [ $# -ne 2 ]);then
echo "usage ./view_vspa_reg <core_id> <start_addr|module_name> [size]"
echo core_id: 0,1,2,3,4,5,6,7
echo start_addr: start address of the reg 0-0x3FFC.
echo module_name: name of modules such as dma
echo size:  size in bytes
echo
exit
fi

size=16

if [ $# -eq 3 ];then
size=$(($3)); [ $size -gt 128 ] && { echo -e "***ERROR: size too large, should be no more than 128\n"; exit 1; }
fi

((core_id=$1%8))

start_addr=$2; module_name=""

if [ $2 = swver ]; then			start_addr=4
elif [ $2 = hsstat ]; then		start_addr=0x53c
elif [ $2 = dma ]; then			start_addr=0xb0; size=48; module_name=dma
elif [ $2 = axiq ]; then		start_addr=0x500; size=64; module_name=axiq
fi

while [ $((1)) ]
do

((start_addr_host=modembase_phy+0x1000000+$core_id*0x4000+$start_addr))
((end_addr_host=start_addr_host+size-1))
start_addr_host=`printf 0x%x $start_addr_host`
end_addr_host=`printf 0x%x $end_addr_host`
echo start_addr_host = $start_addr_host, end_addr_host=$end_addr_host

echo ./utils/loadmem null $start_addr_host -r $size
./utils/loadmem null $start_addr_host -r $size

if [ "$module_name" = dma ];then
	echo "DMA_STAT:     "`./utils/memrw r 32 $((start_addr_host+0x10))`
	echo "DMA_IRQSTAT:  "`./utils/memrw r 32 $((start_addr_host+0x14))`
	echo "DMA_COMPSTAT: "`./utils/memrw r 32 $((start_addr_host+0x18))`
	echo "DMA_XFRERROR: "`./utils/memrw r 32 $((start_addr_host+0x1c))`
	echo "DMA_CFGERROR: "`./utils/memrw r 32 $((start_addr_host+0x20))`
	echo "DMA_XRUNSTAT: "`./utils/memrw r 32 $((start_addr_host+0x24))`
	echo "DMA_GOSTAT:   "`./utils/memrw r 32 $((start_addr_host+0x28))`
	echo "DMA_FIFOSTAT: "`./utils/memrw r 32 $((start_addr_host+0x2c))`
	exit 0;
elif [ "$module_name" = axiq ];then
	if [ $vspa_dev_type = LA9310 ];then
	gpi0=`./utils/memrw r 32 $((start_addr_host+0x0))`
	gpi1=`./utils/memrw r 32 $((start_addr_host+0x4))`
	gpo4=`./utils/memrw r 32 $((start_addr_host+0x80+4*4))`
	gpo5=`./utils/memrw r 32 $((start_addr_host+0x80+4*5))`
	gpo7=`./utils/memrw r 32 $((start_addr_host+0x80+4*7))`
	./utils/loadmem null $((start_addr_host+0x80)) -r $size #show CONTROL REGS
	
	echo
	echo "TX CHAN CONTROL:"
	echo "TX CHAN   ENABLE:         "`show_bits $gpo7 0 1`
	echo "TX CHAN   FIFO THRESHOLD: "`show_bits $gpo7 1 2`
	echo "TX CHAN   IQSWAP:         "`show_bits $gpo7 3 1`
	echo "TX CHAN   CLR ERROR:      "`show_bits $gpo7 4 1`
	
	echo
	echo "TX CHAN STATUS:"
	echo "TX CHAN   ENABLE:         "`show_bits $gpi1 16 1`
	echo "TX CHAN   FIFO NOT EMPTY: "`show_bits $gpi1 17 1`
	echo "TX CHAN   UNDERFLOW:      "`show_bits $gpi1 18 1`
	echo "TX CHAN   OVERFLOW:       "`show_bits $gpi1 19 1`

	echo 
	echo "RX CHAN CONTROL: 0 1 2 3"
	echo " ENABLE:         "`show_bits $gpo4 $((0*8+0)) 1` `show_bits $gpo4 $((1*8+0)) 1` `show_bits $gpo4 $((2*8+0)) 1` `show_bits $gpo4 $((3*8+0)) 1`
	echo " FIFO THRESHOLD: "`show_bits $gpo4 $((0*8+1)) 2` `show_bits $gpo4 $((1*8+1)) 2` `show_bits $gpo4 $((2*8+1)) 2` `show_bits $gpo4 $((3*8+1)) 2`
	echo " IQSWAP:         "`show_bits $gpo4 $((0*8+3)) 1` `show_bits $gpo4 $((1*8+3)) 1` `show_bits $gpo4 $((2*8+3)) 1` `show_bits $gpo4 $((3*8+3)) 1`
	echo " CLR ERROR:      "`show_bits $gpo4 $((0*8+4)) 1` `show_bits $gpo4 $((1*8+4)) 1` `show_bits $gpo4 $((2*8+4)) 1` `show_bits $gpo4 $((3*8+4)) 1`

	echo
	echo "RX CHAN STATUS:  0 1 2 3"
	echo " ENABLE:         "`show_bits $gpi0 $((0*4+0)) 1` `show_bits $gpi0 $((1*4+0)) 1` `show_bits $gpi0 $((2*4+0)) 1` `show_bits $gpi0 $((3*4+0)) 1`
	echo " FIFO NOT EMPTY: "`show_bits $gpi0 $((0*4+1)) 1` `show_bits $gpi0 $((1*4+1)) 1` `show_bits $gpi0 $((2*4+1)) 1` `show_bits $gpi0 $((3*4+1)) 1`
	echo " UNDERFLOW:      "`show_bits $gpi0 $((0*4+2)) 1` `show_bits $gpi0 $((1*4+2)) 1` `show_bits $gpi0 $((2*4+2)) 1` `show_bits $gpi0 $((3*4+2)) 1`
	echo " OVERFLOW:       "`show_bits $gpi0 $((0*4+3)) 1` `show_bits $gpi0 $((1*4+3)) 1` `show_bits $gpi0 $((2*4+3)) 1` `show_bits $gpi0 $((3*4+3)) 1`
	
	else
	gpi8=`./utils/memrw r 32 $((start_addr_host+4*8))`  #LA12xx RX AXIQ DCS0,1 STATUS
	gpi11=`./utils/memrw r 32 $((start_addr_host+4*11))`  #LA12xx RX AXIQ DCS2,3 STATUS
	gpi15=`./utils/memrw r 32 $((start_addr_host+4*15))`  #LA12xx TX and RX AXIQ DCS4,5 STATUS
	gpi9=`./utils/memrw r 32 $((start_addr_host+4*9))`  #LA12xx TX AXIQ DCS0,1 STATUS
	gpi12=`./utils/memrw r 32 $((start_addr_host+4*12))`  #LA12xx TX AXIQ DCS2,3 STATUS
	
	gpo8=`./utils/memrw r 32 $((start_addr_host+0x80+4*8))`  #LA12xx RX AXIQ DCS0,1 CONTROL
	gpo10=`./utils/memrw r 32 $((start_addr_host+0x80+4*10))`  #LA12xx RX AXIQ DCS2,3 CONTROL
	gpo12=`./utils/memrw r 32 $((start_addr_host+0x80+4*12))`  #LA12xx TX and RX AXIQ DCS4 CONTROL
	gpo13=`./utils/memrw r 32 $((start_addr_host+0x80+4*13))`  #LA12xx TX and RX AXIQ DCS5 CONTROL
	gpo9=`./utils/memrw r 32 $((start_addr_host+0x80+4*9))`  #LA12xx TX AXIQ DCS0,1 CONTROL
	gpo11=`./utils/memrw r 32 $((start_addr_host+0x80+4*11))`  #LA12xx TX AXIQ DCS2,3 CONTROL
	./utils/loadmem null $((start_addr_host+0x80)) -r $size  #show CONTROL REGS
	
	echo 
	echo "TX CHAN CONTROL: 0 1 2 3 4 5"
	echo " ENABLE:         "`show_bits $gpo9 $((0*8+0)) 1` `show_bits $gpo9 $((1*8+0)) 1` `show_bits $gpo11 $((0*8+0)) 1` `show_bits $gpo11 $((1*8+0)) 1` `show_bits $gpo12 16 1` `show_bits $gpo13 16 1`
	echo " FIFO THRESHOLD: "`show_bits $gpo9 $((0*8+1)) 2` `show_bits $gpo9 $((1*8+1)) 2` `show_bits $gpo11 $((0*8+1)) 2` `show_bits $gpo11 $((1*8+1)) 2` `show_bits $gpo12 17 2` `show_bits $gpo13 17 2`
	echo " IQSWAP:         "`show_bits $gpo9 $((0*8+3)) 1` `show_bits $gpo9 $((1*8+3)) 1` `show_bits $gpo11 $((0*8+3)) 1` `show_bits $gpo11 $((1*8+3)) 1` `show_bits $gpo12 19 1` `show_bits $gpo13 19 1`
	echo " CLR ERROR:      "`show_bits $gpo9 $((0*8+4)) 1` `show_bits $gpo9 $((1*8+4)) 1` `show_bits $gpo11 $((0*8+4)) 1` `show_bits $gpo11 $((1*8+4)) 1` `show_bits $gpo12 20 1` `show_bits $gpo13 20 1`
	
	echo
	echo "TX CHAN STATUS:  0 1 2 3 4 5"
	echo " ENABLE:         "`show_bits $gpi9 $((0*8+0)) 1` `show_bits $gpi9 $((1*8+0)) 1` `show_bits $gpi12 $((0*8+0)) 1` `show_bits $gpi12 $((1*8+0)) 1` `show_bits $gpi15 $((1*8+0)) 1` `show_bits $gpi15 $((3*8+0)) 1`
	echo " FIFO NOT EMPTY: "`show_bits $gpi9 $((0*8+1)) 1` `show_bits $gpi9 $((1*8+1)) 1` `show_bits $gpi12 $((0*8+1)) 1` `show_bits $gpi12 $((1*8+1)) 1` `show_bits $gpi15 $((1*8+1)) 1` `show_bits $gpi15 $((3*8+1)) 1`
	echo " TX ALLOWED:     "`show_bits $gpi9 $((0*8+2)) 1` `show_bits $gpi9 $((1*8+2)) 1` `show_bits $gpi12 $((0*8+2)) 1` `show_bits $gpi12 $((1*8+2)) 1` `show_bits $gpi15 $((1*8+2)) 1` `show_bits $gpi15 $((3*8+2)) 1`
	echo " RESET COMPLETE: "`show_bits $gpi9 $((0*8+3)) 1` `show_bits $gpi9 $((1*8+3)) 1` `show_bits $gpi12 $((0*8+3)) 1` `show_bits $gpi12 $((1*8+3)) 1` `show_bits $gpi15 $((1*8+3)) 1` `show_bits $gpi15 $((3*8+3)) 1`
	echo " UNDERFLOW:      "`show_bits $gpi9 $((0*8+4)) 1` `show_bits $gpi9 $((1*8+4)) 1` `show_bits $gpi12 $((0*8+4)) 1` `show_bits $gpi12 $((1*8+4)) 1` `show_bits $gpi15 $((1*8+4)) 1` `show_bits $gpi15 $((3*8+4)) 1`
	echo " OVERFLOW:       "`show_bits $gpi9 $((0*8+5)) 1` `show_bits $gpi9 $((1*8+5)) 1` `show_bits $gpi12 $((0*8+5)) 1` `show_bits $gpi12 $((1*8+5)) 1` `show_bits $gpi15 $((1*8+5)) 1` `show_bits $gpi15 $((3*8+5)) 1`
	echo " RESET ERROR:    "`show_bits $gpi9 $((0*8+6)) 1` `show_bits $gpi9 $((1*8+6)) 1` `show_bits $gpi12 $((0*8+6)) 1` `show_bits $gpi12 $((1*8+6)) 1` `show_bits $gpi15 $((1*8+6)) 1` `show_bits $gpi15 $((3*8+6)) 1`

	echo 
	echo "RX CHAN CONTROL: 0 1 2 3 4 5"
	echo " ENABLE:         "`show_bits $gpo8 $((0*8+0)) 1` `show_bits $gpo8 $((1*8+0)) 1` `show_bits $gpo10 $((0*8+0)) 1` `show_bits $gpo10 $((1*8+0)) 1` `show_bits $gpo12 0 1` `show_bits $gpo13 0 1`
	echo " FIFO THRESHOLD: "`show_bits $gpo8 $((0*8+1)) 2` `show_bits $gpo8 $((1*8+1)) 2` `show_bits $gpo10 $((0*8+1)) 2` `show_bits $gpo10 $((1*8+1)) 2` `show_bits $gpo12 1 2` `show_bits $gpo13 1 2`
	echo " IQSWAP:         "`show_bits $gpo8 $((0*8+3)) 1` `show_bits $gpo8 $((1*8+3)) 1` `show_bits $gpo10 $((0*8+3)) 1` `show_bits $gpo10 $((1*8+3)) 1` `show_bits $gpo12 3 1` `show_bits $gpo13 3 1`
	echo " CLR ERROR:      "`show_bits $gpo8 $((0*8+4)) 1` `show_bits $gpo8 $((1*8+4)) 1` `show_bits $gpo10 $((0*8+4)) 1` `show_bits $gpo10 $((1*8+4)) 1` `show_bits $gpo12 4 1` `show_bits $gpo13 4 1`

	echo
	echo "RX CHAN STATUS:  0 1 2 3 4 5"
	echo " ENABLE:         "`show_bits $gpi8 $((0*8+0)) 1` `show_bits $gpi8 $((1*8+0)) 1` `show_bits $gpi11 $((0*8+0)) 1` `show_bits $gpi11 $((1*8+0)) 1` `show_bits $gpi15 $((0*8+0)) 1` `show_bits $gpi15 $((2*8+0)) 1`
	echo " FIFO NOT EMPTY: "`show_bits $gpi8 $((0*8+1)) 1` `show_bits $gpi8 $((1*8+1)) 1` `show_bits $gpi11 $((0*8+1)) 1` `show_bits $gpi11 $((1*8+1)) 1` `show_bits $gpi15 $((0*8+1)) 1` `show_bits $gpi15 $((2*8+1)) 1`
	echo " RX ALLOWED:     "`show_bits $gpi8 $((0*8+2)) 1` `show_bits $gpi8 $((1*8+2)) 1` `show_bits $gpi11 $((0*8+2)) 1` `show_bits $gpi11 $((1*8+2)) 1` `show_bits $gpi15 $((0*8+2)) 1` `show_bits $gpi15 $((2*8+2)) 1`
	echo " RESET COMPLETE: "`show_bits $gpi8 $((0*8+3)) 1` `show_bits $gpi8 $((1*8+3)) 1` `show_bits $gpi11 $((0*8+3)) 1` `show_bits $gpi11 $((1*8+3)) 1` `show_bits $gpi15 $((0*8+3)) 1` `show_bits $gpi15 $((2*8+3)) 1`
	echo " UNDERFLOW:      "`show_bits $gpi8 $((0*8+4)) 1` `show_bits $gpi8 $((1*8+4)) 1` `show_bits $gpi11 $((0*8+4)) 1` `show_bits $gpi11 $((1*8+4)) 1` `show_bits $gpi15 $((0*8+4)) 1` `show_bits $gpi15 $((2*8+4)) 1`
	echo " OVERFLOW:       "`show_bits $gpi8 $((0*8+5)) 1` `show_bits $gpi8 $((1*8+5)) 1` `show_bits $gpi11 $((0*8+5)) 1` `show_bits $gpi11 $((1*8+5)) 1` `show_bits $gpi15 $((0*8+5)) 1` `show_bits $gpi15 $((2*8+5)) 1`
	echo " RESET ERROR:    "`show_bits $gpi8 $((0*8+6)) 1` `show_bits $gpi8 $((1*8+6)) 1` `show_bits $gpi11 $((0*8+6)) 1` `show_bits $gpi11 $((1*8+6)) 1` `show_bits $gpi15 $((0*8+6)) 1` `show_bits $gpi15 $((2*8+6)) 1`
	fi
	exit 0;
fi

read -p "Press ENTER to view the next block, Other key to break: " -s -n 1 yesno; [ "$yesno" != "" ] && { echo; echo; exit 0; }
start_addr=$((start_addr+size))

done
