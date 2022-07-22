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
echo "usage: ./send_singletone.sh [ant id] [frequency] [amplitude] [-y] [I|Q] [add]"
echo "usage: ./send_singletone.sh [ant id] stop"
echo "    all the arguments are optional, in this case the script will send lowest subcarrier freq singletone with 80% scale amplitude to ant 0(FR1) or ant 4(FR2)"
echo "    ant id:    antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels."
echo "    frequency: frequency of the singletone desired, such as 1000000 represents 1Mhz. Can be negative frequency."
echo "    amplitude: aplitude of the singletone, legal values are 1-100 representing 1% to 100% of DAC full scale, such as 25 representing 25% of DAC full scale. NOTE that high amplitude may damage PA. When amplitude is higher than 40%, a warning will be prompted for users to make sure the amplitude is safe."
echo "    -y:        confirm the configured amplitude is safe to PA. with this argument the script will set the amplitude without any warning or prompt."
echo "    I:         send single tone on I path only, Q path no signal."
echo "    Q:         send single tone on Q path only, I path no signal."
echo "    add:       add current single tone onto previous single tones in order to send multiple single tones simultaneously. Maximum 16 single tones."
echo "    stop:      stop sending single tone"
echo "example: ./send_singletone.sh 0 1000000 80     will send on antenna 0 with 1Mhz 80% scale single tone."
echo "example: ./send_singletone.sh 0 -1000000 80    will send on antenna 0 with negative 1Mhz 80% scale single tone."
echo "example: ./send_singletone.sh 2 2000000 100 I  will send on antenna 2 with 2Mhz 100% scale single tone on I path only."
echo
}

source ./check_dfe_cap_core_map.sh

freq=""
amp=25; yesno=0  #default amplitude 25% full scale
ant=0
Ionly=0
Qonly=0
stopping=0
add_tone=0
num_counter=0
rx=0
arg_parse()
{
	arg=$1
	if [ "${arg: -4}" = help ]; then				print_usage; exit 1;
	elif ([ $1 = stop ] || [ $1 = dis ]); then		stopping=1
	elif [ $1 = I ]; then							Ionly=1
	elif [ $1 = fast ]; then						fast=1
	elif [ $1 = rx ]; then							rx=1
	elif [ $1 = tx ]; then							rx=0
	elif [ $1 = -y ]; then							yesno=1
	elif [ $1 = Q ]; then							Qonly=1
	elif [ $1 = add ]; then							add_tone=1
		[ $((vspa_image_version)) -lt $((0x307)) ] && { echo Sending multiple single tone is only supported since VSPA images version v307, current version is $vspa_image_version; exit 1; }
	else
		if [ $num_counter = 0 ];then
			ant=$(get_ant_id_from_arg $1)
			[ $ant = null ] && { echo Wrong Argument; print_usage; exit 1; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			freq=$1
			num_counter=$((num_counter+1))
		elif [ $num_counter = 2 ];then
			amp=$(($1))
			[ $amp -gt 100 ] && amp=100
			num_counter=$((num_counter+1))
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $lphy = 1 ] && { echo -e "***ERROR: This command is not supported for option lphy.\n"; exit 1; }
if ([ $((amp)) -gt 40 ] && [ $yesno = 0 ] && [ $rx = 0 ]);then
	echo "***WARNING: High amplitude may damage PA. The amplitude you set is $amp% full scale."
	echo -n "Are you sure the amplitude you set is safe?  Input Y to Continue, N to Abort: "
	read yesno
	([ "$yesno" != Y ] && [ "$yesno" != y ]) &&  { echo Command Aborted; exit 1; }
fi	

if [ $rx = 0 ];then
	check_ant_enable_tx $ant
	core=${anttx[$ant]}
	trid=${tidant[$ant]}
	get_chan_para $ant $core
	sps=$txaxiq
else
	check_ant_enable_rx $ant
	core=${antrx[$ant]}
	trid=${ridant[$ant]}
	get_chan_para $ant $core
	sps=$rxaxiq
fi

[ "$freq" = "" ] && ((freq=$scs*1000))

tag_Ionly=("" ", on I path only Q path no signal")
tag_Qonly=("" ", on Q path only I path no signal")

if [ $stopping = 0 ];then
echo Sending single tone $freq Hz with $amp% scale to antenna $ant ${tag_Ionly[$Ionly]} ${tag_Qonly[$Qonly]}, SPS=$sps Ksps
else
echo Stopping single tone to antenna $ant
fi

frequency=$freq
amplitude=$amp
((amp=0x7FF*amp/100))

freq=$(echo $freq $sps | awk '{ freq=4294967296*$1/$2/1000; printf("%d",freq); }') #convert frequency in Hz to frequency value used by NCO
if [ $freq -lt 0 ];then
((freq=freq-1))    #the freq factor is 1's complement, equals to 2'complement plus 1
echo Negative frequency!
fi
((freq=freq&0xFFFFFFFF))  #get 32LSB

if [ $stopping = 0 ];then
((msb=0x0A0E0000+(rx<<20)+(add_tone<<22)+(trid<<15)+(Ionly<<12)+(Qonly<<14)+amp))
else
((msb=0x0A0E2000+(rx<<20)+(trid<<15)+(Ionly<<12)+amp))
fi

msb=`printf "0x%08x" $msb`
lsb=`printf "0x%08x" $freq`
vspa_mbox_ifsend $core $host_vspa_mbox_id $msb $lsb

if [ $fast = 0 ];then
echo vspa_mbox_ifsend $core $host_vspa_mbox_id $msb $lsb
num_tones=(ONE MULTIPLE)
txrxsend=("TX is sending" "RX is injecting")
txrxstop=("TX has stopped sending" "RX has stopped injecting")
if [ $stopping = 0 ];then
echo -e "Antenna $ant ${txrxsend[rx]} ${num_tones[add_tone]} time-domain single tone(s) now.\n"
else
echo -e "Antenna $ant ${txrxstop[rx]} time-domain single tone.\n"
fi

[ $sinad = 0 ] && check_error_ant $ant
fi
