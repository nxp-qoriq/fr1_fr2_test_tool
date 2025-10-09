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

known_waveform_list=(
#list for TX freq domain symbol dump:
6fc96d93dcbcb90cc0aca6e3eac12fa2 "Default TM3.3 100Mhz 30Khz FDD compressed 20ms"
3f97af04ee5d99a5ff546cd60643b7da "Default TM3.3 100Mhz 30Khz FDD 20ms"
ffd09d08de95792ff32e3665e072d1ee "Default TM3.3 100Mhz 30Khz TDD 20ms"
8f721c11f21bc2ae3a5092edec4b1aeb "Default TM3.3 100Mhz 30Khz 9-bit compressed TDD 20ms"
c67db8ea7e7004607ac104e9abb6b4e4 "Default TM3.3 100Mhz 30Khz 9-bit compressed FDD 20ms"
6890d1f9a181391cfb3e2e8faefd1aa2 "Default TM3.3 100Mhz 30Khz FDD 20ms option8"
03a4ab8fd2adbd9b6305baaacf7e695f "Default TM3.3 100Mhz 30Khz TDD 20ms option8"
c11a3f0674475ed4fec43da39cc8b5e9 "Default TM3.1 400Mhz 120Khz TDD"
6146b49c090b4f97a761edaeb6919a06 "Default TM3.1 400Mhz 120Khz FDD"
29c00381b08f947d7241679268668655 "Default TM3.1_200MHz_60kHz_FDD_fd_20ms"
8a5b6d26d0acaea2827736ceb292a04a "Default TM3.1_200MHz_60kHz_TDD_fd_20ms"
0 )  #the last element must be a 0 for end of list flag

print_tx_dump_check_correct()
{
echo
echo "***** CORRECT! CORRECT! CORRECT! ***** dumped data are expected."
echo
}

print_usage()
{
echo
echo usage: ./dump_freq_domain_tx/rx.sh [ant_id] [time_len_ms]
echo "    ant_id = 0,1,2,3,4,5"
echo "    time_len_ms: = 0.5ms, 1ms, 2ms, 5ms, 10ms, 20ms, 40ms"
echo
}

default_time_len=${input_waveform_len[$tx_fdd]}; tag=$default_time_len
[ $default_time_len = 0.5 ] && default_time_len=500 || default_time_len=$((default_time_len*1000))
time_len=$default_time_len
ant=0;
num_counter=0

arg_parse()
{
	if 	([ $1 = 0.5ms ] || [ $1 = .5ms ]); 	then			time_len=500; tag=0.5
	elif 	[ $1 = 1ms ]; 	then		time_len=1000; tag=1
	elif 	[ $1 = 2ms ]; 	then		time_len=2000; tag=2
	elif 	[ $1 = 5ms ]; 	then		time_len=5000; tag=5
	elif 	[ $1 = 10ms ]; 	then		time_len=10000; tag=10
	elif 	[ $1 = 20ms ]; 	then		time_len=20000; tag=20
	elif 	[ $1 = 40ms ]; 	then		time_len=40000; tag=40
	else
		if [ $num_counter = 0 ];then	((num_counter++));	ant=$(get_ant_id_from_arg $1); [ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit; }
		else							echo Wrong Argument: $1; print_usage; exit
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $((vspa_image_version)) -lt $((0x500)) ] && { echo -e "***ERROR: VSPA image version older than 5.0 does not support TX freq domain dump.\n"; exit 1; }
check_ant_enable_tx $ant; core=${anttx[$ant]}; trid=${tidant[$ant]}; cmd=0x0A0F0000;
get_chan_para $ant $core

msb=`size_align $((sym_size*4)) 128`
((msb=cmd+(msb/128) + (trid<<15) ))
num_sym_to_dump=$((sym_num*time_len/default_time_len))
size_file=$((invecsize*time_len/default_time_len))

end_hram=$next_HRAMaddr_phy
end_hram=`size_align $end_hram 4096`
available_hram=$((HRAMaddr_phy+HRAM_size-end_hram))
if [ $size_file -gt $available_hram ];then
	malloc_for_dump $size_file
	addr_phy=$addr_dump
else
	addr_phy=$end_hram
fi
addr_vir=`phy2vir $addr_phy`

((lsb=(num_sym_to_dump<<20)+(addr_phy>>12)))

if [ $((option8_tx[$ant])) -eq 1 ];then
	filename=tx_timedomain_$tag\ms_$baseband_txsps\ksps_dump_ant$ant.bin
else
	filename=tx_freqdomain_$tag\ms_dump_ant$ant.bin
fi
echo Clearing memory from $addr_vir with size $size_file...
clear_mem $addr_vir $size_file
[ -f $filename ] && rm $filename
dumpfile $addr_vir $filename $size_file
tempmd5sum=`md5sum $filename`
tempmd5sum=${tempmd5sum:0:32}

msb=`printf "0x%08x" $msb`
lsb=`printf "0x%08x" $lsb`
vspa_mbox_ifsend $core $host_vspa_mbox_id $msb $lsb
echo vspa_mbox send $core $host_vspa_mbox_id $msb $lsb
sleep 0.1
[ -f $filename ] && rm $filename; dumpfile $addr_vir $filename $size_file
echo Antenna $ant done: Dumped to address $addr_vir with size $size_file, file: $filename

#check dump data correctness
checksum=`md5sum $filename`
checksum=${checksum:0:32}
echo md5checksum: $checksum
if [ $tempmd5sum = $checksum ];then
	echo -e "***WARNING: The dump data are all zero. TX frequency domain dump may not be supported by VSPA.\n"
fi

check_known_waveform $checksum

if [ $checksumpass = 1 ];then
print_tx_dump_check_correct
elif [ -f ${invecfile_cur[$ant]} ];then
#check dump data correctness
checksum1=`md5sum ${invecfile_cur[$ant]}`
checksum1=${checksum1:0:32}
[ $checksum = $checksum1 ] && { echo Dump identified: Dump is idential to waveform file ${invecfile_cur[$ant]}; print_tx_dump_check_correct; }
else
echo Input waveform does not exist.
fi
check_error_ant $ant
