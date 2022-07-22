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

# Description
#	This qec_open_loop_tx.sh takes the input imbalance or DC_offset which are obtained externally, for
#	example read from Keysight VSA, then converts the imbalance/DC_offset into QEC coefficients and 
#	applies/uploads the coefficients onto VSPA QEC module
#	The generated qec coef is saved into bin file qec\qec_coeff_tx_ant${tx_ant_id}.bin

# usage: 
#	./qec_open_loop_tx.sh  [help]  $tx_ant_id   ${iq_gain_imb_dB} ${iq_phase_imb_deg} ${gain_re} ${gain_im} ${dc_re} ${dc_im}

# Input Parameters:
#	help            :  Print below help info
# 	tx_ant_id       :  TX antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.
#	iq_gain_imb_dB  :  IQ gain imbalance read from instrument
#	iq_phase_imb_deg:  IQ ohase imbalance read from instrument
# 	gain_re         :  Complex gain of I.
# 	gain_im         :  Complex gain of Q.
#	dc_re/dc_im     :  TX IQ DC offset read from instrument

#example:
#	./qec_open_loop_tx.sh   0  3  0   1  0  0  0   
#	./qec_open_loop_tx.sh   0  0  0   1  0  0.1  -0.2   
#	./qec_open_loop_tx.sh   help


function show_help()
{
	echo  'usage:' 
	echo  '   ./qec_open_loop_tx.sh [help] tx_ant_id iq_gain_imb_dB iq_phase_imb_deg gain_re gain_im dc_re dc_im qec_coeff'
	echo  'Input Parameters:'
	echo  '   help            :  Print below help info'
	echo  '   tx_ant_id       :  TX antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.'
	echo  '   iq_gain_imb_dB  :  IQ gain imbalance read from instrument'
	echo  '   iq_phase_imb_deg:  IQ ohase imbalance read from instrument'
	echo  '   gain_re         :  Complex gain of I.'
	echo  '   gain_im         :  Complex gain of Q.'
	echo  '   dc_re/dc_im     :  TX IQ DC offset read from instrument'
	echo  '   The generated qec coef is saved into bin file at qec\qec_coeff_tx_ant${tx_ant_id}.bin'
	 
	
}


[ $# -lt 7 ] && { show_help; exit; }

source ./check_dfe_cap_core_map.sh

tx_ant_id=$1
iq_gain_imb_dB=$(echo "-1*$2" | bc -l)
iq_phase_imb_deg=$(echo "-1*$3" | bc -l)  
gain_re=$4  
gain_im=$5  
dc_re=$(echo "-1*$6" | bc -l)  
dc_im=$(echo "-1*$7" | bc -l)
 
check_ant_enable_tx $tx_ant_id   	#to avoid illegal ant id causing system crash

echo "Applying Open Loop QEC/DC compensation for TX ant $tx_ant_id ..."
echo "iq_gain_imb_dB   = $iq_gain_imb_dB"
echo "iq_phase_imb_deg = $iq_phase_imb_deg"
echo "gain_re          = $gain_re"
echo "gain_im          = $gain_im"
echo "dc_re            = $dc_re"
echo "dc_im            = $dc_im"


/bin/bash ./update_qec_coeff_tx.sh   $tx_ant_id   imb=${iq_gain_imb_dB}:${iq_phase_imb_deg} gain=${gain_re}:${gain_im} dc=${dc_re}:${dc_im}
cp ./qec/qec_coeff_tx_ant$tx_ant_id.bin ./qec/qec_open_loop_coeff_tx_ant$tx_ant_id.bin
declare -p iq_gain_imb_dB iq_phase_imb_deg gain_re gain_im dc_re dc_im >> qec/qec_tx_ant${tx_ant_id}.cfg
 
echo TX QEC Open Loop Calibration Done
