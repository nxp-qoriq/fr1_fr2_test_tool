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
echo "usage: ./update_phase_compensation_coeff.sh [ant id] [coeff_bin_file|addr|arfcn=] [dis] [tx|rx] [scale=scaling_factor]"
echo "  ant id        : antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.  "
echo "  coeff_bin_file: filename of the coefficients, each coeff has 8 bytes (I and Q each 4 bytes in float format). total num of coefficients: scs15 7, scs30 14, scs120 56"
echo "  addr          : must starts with 0x, the coefficients will be updated from this address. addr is in host side view."
echo "  arfcn=idx     : arfcn number, idx range (0 ~ 3279165)"
echo "  dis           : disable cell tracking"
echo "  tx|rx         : TX or RX, if not specified, TX will be used"
echo "  scaling_factor: scale phase compensation coefficients by this factor, percentage. This can be used as input scaling"
echo
}

source ./check_dfe_cap_core_map.sh

ant=0; dis=0; filename=""; txrx=TX
arfcn=""
input_scaling_factor=""

arg_parse()
{
	arg=$1
	if ([ $1 = help ] || [ $1 = -help ]); then			print_usage; exit 1;
	elif [ $1 = dis ]; then								dis=1
	elif [ $1 = 0 ]; then								ant=$1
	elif [ $1 = 1 ]; then								ant=$1
	elif [ $1 = 2 ]; then								ant=$1
	elif [ $1 = 3 ]; then								ant=$1
	elif [ $1 = 4 ]; then								ant=$1
	elif [ $1 = 5 ]; then								ant=$1
	elif [ $1 = tx ]; then								txrx=TX
	elif [ $1 = rx ]; then								txrx=RX
	elif [ ${arg:0:6} = scale= ];then					input_scaling_factor=${arg:6}
	elif [ ${arg:0:6} = arfcn= ];then					
									arfcn=${arg:6}
									[ $arfcn -lt 0 ]       && { echo -e "Illegal ARFCN\n"; echo; print_usage; exit 1; }
									[ $arfcn -gt 3279165 ] && { echo -e "Illegal ARFCN\n"; echo; print_usage; exit 1; }
	else												filename=$1
	fi
}

for i in "$@"
do
	arg_parse $i
done


if [ $txrx = TX ];then	
	check_ant_enable_tx $ant; cmd=0x18000000; core=${anttx[$ant]}; trid=${tidant[$ant]}
else 					
	check_ant_enable_rx $ant; cmd=0x18400000; core=${antrx[$ant]}; trid=${ridant[$ant]}
fi

get_chan_para $ant $core

addr_phy=$addr_dump
addr_vir=`phy2vir $addr_phy`

coeff_filename=./phcom_coeff_${txrx}_ant$ant.bin
expected_size=$((sym_num_1m/2*8))

if [ $dis = 0 ];then
	if [ "$arfcn" != "" ];then
	SYMB_LEN=1024
	CP_LEN=72
	precision=30
	N=$((sym_num_1m/2))
	scsHz=$((scs*1000))
	
	fc=$(echo "scale=$precision; 3000000000+15000*(${arfcn#-}-600000)"|bc);
	[ $arfcn -lt 600000 ] && { fc=$(echo "scale=$precision; 5000*(${arfcn#-})"|bc); }
	[ $arfcn -ge 2016667 ] && { fc=$(echo "scale=$precision; 24250080000+60000*(${arfcn#-}-2016667)"|bc); }

	pi=$(echo "scale=$precision; 4*a(1)" | bc -l) 
	f_times_T=$(echo "scale=$precision; $fc/$scsHz*($SYMB_LEN+$CP_LEN)/$SYMB_LEN"|bc)
	
	[ $txrx = TX ] && {  f_times_T=$(echo "$f_times_T*(-1)"|bc ); }
	
	
	for ((i=0; i<$N; i++))
	do
		t_c=$(echo "scale=$precision; c(2*$pi*$f_times_T*$i)"|bc -l)
		t_c=(`./utils/hex2float -r $t_c`)
		table[2*$i]=$t_c
		./utils/memrw w 32 $((addr_vir+i*8)) ${table[2*$i]}
		
		t_s=$(echo "scale=$precision; s(2*$pi*$f_times_T*$i)"|bc -l)
		t_s=(`./utils/hex2float -r $t_s`)
		table[2*$i+1]=$t_s
		./utils/memrw w 32 $((addr_vir+i*8+4)) ${table[2*$i+1]}

		#echo $i: ${table[2*$i]}  ${table[2*$i+1]}
	done
	tag="$txrx phase compensation coefficients updated to antenna $ant for arfcn=$arfcn from address $addr_vir"	
	
	elif [ "$filename" != "" ];then
	if [ ${filename:0:2} != 0x ];then
	[ -f $filename ] || { echo -e "***ERROR: File $filename does not exist\n"; echo; print_usage; exit 1; }
	filesize=$(stat --format=%s $filename)
	[ $filesize -ne $expected_size ] && { echo -e "***ERROR: File size $filesize is not expected size $expected_size. Command failed\n"; exit 1; }
	loadfile $addr_vir $filename
	tag="$txrx phase compensation coefficients updated to antenna $ant from file $filename from address $addr_vir"
	else
	src_addr_vir=$filename
	mem_addr_check_host_view $src_addr_vir $expected_size
	./utils/memcpy $src_addr_vir $addr_vir $((expected_size/4))
	tag="$txrx phase compensation coefficients updated to antenna $ant from address $src_addr_vir"
	fi
	
	else
	
	if [ -f $coeff_filename ];then
	loadfile $addr_vir $coeff_filename $expected_size
	tag="$txrx phase compensation coefficients loaded from file $coeff_filename"
	else
	for((i=0;i<expected_size/8;i++))
	do
		./utils/memrw w 64 $((addr_vir+i*8)) 0x3f800000
	done
	tag="$txrx phase compensation coefficients set to passthrough on antenna $ant from address $addr_vir"
	fi
	
	fi
else
for((i=0;i<expected_size/8;i++))
do
	./utils/memrw w 64 $((addr_vir+i*8)) 0x3f800000
done
tag="$txrx phase compensation coefficients set to passthrough on antenna $ant from address $addr_vir"
fi
[ -f $coeff_filename ] && rm $coeff_filename; dumpfile $addr_vir $coeff_filename $((expected_size)); echo Updated coeff saved to file $coeff_filename  #keep the coefficients to file

[ "$input_scaling_factor" = "" ] && input_scaling_factor=`./utils/memrw r 32 $((test_tool_env_tx_scaling_input+ant*4))`
./utils/scale $((addr_vir)) $((addr_vir)) $((sym_num_1m/2*2)) $((input_scaling_factor)) float  #scaling
./utils/memrw w 32 $((test_tool_env_tx_scaling_input+ant*4)) $((input_scaling_factor))

vspa_mbox_ifsend $core $host_vspa_mbox_id $((cmd+(trid<<23)+sym_num_1m/2)) $addr_phy
echo vspa_mbox_ifsend $core $host_vspa_mbox_id `HEX $((cmd+(trid<<23)))` `HEX $addr_phy`

echo $tag
echo -e "Input scaled to $((input_scaling_factor))%\n"
check_error_ant $ant
