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
echo "usage ./AFC.sh [ant_id] [ssb_cfg=a:b:c:d:e] [carrier=frequency] [CFO=CFO_NCO]"
echo "  This script is used to run AFC (Automatic Frequency Control). The CFO is compensated through SI5510 based on SBB measurements or based on CFO_NCO received"
echo "	ant_id:       0-5 representing the 6 DCS channels. if not specified, ant 0 will be used"
echo "  ssb_cfg=a:b:c:d:e               set SSB info for cell tracking, a,b,c,d,e are ssb_period,ssb_sym_id,ssb_re_offset,nid2,nid1"
echo "	carrier:      Carrier Frequency in Hz. 3400000000 Hz default value"
echo "	CFO:          CFO value in NCO units @61.44MSPS"
echo "  example:  ./AFC.sh           will run AFC on ant 0 with carrier=3.4Ghz, SSB_CFG=1:4:186:0:1"
echo "  example:  ./AFC.sh 0 carrier=3400000000 ssb_cfg=a:b:c:d:e  will run AFC on ant0, SSB info will be set to a,b,c,d,e, Carrier=3.4Ghz. CFO used to compensate is measured based on SSB cfg"
echo "  example:  ./AFC.sh carrier=3400000000 CFO=2345             will run AFC with carrier=3.4Ghz, CFO=2345 NCO units @61.44MSPS. CFO used to compensate is the one received"
echo
}

source ./check_dfe_cap_core_map.sh

ant=0
carrier=3400000000
resolution_ppb=0.1       #0.1ppb
cfo=NULL
cell_id=0

ssb_period=$SSB_PERIOD; 
ssb_sym_id=$SSB_SYM_ID; 
ssb_re_offset=$SSB_RE_OFFSET;
nid2=$NID2; 
nid1=$NID1

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
	elif [ ${arg:0:8} = ssb_cfg= ]; then                arg=${arg:8};
                                                        arg=(${arg//:/ }); [ ${#arg[@]} != 5 ] && { echo -e "***ERROR: wrong SSB parameters\n"; exit 1; }
														ssb_period=${arg[0]}; ssb_sym_id=${arg[1]}; ssb_re_offset=${arg[2]};
														nid2=${arg[3]}; nid1=${arg[4]}
    elif [ ${arg:0:8} = carrier= ];then			        carrier=${arg:8}
    elif [ ${arg:0:4} = CFO= ];then                     cfo=${arg:4}
	else
        echo Wrong Argument: $1; print_usage; exit 1;
	fi
}

for i in "$@"
do
	arg_parse $i
done

[ $vspa_dev_type = LA12xx ] && { echo AFC is only supported on LA93xx device; exit 1; }

check_ant_enable_tx $ant
check_ant_enable_rx $ant

txcore=${anttx[$ant]}
rxcore=${antrx[$ant]}

get_chan_para $ant $txcore


if [ $cfo = NULL ];then

    extbuf_phy=$celltrack_extbuf_base
    extbuf_vir=`phy2vir $extbuf_phy`

    devmem $((extbuf_vir+0)) w 0xFFFFFFFF	#set flag before sending cell tracking request
    echo send_celltrack_cmd $rxcore $ssb_period $ssb_sym_id $ssb_re_offset $nid2 $nid1
    send_celltrack_cmd $rxcore $ssb_period $ssb_sym_id $ssb_re_offset $nid2 $nid1
    echo Cell Tracking request sent. Cell Tracking result:
    sleep 0.03

    cell_id=`devmem $((extbuf_vir+0))`
    time_oft=`devmem $((extbuf_vir+4))`
    cfo=`devmem $((extbuf_vir+8))`
    rssi=`devmem $((extbuf_vir+12))`
    rsrp=`devmem $((extbuf_vir+16))`
    rsrq=`devmem $((extbuf_vir+20))`
    sinr=`devmem $((extbuf_vir+24))`
    [ $((cell_id)) -eq $((0xFFFFFFFF)) ] && { echo -e "***ERROR: Request failed, vspa did not send back result.\n"; exit 1; }
    echo "cell_id   :" $cell_id
    echo "time_ofst :" $time_oft
    echo "cfo       :" $cfo
    echo "ss_rssi_db:" $rssi
    echo "ss_rsrp_db:" $rsrp
    echo "ss_rsrq_db:" $rsrq
    echo "ss_sinr_db:" $sinr
fi

if [ $cell_id = 0xdead ];then
    echo -e "*** Error: Cell ID not found \n"
else
    printf -v cfo %d $cfo
    if [ $cfo -gt 2147483648 ];then
        ((cfo=-(((cfo ^ 0xFFFFFFFF) - 1))))
        echo Negative frequency!
    fi

    sps=${axiqsps_tx[ant]}

    echo CFO_NCO = $cfo
    cfo_Hz=$(echo $cfo $sps | awk '{ cfo_Hz=$1*$2*1000/2^32; printf("%d",cfo_Hz); }') #convert frequency in Hz
    echo CFO_Hz  = $cfo_Hz

    resolution_hz=$(echo "scale=10; $carrier*$resolution_ppb*10^-9"|bc)
    echo resolution_hz  = $resolution_hz

    SI5510_steps=$(echo "scale=0; $cfo_Hz/$resolution_hz"|bc)
    echo SI5510_steps  = $SI5510_steps

    freq_correction -o add -d 1 -c $SI5510_steps
fi

check_error $ant
