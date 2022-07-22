#!/bin/bash
# Copyright 2024 NXP
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
echo "usage ./dfe_state.sh [ant_id] [stop|search|attach|normal|track|track=a:b:c:d:e] [apply=a:b] [carrier=frequency]"
echo "  This script is used to change DFE state between cell search, cell attach and normal mode. This script should be run after channels have started"
echo "	ant_id:       0-5 representing the 6 DCS channels. if not specified, ant 0 will be used"
echo "	search|attach|normal|track:   mode to set. if not specified, normal mode will be used"
echo "	carrier:      Carrier Frequency in Hz. 3400000000 Hz default value"
echo "  track=a:b:c:d:e               set SSB info for cell tracking, a,b,c,d,e are ssb_period,ssb_sym_id,ssb_re_offset,nid2,nid1"
echo "  apply=a:b                     enables the correction for AFC/TOC based on SSB measurements"
echo "  example:  ./dfe_state.sh 0 search           will set ant0 to work in cell search mode"
echo "  example:  ./dfe_state.sh 0 track            will set ant0 to work in cell track mode, SSB info will be used from config.dat"
echo "  example:  ./dfe_state.sh 0 track=a:b:c:d:e  will set ant0 to work in cell track mode, SSB info will be set to a,b,c,d,e"
echo "  example:  ./dfe_state.sh 0 track=a:b:c:d:e carrier=3400000000 apply=1:1  will set ant0 to work in cell track mode, SSB info will be set to a,b,c,d,e, carrier=3.4Ghz and AFC=TOC=1, all corrections will be applied"
echo
}

source ./check_dfe_cap_core_map.sh

ant=0
state=$CELL_STATE_NORMAL; tag_state=NORMAL
carrier=3400000000
AFC=0
TOC=0
track_apply=0
GREEN='\033[0;32m'
NC='\033[0m' # No Color

arg_parse()
{
	arg=$1
	if [ "${arg: -4}" = help ]; then					print_usage; exit 1
	elif [ $1 = 0 ]; then								ant=0
	elif [ $1 = 1 ]; then								ant=1
	elif [ $1 = 2 ]; then								ant=2
	elif [ $1 = 3 ]; then								ant=3
	elif [ $1 = 4 ]; then								ant=4
	elif [ $1 = 5 ]; then								ant=5
	elif [ $1 = stop ]; then							state=$CELL_STATE_STOPPED; tag_state=STOPPED
	elif [ $1 = search ]; then							state=$CELL_STATE_SEARCH; tag_state=SEARCH
	elif [ $1 = attach ]; then							state=$CELL_STATE_ATTACH; tag_state=ATTACH
	elif [ $1 = normal ]; then							state=$CELL_STATE_NORMAL; tag_state=NORMAL
	elif [ $1 = track ]; then							state=track;
														ssb_period=$SSB_PERIOD; ssb_sym_id=$SSB_SYM_ID; ssb_re_offset=$SSB_RE_OFFSET;
														nid2=$NID2; nid1=$NID1
	elif [ ${arg:0:6} = track= ]; then					state=track; 
                                                        arg=${arg:6};
														arg=(${arg//:/ }); [ ${#arg[@]} != 5 ] && { echo -e "***ERROR: wrong SSB parameters\n"; exit 1; }
														ssb_period=${arg[0]}; ssb_sym_id=${arg[1]}; ssb_re_offset=${arg[2]};
														nid2=${arg[3]}; nid1=${arg[4]}
    elif [ ${arg:0:8} = carrier= ];then					carrier=${arg:8}
    elif [ ${arg:0:6} = apply= ]; then					track_apply=1;
                                                        arg=${arg:6};
                                                        arg=(${arg//:/ }); [ ${#arg[@]} != 2 ] && { echo -e "***ERROR: wrong AFC/TOC parameters\n"; exit 1; }
                                                        AFC=${arg[0]}; TOC=${arg[1]};
	else
		echo Wrong Argument: $1; print_usage; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done

sign_convert()
{
    local var=$1
    if [ $var -gt 2147483648 ];then
        ((var=-((((var ^ 0xFFFFFFFF) - 1)))))
    fi
    echo $var
}

[ $vspa_dev_type = LA12xx ] && [ $state != track ] && { echo DFE state change is only supported on LA93xx device; exit 1; }
([ $((tx_fdd|rx_fdd)) -ne 0 ] && [ $state != track ]) && { echo DFE state change is only supported in TDD mode, current mode is FDD; exit 1; }
#[ $cpe = 0 ] && { echo DFE state change is only supported in UE/CPE mode, current mode is base station; exit 1; }

[ $state != track ] && [ $state != $CELL_STATE_SEARCH ] && check_ant_enable_tx $ant
check_ant_enable_rx $ant
cell_state_pre=`./utils/devmem $test_tool_env_cell_state`
if [ $state != track ];then
	[ $((cell_state_pre)) = $state ] && { echo -e "DFE is already in current state\n"; exit 1; }
	([ $((cell_state_pre)) != $CELL_STATE_ATTACH ] && [ $state = $CELL_STATE_NORMAL ]) && { echo -e "Set cell state to ATTACH first before setting to NORMAL.\n"; exit 1; }
	./utils/devmem $test_tool_env_cell_state w $state
else
	[ $((cell_state_pre)) = $CELL_STATE_SEARCH ] && { echo -e "Current state is SEARCH, can not do cell tracking.\n"; exit 1; }
	[ $((cell_state_pre)) = $CELL_STATE_STOPPED ] && { echo -e "Current state is STOPPED, can not do cell tracking.\n"; exit 1; }
fi

txcore=${anttx[$ant]}
rxcore=${antrx[$ant]}
rid=${ridant[$ant]}
get_chan_para $ant $txcore

if [ $state = $CELL_STATE_STOPPED ];then
	echo dpdk-dfe_app -c "tdd stop"
	dpdk-dfe_app -c "tdd stop"
	echo -e "\n\nDFE state has changed to $tag_state state. Run ./check_all.sh to see current status.\n"

elif [ $state = $CELL_STATE_SEARCH ];then
	[ $((cell_state_pre)) -ne $CELL_STATE_STOPPED ] && { echo dpdk-dfe_app -c "tdd stop"; dpdk-dfe_app -c "tdd stop"; }

	pattern_digits=${pattern[0]}
	for ((i=1;i<${#pattern[@]};i++))
	do
			pattern_digits="$pattern_digits,${pattern[i]}"
	done

	echo dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"
	dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"

	echo dpdk-dfe_app -c "tdd start"
	dpdk-dfe_app -c "tdd start"

	echo -e "\n ${GREEN} DFE state has changed to $tag_state state. Run ./check_all.sh to see current status.${NC} \n"

elif [ $state = $CELL_STATE_ATTACH ];then
	[ $((cell_state_pre)) -ne $CELL_STATE_STOPPED ] && { echo dpdk-dfe_app -c "tdd stop"; dpdk-dfe_app -c "tdd stop"; }

	echo Clearing TX symbols buffer to avoid sending unwanted signal during mode change from SEARCH to ATTACH.
	./utils/memset `phy2vir $tx_sym_queue_base` $((tx_sym_queue_size/4)) 0

	echo Setting DFE MODE option8 bit to set TX in Time Domain.
	msb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+0))`
	lsb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+4))`
	msb=$((msb|DFE_MODE_OPTION8))
	vspa_mbox_mpsend $txcore $host_vspa_mbox_id $msb $lsb
	
	log=`./inject_freq_domain_tx.sh $ant stop`  #make sure to use symbol buffers interface
	
	pattern_digits=${pattern[0]}
	for ((i=1;i<${#pattern[@]};i++))
	do
			pattern_digits="$pattern_digits,${pattern[i]}"
	done

	echo dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"
	dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"

	echo dpdk-dfe_app -c "tdd start"
	dpdk-dfe_app -c "tdd start"

	echo -e "\n ${GREEN} DFE state has changed to $tag_state state. Run ./check_all.sh to see current status."
	echo -e "\n ${GREEN} Currently DFE is sending time domain symbols from TX symbol buffers which are cleared to all 0."
	echo -e "\n ${GREEN} To load time domain PRACH sequence to TX symbol buffer, run ./update_test_vector.sh <PRACH_waveform_file>${NC} \n"

elif [ $state = $CELL_STATE_NORMAL ];then
	
	echo Clearing TX symbols buffer to avoid sending unwanted signal during mode change from ATTACH to NORMAL.
	./utils/memset `phy2vir $tx_sym_queue_base` $((tx_sym_queue_size/4)) 0
	
	echo Restoring DFE MODE to original state.
	msb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+0))`
	lsb=`devmem $((test_tool_env_dfe_mode_msg+txcore*8+4))`
	vspa_mbox_mpsend $txcore $host_vspa_mbox_id $msb $lsb
	echo Starting to play waveform
	log=`./inject_freq_domain_tx.sh $ant` #to start playing default waveform
	
	if [ $((cell_state_pre)) -eq $CELL_STATE_STOPPED ];then
	pattern_digits=${pattern[0]}
	for ((i=1;i<${#pattern[@]};i++))
	do
			pattern_digits="$pattern_digits,${pattern[i]}"
	done

	echo dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"
	dpdk-dfe_app -c "tdd config pattern_fr1fr2 $pattern_digits"

	echo dpdk-dfe_app -c "tdd start"
	dpdk-dfe_app -c "tdd start"
	fi

	echo -e "\n${GREEN}DFE state has changed to $tag_state state. Run ./check_all.sh to see current status.${NC} \n"
else

extbuf_phy=$celltrack_extbuf_base
extbuf_vir=`phy2vir $extbuf_phy`

devmem $((extbuf_vir+0)) w 0xFFFFFFFF	#set flag before sending cell tracking request
echo send_celltrack_cmd $rxcore $ssb_period $ssb_sym_id $ssb_re_offset $nid2 $nid1
send_celltrack_cmd $rxcore $ssb_period $ssb_sym_id $ssb_re_offset $nid2 $nid1
echo !! Cell Tracking request sent. Cell Tracking result: !!
sleep 0.1

cell_id=`./utils/memrw r 32 $((extbuf_vir+0))`
time_oft=`./utils/memrw r 32 $((extbuf_vir+4))`
cfo=`./utils/memrw r 32 $((extbuf_vir+8))`
rssi=`./utils/memrw r 32 $((extbuf_vir+12))`
rsrp=`./utils/memrw r 32 $((extbuf_vir+16))`
rsrq=`./utils/memrw r 32 $((extbuf_vir+20))`
sinr=`./utils/memrw r 32 $((extbuf_vir+24))`

rssi_dec=$(sign_convert $(printf "%d" $rssi))
rsrp_dec=$(sign_convert $(printf "%d" $rsrp))
rsrq_dec=$(sign_convert $(printf "%d" $rsrq))
sinr_dec=$(sign_convert $(printf "%d" $sinr))
time_oft_dec=$(sign_convert $(printf "%d" $time_oft))

time_oft_dec=$(echo "scale=0; $time_oft_dec/65536" | bc)
rssi_dec=$(echo "scale=8; $rssi_dec/65536" | bc)
rsrp_dec=$(echo "scale=8; $rsrp_dec/65536" | bc)
rsrq_dec=$(echo "scale=8; $rsrq_dec/65536" | bc)
sinr_dec=$(echo "scale=8; $sinr_dec/65536" | bc)

[ $((cell_id)) -eq $((0xFFFFFFFF)) ] && { echo -e "***ERROR: Request failed, vspa did not send back result.\n"; exit 1; }
printf -v cell_id_dec %d $cell_id
if [ $((cell_id)) = $((0xdead)) ];then
    echo -e "Cell ID not found \n"
else
echo "cell_id   :" $cell_id "=" $cell_id_dec
echo "time_ofst :" $time_oft "=" $time_oft_dec "samples @ "${axiqsps_rx[ant]}"KSPS"
echo "cfo       :" $cfo "=" $(echo $(sign_convert $(printf "%d" $cfo)) ${axiqsps_rx[ant]} | awk '{ cfo_Hz=$1*$2*1000/2^32; printf("%d",cfo_Hz); }') "Hz"
echo "ss_rssi_db:" $rssi "=" $rssi_dec "dB"
echo "ss_rsrp_db:" $rsrp "=" $rsrp_dec "dB"
echo "ss_rsrq_db:" $rsrq "=" $rsrq_dec "dB"
echo "ss_sinr_db:" $sinr "=" $sinr_dec "dB"
if [ $track_apply = 1 ];then
if [ $AFC = 1 ];then
    echo !! Run AFC !!;
    ./board_specific/rfnm_afc.sh $ant carrier=$carrier CFO=$cfo
fi
if [ $TOC = 1 ];then
    echo !! Apply TOI !!;
    dpdk-dfe_app -c "tdd time-offset $time_oft_dec"
fi
fi 
fi
str="$cell_id$time_oft$cfo$rssi$rsrp$rsrq$sinr"
[ $str = 0x000000040x002ad0000x000108750xffcfc2e40xffcf96800x000a12a40x000fdd94 ] && echo -e "CORRECT CORRECT CORRECT.  Cell Tracking result is expected"
[ $str = 0x000000040x001ad0000x000107b00xffcfbf440xffcf98c00x000a18840x00100814 ] && echo -e "CORRECT CORRECT CORRECT.  Cell Tracking result is expected, loopback delay is 1 sample"
fi

check_error $ant