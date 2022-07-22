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

source ./check_dfe_cap_core_map.sh

training_len=16384 #65536 #32768 #16384 #16384 #8192 #4096
training_tool_delay=256 # discarded segment provided by training tool designer
physical_delay=256
SYNC=NULL
dpdo_feedback_size_cal() #$1=training len
{
	block_len=$1
	dpdo_size=$(((block_len+training_tool_delay)*4))
	dpdo_size_aligned=$(((dpdo_size+32767)/32768*32768))
	dpdo_dump_addr_la=$((HRAMaddr_phy+HRAM_size-dpdo_size_aligned))
	dpdo_dump_addr_host=`phy2vir $dpdo_dump_addr_la`
	feedback_size=$(((dpdo_size+physical_delay*4)*feedback_sps/dpdo_sps))        	    		#srx size is DPDO size
	feedback_size_aligned=$(((feedback_size+32767)/32768*32768))
	feedback_dump_addr_la=$((HRAMaddr_phy+HRAM_size-feedback_size_aligned))
	feedback_dump_addr_host=`phy2vir $feedback_dump_addr_la`
	dpdo_file=tx_timedomain_$dpdo_size$tag_dpdout\_$dpdo_sps\ksps_dump_ant$ant.bin
	qeco_file=tx_timedomain_$dpdo_size\_$dpdo_sps\ksps_dump_ant$ant.bin
	feedback_file=rx_timedomain_$feedback_size\_$feedback_sps\ksps_dump_ant$ant_feedback.bin
}

dpd_out_power_increase_limit=2	#must be integer.
p_inc=0; poly_idx=0
max_nmsemyp100=0;

set_srch_init_model()
{
	dpd_model_id_para[2]=1;dpd_model_id_para[5]=1   #set p for first 2 polynomials to 1, others not used
	for ((i=2;i<n_poly;i=i+1))
	do
		dpd_model_id_para[i*3+2]=-
	done
}

update_dpd_model()
{
	p_cur=$((p_cur+1))
	p_inc=$((p_inc+1))
	if [ $p_inc -gt $((dpd_model_max_p[poly_idx*3+2]+1)) ];then 
		dpd_model_id_para[poly_idx*3+2]=$p_with_max_nmsemyp100
		p_inc=0;
		((poly_idx++))
		if [ $((poly_idx)) -ge $n_poly ];then
			echo -e "\nEND of DPD model searching ROUND $round, total searched num of models $tc. Result saved in file $dpd_model_search_report"
			num_coeff=`dpd_model_num_coeff`
			estimated_ld_dpd=`dpd_model_est_load $num_coeff`
			dpd_model_legal_check
			echo "Best DPD model  ROUND $round: `print_dpd_model` NMSE=$max_nmse, num coeff $num_coeff, Est_core_load $estimated_ld_dpd% " >> $dpd_model_search_report
			echo "Best DPD model  ROUND $round: `print_dpd_model` NMSE=$max_nmse, num coeff $num_coeff, Est_core_load $estimated_ld_dpd% "
			echo "Search End time ROUND $round: hh:mm:ss `get_running_time`" >> $dpd_model_search_report
			echo "NOTE: The NMSE values in this report are calculated from observation path dump, which is worse than real NMSE. Users should get real NMSE values on equipment." >> $dpd_model_search_report
			echo "NOTE: The NMSE values are calculated from observation path dump, which is worse than real NMSE. Users should get real NMSE values on equipment."
			if [ $round -lt 2 ];then
				echo Please choose next step:
				echo 1 Continue next ROUND of searching,
				echo 0 Stop searching and apply the best model.
				read -t 20 -p "Your choice (Timeout 20s to next round): " choice
			else
				#read -p "Press ENTER to apply the best DPD model and check NMSE on equipment: " choice
				choice=0
				echo
			fi
			
			echo
			if [ "$choice" = 0 ];then
				srch=0; training_cout=4   #4 iterations for best model
				dpdo_feedback_size_cal $training_len 
				final_print="\nBest DPD model found and applied $training_cout iterations, best DPD model=`print_dpd_model`\nPlease check NMSE on equipment, search report file: $dpd_model_search_report\n"
				return
			else
				poly_idx=0; round=$((round+1))
			fi
		fi
		p_cur=0
		p_with_max_nmsemyp100=${dpd_model_id_para[poly_idx*3+2]}
	fi
	
	if [ $p_cur -eq $((dpd_model_max_p[poly_idx*3+2]+1)) ];then dpd_model_id_para[poly_idx*3+2]=-
	else dpd_model_id_para[poly_idx*3+2]=$p_cur
	fi
}


print_usage()
{
echo "usage ./dpd_training_close_loop.sh <ant_id_tx> <ant_id_fd> <training_count> [srch] [offset=X]"
echo "ant_id_tx:      ant_id 0,1,2,3 of LS TX channel to be trained"
echo "ant_id_fd:      ant_id 0,1,2,3,4,5 of feedback channel"
echo "srch:           automatic searching for best DPD model"
echo "offset=x:       DPD output dump offset from boundary, x=1-0x7F, num of 64KB. For example offset=5 will set the dump to start from offset 320KB after the boundary"
echo "	              offset should be set to multiple of 5 for DPD training"
echo "                SRX dump offset will be derived from DPD output offset according to TX/RX sampling rate. DPD dump offset setting should make sure SRX offset is multiple of 32KB"
echo "                for example for TX 491Msps and RX 245Msps, offset setting offset=5 will result in SRX offset to 2.5 which is not a legal number. So in this case, set offset=10"
echo "training_count: number of training times. 1-just train 1 time.  Can be any integer number. "
echo
}
[ $# = 0 ] && { print_usage; exit; }
ant=0
ant_feedback=0
training_cout=1
num_counter=0
fstop=1
dcm=0; tagdcm=("" dcm); srch=0
dpdpath=./dpd_training
final_print="\nDPD Training done.\n"
tag_dpdo=dpdo; tag_dpdout=_DPDoutput
offset_granul=65536  #a valude determined by vspa, do not change
offset=10 #default offset 5 symbols for 491Msps, can change

arg_parse()
{
	arg=$1
	if [ $1 = fstop ]; then							fstop=1
	elif [ $1 = nstop ]; then						fstop=0
	elif [ $1 = dcm ]; then							dcm=1
	elif [ $1 = srch ]; then						srch=1
	elif [ ${arg:0:7} = offset= ]; 	then			offset=${arg:7}; offset=$((offset))
	elif [ $1 = help ]; then						print_usage; exit;
	else
		if [ $num_counter = 0 ];then
			ant=$(get_ant_id_from_arg $1)
			[ $ant = null ] && { echo Wrong Argument; print_usage; exit; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 1 ];then
			ant_feedback=$(get_ant_id_from_arg $1)
			[ $ant_feedback = null ] && { echo Wrong Argument; print_usage; exit; }
			num_counter=$((num_counter+1))
		elif [ $num_counter = 2 ];then
			training_cout=$(($1))
			num_counter=$((num_counter+1))
		else
			echo ***ERROR: Illegal argument $1
			print_usage; exit;
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done
[ $offset -gt $((0x3F)) ] && { echo -e "***ERROR: offset must be no larger than $((0x3F))\n"; exit 1; }
check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }
txcore=${anttx[$ant]}
tid=${tidant[$ant]}

check_ant_enable_rx $ant_feedback #[ $((ant_enable[ant_feedback]&BITMASK_ANT_ENABLE_RX)) = 0 ] && { echo ***ERROR: Current RX ant $ant_feedback is not enabled.; exit 1; }
rxcore=${antrx[$ant_feedback]}
rid=${ridant[$ant_feedback]}

get_chan_para $ant_feedback $rxcore
[ $ant_feedback -ge 4 ] && ant_buf_size_rx=$(((block_size*downsampling_ratio)>>hsdiv2)) || ant_buf_size_rx=$((block_size*downsampling_ratio))
([ $rx_fdd = 0 ] && [ $((rx_allowed_ext)) -ne 15 ]) && { echo "***ERROR: RX feedback path must be set in FDD mode or TDD listening mode for DPD close loop testing. TX path can be TDD or FDD."; exit; }
feedback_sps=$((rxaxiq*(1-dcm) + baseband_rxsps*dcm))

get_chan_para $ant $txcore
ant_buf_size_tx=$(((block_size*upsampling_ratio)>>lsdiv2))
[ $((dpd_model_id)) -eq 0 ] && { echo DPD is disabled in current VSPA image, command failed.; echo; exit 1; }
dpd_model_get_para
num_coeff=`dpd_model_num_coeff`	
((dpdo_sps=baseband_txsps*dpd_sps_ratio))
echo ant_buf_size_tx=$ant_buf_size_tx, ant_buf_size_rx=$ant_buf_size_rx
[ $(((offset*offset_granul)%ant_buf_size_tx)) -ne 0 ] && { echo -e "***ERROR: offset must be multiple of $ant_buf_size_tx for DPD dump, set offset to multiple of 5\n"; exit 1; }

offset_rx_dump=$((offset*feedback_sps/dpdo_sps))
[ $offset_rx_dump -gt $((0x3F)) ] && { echo -e "***ERROR: offset for feedback dump $offset_rx_dump must be no larger than $((0x3F)). Reduce offset value.\n"; exit 1; }
[ $((offset_rx_dump*dpdo_sps/feedback_sps)) -ne $offset ] && { echo -e "***ERROR: offset for RX dump is not integer, please double offset\n"; exit 1; }

tc=0
round=1
((n_poly=${#dpd_model_id_para[@]}/3))
dpd_model_search_report=$dpdpath/dpd_model_search_report$(date "+%Y%m%d%H%M")
if [ $srch = 1 ];then
	[ $baseband_txsps -ne $txaxiq ] && { echo "***ERROR: Command aborted. Current VSPA image does not support DPD model searching (Only T4x image supports)"; echo; exit 1; }
	dpdo_feedback_size_cal $training_len  #4096    #can set smaller len for faster running
	set_srch_init_model
	p_with_max_nmsemyp100=${dpd_model_id_para[poly_idx*3+2]}
	p_cur=0; dpd_model_id_para[poly_idx*3+2]=$p_cur
	echo -e "DPD model searching command ./dpd_training_close_loop.sh $1 $2 $3 $4, dpd_out_power_increase_limit=$dpd_out_power_increase_limit \nSearch start time: hh:mm:ss `get_running_time`" >> $dpd_model_search_report
	echo "Big model for searching =`print_dpd_model_max`" >> $dpd_model_search_report
else
	dpdo_feedback_size_cal $training_len
fi

coef_file=$dpdpath/dpd_coeff_vspa.flp

log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e21ff 0x00040000`  #restore to 5G waveform #stop single tone in case channel is sending single tone

if [ $fstop = 1 ];then ./channels_act_tx.sh $ant   #set only required TX channel active for DPD training, other channels set idle because DPD training tool may cause DDR busy and cause other channels underrun
fi

while [ 1 ]
do
dpd_model_legal_check
echo "DPD model: `print_dpd_model`"
str1="${dpd_model_id_para[@]}"
str2="${dpd_model_id_para_pre[@]}"
if [ "$str1" != "$str2" ];then
	echo DPD model changed, set DPD to passthrough; 
	dpd_model_id_para_pre=(${dpd_model_id_para[@]}) 
	echo "dpd_model_id_para_pre=(${dpd_model_id_para[@]})" >> ./runtime_config.txt
	mailbox_msg_send_dpd_passthrough $txcore $tid 
fi 

dpd_model_spec_file_gen

[ -f $dpdo_file ] && rm $dpdo_file; [ -f $feedback_file ] && rm $feedback_file; [ -f $coef_file ] && rm $coef_file; 

record_id=0
tag=(1st 2nd last)

echo "Dumping DPD output to file $dpdo_file"
echo dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
dumpfile $dpdo_dump_addr_host $dpdo_file $dpdo_size

log=`python3 ./utils/calc_pwr.py -i $dpdo_file -f $((1000*dpdo_sps))`
pwr_ori=${log:${#log}-6}
pwr00=$pwr_ori\00
argpwr=(${pwr00//./ })
pwrmpy100_ori=${argpwr[0]}${argpwr[1]:0:2}

echo "Dumping feedback to file $feedback_file"
echo dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
dumpfile $feedback_dump_addr_host $feedback_file $feedback_size


#split feedback dump into multiple files
if [ $feedback_sps -gt $dpdo_sps ];then
	addr_dump_vir=`phy2vir $addr_dump`
	./utils/memcpy $feedback_dump_addr_host $addr_dump_vir $((feedback_size/4)) $((feedback_sps/dpdo_sps)) 1
	newsize=$((feedback_size/(feedback_sps/dpdo_sps)))
	for ((count=0;count<feedback_sps/dpdo_sps;count++))
	do
		dumpfile $((addr_dump_vir+count*newsize)) rx_timedomain_${newsize}_${dpdo_sps}ksps_dump_ant${ant_feedback}_$((feedback_sps/dpdo_sps))_${count}.bin $newsize
	done
fi

[ $srch = 1 ] && { training_cout=10; nmse_pre=0; max_iteration=$training_cout; }
for ((i=1;i<=$training_cout;i++))
do
	echo -e "\n*****************************DPD CLOSE LOOP TRAINING RUN COUNTER = $i **************************************"

	[ -f $dpdo_file ] || { echo File $dpdo_file does not exist, command failed.; echo; exit; }
	[ -f $feedback_file ] || { echo File $feedback_file does not exist, command failed.; echo; exit; }

	#if [ $deqec = 1 ];then
	#	echo ./dump_time_domain_tx.sh $ant $dpdo_size HRAM fast   #dump QEC output and de-qec to get DPDO file.
	#	./dump_time_domain_tx.sh $ant $dpdo_size HRAM fast
	#	echo Rounding and truncating samples from 16bit to 12bit, and de-qec TX dump to get training ref file.
	#	vspa_status_vir=`phy2vir $addr_vspa_status`   addr_vspa_status was removed****
	#	f1=`devmem $((vspa_status_vir)) w`
	#	f2=`devmem $((vspa_status_vir+4)) w`
	#	f4=`devmem $((vspa_status_vir+8)) w`
	#	gainI=`devmem $((vspa_status_vir+12)) w`
	#	gainQ=`devmem $((vspa_status_vir+16)) w`
	#	dcoffI=`devmem $((vspa_status_vir+20)) w`
	#	dcoffQ=`devmem $((vspa_status_vir+24)) w`
	#	addr_vir=`phy2vir $addr_dump`
	#	filesize=$(stat --format=%s $dpdo_file)
	#	loadfile $addr_vir $qeco_file
	#
	#	echo ./utils/deqec $addr_vir $((filesize/4)) $f1 $f2 $f4 $gainI $gainQ $dcoffI $dcoffQ
	#	./utils/deqec $addr_vir $((filesize/4)) $f1 $f2 $f4 $gainI $gainQ $dcoffI $dcoffQ
	#	dumpfile $addr_vir $dpdo_file $filesize
	#fi
	
	if [ $fstop = 1 ];then log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e0000 0x00040000`; echo Ant $ant is set idle before training.
	fi
	
		dpdo_fb_ratio=$((dpdo_sps/feedback_sps)); fb_dpdo_ratio=$((feedback_sps/dpdo_sps))
		if [ $dpdo_fb_ratio -eq 1 ];then
			srx_resampling_arg=0
		elif [ $dpdo_fb_ratio -eq 2 ];then
			srx_resampling_arg=1
		elif [ $fb_dpdo_ratio -eq 2 ];then
			srx_resampling_arg=3
		elif [ $fb_dpdo_ratio -eq 4 ];then
			srx_resampling_arg=5
		else
			echo Error sampling rate configuration: DPDoutput=$dpdo_sps ksps, feedback=$feedback_sps ksps.; exit 1;
		fi

		if [ $SYNC == NULL ];then
			echo "$dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $block_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -d 0.00001"
			log=$($dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $block_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -d 0.00001)
			echo "$log"
			SYNC=$(echo "$log" | tail -n 1)
		else
			echo "$dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $block_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -t $SYNC -d 0.00001"
			log=$($dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $block_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -t $SYNC -d 0.00001)
			echo "$log"
		fi
		nmse=$(echo "$log" | grep "NMSE" | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$')
		cp ./dpd_coeff_vspa.flp ./dpd_coeff_vspa_ant$ant.flp 

	check_error_ant $ant #./check_error.sh
	check_error_ant $ant_feedback
	if [ $fstop = 1 ];then log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e21ff 0x00040000`; echo Ant $ant is set active after training.
	fi
	
	if [ -f dpd_coeff_vspa.flp ];then
	mv dpd_coeff_*.* $dpdpath/
	output_turn_off $txcore $tid #shut down TX output to AXIQ before applying DPD coeff to avoid PA damage before TX power is checked
	echo TX signal shut down before applying DPD coeff.
	
	ncvt=0
	addr_phy=$addr_dump
	addr_vir=`phy2vir $addr_phy`
	loadfile $addr_vir $coef_file
	update_dpd_coeff #./update_dpd_coeff.sh $ant $coef_file
	
	#save the first 2 and the last training record
	cp $dpdo_file $dpdpath/dpd_training_record_file_dpdo_ant$ant\_${tag[record_id]}.bin
	cp $feedback_file $dpdpath/dpd_training_record_file_feedback_ant$ant_feedback\_${tag[record_id]}.bin
	cp $coef_file $dpdpath/dpd_training_record_file_coef_ant$ant\_${tag[record_id]}.bin
	
	((record_id++))
	[ $record_id -eq 3 ] && record_id=2
	else
	echo -e "***ERROR: DPD training failed. File $coef_file does not exist, command failed, DPD coeff not updated."
	read -t 20 -p "Press CTRL+C to abort. ENTER to continue: " yesno
	fi

	echo "Dumping DPD output to file $dpdo_file"
	echo dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
	dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
	dumpfile $dpdo_dump_addr_host $dpdo_file $dpdo_size

	log=`python3 ./utils/calc_pwr.py -i $dpdo_file -f $((1000*dpdo_sps))`   #check TX power
	pwr=${log:${#log}-6}
	pwr00=$pwr\00
	argpwr=(${pwr00//./ })
	pwrmpy100=${argpwr[0]}${argpwr[1]:0:2}
	
	flag_power_too_high=0
	if [ $((pwrmpy100-pwrmpy100_ori)) -ge $((dpd_out_power_increase_limit*100)) ];then
		flag_power_too_high=1
		echo ***WARNING: DPD training caused power increase exceeding limit, power before training=$pwr_ori, after traing=$pwr. Set DPD to passthrough.
		mailbox_msg_send_dpd_passthrough $txcore $tid 
		output_turn_on $txcore $tid $ant		#resume TX output to AXIQ
		echo TX signal resumed.
		break;
	fi

	output_turn_on $txcore $tid $ant		#resume TX output to AXIQ
	echo TX signal resumed.
	
	echo "Dumping feedback to file $feedback_file"
	echo dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
	dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
	dumpfile $feedback_dump_addr_host $feedback_file $feedback_size

	##split feedback dump into multiple files
	#if [ $feedback_sps -gt $dpdo_sps ];then
	#	addr_dump_vir=`phy2vir $addr_dump`
	#	./utils/memcpy $feedback_dump_addr_host $addr_dump_vir $((feedback_size/4)) $((feedback_sps/dpdo_sps)) 1
	#	newsize=$((feedback_size/(feedback_sps/dpdo_sps)))
	#	for ((count=0;count<feedback_sps/dpdo_sps;count++))
	#	do
	#		dumpfile $((addr_dump_vir+count*newsize)) rx_timedomain_${newsize}_${dpdo_sps}ksps_dump_ant${ant_feedback}_$((feedback_sps/dpdo_sps))_${count}.bin $newsize
	#	done
	#fi
	
	if [ $srch = 1 ];then
		nmse_current=$(echo "$nmse * 10000 / 1" | scale=0 bc)
		echo nmse_current=$nmse_current, nmse_pre=$nmse_pre
		if [ $nmse_current -lt $nmse_pre ];then
			nmse_pre=$nmse_current
		else
			max_iteration=$((i-1))
			break
		fi
	fi

done

[ $srch = 0 ] && { echo -e $final_print; exit; }

if [ $flag_power_too_high = 0 ];then
	#log=`python3 ./utils/calc_aclr.py -i $feedback_file -f $((1000*feedback_sps))`
	##aclr=${log:${#log}-6}
	##aclr00=$aclr\00
	#list=($(echo $log | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$'))
	#aclr_lower=${list[0]}
	#aclr_upper=${list[1]}
	#aclr_sum=$(echo "scale=2; $aclr_lower + $aclr_upper" | bc -l)
	#aclr_avg=$(echo "scale=2; $aclr_sum/2" | bc -l)
	#aclr00=$aclr_avg\00
	#argaclr=(${aclr00//./ })
	#aclrmpy100=${argaclr[0]}${argaclr[1]:0:2}
	##echo aclr=$aclr aclrmpy100=$aclrmpy100
	##[ $((aclrmpy100)) -lt $max_aclrmyp100 ] && { max_aclrmyp100=$aclrmpy100; p_with_max_aclrmyp100=${dpd_model_id_para[poly_idx*3+2]}; max_aclr=$aclr; }
	#echo aclr_avg=$aclr_avg aclrmpy100=$aclrmpy100
	#[ $((aclrmpy100)) -lt $max_nmsemyp100 ] && { max_nmsemyp100=$aclrmpy100; p_with_max_aclrmyp100=${dpd_model_id_para[poly_idx*3+2]}; max_aclr=$aclr_avg; }

	argnmse=(${nmse//./ })
	nmsempy100=${argnmse[0]}${argnmse[1]:0:3}
	echo nmse=$nmse nmsempy100=$nmsempy100
	[ $((nmsempy100)) -lt $max_nmsemyp100 ] && { max_nmsemyp100=$nmsempy100; p_with_max_nmsemyp100=${dpd_model_id_para[poly_idx*3+2]}; max_nmse=$nmse; }

	num_coeff=`dpd_model_num_coeff`
	estimated_ld_dpd=`dpd_model_est_load $num_coeff`
	echo dpd_model_searched_idx_$tc=`print_dpd_model`, max_iteration=$max_iteration, NMSE=$nmse, DPD out power before training=$pwr_ori, after traing=$pwr, num coeff $num_coeff, Est_core_load=$estimated_ld_dpd% >> $dpd_model_search_report
else
	echo "dpd_model_searched_idx_$tc=`print_dpd_model`, DPD out power before training=$pwr_ori, after traing=$pwr, Power increase exceeding limit, Model skipped"
	echo "dpd_model_searched_idx_$tc=`print_dpd_model`, DPD out power before training=$pwr_ori, after traing=$pwr, Power increase exceeding limit, Model skipped" >> $dpd_model_search_report
fi
tc=$((tc+1))
update_dpd_model

done 
