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

if [ $vspa_dev_type = LA9310 ];then	test_size=2048
else								test_size=16384
fi

ddr_address=$ddr_phy       #users can change
#peb_address=$((0xe0200000+0x200000-65536))     #do not change
hram_address=$HRAMaddr_phy    #do not change

if [ $# -ge 1 ];then
	if ([ $(($1)) -le $test_size ] && [ $(($1)) -gt 0 ]); then
		test_size=$(($1))
		echo DMA size updated to $test_size
	else
		echo -e "***ERROR: Wrong size $1, expected size should be no larger than $test_size\n"; exit 1
	fi
fi


swversion=0; swversion_allcore=0
for ((i=0;i<NUM_CORES;i++))
do
		swverion_addr=$((modembase_phy+0x1000000+i*0x4000+4))
		swverion_value=`./utils/devmem $swverion_addr w`
		if [ $((swverion_value>>16)) -eq $((0xdfef)) ];then
			((swversion=swverion_value))
			((swversion_allcore=swversion_allcore|swversion))
			txcore=$i
		fi
done
vspa_image_version=`printf "0x%x" $((swversion&0xFFF))`

if [ $((swversion>>16)) -ne $((0xdfef)) ];then
		echo "*** ERROR: VSPA images are not FR1 FR2 Test Tool VSPA images."
		exit 1;
fi
echo

echo VSPA core $txcore is availabe for the testing.

cycle2time ()
{
	((ns=$1*1000000/vspa_core_clock))
	printf %6d $ns
}

#return value is in Gbps
calc_bps ()     #calc_bps <size_byte> <cyclecount>
{
	if [ $(($2)) -eq 0 ]; then
	echo wrong paramter, cycle count is 0
	exit 1
	fi
	
	((bps=$1*8*vspa_core_clock/$2/1000))
	printf %3d $bps
}

#show_result <string> <size> <cyclecount>
show_result()
{
echo "$1", $2 bytes, cycle count "`printf %6d $(($3))`"," `cycle2time $3`" ns, " `calc_bps $2 $3` Mbps" $4
}

mem_test $txcore $ddr_address $test_size 0; [ $? -ne 0 ] && { echo ***ERROR: VSPA no response; exit 1; }
ddr_read_cycle_2chan=$cycle2chan 
ddr_read_cycle_1chan=$cycle1chan
if [ $vspa_dev_type = LA12xx ];then
ddr_read_cycle_back2=$cycle4chan
ddr_read_cycle_back1=$cycle3chan
fi
mem_test $txcore $ddr_address $test_size 1; [ $? -ne 0 ] && { echo ***ERROR: VSPA no response; exit 1; }
ddr_write_cycle_2chan=$cycle2chan 
ddr_write_cycle_1chan=$cycle1chan
if [ $vspa_dev_type = LA12xx ];then
ddr_write_cycle_back2=$cycle4chan
ddr_write_cycle_back1=$cycle3chan
fi
#mem_test $txcore $peb_address $test_size 0
#peb_read_cycle_2chan=$cycle2chan 
#peb_read_cycle_1chan=$cycle1chan
#peb_read_cycle_back2=$cycle4chan
#peb_read_cycle_back1=$cycle3chan

#mem_test $txcore $peb_address $test_size 1
#peb_write_cycle_2chan=$cycle2chan 
#peb_write_cycle_1chan=$cycle1chan
#peb_write_cycle_back2=$cycle4chan
#peb_write_cycle_back1=$cycle3chan

if [ $vspa_dev_type = LA12xx ];then
mem_test $txcore $hram_address $test_size 0; [ $? -ne 0 ] && { echo ***ERROR: VSPA no response; exit 1; }
hram_read_cycle_2chan=$cycle2chan 
hram_read_cycle_1chan=$cycle1chan
hram_read_cycle_back2=$cycle4chan
hram_read_cycle_back1=$cycle3chan

mem_test $txcore $hram_address $test_size 1; [ $? -ne 0 ] && { echo ***ERROR: VSPA no response; exit 1; }
hram_write_cycle_2chan=$cycle2chan 
hram_write_cycle_1chan=$cycle1chan
hram_write_cycle_back2=$cycle4chan
hram_write_cycle_back1=$cycle3chan

tag_back1_read=" with background WRITE by 1 channel"
tag_back2_read=" with background READ. by 2 channels on DDR"
tag_back1_writ=" with background READ. by 2 channels"
tag_back2_writ=" with background WRITE by 1 channel. on DDR"
fi

echo
echo VSPA DMA Memory read/write performance test result:
show_result "DDR  READ   by VSPA DMA 1 channel " $test_size $ddr_read_cycle_1chan ""
[ $vspa_dev_type = LA12xx ] && show_result "DDR  READ   by VSPA DMA 2 channels" $test_size $ddr_read_cycle_2chan ""
show_result "DDR  WRITE  by VSPA DMA 1 channel " $test_size $ddr_write_cycle_1chan ""
[ $vspa_dev_type = LA12xx ] && show_result "DDR  WRITE  by VSPA DMA 2 channels" $test_size $ddr_write_cycle_2chan ""
#show_result "PEBM READ   by VSPA DMA 1 channel " $test_size $peb_read_cycle_1chan ""
#show_result "PEBM READ   by VSPA DMA 2 channels" $test_size $peb_read_cycle_2chan ""
#show_result "PEBM WRITE  by VSPA DMA 1 channel " $test_size $peb_write_cycle_1chan ""
#show_result "PEBM WRITE  by VSPA DMA 2 channels" $test_size $peb_write_cycle_2chan ""

if [ $vspa_dev_type = LA12xx ];then
show_result "HRAM READ   by VSPA DMA 1 channel " $test_size $hram_read_cycle_1chan ""
show_result "HRAM READ   by VSPA DMA 2 channels" $test_size $hram_read_cycle_2chan ""
show_result "HRAM WRITE  by VSPA DMA 1 channel " $test_size $hram_write_cycle_1chan ""
show_result "HRAM WRITE  by VSPA DMA 2 channels" $test_size $hram_write_cycle_2chan ""

echo
if [ $((vspa_image_version)) -ge $((0x313)) ];then
show_result "DDR  READ   by VSPA DMA 2 channels" $test_size $ddr_read_cycle_back1   "$tag_back1_read"
show_result "DDR  READ   by VSPA DMA 1 channel " $test_size $ddr_read_cycle_back2   "$tag_back2_read"
show_result "DDR  WRITE  by VSPA DMA 1 channel " $test_size $ddr_write_cycle_back1  "$tag_back1_writ"
show_result "DDR  WRITE  by VSPA DMA 1 channel " $test_size $ddr_write_cycle_back2  "$tag_back2_writ"
#show_result "PEBM READ   by VSPA DMA 2 channels" $test_size $peb_read_cycle_back1   "$tag_back1_read"
#show_result "PEBM READ   by VSPA DMA 1 channel " $test_size $peb_read_cycle_back2   "$tag_back2_read"
#show_result "PEBM WRITE  by VSPA DMA 1 channel " $test_size $peb_write_cycle_back1  "$tag_back1_writ"
#show_result "PEBM WRITE  by VSPA DMA 1 channel " $test_size $peb_write_cycle_back2  "$tag_back2_writ"
show_result "HRAM READ   by VSPA DMA 2 channels" $test_size $hram_read_cycle_back1  "$tag_back1_read"
show_result "HRAM READ   by VSPA DMA 1 channel " $test_size $hram_read_cycle_back2  "$tag_back2_read"
show_result "HRAM WRITE  by VSPA DMA 1 channel " $test_size $hram_write_cycle_back1 "$tag_back1_writ"
show_result "HRAM WRITE  by VSPA DMA 1 channel " $test_size $hram_write_cycle_back2 "$tag_back2_writ"
fi
fi
echo
exit 0
