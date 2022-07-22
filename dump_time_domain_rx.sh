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

print_usage()
{
echo
echo "usage ./dump_time_domain_rx.sh [ant_id] [+ant_id +ant_id ...] [num_32KB] [0.5ms|1ms|2ms|5ms|10ms|20ms|40ms] [HRAM|ddr] [mem] [dcm] [offset=x] [pow]"
echo "  ant_id:  	0-5"
echo "  +ant_id:  	multiple RX antennas to be dumped synchronosly at the same time"
echo "  num_32KB:   dump size, num of 32KB, 1 represents 32KB, 2 represents 64KB, etc, must be smaller than 1ms size"
echo "  0.5ms|1ms|2ms|5ms|10ms|20ms|40ms: dump time length"
echo "  HRAM|ddr:   use HRAM memory or DDR as dump memory"
echo "  mem:        dump to memeory without saving to file."
echo "  dcm:        dump decimated antenna data. with decimation enabled, sampling rate will be reduced to base band sampling rate."
echo "  pow:        measure power level on the dump"
echo "	offset=x:     offset from boundary, x=1-0x7F, num of 64KB. For example offset=5 will set the dump to start from offset 320KB after the boundary"
echo "  example: ./dump_time_domain_rx.sh 4 1         will dump 32KB data for antenna 4"
echo "  example: ./dump_time_domain_rx.sh 0           will dump len defined by dump_time_len (default 20ms) for antenna 0"
echo "  example: ./dump_time_domain_rx.sh 0 +1 1      will dump 32KB for antenna 0 and 1 at the same time"
echo "  example: ./dump_time_domain_rx.sh 0 +1 +2 +3 1ms      will dump 1ms for antenna 0,1,2,3 at the same time"
echo
}

#To retrieve the dump filename, use the following way:
#log=$(./dump_time_domain_rx.sh [arg])                       #run the command, log info will be saved to $log
#echo "$log"                                                 #print the log is needed.
#filename=`echo "$out" | grep file: | cut -d ":" -f3`        #retrieve the filename from log.

source ./check_dfe_cap_core_map.sh

known_waveform_list=(
#list for RX time domain dump:
3186a4b1fcc7cc4375f90a788fb71b48 "FDD single tone 30Khz 25% scale at 61Msps time domain dump" 
05b35b703c659129117f5c9a7f95d6d6 "TDD single tone 30Khz 25% scale at 245Msps time domain dump for pattern 7624"
bccbdab7f62763014a6d2026ee99ef44 "FDD single tone 15Khz 25% scale at 61Msps time domain dump" 
9a5332e4ecf6fda434f66c1a2014e47b "TDD single tone 15Khz 25% scale at 61Msps time domain dump for pattern DDGUG"
d5fbdae4f8c3d684b00693d9b4f40b29 "TDD single tone 15Khz 25% scale at 61Msps time domain dump for pattern DDGGG GGUUG GGGGG UUUUG"
9a41fe86de17ed62d5060e17b6f0bd63 "TDD (3 6 1 4 0 0   2 10 2 2 0 0) single tone 30Khz 25% scale"
8c1d8814f1573e7fb9d0376f32e8a2f8 "400Mhz 120Khz FDD injection vector 1ms" 
d84fc5f9cae660ff56e77d37ea222da8 "G-FR1-A1-5_UL_20ms_100MHz_30kHz_TDD input waveform" 
8de025b9568c942f2fb0307ec761576c "G-FR1-A1-5_UL_20ms_100MHz_30kHz_TDD QEC passthrough input waveform." 
ed737e9cd9d7ed4ed204a441bc2a38af "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD input waveform before rxqec." 
2a43681e19555c9541d4c739734e857b "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD 20ms" 
40b99fdd5c53946a64c6104039e187d8 "100MHz_30kHz_FDD single tone 30Khz 25% scale 20ms time domain dump" 
0490e7f14f06bc0b320082b2bd9ee5ba "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD 20ms decimated" 
3b74043ceac96650d50322dde780fdf4 "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD 10ms" 
9edc0b65dbce197890cf9bf42beeb274 "G-FR1-A1-5msx4_UL_20ms_100MHz_30kHz_FDD 20ms rxqec coeff applied tap0." 
8dfba2375076aee731b6ae79bb14f7b0 "TM3.1 400Mhz 120Khz TX loopbacked to RX time domain reference 1.9Gsps RX 2x decimation ON." 
91ef6e6bc96b5aacc346718418cebd95 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps time domain reference 1.9Gsps." 
6a1bb47bc671ecc3731c94ea28b922c4 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps(stop10000) time domain 20ms dump" 
af807961c95043e91c29693a9801d7a0 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps(stop10000) time domain QEC imb applied 1ms dump" 
e1e76c5d211d3f17946d7f5478012991 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps(stop10000) time domain QEC imb+dc applied 1ms dump" 
36b7fe25aecfb93fd8d2cb8a6cff6f85 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps(stop10000) time domain 1ms dump" 
91e8342348e91b18316ff61057c846d5 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps(stop10000) time domain reference 1.9Gsps RX QEC tap0 applied." 
f3f5f54d0d1bac2183fe09fbf96aaf90 "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps time domain reference 1.9Gsps TXTDD RXFDD IQ swapped." 
c7770c80c6c83bed62903d57b1e2d8cf "TM3.1 400Mhz 120Khz TX loopbacked to RX 4xup new 32 taps time domain reference 1.9Gsps TXTDD RXFDD." 
a76af946a4bdfce384fb91524d55570c "TM3.1 400Mhz 120Khz TX loopbacked to RX time domain reference 983Msps RX 2x decimation OFF." 
0754541bc1515c7913b9a71140232a72 "TM3.1 200Mhz 60Khz TX loopbacked to RX time domain reference." 
b6c2ce4ae103c85572e16449051501cd "TM3.1 800Mhz 120Khz TX loopbacked to RX time domain reference." 
d2e886c9f9aecf470ce439a6ac35e783 "TM3.3_20MHz_30kHz_FDD TX loopbacked to RX RFNM with 17 samples delay time domain reference." 
5e5557ea955169e62fddb78040ac8004 "TM3.3_20MHz_30kHz_FDD TX loopbacked to RX RFNM with 1 sample delay time domain reference." 
fb6ada43df24254b500f84d7e9136c19 "Singletone 120Khz 1.9Gsps TDD RX dump 1ms"
c0936b41d74cb9661fc18703eaa6f614 "Singletone 120Khz 1.9Gsps FDD RX dump 1ms"
0)

md5sum_check()
{
	local ant=$1; local filename=$2
	checksum=`md5sum $filename`
	checksum=${checksum:0:32}
	echo md5sum $checksum
	echo

	check_known_waveform $checksum

	if [ $checksumpass = 1 ];then
		echo "***** CORRECT! CORRECT! CORRECT! ***** RX time domain ant $ant data are expected."
		echo
	fi
}

ant=0; sync_dump_txrx=(); sync_dump_ant=(); sync_dump_addr_la=(); sync_dump_size=(); sync_dump_offset=(); sync_dump_dpdout_dcm=()
size_hram=$((6*1024*1024))
offset_granul=0
num_32KB=""
time_len=""; arg_time_len=""; arg_mem_type=""
dump_via_hram=0
force_ddr=0
mem=0
num_counter=0
dcm=0
offset=0
pow=0

arg_parse()
{
	arg1=$1; arg2=${arg1:0:1}; arg3=${arg1:1:1}
	if 		([ $1 = HRAM ] || [ $1 = hram ]); 	then		dump_via_hram=1;arg_mem_type=$1
	elif 	([ $1 = H2M ] || [ $1 = h2m ]); 	then		size_hram=$((2*1024*1024)); offset_granul=6; dump_via_hram=1; arg_mem_type=$1
	elif 	([ $1 = DDR ] || [ $1 = ddr ]); 	then		force_ddr=1;arg_mem_type=$1
	elif 	[ $1 = mem ]; 	then		mem=1
	elif 	([ $1 = 0.5ms ] || [ $1 = .5ms ]); then			time_len=0.5; arg_time_len=0.5
	elif 	[ $1 = 1ms ]; then			time_len=1; arg_time_len=$1
	elif 	[ $1 = 2ms ]; then			time_len=2; arg_time_len=$1
	elif 	[ $1 = 5ms ]; then			time_len=5; arg_time_len=$1
	elif 	[ $1 = 10ms ]; then			time_len=10; arg_time_len=$1
	elif 	[ $1 = 20ms ]; then			time_len=20; arg_time_len=$1
	elif 	[ $1 = 40ms ]; then			time_len=40; arg_time_len=$1
	elif 	[ $1 = dcm ]; then			dcm=1
	elif 	[ $1 = pow ]; then			pow=1
	elif 	[ ${arg1:0:7} = offset= ]; 	then		offset=${arg1:7}; offset=$((offset)); [ $offset -gt $((0x3F)) ] && { echo -e "***ERROR: offset must be no larger than $((0x3F))\n"; exit 1; }
	elif 	[ $1 = fast ]; then			fast=1
	elif 	[ $arg2 = + ]; then			ant=$((arg3%$NUM_ANTS)); sync_dump_ant=(${sync_dump_ant[@]} $ant)
	else
		if [ $num_counter = 0 ];then	((num_counter++));	ant=$(get_ant_id_from_arg $1); [ $ant = null ] && { echo Wrong Argument: $1; print_usage; exit 1; } || sync_dump_ant=(${sync_dump_ant[@]} $ant)
		elif [ $num_counter = 1 ];then	((num_counter++));	num_32KB=$(($1));
		else							echo Wrong Argument: $1; print_usage; exit 1
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $lphy = 1 ] && { echo -e "***ERROR: This command is not supported for option lphy.\n"; exit 1; }
[ $fr1_used = 0 ] && ant=$(((ant%2)+4))
[ $buffer_mode = 1 ] && { echo -e "***ERROR: Current mode is buffer mode. Should not run this script before buffer mode is stopped.\n"; exit 1; }
[ ${#sync_dump_ant[@]} = 0 ] && sync_dump_ant=($ant)
[ ${#sync_dump_ant[@]} -gt 1 ] && echo "Synced RX dump for ${#sync_dump_ant[@]} antennas: ${sync_dump_ant[@]}"

for ((i=0;i<${#sync_dump_ant[@]};i++))
do
	check_ant_enable_rx ${sync_dump_ant[i]}
	sync_dump_txrx=(${sync_dump_txrx[@]} 1)
	sync_dump_dpdout_dcm=(${sync_dump_dpdout_dcm[@]} $dcm)
done


[ "$time_len" != "" ] && dump_time_len=$time_len

rxcore=${antrx[$ant]}
rid=${ridant[$ant]}

#get_chan_para $ant $rxcore
baseband_rxsps=${bbsps_rx[ant]}; rxaxiq=${axiqsps_rx[ant]}; option8=${option8_rx[ant]}
([ $baseband_rxsps = $rxaxiq ] && [ $dcm = 1 ]) && echo "dcm is not valid in current configuration, ignored."
num_32KB=$((num_32KB))

((sps=rxaxiq*(1-dcm) + baseband_rxsps*dcm ))  
[ $dump_time_len = 0.5 ] && dump_time_len_double=1 || dump_time_len_double=$((dump_time_len*2))
if [ $num_32KB -eq 0 ];then
	((size=sps*4*$dump_time_len_double/2))
	dump_filename=rx_timedomain_$dump_time_len\ms_$sps\ksps_dump_ant
else
	if [ $num_32KB -lt 1024 ];then
		((size=num_32KB*32768))
		dump_filename=rx_timedomain_$((num_32KB*32))KB_$sps\ksps_dump_ant
	else
		((size=num_32KB))
		dump_filename=rx_timedomain_$num_32KB\_$sps\ksps_dump_ant
	fi
fi

size_32KB_aligned=$(((size+32767)/32768*32768))
extra_size=$((size_32KB_aligned-size))
size_32KB_aligned_per_ant=$size_32KB_aligned
size_32KB_aligned=$((size_32KB_aligned*${#sync_dump_ant[@]}))
warn_saturated=""
dump_1time()
{
	for ((i=0;i<${#sync_dump_ant[@]};i++))
	do
		sync_dump_addr_la=(${sync_dump_addr_la[@]} $((addr_phy+i*size_32KB_aligned_per_ant)))
		sync_dump_size=(${sync_dump_size[@]} $size_32KB_aligned_per_ant)
		sync_dump_offset=(${sync_dump_offset[@]} $offset)
	done
	addr_vir=`phy2vir $addr_phy`
	log=`sync_dump_time_domain_1time`; log1=`echo "$log" | grep ERROR`; [ $? -eq 0 ] && { echo $log; exit 1; }
	
	for ((i=0;i<${#sync_dump_ant[@]};i++))
	do
		addr_vir_ant=$((addr_vir+i*size_32KB_aligned_per_ant))
		if [ $mem = 0 ];then
			dump_filename=$dump_filename${sync_dump_ant[i]}.bin
			dumpfile $addr_vir_ant $dump_filename $size
			echo "Antenna ${sync_dump_ant[i]} dumping done, size:$size, address:`printf 0x%x $addr_vir_ant`, file:$dump_filename"
			[ $fast = 0 ] && { md5sum_check ${sync_dump_ant[i]} $dump_filename; check_error_ant ${sync_dump_ant[i]}; }
		else
			echo "Antenna ${sync_dump_ant[i]} dumping done, size:$size, address:`printf 0x%x $addr_vir_ant`"
		fi
		
		if ([ $fast = 0 ] && [ $pow = 1 ]);then
		dump_size=$((10*14*65536)); [ $dump_size -gt $((size_32KB_aligned_per_ant/4)) ] && dump_size=$((size_32KB_aligned_per_ant/4))
		log=`./utils/power $addr_vir_ant 0 $((size_32KB_aligned_per_ant/4))`
		eval "$log"

		v_tx_pow_acc=$power_IQ
		v_tx_pow_num_samples=$num_samples_valid
		sample_power=($(echo $v_tx_pow_acc $v_tx_pow_num_samples | awk '{ x=10*(log($1/$2)/log(10)); printf("%f %3.1f %d\n", $1/$2, x, x); }'))
		[ ${sample_power[1]} = -inf ] && { sample_power[1]=-99999; sample_power[2]=-99999; }  #negative infinite
		echo "Sample power at ADC: ${sample_power[0]}/sample, ${sample_power[1]} dB, max I=$max_I, max Q=$max_Q, dc_I=$dc_I, dc_Q=$dc_Q"
		[ $((sample_power[2])) -lt -15 ] && echo -e "***WARNING: RX ant ${sync_dump_ant[i]} ADC input power does not reach 10-15 dB, your test is not fully utilizing the DAC dynamic range!\n"
		
		max_IQ100=`echo $max_IQ | awk '{ abs_val = ($1 >= 0) ? $1 : -$1; printf("%d\n", abs_val*100); }'`
		[ $max_IQ100 -ge 97 ] && warn_saturated="***WARNING: RX ant ${sync_dump_ant[i]} ADC input is saturated, max value $max_IQ\n"
		fi
	done
}

dump_via_hram_mlti_times()
{
	([ ${#sync_dump_ant[@]} -gt 1 ] || [ $mem = 1 ]) && { echo -e "***ERROR: HRAM available size $size_hram is not enough for required dump size $size_32KB_aligned.\n"; exit 1; }
	start_hram_vir=`printf "0x%x" $((HRAMaddr_vir+6*1024*1024-size_hram))`
	((start_hram_phy=HRAMaddr_phy+6*1024*1024-size_hram))
	[ $fast = 0 ] && echo Using HRAM size $size_hram starting from $start_hram_vir as intermediate buffer for dumping...
	
	flag_addr=`printf "0x%x" $((start_hram_vir+size_hram-4))`
	((num_chunks=size_32KB_aligned/size_hram))
	((size_left=size_32KB_aligned-num_chunks*size_hram))
	[ $size_left = 0 ] && { ((num_loop=num_chunks)); size_left=$size_hram; } || ((num_loop=num_chunks+1))
	[ $num_loop -ge 64 ] &&  { echo ***Error: HRAM available size too small, num of blocks exceeds 64.; exit 1; }
	
	dump_filename=$dump_filename$ant.bin
	[ -f $dump_filename ] && rm $dump_filename
	lsb=`printf "0x%08x" $(( ((size_hram/32/1024)<<20) + (start_hram_phy>>12) ))`
	
	[ $fast = 0 ] && echo -n Dumping in progress, waiting...
	for ((i=0;i<$(($num_loop));i++))
	do
		[ $fast = 0 ] && echo -n "$(($i*100/num_loop))%"
		msb=`printf "0x%08x" $((0x0A180000 + (tid<<15) + (dcm<<13) + (offset_granul<<8) + i))`
		[ $tx_fdd = 0 ] && clear_mem $start_hram_vir $size_hram
		devmem $flag_addr w 0x1234abcd
		
		vspa_mbox send $rxcore $host_vspa_mbox_id $msb $lsb;
		wait_for_flag_change $flag_addr 0x1234abcd

		size0=$size_hram
		if [ $((i)) -eq $((num_loop-1)) ];then
		size0=$((size_left-extra_size))
		fi
		
		if [ $mem = 0 ];then
			dumpfile $start_hram_vir temp_dump.bin $size0
			cat temp_dump.bin >> $dump_filename
		fi
	done
	[ $fast = 0 ] && echo 100%
	if [ $mem = 0 ];then 
		rm temp_dump.bin; 
		echo Antenna $ant dumping done, size:$size, file:$dump_filename
		[ $fast = 0 ] && { md5sum_check $ant $dump_filename; check_error_ant $ant; }
	else 
		echo Antenna $ant dumping done, size:$size, sampling rate:$sps\ksps, address:$start_hram_vir
	fi
}

end_hram=$next_HRAMaddr_phy
available_hram=$((HRAMaddr_phy+HRAM_size-end_hram))

if [ $((dump_via_hram+force_ddr)) = 0 ];then
	if [ $size_32KB_aligned -le $available_hram ]; then addr_phy=$((HRAMaddr_phy+HRAM_size-available_hram)); dump_1time; exit 0
	elif ([ $sps -ge 983040 ] || [ $baseband_rxsps -ge 491520 ])then	dump_via_hram=1
	fi
fi

if [ $dump_via_hram = 1 ];then 	
	if [ $size_hram -gt $available_hram ];then
		size_hram=$((available_hram/1024/1024))
		if [ $size_hram -ge 4 ]; then
			size_hram=$((4*1024*1024));	offset_granul=7;
		elif [ $size_hram -ge 2 ]; then
			size_hram=$((2*1024*1024));	offset_granul=6;
		elif [ $size_hram -ge 1 ]; then
			size_hram=$((1*1024*1024));	offset_granul=5;
		else
			echo Available HRAM size is too small to use. command failed; exit 1;
		fi
	fi
	if [ $size_32KB_aligned -le $available_hram ];then
		addr_phy=$((HRAMaddr_phy+HRAM_size-available_hram)); dump_1time;
	else				
		dump_via_hram_mlti_times
	fi
else
	malloc_for_dump $size_32KB_aligned
	addr_phy=$addr_dump 							
	dump_1time
fi
echo -e "$warn_saturated"
