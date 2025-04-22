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

# usage ./rx_iq_correction.sh tx_ant rx_ant
# 

function wait_here() 
{
	printf "Press ENTER to continue ...\n"
	read tmp
	echo
}
[ $# -lt 2 ] && { echo "***ERROR: ./rx_iq_correction.sh <tx_ant_id> <rx_ant_id>"; exit 1; }
tx_ant_id=$(($1%6))
rx_ant_id=$(($2%6))

cmd_dir=($PWD/qec)

source ./check_dfe_cap_core_map.sh
source ./runtime_config.txt

ref_file=./test_vectors/TM1.1_100MHz_30kHz_FDD_timedomain_491520ksps.bin

check_ant_enable_tx $tx_ant_id   #to avoid illegal ant id causing system crash
check_ant_enable_rx $rx_ant_id
		
txcore=${anttx[$tx_ant_id]}
get_chan_para $tx_ant_id $txcore
tx_sps=$txaxiq

rxcore=${antrx[$rx_ant_id]}
get_chan_para $rx_ant_id $rxcore
feedback_sps=$rxaxiq
#echo feedback_sps=$feedback_sps
 
init=1
detection=0
iq_offset_threshold=1000
min_dre_step=20
min_dim_step=20
divider=100000

single_slot=$((61440*4))
fs_ratio=$((feedback_sps/122880))
rx_dump_size=$(((single_slot*fs_ratio)*2/32768))
rx_dump_file_size=$((rx_dump_size*32))
echo Apply QEC Rx passthrough mode on DC offset values...
echo ./update_qec_coeff_rx.sh $rx_ant_id dc=0:0 inc
./update_qec_coeff_rx.sh $rx_ant_id dc=0:0 inc > /dev/null 2>&1

#tx_file=$invecfile_cur
tx_file=${invecfile_cur[$tx_ant_id]}
rx_file=rx_timedomain_$rx_dump_file_size\KB_$feedback_sps\ksps_dump_ant$rx_ant_id.bin

echo Starting Rx IQ correction...

if [ $detection == 1 ]
then
	#echo detect symbol offset ...
	./dump_time_domain_rx.sh $rx_ant_id $rx_dump_size > /dev/null 2>&1
	#s0=`./utils/rx_meas_fr1_tiny -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s 4`
	s0=`python3 ./utils/rx_meas_fr1_tiny.py -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s 4`

	if ([ "${s0[0]}" = "Error" ]) then
		echo Error!! Invalid Rx signal ... Please reset and try again...
		exit 1
	fi
		
	list=($(echo $s0 | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$'))
	symbol_offset0=${list[0]}
	#echo symbol_offset0=$symbol_offset0
	#echo IQ offset = ${list[3]}
	
	#./update_qec_coeff_rx.sh $rx_ant_id $cmd_dir/qec_coeff_rx_temp_ant$rx_ant_id.bin > /dev/null 2>&1
	echo ./update_qec_coeff_rx.sh $rx_ant_id  dc=0.001:0 inc
	./update_qec_coeff_rx.sh $rx_ant_id  dc=0.001:0 inc  > /dev/null 2>&1
	
	./dump_time_domain_rx.sh $rx_ant_id $rx_dump_size > /dev/null 2>&1
	#echo ./dump_time_domain_tx.sh $rx_ant_id $rx_dump_size;
	#s1=`./utils/rx_meas_fr1_tiny -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s 4`
	s1=`python3 ./utils/rx_meas_fr1_tiny.py -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s 4`
	
	if ([ "${s1[0]}" = "Error" ]) then
		echo Error!! Invalid Rx signal ... Please reset and try again...
		exit 1
	fi
	
	list=($(echo $s1 | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$'))
	symbol_offset1=${list[0]}
	#echo symbol_offset1=$symbol_offset1 
	#echo IQ offset = ${list[3]}

	incr_scale=$(echo "scale=2; $symbol_offset1 - $symbol_offset0" | bc -l) 
	echo incr_scale=$incr_scale
	
	./update_qec_coeff_rx.sh $rx_ant_id dis > /dev/null 2>&1

else
	incr_scale=4
	echo incr_scale is set to default $incr_scale...
fi

#wait_here

for (( count=1; count<=30; count++ ))
do
	#echo $count
	./dump_time_domain_rx.sh $rx_ant_id $rx_dump_size > /dev/null 2>&1

	#x=`./utils/rx_meas_fr1_tiny -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s $incr_scale`
	x=`python3 ./utils/rx_meas_fr1_tiny.py -r $tx_file -i $rx_file -f $((feedback_sps*1000)) -s $incr_scale`

	if ([ "${x[0]}" = "Error" ]) then
		echo Error!! Invalid Rx signal ... Please reset and try again...
		exit 1
	fi
		
	list=($(echo $x | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$'))

	iq_distance=${list[3]}
	echo IQ delta = $iq_distance

	temp_dre100000=${list[1]}
	temp_dim100000=${list[2]}	
		
	#echo ${temp_dre100000#-}
	#echo ${temp_dim100000#-}
		
	if [ $init == 1 ]
	then
		iq_distance_initial=$iq_distance
		init=0
	fi
		
	#if ([ $iq_distance -lt $iq_offset_threshold ])
	if ([ ${temp_dre100000#-} -lt $min_dre_step ] && [ ${temp_dim100000#-} -lt $min_dim_step ])
	then	
		echo Calibration done...found the best --dre $final_dre --dim $final_dim
		cp ./qec/qec_coeff_rx_ant$rx_ant_id.bin ./qec/qec_open_loop_coeff_rx_ant$rx_ant_id.bin
		#echo ${temp_dre100000#-}
		#echo ${temp_dim100000#-}
		echo Reporting Rx EVM ...
		#echo python3 utils/rx_evm.py -r $ref_file -i $rx_file -s
		python3 utils/rx_evm.py -r $ref_file -i $rx_file -s
		cp $cmd_dir/trx_meas.png $cmd_dir/trx_meas_ant$rx_ant_id.png
		rm $cmd_dir/trx_meas.png
		echo Check the plot at $cmd_dir/trx_meas_ant$rx_ant_id.png
		exit;
	fi
			
	#echo temp dre=$temp_dre100000
	#echo temp dim=$temp_dim100000
					
	if ([ $iq_distance -gt $iq_distance_initial ]); then
		echo calibration failed...please retry.
		exit;
	fi		
		
	if [ $count == 1 ]
	then
		calc_dre100000=$temp_dre100000
		calc_dim100000=$temp_dim100000
		#echo calc_dre100000=$calc_dre100000
		#echo calc_dim100000=$calc_dim100000
	else
		if ([ ${temp_dre100000#-} -gt $min_dre_step ])
		then
			calc_dre100000=$((calc_dre100000+temp_dre100000))
		fi
		if ([ ${temp_dim100000#-} -gt $min_dim_step ])
		then
			calc_dim100000=$((calc_dim100000+temp_dim100000))
		fi

		#echo calc_dre100000=$calc_dre100000
		#echo calc_dim100000=$calc_dim100000
	fi
		
	final_dre=$(echo "scale=5; ${calc_dre100000}/${divider}" | bc)
	final_dim=$(echo "scale=5; ${calc_dim100000}/${divider}" | bc)
	#python3 utils/imb2qec.py rx $gain_error $phase_error 0 0 0 1.0 0 $final_dre $final_dim $cmd_dir/qec_coeff_rx_temp_ant$rx_ant_id.bin #> /dev/null 2>&1
	#echo python3 utils/imb2qec.py rx $gain_error $phase_error 0 0 0 1.0 0 $final_dre $final_dim $cmd_dir/qec_coeff_rx_temp_ant$rx_ant_id.bin
		
	echo ./update_qec_coeff_rx.sh $rx_ant_id dc=$final_dre:$final_dim inc #> /dev/null 2>&1
	./update_qec_coeff_rx.sh $rx_ant_id dc=$final_dre:$final_dim inc > /dev/null 2>&1
	declare -p final_dre final_dim >> qec/qec_rx_ant${rx_ant_id}.cfg
	
	#wait_here
done
