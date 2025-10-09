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

num_idx_dc=10

print_usage()
{
echo
echo "usage ./sinad_test.sh <ant_id> <start_point> <num_points> [dest_address]"
echo "ant_id: 4 or 5 for HSADC0 and 1"
echo "start_point: signal start point in the 8192 FFT output, range 0-8191"
echo "num_points:  number of signal points from start point"
echo "dest_address: the address in host view(40bit) where SINAD result(24bytes needed) are stored, must be 4096 bytes aligned. must be on DDR.  if not specified, test tool will assign the address."
echo "example: ./sinad_test.sh 4 1660 13      will test SINAD for antenna 4, signal starts from point 1660 and end at point 1672 total 13 points(400Mhz single tone at 1.9Gbps)."
echo "example: ./sinad_test.sh 4 2910 13      will test SINAD for antenna 4, signal starts from point 2910 and end at point 2922 total 13 points(700Mhz single tone at 1.9Gbps)."
echo "example: ./sinad_test.sh 4 3327 13      will test SINAD for antenna 4, signal starts from point 3327 and end at point 3339 total 13 points(400Mhz single tone at 983Mbps)."
echo
}

[ $# -lt 3 ] && { echo Wrong arguments; print_usage; exit; }

start_idx_sig=$2
num_idx_sig=$3

[ $start_idx_sig -gt 8191 ] && { echo Wrong start_point; print_usage; exit; }
[ $((start_idx_sig+num_idx_sig)) -gt 8191 ] && { echo Wrong start_point or num_points, end point exceeds 8191; print_usage; exit; }

source ./check_dfe_cap_core_map.sh
fast=1

ant=$(get_ant_id_from_arg $1)
[ $ant = null ] && { echo Wrong Argument; print_usage; exit; }

[ $((ant)) -lt 4 ] &&  { echo Wrong ant id: ant id must be 4 or 5; print_usage; exit; }

[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_RX)) = 0 ] && { echo ***ERROR: Current RX ant $ant is not enabled.; exit 1; }

rxcore=${antrx[$ant]}
rid=${ridant[$ant]}
get_chan_para $ant $rxcore

[ $sinad_enable = 0 ] && { echo SINAD measurement is disabled in current VSPA images, command failed; echo; exit; }

if [ $# -ge 4 ];then
addr_vir=$(($4))
[ $addr_vir -eq 0 ] && { echo "*** Error: Dest address is 0, command failed."; print_usage; echo; exit; }
[ $((addr_vir&0xFFF)) -ne 0 ] && { echo "*** Error: Dest addr is not 4096 aligned, command failed."; echo; exit; }
addr_vir=`printf "0x%x" $addr_vir`
addr_phy=`vir2phy $addr_vir`
else
addr_phy=$addr_dump
addr_vir=`phy2vir $addr_phy`
fi

((msb=0x0A300000+start_idx_sig))
((lsb=(num_idx_sig<<26)+(num_idx_dc<<20)+(addr_phy>>12)))

flag_invalid=0x1234abcd

./utils/memrw w 32 $addr_vir $flag_invalid  #clear SINAD buffer

if [ $fast = 0 ];then
echo ./utils/memrw w 32 $addr_vir $flag_invalid
echo vspa_mbox send $rxcore $host_vspa_mbox_id $msb $lsb
fi

vspa_mbox send $rxcore $host_vspa_mbox_id $msb $lsb

addrQ=`printf "0x%08x" $((addr_vir+4))`
sinadI=`./utils/memrw r 32 $addr_vir`
counter=1000
while [ $((sinadI)) -eq $((flag_invalid)) ]
do
	sinadI=`./utils/memrw r 32 $addr_vir`
	((counter--))
	[ $counter -eq 0 ] && { echo "*** ERROR: VSPA response timeout, command failed."; echo; exit; }
done

if [ $fast = 0 ];then
check_error_ant $ant

echo "*** NOTE:"
echo "*** During SINAD measurement RX AXIQ DMA can not be serviced in time, which may cause RX AXIQ errors."
echo "*** VSPA will recover the errors so users can ignore the errors and continue to do SINAD measurement."
echo


echo SINA measurement result:
addr_test1=`printf "0x%08x" $((addr_vir+8))`
echo Noise Win Start = $((`./utils/memrw r 32 $addr_test1`))
addr_test2=`printf "0x%08x" $((addr_vir+12))`
echo "Noise Win End   "= $((`./utils/memrw r 32 $addr_test2`))
addr_test3=`printf "0x%08x" $((addr_vir+16))`
echo "Signal Start    "= $((`./utils/memrw r 32 $addr_test3`))
addr_test4=`printf "0x%08x" $((addr_vir+20))`
echo "Signal Len      "= $((`./utils/memrw r 32 $addr_test4`))

fi

echo SINAD_I at address: $addr_vir, Q at address $addrQ, data type is 32-bit float little endian.
echo "SINAD_I: $(eval "./utils/hex2float $(./utils/memrw r 32 $addr_vir)")"
echo "SINAD_Q: $(eval "./utils/hex2float $(./utils/memrw r 32 $addrQ)")"
echo
