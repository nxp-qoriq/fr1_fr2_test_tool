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

if [ -f ./runtime_config.txt ];then
source ./check_dfe_cap_core_map.sh
else
source ./config.dat
fi

log_opcode_list=(
0xFF000000 "Log Stopped"					
0xF8000000 "HighPHY TX symbol not ready"	
0xF9000000 "HighPHY RX symbol buffer not empty"	
0xF0000000 "Mailbox msg received"			
0x10000000 "TX symbol DMA started"		
0x1F000000 "TX coreA gets a block from coreB"
0x24000000 "TX AXIQ DMA configured"		
0x25000000 "TX AXIQ DMA completed"	
0x27000000 "One block of data written into TX ant buffer"
0x34000000 "RX AXIQ DMA configured"			
0x35000000 "RX AXIQ DMA completed"			
0x37000000 "One block of RX ant buffer released"	
0x12000000 "TX iFFT started"			
0x32000000 "RX FFT started"				
0xF1000000 "Mailbox msg sent"				
)

log_parse()
{
	local i=0; local data64bit=$1
	local tag="Event or Log Opcode undefined"
	local opcode=`HEX $((data64bit&0xFF000000))`
	for ((i=0;i<${#log_opcode_list[@]};i+=2))
	do
		if [ $((opcode)) -eq $((log_opcode_list[i])) ];then
			tag=${log_opcode_list[i+1]}
			break;
		fi
	done
	local timestamp=`HEX $((data64bit&0x00FFFFFF))`
	local lsb=`HEX $(((data64bit>>32)&0xFFFFFFFF))`
	local interval=$(((((timestamp-timestamp_pre)&0xFFFFFF)*1000+vspa_core_clock/2)/vspa_core_clock)) #us
	timestamp_pre=$timestamp
	echo "$opcode $lsb $timestamp    `printf %6d   $interval`         $tag"
}


coredump()
{
local coreid=$1
((vcpuaddr=VDRAMaddr_vir+0x400000*coreid))
vcpuaddr=`printf 0x%08x $vcpuaddr`
((ippuaddr=VDRAMaddr_vir+0x400000*coreid+0x100000))
ippuaddr=`printf 0x%08x $ippuaddr`
((ipaddr=modembase_phy+0x1000000+coreid*0x4000))
ipaddr=`printf 0x%08x $ipaddr`

log=`./utils/bin2mem -f vspa_coredump_core$coreid\_$2.bin -a $vcpuaddr -r $((VCPUDMEM_SIZE))`
log=`./utils/bin2mem -f debug_dump_temp.bin -a $ippuaddr -r $((IPPUDMEM_SIZE))`
cat debug_dump_temp.bin >> vspa_coredump_core$coreid\_$2.bin
log=`./utils/bin2mem -f debug_dump_temp.bin -a $ipaddr -r 16384`
cat debug_dump_temp.bin >> vspa_coredump_core$coreid\_$2.bin
echo Core$coreid coredump done to file:vspa_coredump_core$coreid\_$2.bin
}

ext_log_dump()
{
local coreid=$1
if ([ $((vspa_image_version)) -ge $((0x456)) ] && [ -f ./runtime_config.txt ]);then
ext_log_buf_phy=`get_wordvalue_from_vspa $coreid $ext_log_buf_base`
ext_log_buf_sz=`get_wordvalue_from_vspa $coreid $ext_log_buf_size`
if [ $((ext_log_buf_sz)) -ne 0 ];then
start_addr_host=`phy2vir $ext_log_buf_phy`
log=`./utils/bin2mem -f vspa_exttrace_core$coreid\_$2.bin -a $start_addr_host -r $((ext_log_buf_sz))`
echo Core$coreid exttrace done to file:vspa_exttrace_core$coreid\_$2.bin

#echo Parsing trace and log into text file... This may take a while, press CTRL+C to abort...
#timestamp_pre=`devmem $((start_addr_host))`
#timestamp_pre=$((timestamp_pre&0xffffff))
#log_parse_filename=./vspa_exttrace_core$coreid\_$2_\parsed.txt
#echo "VSPA Trace and Log Records:" > $log_parse_filename
#echo "Opcode     Log_data   Timestamp(24bit) interval(us)  Event" >> $log_parse_filename
#local i=0;
#for ((i=0;i<ext_log_buf_sz/2;i+=8))
#do
#	log_entry_64bit=`./utils/memrw r 64 $((start_addr_host+i))`
#	log_parse $log_entry_64bit >> $log_parse_filename
#done
#
#echo -e "\n\nAbove $((ext_log_buf_sz/2/8)) records are recorded since system startup\nBelow $((ext_log_buf_sz/2/8)) records are the latest if the system is running well, or the last records before errors."  >> $log_parse_filename
#
#log_parse_filename1=./vspa_exttrace_core$coreid\_$2_\parsed1.txt
#echo " "  > $log_parse_filename1
#for ((i=ext_log_buf_sz/2;i<ext_log_buf_sz;i+=8))
#do
#	log_entry_64bit=`./utils/memrw r 64 $((start_addr_host+i))`
#	log_parse $log_entry_64bit >> $log_parse_filename1
#	[ $((log_entry_msb32&0xFF000000)) -eq $((0xFF000000)) ] && break
#done
#
#for ((i=i+8;i<ext_log_buf_sz;i+=8))
#do
#	log_entry_64bit=`./utils/memrw r 64 $((start_addr_host+i))`
#	log_parse $log_entry_64bit >> $log_parse_filename
#done
#
#cat $log_parse_filename1 >> $log_parse_filename
#rm $log_parse_filename1
#echo Core$coreid parsed trace done to file:$log_parse_filename You can open this file to see the VSPA Trace Log.

fi
fi
}


tag=0
[ $# -ge 1 ] && tag=$1

dfe_core=(0 0 0 0 0 0 0 0) 
swversion_allcore=0
slave_core=(0 0 0 0 0 0 0 0)
one_dfe_core=$INVALID_CORE
for ((i=0;i<NUM_CORES;i++))
do
	swversion=`./utils/devmem $((modembase_phy+0x1000000+i*0x4000+4)) w`
	((swversion_iden=swversion>>16))
	if [ $((swversion_iden)) -eq $((0xDFEF)) ];then
		((swversion_allcore=swversion_allcore|swversion))
		dfe_core[$i]=1
		one_dfe_core=$i
		((slave_core[$i]=(swversion>>13)&7))
	fi
done
[ $((one_dfe_core)) -ge $INVALID_CORE ] && { echo ***ERROR: VSPA images are not $test_tool_name images.; echo; exit 1; }
((flag_dfe_initialized=(swversion_allcore>>12)&1))
vspa_image_version=`printf "0x%x" $((swversion_allcore&0xFFF))`

for ((i=0;i<NUM_CORES;i++))
do
	coredump $i $tag
	if [ $((dfe_core[i])) -ne 0 ];then
		ext_log_dump $i $tag
		score=${slave_core[i]}
		[ $((score)) -ne $i ] && ext_log_dump $score $tag
	fi
done

rm debug_dump_temp.bin
echo
