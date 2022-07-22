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

# usage:   ./qec_tx_cl_search.sh   tx_ant  rx_ant

#cmd_dir=./qec

###########################
#                         #
# CONFIGURABLE PARAMETERS #
#                         #
###########################



#intermediary used parameters
IMRR_value=0
IMRR_best=0
step_best=1
tunable_param=0  # 0 for phase
				         # 1 for gain

 
###################
#### Functions ####
###################




function wait_here() 
{
	printf "Press ENTER continue at  `basename $0` line:${LINENO}\n"
	read tmp
	echo
}

function clean_files {
	#ant_feedback=$(($rx_ant%6))
	
	#rxcore=${antrx[$ant_feedback]}
	#feedback_size=$((cap_size/32768*32))	# unit: KB

	#get_chan_para $ant_feedback $rxcore
	#feedback_sps=$rxdcs
	feedback_file=rx_timedomain_$feedback_size\KB_$feedback_sps\ksps_dump_ant$ant_feedback.bin
	rm $feedback_file
	if (( $verbose_en == 1 ));then
		echo clean_files $1
	fi
	#wait_here
	if [[ $1 == "-e" ]]; then
		exit
	fi
		
}

#trap cleanup SIGINT
#trap cleanup SIGTERM
#trap cleanup INT
#trap cleanup SIGQUIT
#trap cleanup EXIT


function IMRR_extract {
	[ $verbose_en = 1 ] &&  	  printf " imb2qec_apply in  `basename $0` line:${LINENO}\n"
	$cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --sg $gain_tmp --sp $phase_tmp         > /dev/null

	#sleep 0.1
  	[ $verbose_en = 1 ] &&  	  echo	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 ))
 
	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 ))     > /dev/null      # dump multiple of 32KB data for antenna rx_ant
  	#dump_filename=$feedback_file
  	#dump_via_hram   > /dev/null  
  	#dump_via_ddr   > /dev/null

 	[ -f $feedback_file ] || { echo File $feedback_file does not exist, command failed.; echo; exit 1; }

#	IMRR_value=$($cmd_dir/imrr -i $feedback_file -c $rx_tx_LO_delta/245.76 -f $tone_freq/245.76 -q)
	Fs=$(echo "scale=2; $rxaxiq/1000" | bc -l)
	[ $verbose_en = 1 ] &&  	  echo "($cmd_dir/imrr -i $feedback_file -c $rx_tx_LO_delta/$Fs -f $tone_freq/$Fs -q)"
	IMRR_value=$($cmd_dir/imrr -i $feedback_file -c $rx_tx_LO_delta/$Fs -f $tone_freq/$Fs -q)

	echo
	echo
	echo "        step       = $step;"
	echo "        IMRR_value = ${IMRR_value}"
	echo "        IMRR_best  = $IMRR_best"
	echo "        gain_tmp  = $gain_tmp;  phase_tmp  = $phase_tmp"
	echo "        gain_best = $gain_best; phase_best = $phase_best"

	if [[ $? == 1 ]]; then
		echo "Internal error !!"
		exit 1
	fi
	
	if (( $(echo "$IMRR_value >= $IMRR_threshold" | bc -l))); then
		phase_init=$phase_tmp
		gain_init=$gain_tmp

		IMRR_best=$IMRR_value;

		#/bin/bash   qec_apply.sh -p tx -m dpdh --sg $gain_init --sp $phase_init     > /dev/null
		/bin/bash    $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --sg $gain_init --sp $phase_init   -s   > /dev/null

		printf "\n"
		printf "****** Computed parameters  ******\n"
		printf ">  IMRR_value       = %12s %sdB\n"  $IMRR_value
		printf ">  phase_obtn       = %12s %sdegrees\n"  $phase_init
		printf ">  gain_obtn        = %12s %sdB\n"  $gain_init

		#killall -9 clpoc_refapp> /dev/null

		exit 0
	fi
}

##################

function estimate_param {
	multiplication=1
	gain_tmp=1
	phase_tmp=1
	phase_best=$phase_init
	gain_best=$gain_init
	IMRR_local=0

	for ((count=1; count<=$tx_inner_loop_count; count++))
	do
		if [[ $tunable_param == 0 ]]; then
			gain_minus=$gain_init
			gain_center=$gain_init
			gain_plus=$gain_init
			
			phase_minus=$(echo "$phase_init + $step*($multiplication - 2)" | bc -l)
			phase_center=$(echo "$phase_init + $step*($multiplication - 1)" | bc -l)
			phase_plus=$(echo "$phase_init + $step*($multiplication)" | bc -l)
		else
			gain_minus=$(echo "$gain_init + $step*($multiplication - 2)" | bc -l)
			gain_center=$(echo "$gain_init + $step*($multiplication - 1)" | bc -l)
			gain_plus=$(echo "$gain_init + $step*($multiplication)" | bc -l)
			
			phase_minus=$phase_init
			phase_center=$phase_init
			phase_plus=$phase_init
		fi

		######## debug ##########
		phase_tmp=$phase_minus
		gain_tmp=$gain_minus
		######## debug ##########

		#IMRR_extract $fetch_addr_2nd_half $cap_size $gain_tmp  $phase_tmp $step
		if (( $verbose_en == 1 ));then
			echo IMRR_extract  minus
		fi
		IMRR_extract  $cap_size $gain_tmp  $phase_tmp $step
		IMRR_minus=$IMRR_value
		if (( $(echo "$IMRR_value > $IMRR_best" | bc -l))); then
			IMRR_best=$IMRR_minus
			phase_best=$phase_tmp
			gain_best=$gain_tmp
			step_best=$step
			######## debug ##########
			echo "            IMRR_best(minus)=$IMRR_best;"
			echo "            gain_best(minus)=$gain_best;"
			echo "            phase_best(minus)=$phase_best;"
			#########################
		fi
		IMRR_local=$IMRR_minus

		######## debug ##########
		phase_tmp=$phase_center
		gain_tmp=$gain_center
		######## debug ##########

		#IMRR_extract $fetch_addr_2nd_half $cap_size $gain_tmp $phase_tmp $step
		if (( $verbose_en == 1 ));then
			echo IMRR_extract  center
		fi
		IMRR_extract   $cap_size $gain_tmp $phase_tmp $step
		IMRR_center=$IMRR_value
		if (( $(echo "$IMRR_value > $IMRR_best" | bc -l))); then
			IMRR_best=$IMRR_center
			phase_best=$phase_tmp
			gain_best=$gain_tmp
			step_best=$step
			######## debug ##########
			echo "            IMRR_best(center)=$IMRR_best;"
			echo "            gain_best(center)=$gain_best;"
			echo "            phase_best(center)=$phase_best;"
			#########################
		fi
		if (( $(echo "$IMRR_value > $IMRR_local" | bc -l))); then
			IMRR_local=$IMRR_center
		fi

		######## debug ##########
		phase_tmp=$phase_plus
		gain_tmp=$gain_plus
		######## debug ##########

		#IMRR_extract $fetch_addr_2nd_half $cap_size $gain_tmp $phase_tmp $step
		if (( $verbose_en == 1 ));then
			echo IMRR_extract  plus
		fi
		IMRR_extract   $cap_size $gain_tmp $phase_tmp $step
		IMRR_plus=$IMRR_value
		if (( $(echo "$IMRR_value > $IMRR_best" | bc -l))); then
			IMRR_best=$IMRR_plus
			phase_best=$phase_tmp
			gain_best=$gain_tmp
			step_best=$step
			######## debug ##########
			echo "            IMRR_best(plus)=$IMRR_best;"
			echo "            gain_best(plus)=$gain_best;"
			echo "            phase_best(plus)=$phase_best;"
			#########################
		fi
		if (( $(echo "$IMRR_value > $IMRR_local" | bc -l))); then
			IMRR_local=$IMRR_plus
		fi

		if (( $(echo "$IMRR_center >= $IMRR_local" | bc -l) )); then
			if (( $(echo "($step)/2 > 0.000005" | bc -l) )); then
				step=$(echo "($step)/2" |bc -l)
			else
				step=$(echo "$step + 0.0001" |bc -l)
			fi
			multiplication=1

			if [[ $tunable_param == 0 ]]; then
				phase_init=$phase_best
			else
				gain_init=$gain_best
			fi
			
			echo "  ****  dir = 0"
			
		elif (( $(echo "$IMRR_minus >= $IMRR_local" | bc -l) )); then
			multiplication=$(echo "$multiplication - 1" | bc -l)
			echo "  ****  dir = -1; multiplication = $multiplication"
		elif (( $(echo "$IMRR_plus >= $IMRR_local" | bc -l) )); then
			multiplication=$(echo "$multiplication + 1" | bc -l)
			echo "  ****  dir = +1; multiplication = $multiplication;"
		else
				echo
				echo "****  dir = FF;"
				echo
		fi
	done

	phase_init=$phase_best
	gain_init=$gain_best
}


function tune_IMRR {
	for ((count_out=1; count_out<=$tx_outer_loop_count; count_out++))
	do
		step=$step_phase_init;
		tunable_param=0
		#estimate_param $fetch_addr_2nd_half $cap_size $tx_inner_loop_count $gain_init $phase_init $tunable_param $step $step_best
		if (( $verbose_en == 1 ));then
		   echo estimate_param  cap_size:$cap_size tx_inner_loop_count:$tx_inner_loop_count gain_init:$gain_init phase_init:$phase_init tunable_param:$tunable_param step:$step step_best:$step_best
		fi
		estimate_param   $cap_size $tx_inner_loop_count $gain_init $phase_init $tunable_param $step $step_best
		step_phase_init=$step_best

		step=$step_gain_init;
		tunable_param=1
		#estimate_param $fetch_addr_2nd_half $cap_size $tx_inner_loop_count $gain_init $phase_init $tunable_param $step $step_best
		if (( $verbose_en == 1 ));then
		   echo estimate_param  cap_size:$cap_size tx_inner_loop_count:$tx_inner_loop_count gain_init:$gain_init phase_init:$phase_init tunable_param:$tunable_param step:$step step_best:$step_best
		fi
		estimate_param   $cap_size $tx_inner_loop_count $gain_init $phase_init $tunable_param $step $step_best
		step_gain_init=$step_best
	done
}

########################
##### Main routine #####
########################
printf "Start TX QEC Close Loop Calibration ... \n"

if [ $# -lt 2 ];then
	echo Wrong arguments
	#print_usage
	echo
	exit 1
fi
if [ $# -ge 2 ];then
	((tx_ant=$1%6))
	((rx_ant=$2%6))
fi

source ./check_dfe_cap_core_map.sh
source qec_init.cfg
source $cmd_dir/qec_common.sh $tx_ant  $rx_ant


# correction parameters
tx_corr_dc_re=0
tx_corr_dc_im=0

if [[ -f $cmd_dir/qec_tx_ant${tx_ant}.cfg ]]; then
	#If a previous configuration file exists, update the values  
	source $cmd_dir/qec_tx_ant${tx_ant}.cfg
	# correction parameters
	tx_corr_dc_re=$dc_re
	tx_corr_dc_im=$dc_im
else
	echo $cmd_dir/qec_tx_ant${tx_ant}.cfg doesn not exist
	#wait_here  
fi


printf "\n"
printf "****** Initial parameters  ******\n"
printf "\n"
printf ">  phase_init       = %12s %sdegrees\n"  $phase_init
printf ">  gain_init        = %12s %sdB\n"  $gain_init
printf ">  step_gain_init   = %12s %sdB\n"  $step_gain_init
printf ">  step_phase_init  = %12s %sdegrees\n"  $step_phase_init
printf ">  tx_inner_loop_count = %12s %s\n"  $tx_inner_loop_count
printf ">  tx_outer_loop_count = %12s %s\n"  $tx_outer_loop_count
printf ">  tone frequency   = %12s %sMHz\n"  $tone_freq
printf ">  rx_tx_LO_delta   = %12s %sMHz\n"  $rx_tx_LO_delta
printf ">  IMRR_threshold   = %12s %sdB\n"  $IMRR_threshold
printf ">  tx_corr_dc_re    = %12s %s\n"  $tx_corr_dc_re
printf ">  tx_corr_dc_im    = %12s %s\n"  $tx_corr_dc_im
printf "\n"                   
#printf ">  fetch_addr       = %12s %sSRX sig address\n" $fetch_addr_2nd_half
printf ">  cap_size         = %12s %sbytes\n" $cap_size
printf "\n"
printf "*********************************\n"
printf "\n"

printf "Please make sure that all the necessary parameters are correctly configured!\n"
#wait_here
# Detect if the last init configured the correct mode.{
#if [[ -f /tmp/.init_refapp.cfg ]]; then
# ...
#fi
# Detect if the last init configured the correct mode.}

#printf "Press ENTER continue at  `basename $0` line:${LINENO}\n"
#read tmp


#should have sent at the beginning of CL-QEC
#  echo send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 
#./send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 
#sleep 0.1

if (( $verbose_en == 1 ));then
  echo reaching   `basename $0` line:${LINENO}
fi
/bin/bash $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --sg 0 --sp 0        > /dev/null

if (( $verbose_en == 1 ));then
  echo tune_IMRR 
fi
#tune_IMRR $step_gain_init $tx_outer_loop_count $fetch_addr_2nd_half $cap_size $tx_inner_loop_count $gain_init $phase_init
tune_IMRR $step_gain_init $tx_outer_loop_count $cap_size $tx_inner_loop_count $gain_init $phase_init

# apply QEC with the best values
echo IMRR threshold: ${IMRR_threshold}dB not met, applying QEC with the best values 
#/bin/bash qec_apply.sh -p tx -m dpdh --sg $gain_init --sp $phase_init     > /dev/null
/bin/bash $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --sg $gain_init --sp $phase_init    -s  > /dev/null

printf "\n"
printf "****** Computed parameters  ******\n"
printf ">  phase_obtn       = %12s %sdegrees\n"  $phase_init
printf ">  gain_obtn        = %12s %sdB\n"  $gain_init

clean_files 
exit 2
