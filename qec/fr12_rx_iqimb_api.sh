#!/bin/bash

# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only be used strictly
# in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.


# example:   ./fr12_rx_iqimb_api.sh   $tone_freq  $feedback_file  $rx_ant 

source ./check_dfe_cap_core_map.sh
source qec_init.cfg

###############
#  Functions  #  
###############

function input_MHz()
{
	inMHz=${1/Hz/};

	if [[ "$inMHz" =~ .*"G".* ]]; then
		inMHz=${inMHz/G*/}
		inMHz=`echo $inMHz \* 1000 | bc`
	fi

	if [[ "$inMHz" =~ .*"M".* ]]; then
		inMHz=${inMHz/M*/}
	fi

	if [[ "$inMHz" =~ .*"K".* ]]; then
		inMHz=${inMHz/K*/}
		inMHz=`echo "scale=6; $inMHz / 1000" | bc`
	fi

	if [[ "$inMHz" =~ .*"k".* ]]; then
		inMHz=${inMHz/k*/}
		inMHz=`echo "scale=6; $inMHz / 1000" | bc`
	fi

	inMHz=${inMHz/.000000/}

	echo Converted to $inMHz MHz
}



#Tunable parameters
#rx_tx_LO_delta=45 #value in MHz; Frequency discrimination (F_TX_LO - F_RX_LO) in MHz , in qec_init,cfg
#rx_tx_LO_delta=0   #value in MHz; Frequency discrimination (F_TX_LO - F_RX_LO) in MHz
#N=4096   #FFT Length (power of two, maximum L), in qec_init,cfg

#Fixed parameters - Do not change
#default_tone_value=24
#default_tone_value=3  #xl
#param=${$1:-$default_tone_value}


input_MHz $1
tone=$inMHz           #Transmitted tone frequency in MHz

#Fs=245.76             #LS-ADC sampling frequency in MHz , in qec_init,cfg
#L=16384               #LS-ADC capture length , in qec_init,cfg

Fi=`echo $tone + $rx_tx_LO_delta | bc`

echo
echo "### Rx IQ Imbalance API ###"
echo
echo "Test tone frequency (Tx): $tone MHz"
echo "          Tx-Rx LO delta: $rx_tx_LO_delta MHz"
echo
echo
echo "Observed tone frequency (Rx): $Fi MHz"
echo "           Rx capture length: $L samples"
echo "               Rx FFT length: $N samples"
echo
echo
echo

source ./check_dfe_cap_core_map.sh
get_chan_para $3 ${antrx[$3]}

Fs=$(echo "scale=2; $rxaxiq/1000" | bc -l)
#echo Fs=$Fs   rxdcs=$rxdcs
python3 $cmd_dir/rx_iqimb_extract.py $2 $Fi $Fs $N $L $3  -a
