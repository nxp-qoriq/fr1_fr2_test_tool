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

source ./check_dfe_cap_core_map.sh

print_usage()
{
echo "usage: ./update_filter_coeff.sh <ant id> <filter_type> <coeff_filename>"
echo "ant id:           antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels."
echo "filter_type:      up 4xup 2xdown 4xdown rx"
echo "coeff_filename:   filename of the coeff."
echo "example: ./update_filter_coeff.sh 4 4xup f.bin    will update 4x upsampling filter coeff from f.bin on ant 4."
echo
}

get_addr_rx_fir_taps() #$1=core
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + addr_rx_fir_filter_taps))
	addr=`./utils/memrw r 16 $addr_vir`; [ $((addr)) -eq 0 ] && { echo -e "***ERROR: Filter is not present in current ant, filter taps address is 0.\n"; exit 1; }
	addr=$((addr<<7))
	echo `get_vspa_dmem_addr $1 $addr`
}

get_addr_downsampling_taps() #$1=core
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + RXPATH_STATUS_OFFSET_ADDR_DOWNSAMPLING_TAPS))
	addr=`./utils/memrw r 16 $addr_vir`; [ $((addr)) -eq 0 ] && { echo -e "***ERROR: Filter is not present in current ant, filter taps address is 0.\n"; exit 1; }
	addr=$((addr<<7))
	echo `get_vspa_dmem_addr $1 $addr`
}
get_addr_upsampling_taps() #$1=core
{
	local addr_vir=$(( $(get_vspa_dmem_base $1) + TXPATH_STATUS_OFFSET_ADDR_UPSAMPLING_TAPS))
	addr=`./utils/memrw r 16 $addr_vir`; [ $((addr)) -eq 0 ] && { echo -e "***ERROR: Filter is not present in current ant, filter taps address is 0.\n"; exit 1; }
	addr=$((addr<<7))
	echo `get_vspa_dmem_addr $1 $addr`
}

ant=0
dis=0
filter_type=0
filename=0

arg_parse()
{
	arg=$1
	if [ $1 = dis ]; then		dis=1
	elif [ $1 = 2xup ];then		filter_type=2
	elif [ $1 = 2xup1 ];then	filter_type=2
	elif [ $1 = 2xup2 ];then	filter_type=2
	elif [ $1 = 4xup ];then		filter_type=2
	elif [ $1 = up ];then		filter_type=2
	elif [ $1 = 4xdown ];then	filter_type=3
	elif [ $1 = 2xdown ];then	filter_type=3
	elif [ $1 = down ];then		filter_type=3
	elif [ $1 = rx ];then		filter_type=4
	elif [ $1 = 0 ]; then 		ant=$1
	elif [ $1 = 1 ]; then 		ant=$1
	elif [ $1 = 2 ]; then 		ant=$1
	elif [ $1 = 3 ]; then 		ant=$1
	elif [ $1 = 4 ]; then 		ant=$1
	elif [ $1 = 5 ]; then 		ant=$1
	else
		filename=$1
		[ -f $filename ] || { echo -e "***ERROR: File $filename doesn't exist, command failed\n"; print_usage; exit 1; }
		filesize=$(stat --format=%s $filename)
	fi
}

for i in "$@"
do
	arg_parse $i
done


if [ $filter_type -lt 3 ];then
check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

txcore=${anttx[$ant]}
tid=${tidant[$ant]}

get_chan_para $ant $txcore
core=$txcore

else
check_ant_enable_rx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_RX)) = 0 ] && { echo ***ERROR: Current RX ant $ant is not enabled.; exit 1; }

rxcore=${antrx[$ant]}
rid=${ridant[$ant]}

get_chan_para $ant $rxcore
core=$rxcore
fi

[ $((vspa_image_version)) -lt $((0x420)) ] && { echo -e "***ERROR: Version earlier than v420 does not support this command.\n"; print_usage; exit 1; }

if [ $filter_type -eq 4 ];then  #rx fir filter
	[ $rx_lpf_63taps_enable = 1 ] || { echo -e "***ERROR: RX LP Filter doesn't exist in currect VSPA image, command failed\n"; exit 1; }
	addr_vir=$(HEX `get_addr_rx_fir_taps ${slave_core[core]}`)
	num_taps=63
	backup_filename=backup_filter_coeff_rx_fir_${num_taps}taps.bin
	[ -f $backup_filename ] || { dumpfile $addr_vir $backup_filename $((num_taps*4)); echo Original filter coeff backed up to $backup_filename; }
	if [ $dis = 1 ];then
		./utils/memset $addr_vir $((num_taps-1)) 0
		./utils/memrw w 32 $((addr_vir+4*(num_taps/2))) 0x3f800000 #write the middle tap to 1.0 for passthrough
		echo RX LPF filter taps at address $addr_vir are set to passthrough on ant $ant.
	else
		[ $filesize -ne $((num_taps*4)) ] && { echo -e "***ERROR: File size $filesize is not expected $((num_taps*4)).\n"; exit 1; }
		loadfile $addr_vir $filename
		echo RX LPF filter taps are updated at address $addr_vir from file $filename on ant $ant.
	fi

elif [ $filter_type -eq 3 ];then  #2xdown
	addr_vir=$(HEX `get_addr_downsampling_taps ${slave_core[core]}`)
	backup_filename=backup_filter_coeff_downsampling_${num_downsampling_taps}taps.bin
	[ -f $backup_filename ] || { dumpfile $addr_vir $backup_filename $((num_downsampling_taps*4)); echo Original filter coeff backed up to $backup_filename; }
	if [ $dis = 1 ];then
		./utils/memset $addr_vir $((num_downsampling_taps-1)) 0
		./utils/memrw w 32 $((addr_vir+4*(num_downsampling_taps-1))) 0x3f800000 #write the last tap to 1.0 for passthrough
		echo Down sampling filter taps at address $addr_vir are set to passthrough on ant $ant.
	else
		[ $filesize -ne $((num_downsampling_taps*4)) ] && { echo -e "***ERROR: File size $filesize is not expected $((num_downsampling_taps*4)).\n"; exit 1; }
		loadfile $addr_vir $filename
		echo Down sampling filter taps are updated at address $addr_vir from file $filename on ant $ant.
	fi
	
elif [ $filter_type -eq 2 ];then  #4xup
	upsampling_ratio=$((axiqsps_tx[ant]/bbsps_tx[ant]))
	ntaps=$up1
	[ $upsampling_ratio == 4 ] && filter_taps_ratio=2 || filter_taps_ratio=1
	addr_vir=$(HEX `get_addr_upsampling_taps ${slave_core[core]}`)
	backup_filename=backup_filter_coeff_upsampling_${ntaps}taps.bin
	[ -f $backup_filename ] || { dumpfile $addr_vir $backup_filename $((ntaps*filter_taps_ratio*4)); echo Original filter coeff backed up to $backup_filename; }
	if [ $dis = 1 ];then
		./utils/memset $addr_vir $(((ntaps-upsampling_ratio)*filter_taps_ratio)) 0
		./utils/memset $((addr_vir+4*(ntaps-upsampling_ratio)*filter_taps_ratio)) $((upsampling_ratio*filter_taps_ratio)) 0x3f800000 #write the last tap to 1.0 for passthrough
		echo Up sampling filter taps at address $addr_vir are set to passthrough on ant $ant.
	else
		[ $filesize -ne $((ntaps*filter_taps_ratio*4)) ] && { echo -e "***ERROR: File size $filesize is not expected $((ntaps*filter_taps_ratio*4)).\n"; exit 1; }
		loadfile $addr_vir $filename
		echo Up sampling filter taps are updated at address $addr_vir from file $filename on ant $ant.
	fi
else
	echo -e "***ERROR: Filter type unsupported or not specified, command failed\n" 
	print_usage
	exit
fi
check_error_ant $ant
exit 0;
