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

# usage:   ./dc_offset_cl_search.sh   tx_ant  rx_ant


#cmd_dir=./qec
#source qec_init.cfg

###########################
#                         #
# CONFIGURABLE PARAMETERS #
#                         #
###########################

# Please configure these parameters accordingly.

#initial parameters
#dc_i=0         		# in dB
#dc_q=0         		# in dB
#step_dc_i_init=1    # in dB
#step_dc_q_init=1  	# in dB
#step_dc_i_init=0.5    # in dB
#step_dc_q_init=0.5  	# in dB
#dc_outer_loop_count=3
#dc_inner_loop_count=10
#dir=0				# 1:plus,   -1:minus 	0:unknown

#tone_freq=24      #value in MHz
#amp=80            #80% of full scale
#rx_tx_LO_delta=45 #value in MHz
#dc_offset_threshold=-80 # if threshold value is reached => exit the loop , defined in qec_init.cfg

#verbose enable
#verbose_en=0

## FIXED PARAMETERS BELOW ##
#VERSION=1.0
#echo "******************************************"
#echo "* TX DC OFFSET SEARCH Version v$VERSION  *"
#echo "******************************************"
#echo

tx_ant=$1
rx_ant=$2

#cap_size=32768       #RX dump file size in byte
#ant_feedback=0

#intermediary used parameters
dc_offset_values=0
dc_offset_best=0
step_best=1
tunable_param=0  # 0 for dc_q
				         # 1 for dc_i

source ./check_dfe_cap_core_map.sh
source qec_init.cfg
source $cmd_dir/qec_common.sh $tx_ant  $rx_ant



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
	#find -type f -name '$feedback_file' -delete
	[ $verbose_en = 1 ] &&   echo clean_files $1
	if [[ $1 == "-e" ]]; then 
		exit 0
	fi
		
}



function dc_offset_apply {
#	Call dedicated script to apply the DC corrections
#	./rfic_set_dc_off.sh $dc_i_tmp $dc_q_tmp
	[ $verbose_en = 1 ] &&   echo  $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre  $dc_i_tmp  --dim $dc_q_tmp  in  `basename $0` line:${LINENO}
	$cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre  $dc_i_tmp  --dim $dc_q_tmp        > /dev/null
}

function dc_offset_extract {
	# Apply intermediate DC corrections
	dc_offset_apply $dc_i_tmp $dc_q_tmp

#	wait_here
#	sleep 0.1
	
#	should have sent at the beginning of CL-QEC
#	echo send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 
#	./send_single_tone.sh  $tx_ant  $(($tone_freq*1000000))  $amp 

#	./bin2mem -f ../data/cap_DC.bin -a $fetch_addr_2nd_half -c 4 -r $cap_size > /dev/null
#	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 ))   > /dev/null      # dump multiple of 32KB data for antenna rx_ant
	[ $verbose_en = 1 ] && echo	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 ))  
	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 ))   > /dev/null      # dump multiple of 32KB data for antenna rx_ant
#	./dump_time_domain_rx.sh $rx_ant  $(( cap_size/32768 )) HRAM  > /dev/null 
#	dump_filename=$feedback_file
#	dump_via_hram   > /dev/null  
#	dump_via_ddr   > /dev/null

	[ -f $feedback_file ] || { echo File $feedback_file does not exist, command failed.; echo; exit 1; }

	Fs=$(echo "scale=2; $rxaxiq/1000" | bc -l)
	#echo 	dc_offset_values=$cmd_dir/tonelevel -i $feedback_file -f $rx_tx_LO_delta/$Fs -q
	dc_offset_values=$($cmd_dir/tonelevel -i $feedback_file -f $rx_tx_LO_delta/$Fs -q)
	

	if [[ $? == 1 ]]; then
		echo "Internal error !! in  `basename $0` line:${LINENO}"

		exit 1
	fi
 
  if [[ $verbose_en = 5 ]]; then
	 	echo
	 	echo
	 	echo "        step       = $step;"
	 	echo "        dc_offset_values = ${dc_offset_values}"
	 	echo "        dc_offset_best  = $dc_offset_best"
		echo "        dc_i_tmp  = $dc_i_tmp;  dc_q_tmp  = $dc_q_tmp"
	 	echo "        dc_i_best = $dc_i_best; dc_q_best = $dc_q_best"
  fi

	
	if (( $(echo "$dc_offset_values <= $dc_offset_threshold" | bc -l))); then
		dc_q=$dc_q_tmp
		dc_i=$dc_i_tmp

		dc_offset_best=$dc_offset_values;

		/bin/bash $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre $dc_i --dim $dc_q  -s   > /dev/null

		printf "\n"
		printf "****** Computed parameters  ******\n"
		printf ">  dc_offset_values       = %12s %sdB\n"  $dc_offset_values
		printf ">  dc_q_obtn       = %12s %s\n"  $dc_q
		printf ">  dc_i_obtn       = %12s %s\n"  $dc_i

		# killall -9 clpoc_refapp> /dev/null

		# ./gul_refapp -c "l1c dpd start"
		clean_files -e
		#exit
	fi
}


##################

function estimate_param {
	multiplication=1
	dc_i_tmp=1
    dc_q_tmp=1
	dc_q_best=$dc_q
	dc_i_best=$dc_i
	dc_offset_local=0

	for ((count=1; count<=$dc_inner_loop_count; count++))
	do
		if [[ $tunable_param == 0 ]]; then
			dc_i_minus=$dc_i
			dc_i_center=$dc_i
			dc_i_plus=$dc_i
			
			dc_q_minus=$(echo "$dc_q + $step*($multiplication - 2)" | bc -l)
			dc_q_center=$(echo "$dc_q + $step*($multiplication - 1)" | bc -l)
			dc_q_plus=$(echo "$dc_q + $step*($multiplication)" | bc -l)
		else
			dc_i_minus=$(echo "$dc_i + $step*($multiplication - 2)" | bc -l)
			dc_i_center=$(echo "$dc_i + $step*($multiplication - 1)" | bc -l)
			dc_i_plus=$(echo "$dc_i + $step*($multiplication)" | bc -l)
			
			dc_q_minus=$dc_q
			dc_q_center=$dc_q
			dc_q_plus=$dc_q
		fi

		######## debug ##########
		dc_q_tmp=$dc_q_minus
		dc_i_tmp=$dc_i_minus
		######## debug ##########

		# dc_offset_extract $fetch_addr_2nd_half $cap_size $dc_i_minus  $dc_q_minus $step
		[ $verbose_en = 1 ] && echo dc_offset_extract   cap_size:$cap_size  dc_i_minus:$dc_i_minus  dc_q_minus:$dc_q_minus step:$step

		dc_offset_extract   $cap_size  $dc_i_minus  $dc_q_minus $step
		dc_offset_minus=$dc_offset_values
		if (( $(echo "$dc_offset_values < $dc_offset_best" | bc -l))); then
			dc_offset_best=$dc_offset_minus
			dc_q_best=$dc_q_tmp
			dc_i_best=$dc_i_tmp
			step_best=$step
			######## debug ##########
			echo "            dc_offset_best(minus)=$dc_offset_best;"
			echo "            dc_i_best(minus)=$dc_i_best;"
			echo "            dc_q_best(minus)=$dc_q_best;"
			#########################
		fi
		dc_offset_local=$dc_offset_minus

		######## debug ##########
		dc_q_tmp=$dc_q_center
		dc_i_tmp=$dc_i_center
		######## debug ##########

		# dc_offset_extract $fetch_addr_2nd_half $cap_size $dc_i_center $dc_q_center $step
		[ $verbose_en = 1 ] && echo dc_offset_extract   cap_size:$cap_size  dc_i_center:$dc_i_center  dc_q_center:$dc_q_center step:$step
		dc_offset_extract   $cap_size  $dc_i_center  $dc_q_center $step
		dc_offset_center=$dc_offset_values
		if (( $(echo "$dc_offset_values < $dc_offset_best" | bc -l))); then
			dc_offset_best=$dc_offset_center
			dc_q_best=$dc_q_tmp
			dc_i_best=$dc_i_tmp
			step_best=$step
			######## debug ##########
			echo "            dc_offset_best(center)=$dc_offset_best;"
			echo "            dc_i_best(center)=$dc_i_best;"
			echo "            dc_q_best(center)=$dc_q_best;"
			#########################
		fi
		if (( $(echo "$dc_offset_values < $dc_offset_local" | bc -l))); then
			dc_offset_local=$dc_offset_center
		fi

		######## debug ##########
		dc_q_tmp=$dc_q_plus
		dc_i_tmp=$dc_i_plus
		######## debug ##########

		# dc_offset_extract $fetch_addr_2nd_half $cap_size $dc_i_plus $dc_q_plus $step
		[ $verbose_en = 1 ] &&   echo dc_offset_extract  cap_size:$cap_size  dc_i_plus:$dc_i_plus  dc_q_plus:$dc_q_plus  step:$step
		dc_offset_extract  $cap_size  $dc_i_plus  $dc_q_plus $step
		dc_offset_plus=$dc_offset_values
		if (( $(echo "$dc_offset_values < $dc_offset_best" | bc -l))); then
			dc_offset_best=$dc_offset_plus
			dc_q_best=$dc_q_tmp
			dc_i_best=$dc_i_tmp
			step_best=$step
			######## debug ##########
			echo "            dc_offset_best(plus)=$dc_offset_best;"
			echo "            dc_i_best(plus)=$dc_i_best;"
			echo "            dc_q_best(plus)=$dc_q_best;"
			#########################
		fi
		if (( $(echo "$dc_offset_values < $dc_offset_local" | bc -l))); then
			dc_offset_local=$dc_offset_plus
		fi

		if (( $(echo "$dc_offset_center <= $dc_offset_local" | bc -l) )); then
			if (( $(echo "($step)/2 > 0.000005" | bc -l) )); then
				step=$(echo "($step)/2" |bc -l)
			else
				step=$(echo "$step + 0.0001" |bc -l)
			fi
			multiplication=1

			if [[ $tunable_param == 0 ]]; then
				dc_q=$dc_q_best
			else
				dc_i=$dc_i_best
			fi
			
			echo "  ****  dir = 0"
			
		elif (( $(echo "$dc_offset_minus <= $dc_offset_local" | bc -l) )); then
			multiplication=$(echo "$multiplication - 1" | bc -l)
			echo "  ****  dir = -1; multiplication = $multiplication"
		elif (( $(echo "$dc_offset_plus <= $dc_offset_local" | bc -l) )); then
			multiplication=$(echo "$multiplication + 1" | bc -l)
			echo "  ****  dir = +1; multiplication = $multiplication;"
		else
				echo
				echo "****  dir = FF;"
				echo
		fi
	done

	dc_q=$dc_q_best
	dc_i=$dc_i_best
}

##################

function estimate_param_1 {
	multiplication=1

	dc_q_best=$dc_q
	dc_i_best=$dc_i
	dc_offset_local=0
	#dir_prev=0
	#skip_plus=0

	if [[ $tunable_param == 0 ]]; then
		dir=$dir_q
		dir_prev=$dir_prev_q
		skip_plus=$skip_plus_q
	else
			
		dir=$dir_i
		dir_prev=$dir_prev_i
		skip_plus=$skip_plus_i
	fi

	for ((count=1; count<=$dc_inner_loop_count; count++))
	do
		[ $verbose_en = 2 ] && echo dc_inner_loop_count: $count
		if [[ $tunable_param == 0 ]]; then
			dc_i_minus=$dc_i
			dc_i_center=$dc_i
			dc_i_plus=$dc_i
			
			dc_q_minus=$(echo "$dc_q + $step*($multiplication - 2)" | bc -l)
			dc_q_center=$(echo "$dc_q + $step*($multiplication - 1)" | bc -l)
			dc_q_plus=$(echo "$dc_q + $step*($multiplication)" | bc -l)
		else
			dc_i_minus=$(echo "$dc_i + $step*($multiplication - 2)" | bc -l)
			dc_i_center=$(echo "$dc_i + $step*($multiplication - 1)" | bc -l)
			dc_i_plus=$(echo "$dc_i + $step*($multiplication)" | bc -l)
			
			dc_q_minus=$dc_q
			dc_q_center=$dc_q
			dc_q_plus=$dc_q
		fi

		######## debug ##########
		dc_q_tmp=$dc_q_minus
		dc_i_tmp=$dc_i_minus
		######## debug ##########
		
		if [[ $dir == 0 ]] || [[ $dir == -1 ]]; then

			# dc_offset_extract $fetch_addr_2nd_half $cap_size $dc_i_minus  $dc_q_minus $step
			[ $verbose_en = 1 ] && echo dc_offset_extract   cap_size:$cap_size  dc_i_minus:$dc_i_minus  dc_q_minus:$dc_q_minus step:$step

			dc_offset_extract   $cap_size  $dc_i_minus  $dc_q_minus $step
			dc_offset_minus=$dc_offset_values
			if (( $(echo "$dc_offset_values <= $dc_offset_best" | bc -l))); then
				dc_offset_best=$dc_offset_minus
				dc_q_best=$dc_q_tmp
				dc_i_best=$dc_i_tmp
				step_best=$step
				######## debug ##########
				[ $verbose_en = 5 ] &&  echo "            dc_offset_best(minus)=$dc_offset_best;"
				[ $verbose_en = 5 ] &&  echo "            dc_i_best(minus)=$dc_i_best;"
				[ $verbose_en = 5 ] &&  echo "            dc_q_best(minus)=$dc_q_best;"
				#########################
			fi
			#dc_offset_local=$dc_offset_minus
			if (( $(echo "$dc_offset_values <= $dc_offset_local" | bc -l))); then
				dc_offset_local=$dc_offset_minus
				[ $verbose_en = 2 ] &&  echo dc_offset_local $dc_offset_local
			elif [[ $dir == -1 ]]; then
				dir=0
				skip_plus=1
				dc_offset_local=0
				[ $verbose_en = 2 ] &&  echo skip_plus $skip_plus a
			fi
			
		fi 
		
		[ $verbose_en = 2 ] &&  echo skip_plus $skip_plus  b

		if [[ $skip_plus == 0 ]]; then
			[ $verbose_en = 2 ] &&  echo check_point 1 : dir=$dir
			if [[ $dir == 0 ]] || [[ $dir == 1 ]]; then		
				######## debug ##########
				dc_q_tmp=$dc_q_plus
				dc_i_tmp=$dc_i_plus
				######## debug ##########

				# dc_offset_extract $fetch_addr_2nd_half $cap_size $dc_i_plus $dc_q_plus $step
				[ $verbose_en = 1 ] &&   echo dc_offset_extract  cap_size:$cap_size  dc_i_plus:$dc_i_plus  dc_q_plus:$dc_q_plus  step:$step
				dc_offset_extract  $cap_size  $dc_i_plus  $dc_q_plus $step
				dc_offset_plus=$dc_offset_values
				if (( $(echo "$dc_offset_values <= $dc_offset_best" | bc -l))); then
					dc_offset_best=$dc_offset_plus
					dc_q_best=$dc_q_tmp
					dc_i_best=$dc_i_tmp
					step_best=$step
					######## debug ##########
					[ $verbose_en = 5 ] &&  echo "            dc_offset_best(plus)=$dc_offset_best;"
					[ $verbose_en = 5 ] &&  echo "            dc_i_best(plus)=$dc_i_best;"
					[ $verbose_en = 5 ] &&  echo "            dc_q_best(plus)=$dc_q_best;"
					#########################
				fi
				if (( $(echo "$dc_offset_values <= $dc_offset_local" | bc -l))); then
					dc_offset_local=$dc_offset_plus
					[ $verbose_en = 2 ] && echo dc_offset_local=$dc_offset_plus  plus
					dir=1
					skip_plus=0
					#switching=0		#dir found
				elif  [[ $dir == 0 ]]; then
					dir=-1
					skip_plus=1
					#switching=0		#dir found
				elif  [[ $dir == 1 ]]; then
					dir=0
					dc_offset_local=0
					skip_plus=0
				fi
			fi 
		fi
		
		#if (( $(echo "$dc_offset_center <= $dc_offset_local" | bc -l) )); then
		if [[ $dir != 0 ]]; then
			if (( $(echo "($step)/2 > 0.000005" | bc -l) )); then
				step=$(echo "($step)/2" |bc -l)
			else
				step=$(echo "$step + 0.0001" |bc -l)
			fi
			multiplication=1
			
			if [[ $switching == 1 ]]; then
				switching=0			#dir found
				if [[ $dir_prev == 0 ]]; then
					if [[ $tunable_param == 0 ]]; then
						dc_q=$dc_q_best
					else
						dc_i=$dc_i_best
					fi
				fi
			fi
			 
			[ $verbose_en = 2 ] &&  echo "  ****  dir = $dir"
			
		#elif (( $(echo "$dc_offset_minus <= $dc_offset_local" | bc -l) )); then
		elif [[ $dir_prev == -1 ]]; then
			switching=1
   			if [[ $tunable_param == 0 ]]; then
				dc_q=$dc_q_best
			  else
			  	dc_i=$dc_i_best
			  fi
				#multiplication=$(echo "$multiplication - 1" | bc -l)
				[ $verbose_en = 2 ] &&  echo "  ****  dir = -1; multiplication = $multiplication"
		#elif (( $(echo "$dc_offset_plus <= $dc_offset_local" | bc -l) )); then
		elif [[ $dir_prev == 1 ]];  then
			switching=1
			if [[ $tunable_param == 0 ]]; then
				  dc_q=$dc_q_best
		  	else
			  	dc_i=$dc_i_best
		  	fi				
        			#multiplication=$(echo "$multiplication + 1" | bc -l)
				[ $verbose_en = 2 ] &&  echo "  ****  dir = +1; multiplication = $multiplication;"
		
		else
				[ $verbose_en = 2 ] &&  echo "****  wrong dir ****"
				[ $verbose_en = 2 ] &&  echo "****  dir = FF  $dir;"
				[ $verbose_en = 2 ] &&  echo
		fi
		
		dir_prev=$dir
		skip_plus=0

		#if [[ $tunable_param == 0 ]]; then
		#	dc_q=$dc_q_best
		#else
		#	dc_i=$dc_i_best
  		#fi

		[ $verbose_en = 2 ] &&  echo check_point 2 dir=$dir
		#echo
		echo
	done

	#dc_q=$dc_q_best
	#dc_i=$dc_i_best
	if [[ $tunable_param == 0 ]]; then
		dc_q=$dc_q_best
		dir_q=$dir
		dir_prev_q=$dir_prev
		skip_plus_q=$skip_plus
	else
		dc_i=$dc_i_best
  		dir_i=$dir
		dir_prev_i=$dir_prev
		skip_plus_i=$skip_plus
  	fi
}


function tune_dc_offset {
	for ((count_out=1; count_out<=$dc_outer_loop_count; count_out++))
	do
		step=$step_dc_q_init;
		tunable_param=0
		[ $verbose_en = 1 ] &&   echo estimate_param   cap_size:$cap_size  dc_inner_loop_count:$dc_inner_loop_count  dc_i:$dc_i  dc_q:$dc_q  tunable_param:$tunable_param  step:$step  step_best:$step_best
		estimate_param   $cap_size $dc_inner_loop_count $dc_i $dc_q $tunable_param $step $step_best
		#estimate_param_1   $cap_size $dc_inner_loop_count $dc_i $dc_q $tunable_param $step $step_best
		step_dc_q_init=$step_best

		step=$step_dc_i_init;
		tunable_param=1
		[ $verbose_en = 1 ] &&   echo estimate_param   cap_size:$cap_size  dc_inner_loop_count:$dc_inner_loop_count  dc_i:$dc_i  dc_q:$dc_q  tunable_param:$tunable_param  step:$step  step_best:$step_best
		estimate_param   $cap_size $dc_inner_loop_count $dc_i $dc_q $tunable_param $step $step_best
    		#estimate_param_1   $cap_size $dc_inner_loop_count $dc_i $dc_q $tunable_param $step $step_best
		step_dc_i_init=$step_best
	done
}

########################
##### Main routine #####
########################
printf "Starting TX DC_Offset calibration ...\n"
#source ./check_dfe_cap_core_map.sh
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
printf "\n"
printf "****** Initial parameters  ******\n"
printf "\n"
printf ">  dc_q                  = %12s %sdB\n"  $dc_q
printf ">  dc_i                  = %12s %sdB\n"  $dc_i
printf ">  step_dc_i_init        = %12s %sdB\n"  $step_dc_i_init
printf ">  step_dc_q_init        = %12s %sdB\n"  $step_dc_q_init
printf ">  dc_inner_loop_count   = %12s %s\n"    $dc_inner_loop_count
printf ">  dc_outer_loop_count   = %12s %s\n"    $dc_outer_loop_count
printf ">  tone frequency        = %12s %sMHz\n"  $tone_freq
printf ">  rx_tx_LO_delta        = %12s %sMHz\n"  $rx_tx_LO_delta
printf ">  dc_offset_threshold   = %12s %sdB\n"  $dc_offset_threshold
printf "\n"                   
#printf ">  fetch_addr            = %12s %sSRX sig address\n" $fetch_addr_2nd_half
printf ">  cap_size              = %12s %sbytes\n" $cap_size
printf "\n"
printf "*********************************\n"
printf "\n"

printf "Please make sure that all the necessary parameters are correctly configured!\n"

#wait_here

#echo send_single_tone.sh  $tx_ant  $tone_freq*1000000  $amp 
#./send_single_tone.sh  $tx_ant  $tone_freq*1000000  $amp 

#sleep 0.1
[ $verbose_en = 1 ] &&  echo reaching   `basename $0` line:${LINENO}

/bin/bash $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre 0 --dim 0              > /dev/null

[ $? = 1 ] 	&&	echo "Internal error !! in  `basename $0` line:${LINENO}"


#tune_dc_offset $step_dc_i_init $dc_outer_loop_count $fetch_addr_2nd_half $cap_size $dc_inner_loop_count $dc_i $dc_q
[ $verbose_en = 1 ] &&  echo tune_dc_offset $step_dc_i_init $dc_outer_loop_count $fetch_addr_2nd_half $cap_size $dc_inner_loop_count $dc_i $dc_q  in  `basename $0` line:${LINENO}
tune_dc_offset $step_dc_i_init $dc_outer_loop_count  $cap_size $dc_inner_loop_count $dc_i $dc_q

#wait_here

# apply QEC with the best values
echo DC_Offset_threshold:${dc_offset_threshold}dB not met, applying QEC with the best values
/bin/bash $cmd_dir/imb2qec_apply.sh -p tx -a $tx_ant --dre $dc_i_best --dim $dc_q_best  -s   > /dev/null

printf "\n"
printf "****** Computed parameters  ******\n"
printf ">  dc_i       = %12s %s\n"  $dc_i
printf ">  dc_q       = %12s %s\n"  $dc_q

#killall -9 clpoc_refapp > /dev/null  2>&1

#sleep 0.01

# Start the transmission after applying QEC
#./gul_refapp -c "l1c dpd start"

# Return to the rup folder 
#if  [[ flag_cd_back -eq 1 ]]; then
#	cd ..
#fi
#wait_here
clean_files
exit 2
