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
echo "  usage ./initial_access_demo.sh [ant_id] [track=a:b:c:d:e] [apply=a:b] [carrier=frequency] "
echo "  The purpose of this script is a PoC of Initial Access procedure"
echo "	ant_id:       0-5 representing the 6 DCS channels. if not specified, ant 0 will be used"
echo "	carrier:      Carrier Frequency in Hz. 3400000000 Hz default value"
echo "  track=a:b:c:d:e               set SSB info for cell tracking, a,b,c,d,e are ssb_period,ssb_sym_id,ssb_re_offset,nid2,nid1"
echo "  apply=a:b                     enables the correction for AFC/TOC based on SSB measurements"
echo "  example:  ./initial_access_demo.sh 0            will set ant0 for Initial Access Demo"
echo "  example:  ./initial_access_demo.sh 0 track=a:b:c:d:e  will set ant0 for Initial Access Demo, SSB info will be set to a,b,c,d,e"
echo "  example:  ./initial_access_demo.sh 0 track=a:b:c:d:e carrier=3400000000 apply=1:1  will set ant0 for Initial Access Demo, SSB info will be set to a,b,c,d,e, carrier=3.4Ghz and AFC=TOC=1, all corrections will be applied"
echo
}

source ./check_dfe_cap_core_map.sh

ant=0
carrier=3400000000
AFC=0
TOC=0
track_apply=0
ssb_period=$SSB_PERIOD
ssb_sym_id=$SSB_SYM_ID
ssb_re_offset=$SSB_RE_OFFSET
nid2=$NID2
nid1=$NID1
sfn_delta_example=10
slot_delta_example=7
TA_example=7
TOI_cell_search_example=45
GREEN='\033[0;32m'
NC='\033[0m' # No Color
cfo_search_example=1450

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
	elif [ ${arg:0:6} = track= ]; then 
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

echo -e "\n ${GREEN} !! Starting Initial Access procedure !! ${NC}"
echo -e " ${GREEN} !! Switching to Cell Search mode. !! ${NC} \n"
dpdk-dfe_app -c "tdd config tick keep-alive 1"
./set_dfe_state.sh search
sleep 2

dpdk-dfe_app -c "tdd stop"
echo -e "\n ${GREEN} !! Applying SFN-SLOT delta between TTI and MIB decoded information !! ${NC} \n"
dpdk-dfe_app -c "tdd sfn-slot delta $sfn_delta_example $slot_delta_example"
echo -e "\n ${GREEN} !! Applying Time Offset information !! ${NC} \n"
dpdk-dfe_app -c "tdd time-offset $TOI_cell_search_example"
echo -e "\n ${GREEN} !! Applying CFO correction !! ${NC} \n"
./board_specific/rfnm_afc.sh $ant carrier=$carrier CFO=$cfo_search_example
sleep 1

echo -e "\n ${GREEN} !! Cell Search procedure Done => switching to Attach mode (PRACH) !! ${NC} \n"
./set_dfe_state.sh attach

sleep 1
echo -e "\n ${GREEN} !! Apply TA indication from gNodeB - PRACH procedure Done !! ${NC} \n"
dpdk-dfe_app -c "tdd config ul-time-advance $TA_example"
sleep 1

echo -e "\n ${GREEN} !! Cell Tracking request - CFO + TOI correction !! ${NC} \n"
./set_dfe_state.sh track=$ssb_period:$ssb_sym_id:$ssb_re_offset:$nid2:$nid1 apply=$AFC:$TOC carrier=$carrier
sleep 1

echo -e "\n ${GREEN} !! Cell Attach procedure Done -> switching to Normal mode !! ${NC} \n"
./set_dfe_state.sh normal
sleep 1

echo -e "\n ${GREEN} !! Cell Tracking request - CFO + TOI correction !! ${NC} \n"
./set_dfe_state.sh track=$ssb_period:$ssb_sym_id:$ssb_re_offset:$nid2:$nid1 apply=$AFC:$TOC carrier=$carrier
sleep 1
echo -e "\n ${GREEN} !! Cell Tracking request - CFO + TOI correction !! ${NC} \n"
./set_dfe_state.sh track=$ssb_period:$ssb_sym_id:$ssb_re_offset:$nid2:$nid1 apply=$AFC:$TOC carrier=$carrier
sleep 1
echo -e "\n ${GREEN} !! Cell Tracking request - CFO + TOI correction !! ${NC} \n"
./set_dfe_state.sh track=$ssb_period:$ssb_sym_id:$ssb_re_offset:$nid2:$nid1 apply=$AFC:$TOC carrier=$carrier


./check_all.sh






