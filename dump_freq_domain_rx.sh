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

#usage: ./dump_freq_domain_rx.sh <ant_id>  [nsym=n]
#if ant_id is not specified, default ant_id will be used, which is ant 0 for LSDCS, or ant 4 for HSDCS.

source ./check_dfe_cap_core_map.sh

known_waveform_list=(
#list of RX freq domain symbol dump:
784c931e0da2c8d5645ef201409dfa99 "TDD single tone 30Khz 25% scale at 245Msps with 8taps decimation freq domain dump for pattern 7624"
da6c2cdd77948780b4537cd96012745b "TDD single tone 30Khz 25% scale at 245Msps with 64taps decimation freq domain dump for pattern 7624"
8b49af846a25e80af09d4bfa6f1151d4 "TDD (3 6 1 4 0 0   2 10 2 2 0 0) single tone 30Khz 25% scale freq domain dump"
8c51f76081eec08b5b49b0a38b81f1bf "TDD (3 6 1 4 0 0   2 10 2 2 0 0) single tone 30Khz 25% scale freq domain dump with CFO 30Khz"
58872e2a510300679375ad5ea0ae177a "TDD (3 6 1 4 0 0   2 10 2 2 0 0) single tone 30Khz 25% scale freq domain dump with phase compensation"
8da351ae84bd94856bbc1ea3a5f4d96e "FDD single tone 15Khz 25% scale at 61Msps freq symbols dump for 5Mhz SCS15" 
0fe35bed4188d50849c310a19c9e32ff "FDD single tone 15Khz 25% scale at 61Msps option8 dump for 5Mhz SCS15" 
7a2771661cd30e1c207bef07ac91f7c6 "FDD single tone 15Khz 25% scale at 61Msps freq symbols dump for 10Mhz SCS15" 
19f74bdbbe5d4482fae6c3642c92bf53 "FDD single tone 30Khz 25% scale at 61Msps freq symbols dump 10ms for 10Mhz SCS30" 
dd07de3da4ddfc55fb9ead966f26d05c "FDD single tone 30Khz 25% scale at 61Msps freq symbols dump 10ms for 20Mhz SCS30" 
4917ab6a0b8255272069954ff57a9b6a "FDD single tone 30Khz 25% scale at 61Msps freq symbols dump 10ms for 20Mhz SCS30 with filter dealy compensation" 
159146f7f14f1b6cdec38936b17192a8 "FDD single tone 30Khz 25% scale at 61Msps freq symbols dump 10ms for 20Mhz SCS30 LA12xx" 
00cb95c3921a11970eaf180673d106bf "FDD single tone 30Khz 25% scale at 122Msps freq symbols dump 10ms for 25Mhz SCS30 LA12xx" 
6bb443d8c226e243d7cfc2fa63f19fcc "FDD single tone 30Khz 25% scale at 61Msps freq symbols dump 20ms for 20Mhz SCS30" 
2b680e1ec5fa8d3b70b1b5bde506e21a "TDD single tone 15Khz 25% scale at 61Msps freq symbols dump for pattern DDGUG for 10Mhz SCS15"
3c6aad94923f329d79dc6e02f20d3139 "TDD single tone 15Khz 25% scale at 61Msps freq symbols dump for pattern DDGGG GGUUG GGGGG UUUUG for 5Mhz SCS15"
565fa1685e04b9ebce0722b63525a8b4 "TDD single tone 15Khz 25% scale at 61Msps freq symbols dump for pattern DDGGG GGUUG GGGGG UUUUG for 10Mhz SCS15"
2a43681e19555c9541d4c739734e857b "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD input waveform 20ms after rxqec passthrough." 
3b74043ceac96650d50322dde780fdf4 "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD input waveform 10ms after rxqec passthrough." 
861dc7a9a6d6b9e74dd696b067cce10f "Default G-FR1-A1-5 100Mhz 30Khz TDD Reference"
c4be4f076b183790cfc0f1193f854d94 "Default G-FR1-A1-5 100Mhz 30Khz TDD QEC enabled with filter bypassed Reference"
a80f88b1da76d7ccfc2f2cc8f9d09341 "Default G-FR1-A1-5 100Mhz 30Khz TDD option8 Reference"
0490e7f14f06bc0b320082b2bd9ee5ba "Default G-FR1-A1-5 100Mhz 30Khz FDD option8 Reference"
c548add24325dc1dbda976d414cbafc2 "Default G-FR1-A1-5 100Mhz 30Khz TDD 9-bit compressed Reference"
9efe2d280fb45ef4f52c9714c51a7f31 "G-FR1-A1-5_UL_5msx4_100MHz_30kHz_TDD used as FDD time domain injection reference"
7278f3d5a9a61098cc141174d3882c65 "G-FR1-A1-5_UL_5msx4_100MHz_30kHz_TDD used as FDD time domain injection compressed reference"
ab5c4eae7126eb2d959e40381127ef36 "G-FR1-A1-5_UL_5ms_100MHz_30kHz_TDD used as FDD 10ms freq domain dump"
d4ccc9d730efa7b013c708bf15dc142c "100MHz_30kHz_FDD single tone 30Khz 25% scale decimation tap8 20ms freq domain dump" 
b131389b2eceb4bf79454fef0f0f0b31 "100MHz_30kHz_FDD single tone 30Khz 25% scale decimation tap64 20ms freq domain dump" 
38eab66365b88483957bb0923b7c8667 "100MHz_30kHz_FDD single tone 30Khz 25% scale decimation tap64 + 63 taps low pass filter passthrough + timing offset compensation 20ms freq domain dump" 
eb96da0530415069194301eb8ea13298 "100MHz_30kHz_FDD single tone 30Khz 25% scale decimation tap64 + LPF 63taps with filter delay compensation 10ms dump" 
241a4269784c3b7f74e522e93fec023b "G-FR1-A1-5_UL_5ms_100MHz_30kHz_TDD used as FDD 20ms freq domain dump"
158a33e4d2ba8c4912b6bd5883f4bbbc "400Mhz 120Khz UL 5ms reference"
b3ea9af299f7db28b19871c8b4bb2cd4 "Default TM3.1_400Mhz_120Khz_FDD TX loopback to RX reference QEC passthrough"
6b558098f2ab2408242a17a4a23d9169 "Default TM3.1_400Mhz_120Khz_FDD TX loopback to RX reference QEC coeff applied"
d83130abccdf27ac56f3c658b72e9cd1 "Default TM3.1_400Mhz_120Khz_FDD TX loopback to RX reference 1966Msps RX QEC passthrough"
d21529c28f86b8e5cd38dcb0c4540665 "Default TM3.1_400Mhz_120Khz_FDD TX loopback to RX reference 1966Msps RX QEC coeff applied"
9625995beee5e4f5f1493e4d0dfc8542 "100Mhz 120Khz TM3.1 TDD used for FDD TX loopbacked to RX reference"
3f7bca9c3c9ce52f8d567a7d75baa987 "100Mhz 120Khz TM3.1 FDD TX loopbacked to RX reference 983Msps"
171d4350fa946a5860825e1bc82f3a17 "400Mhz 120Khz FDD 2x16+2x16 taps upsampling waveform TX loopbacked to RX reference"
a48bfdf931bf630cca3586173c61e6ed "400Mhz 120Khz TDD 5ms inject 2xdown-disabled reference"
569413fb0a701ec59de18f36aa905fe4 "Default TM3.1_200Mhz_60Khz_FDD TX loopback to RX reference"
0c52aaaa6867696d75b02e46d9f72616 "Default TM3.3_100Mhz_30Khz_FDD TX loopback to RX reference"
87f4d267db3874693a52af1d482ba733 "400Mhz 120Khz TDD RX injecting with counter6MB.bin"
8de025b9568c942f2fb0307ec761576c "G-FR1-A1-5_UL_20ms_100MHz_30kHz_TDD QEC passthrough input waveform."
75c8f7ab8f55feaea67ff831939a11a3 "Singletone 120Khz 1.9Gsps FDD RX freq domain dump"
afa9ff0def9d3bf21d3ad05d0792852f "Singletone 120Khz 1.9Gsps TDD RX freq domain dump"
d5a3e83d17726394dc4107f48d25e179 "Singletone 30Khz 245Msps FDD RX freq domain with CFO 30Khz 10slot phase reset dump"
6ff26fc800fe7e2e7d710e3efe5331af "Singletone 30Khz 245Msps FDD RX freq domain with CFO 30Khz 40ms phase reset dump"
e4f1245142477e7c88a1ae3f35aa088f "Singletone 30Khz 245Msps TDD RX freq domain with CFO 30Khz dump"
d0fed1c21152ce6f5ac46cce96064ffa "Singletone 30Khz 61Msps FDD RX freq domain with CFO 30Khz dump"
013a03142789171c09549761014b307d "Singletone 30Khz 245Msps FDD RX freq domain with phase compensation dump"
f94fa084e3169ebc0565dc1561339e36 "Singletone 30Khz 245Msps FDD RX freq domain with phase compensation dump"
bf1f7ea2972cafa00389b89c251a2ca1 "Singletone 30Khz 245Msps TDD RX freq domain with phase compensation dump"
0461196b4f0cde6a86ccc85bab58f32a "Singletone 30Khz 245Msps TDD RX freq domain"
662b8867818fd5fd5c99cde4faa85dc0 "20Mhz 30Khz TM3.3 FDD TX loopbacked to RX reference"
5c36b38aa0d7aeedc52fe6dc8484ff88 "1.9Gsps RX single tone 10Mhz 1% scale 10ms freq domain dump"
0 )  #the last element must be a 0 for end of list flag

print_usage()
{
	echo "usage: ./dump_freq_domain_rx.sh <ant_id> [num_32KB] [time_len_ms] [kd] [mem]"
	echo "  and_id:     0-5"
	echo "  num_32KB:   num of 32KB, 1 represents 32KB, 2 represents 64KB, etc, must be smaller than 1ms size"
	echo "  time_len_ms:must be one of 0.5ms, 1ms, 2ms, 5ms, 10ms, 20ms, 40ms"
	echo "  mem:        dump to memeory without saving to file."
	echo "  example:    ./dump_freq_domain_rx.sh 0           will dumped freq domain waveform with length defined in input_waveform_len in config.dat"
	echo "  example:    ./dump_freq_domain_rx.sh 0 1ms         will dumped freq domain waveform 1ms"
	echo
}

print_rx_dump_check_correct()
{
echo
echo "***** CORRECT! CORRECT! CORRECT! ***** dumped data are expected."
echo
}

ant=0
keep_dumping=0
time_len_default=${input_waveform_len[$tx_fdd]}; tag=$time_len_default
[ $time_len_default = 0.5 ] && time_len_default=500 || time_len_default=$((time_len_default*1000))
time_len=$time_len_default
mem=0
num_32KB=0
num_counter=0
dump_via_hram=1
fast=0
nsym=0

arg_parse()
{
	arg=$1
	if [ $1 = kd ]; then							keep_dumping=1; echo "Keep dumping all the time, until dumping once command is issued."
	elif ([ $1 = HRAM ] || [ $1 = hram ]); then		dump_via_hram=1
	elif ([ $1 = DDR ] || [ $1 = ddr ]); then		dump_via_hram=0
	elif [ $1 = mem ]; then							mem=1
	elif 	([ $1 = 0.5ms ] || [ $1 = .5ms ]); 	then			time_len=500; tag=0.5
	elif 	[ $1 = 1ms ]; 	then		time_len=1000; tag=1
	elif 	[ $1 = 2ms ]; 	then		time_len=2000; tag=2
	elif 	[ $1 = 5ms ]; 	then		time_len=5000; tag=5
	elif 	[ $1 = 10ms ]; 	then		time_len=10000; tag=10
	elif 	[ $1 = 20ms ]; 	then		time_len=20000; tag=20
	elif 	[ $1 = 40ms ]; 	then		time_len=40000; tag=40
	elif 	[ $1 = fast ]; 	then		fast=1
	elif 	[ ${arg:0:5} = nsym= ]; then			nsym=$(echo $arg | cut -d "=" -f2)
	else
		if [ $num_counter = 0 ];then
			ant=$(get_ant_id_from_arg $1)
			[ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			num_32KB=$(($1)); time_len=1000; tag=1;
			num_counter=$((num_counter+1))
		else													echo Wrong Argument: $1; print_usage; exit
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done
[ $fr1_used = 0 ] && ant=$(((ant%2)+4))
dcsid=$ant
check_ant_enable_rx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_RX)) = 0 ] && { echo ***ERROR: Current RX ant $ant is not enabled.; exit 1; }

rxcore=${antrx[$ant]}
rid=${ridant[$ant]}
get_chan_para $ant $rxcore

tagmux=""
filelen=$tag
tagdomain=(freq time)

msb=`size_align $((sym_size*4)) 128`
((msb=0x0A1C0000+(msb/128)))
num_sym_to_dump=$((sym_num*time_len/time_len_default))

if [ $((option8_rx[dcsid])) -eq 1 ];then
	size_file=$((invecsize*time_len/time_len_default*bandwidth_rx/bandwidth_tx))
	nsym=0  #option8 does not support num of symbols dumping
	filename0=rx_timedomain_$filelen\ms_$baseband_rxsps\ksps_dump
else
	size_file=$((num_sym_to_dump*$(size_align $((sym_size*4)) 128)*bandwidth_rx/bandwidth_tx))
	filename0=rx_freqdomain_$filelen\ms_dump
fi

if [ $dump_via_hram = 1 ];then
	size_hram=`align_lo $((HRAMaddr_phy+HRAM_size-next_HRAMaddr_phy)) 4096`
	addr_phy=$((HRAMaddr_phy+HRAM_size-size_hram))
	addr_vir=`printf "0x%x" $((HRAMaddr_vir+HRAM_size-size_hram))`
	if [ $((size_hram)) -ge $size_file ];then
		echo Clearing memory from $addr_vir with size $size_hram...; clear_mem $addr_vir $size_hram
		echo Using HRAM size $size_hram starting from $addr_vir as intermediate buffer for dumping...
	else
		#if [ $((bbsps_rx[ant])) -ge 400000 ];then
		#	echo ***ERROR: HRAM size $((size_hram)) is not big enough to hold the dump size $size_file, try dumping with smaller size such as 0.5ms or 1ms
		#	exit 1  #if bandwidth is very high and HRAM size is not enough, exit, otherwise switch to DDR
		#else
			dump_via_hram=0;
		#fi
	fi
fi
if [ $dump_via_hram = 0 ];then
	malloc_for_dump $size_file
	addr_phy=$addr_dump
	addr_vir=`phy2vir $addr_phy`
	echo Clearing memory from $addr_vir with size $size_file...; clear_mem $addr_vir $size_file
	echo Using DDR size $size_file starting from $addr_vir as intermediate buffer for dumping...
fi

filenamesym=0
[ $((nsym)) -eq 0 ] && nsym=$num_sym_to_dump || filenamesym=rx_freqdomain_$nsym\symbols_dump_ant$dcsid.bin

msb=`printf "0x%08x" $((msb + (rid<<15) + (keep_dumping<<14) ))`
lsb=`printf "0x%08x" $(((nsym<<20)+(addr_phy>>12)))`
vspa_mbox_ifsend $rxcore $host_vspa_mbox_id $msb $lsb
sleep 0.1

if [ $mem = 0 ];then

if [ $filenamesym != 0 ];then
	sym_buf_size=`size_align $((sym_size*4)) 128`
	[ -f $filenamesym ] && rm $filenamesym
	dumpfile $addr_vir $filenamesym $((nsym*sym_buf_size))
	echo Ant $dcsid dump done, to address $addr_vir, size:$((nsym*sym_buf_size)), file:$filenamesym
	check_error_ant $dcsid
	exit 0;
fi

filename=$filename0\_ant$dcsid.bin
[ -f $filename ] && rm $filename; dumpfile $addr_vir $filename $size_file
echo Ant $dcsid dump done, to address $addr_vir, size:$size_file, file:$filename

if [ $num_32KB -ne 0 ];then
if [ $((option8_rx[dcsid])) -eq 1 ];then
	filename1=rx_timedomain_$((num_32KB*32))KB_$baseband_rxsps\ksps_dump_ant$dcsid.bin
else
	filename1=rx_freqdomain_$((num_32KB*32))KB_dump_ant$dcsid.bin
fi
[ -f $filename1 ] && rm $filename1
dumpfile $addr_vir $filename1 $((num_32KB*32768))
echo Ant $dcsid dump done, to address $addr_vir size:$((num_32KB*32768)), file:$filename1
fi

if [ $fast = 0 ];then
	#check dump data correctness
	checksum=`md5sum $filename`
	checksum=${checksum:0:32}
	echo md5sum: $checksum

	check_known_waveform $checksum

	if [ $checksumpass = 1 ];then
		print_rx_dump_check_correct
	fi
fi

else
if [ $filenamesym != 0 ];then
echo Ant $ant dump done, to address $addr_vir size $((nsym*sym_buf_size)), $nsym symbols
else
echo Ant $ant dump done, to address $addr_vir size $size_file, time len $tag\ms $tagmux
fi
fi

check_error_ant $ant
