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

source ./check_dfe_cap_core_map.sh

use_vspa_dma=0

if ([ $# -ge 1 ] && [ $1 = vdma ]);then
	use_vspa_dma=1
fi

ant=0
addr_ifft_out_buf_total_release_size=0x00000168

vspa_core_id=${anttx[ant]};

[ -f ./boot_vspa_log.txt ] && source ./boot_vspa_log.txt || { echo ***ERROR: boot_vspa_log.txt does not exist, command failed.; exit 1; }
[ -f ./$vspa_image_folder_name/map_core$vspa_core_id.map ] || { echo ***ERROR: ./$vspa_image_folder_name/map_core$vspa_core_id.map does not exist, command failed.; exit 1; }
str=($(grep " _iFFTout_CFRinout " ./$vspa_image_folder_name/map_core$vspa_core_id.map))

addr_ifft_out_buf_base=${str[0]}; 		#VSPA DMEM address,  need to map to FGPA side PCI address
size_ifft_out_buf=${str[1]}				#The buffer is circular buffer, reading from the buffer from beginning to the end and wrap back to beginning
				
#addr_ifft_out_buf_total_release_size=0x000001d8 #VSPA DMEM address,  need to map to FGPA side PCI address. LX2 view: 0x000000a06a0001d8
#addr_ifft_out_buf_total_release_size=0x00000208 #VSPA DMEM address,  need to map to FGPA side PCI address. LX2 view: 0x000000a06a0001d8

la12xx_addr_ifft_out_buf_base=`dmem2phy $vspa_core_id $addr_ifft_out_buf_base`; 
la12xx_addr_ifft_out_buf_total_release_size=`dmem2phy $vspa_core_id $addr_ifft_out_buf_total_release_size`; 

#the following 3 address conversion convert address from LA view to LX2 view and will be accessed by script running on LX2.
#for FPGA to retrieve Low PHY data from LA12xx to FPGA over the 2nd PCI interface. these 3 conversions must change to convert from LA view to FPGA view.
lx2_addr_ifft_out_buf_base=`phy2vir $la12xx_addr_ifft_out_buf_base`
lx2_addr_ifft_out_buf_total_release_size=`phy2vir $la12xx_addr_ifft_out_buf_total_release_size`


echo addr_ifft_out_buf_base=$addr_ifft_out_buf_base, la12xx_addr_ifft_out_buf_base=`HEX $la12xx_addr_ifft_out_buf_base`, lx2_addr_ifft_out_buf_base=$lx2_addr_ifft_out_buf_base
echo size_ifft_out_buf=$size_ifft_out_buf
echo addr_ifft_out_buf_total_release_size=$addr_ifft_out_buf_total_release_size, la12xx_addr_ifft_out_buf_total_release_size=`HEX $la12xx_addr_ifft_out_buf_total_release_size`, lx2_addr_ifft_out_buf_total_release_size=$lx2_addr_ifft_out_buf_total_release_size
echo

read_ptr_fpga=$lx2_addr_ifft_out_buf_base
block_size=10240 #4096
total_read_size=0
interation=0

filename=fpga_dump.bin
[ -f $filename ] && rm $filename

while [ 1 ]
do
	
	echo copy one block with size $block_size from LA to FPGA here
	#add FGPA copy here, src addr at read_ptr_fpga, dest at FGPA internal, size: block_size. 
	#becasue of circular buffer, need check if read_ptr_fpga reaches end of buffer and wrap back to beginning of buffer
	
	echo Reading from LA from PCI address $read_ptr_fpga with size $block_size
	if [ $total_read_size -lt 4915200 ];then
		if [ $use_vspa_dma = 0 ];then
			dumpfile $read_ptr_fpga tmp.bin $block_size  #simulate directly read from vspa buffer
		else
			./utils/vspa_dma.sh $vspa_core_id $addr_ifft_out_buf_base $addr_dump $block_size 15 conv
			dumpfile `phy2vir $addr_dump` tmp.bin $block_size  #simulate directly read from vspa buffer
		fi
		cat tmp.bin >> $filename
		rm tmp.bin
	else
		break
	fi
	
	total_read_size=$(((total_read_size+block_size)&0xFFFFFFFF)); echo total_read_size=$total_read_size
	
	read_ptr_fpga=`HEX $((read_ptr_fpga+block_size))` #next src addr
	[ $((read_ptr_fpga)) -ge $((lx2_addr_ifft_out_buf_base+size_ifft_out_buf)) ] && read_ptr_fpga=$lx2_addr_ifft_out_buf_base #cirlar buffer

	echo Writing LA at PCI address $lx2_addr_ifft_out_buf_total_release_size with total release size $total_read_size
	./utils/devmem $lx2_addr_ifft_out_buf_total_release_size w $total_read_size

#sleep 1    #sleep here just for users to look at the log manually to understand the steps.  In FPGA implementation, it should wait until a block transmit time has passed.
interation=$((interation+1))
echo -e "interation = $interation\n"
done