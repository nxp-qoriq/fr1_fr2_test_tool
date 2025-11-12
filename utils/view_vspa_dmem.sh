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

if [ -f ./runtime_config.txt ];then
	source ./check_dfe_cap_core_map.sh
else	
	source ./config.dat
fi

print_usage()
{
echo "usage ./view_vspa_dmem <core_id> <start_addr> [size] [bit_width]"
echo core_id: 0,1,2,3,4,5,6,7
echo start_addr: address of the VSPA DMEM 0-0x4FFFF for LA12xx or 0-0x8000 for LA9310.  The following special words can be used as specific address
echo "            log: address of log_buffer, the script will look at map file and retrieve the address of log_buffer"
echo size:  size in bytes, size will be set to 512B if not specified.
echo bit_width: b for byte, h for halfword, w for word, l for long. bit width will be set to w if not specified
echo
}

if [ $# -lt 2 ];then
print_usage
exit
fi

((core_id=$1%NUM_CORES))
start_addr=$2; addr_type=""
size=512
bit_width=w
[ $# -ge 3 ] && size=$(($3))
[ $# -ge 4 ] && bit_width=$4
([ $bit_width != b ] && [ $bit_width != h ] && [ $bit_width != w ] && [ $bit_width != l ]) && { echo -e "***ERROR: illegal bit width.\n"; print_usage; exit 1; }

if [ $start_addr = log ];then
	addr_type=log
	[ -f ./boot_vspa_log.txt ] && source ./boot_vspa_log.txt || { echo ***ERROR: boot_vspa_log.txt does not exist, command failed.; exit 1; }
	[ -f ./$vspa_image_folder_name/map_core$core_id.map ] || { echo ***ERROR: ./$vspa_image_folder_name/map_core$core_id.map does not exist, command failed.; exit 1; }
	str=($(grep " _log_buffer " ./$vspa_image_folder_name/map_core$core_id.map))
	[ "$str" = "" ] && { echo ***ERROR: Var _log_buffer does not exist in map file, command failed.; exit 1; }
	start_addr=${str[0]}; size=${str[1]}
else
	[ $((start_addr)) -ge $((VCPUDMEM_SIZE+IPPUDMEM_SIZE)) ] && { echo -e "***ERROR: start address exceeds VSPA DMEM size.\n"; print_usage; exit 1; }
fi

#while [ $((1)) ]
#do

if [ $(($start_addr)) -ge $((VCPUDMEM_SIZE)) ];then
((start_addr_host=$start_addr-$VCPUDMEM_SIZE+0x100000))
else
start_addr_host=$start_addr
fi

((start_addr_host=VDRAMaddr_vir+$core_id*0x400000+$start_addr_host))
((end_addr_host=start_addr_host+size-1))
start_addr_host=`printf 0x%x $start_addr_host`
end_addr_host=`printf 0x%x $end_addr_host`

if [ -f ./runtime_config.txt ];then
if ([ "$addr_type" = log ] && [ $((vspa_image_version)) -ge $((0x456)) ]);then
ext_log_buf_phy=`get_wordvalue_from_vspa $core_id $ext_log_buf_base`
ext_log_buf_size=`get_wordvalue_from_vspa $core_id $ext_log_buf_size`
if [ $((ext_log_buf_size)) -ne 0 ];then

echo Print log from internal memory $start_addr_host size $ext_log_buf_size
echo start_addr_host = $start_addr_host, end_addr_host=$end_addr_host
echo ./utils/loadmem null $start_addr_host -r $size $bit_width
./utils/loadmem null $start_addr_host -r $size $bit_width | more

start_addr_host=`phy2vir $ext_log_buf_phy`
size=$ext_log_buf_size
end_addr_host=`printf 0x%x $((start_addr_host+size-1))`
echo Print log from external memory $start_addr_host size $size
fi
fi
fi
echo start_addr_host = $start_addr_host, end_addr_host=$end_addr_host
echo ./utils/loadmem null $start_addr_host -r $size $bit_width
./utils/loadmem null $start_addr_host -r $size $bit_width | more

#read -p "Press ENTER to view the next block, Other key to break: " -s -n 1 yesno; [ "$yesno" != "" ] && { echo; echo; exit 0; }
#start_addr=$((start_addr+size))
#done
