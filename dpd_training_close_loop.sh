#!/bin/bash
# Copyright 2022-2025 NXP
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
filt_trans=1024 # discarded segment provided by training tool designer
physical_delay=256
SYNC=NULL
yesno=""
dpd_out_power_increase_limit=2	#must be integer.
p_inc=0; poly_idx=0
max_nmsemyp100=0;
dbFS=0; mem=0

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
echo "usage ./dpd_training_close_loop.sh <ant_id_tx> <ant_id_fd> <training_count> [srch] [offset=X] [mem]"
echo "ant_id_tx:      ant_id 0,1,2,3 of LS TX channel to be trained"
echo "ant_id_fd:      ant_id 0,1,2,3,4,5 of feedback channel"
echo "srch:           automatic searching for best DPD model"
echo "offset=x:       DPD output dump offset from boundary, x=1-0x7F, num of 64KB. For example offset=5 will set the dump to start from offset 320KB after the boundary"
echo "mem:            source data of ref and srx from memory. if not specified, source data from dump files"
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
dcm=0; srch=0
dpdpath=./dpd_training
final_print="\nDPD Training done.\n"
offset_granul=65536  #a valude determined by vspa, do not change
offset=10 #default offset 5 symbols for 491Msps, can change

arg_parse()
{
	arg=$1
	if [ $1 = fstop ]; then							fstop=1
	elif [ $1 = nstop ]; then						fstop=0
	elif [ $1 = dcm ]; then							dcm=1
	elif [ $1 = srch ]; then						srch=1
	elif [ $1 = mem ]; then							mem=1
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
[ $test_vector_on_hram = 1 ] && fstop=0
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


dpdo_size=$(((training_len+filt_trans*2)*4))
dpdo_size_aligned=$(((dpdo_size+32767)/32768*32768))
feedback_size=$(((dpdo_size+physical_delay*4)*feedback_sps/dpdo_sps))        	    		#srx size is DPDO size
feedback_size_aligned=$(((feedback_size+32767)/32768*32768))
dpdo_dump_addr_la=$((HRAMaddr_phy+HRAM_size-dpdo_size_aligned-feedback_size_aligned))
[ $((next_HRAMaddr_phy)) -gt $((dpdo_dump_addr_la)) ] && { echo ***ERROR: HRAM available size is not enough.; exit 1; }
dpdo_dump_addr_host=`phy2vir $dpdo_dump_addr_la`
feedback_dump_addr_la=$((HRAMaddr_phy+HRAM_size-feedback_size_aligned))
feedback_dump_addr_host=`phy2vir $feedback_dump_addr_la`
coef_file=$dpdpath/dpd_coeff_vspa_ant$ant.flp
ref_file=$dpdpath/dump_ref_ant$ant.bin; srx_file=$dpdpath/dump_srx_ant$ant.bin
[ $mem = 0 ] && option_r_s="-r $ref_file -s $srx_file" || option_r_s="-r $dpdo_dump_addr_host:$((dpdo_size/4)) -s $feedback_dump_addr_host:$((feedback_size/4))"

tc=0
round=1
((n_poly=${#dpd_model_id_para[@]}/3))
dpd_model_search_report=$dpdpath/dpd_model_search_report$(date "+%Y%m%d%H%M")
if [ $srch = 1 ];then
	[ $baseband_txsps -ne $txaxiq ] && { echo "***ERROR: Command aborted. Current VSPA image does not support DPD model searching (Only T4x image supports)"; echo; exit 1; }
	set_srch_init_model
	p_with_max_nmsemyp100=${dpd_model_id_para[poly_idx*3+2]}
	p_cur=0; dpd_model_id_para[poly_idx*3+2]=$p_cur
	echo -e "DPD model searching command ./dpd_training_close_loop.sh $1 $2 $3 $4, dpd_out_power_increase_limit=$dpd_out_power_increase_limit \nSearch start time: hh:mm:ss `get_running_time`" >> $dpd_model_search_report
	echo "Big model for searching =`print_dpd_model_max`" >> $dpd_model_search_report
fi


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

[ -f $coef_file ] && rm $coef_file; 

echo dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
[ $flag_deqec = 1 ] && { echo deqec; deqec $txcore $dpdo_dump_addr_host $((dpdo_size/4)); }
check_sample_power $dpdo_dump_addr_host $((dpdo_size/4))
pwr_ori=$dbFS
pwr00=$pwr_ori\00
argpwr=(${pwr00//./ })
pwrmpy100_ori=${argpwr[0]}${argpwr[1]:0:2}

echo dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
check_sample_power $feedback_dump_addr_host $((feedback_size/4))

[ $srch = 1 ] && { training_cout=10; nmse_pre=0; max_iteration=$training_cout; }
for ((i=1;i<=$training_cout;i++))
do
	echo -e "\n*****************************DPD CLOSE LOOP TRAINING RUN COUNTER = $i **************************************"

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
		elif [ $fb_dpdo_ratio -eq 8 ];then
			srx_resampling_arg=7
		else
			echo Error sampling rate configuration: DPDoutput=$dpdo_sps ksps, feedback=$feedback_sps ksps.; exit 1;
		fi

		if [ $mem = 0 ];then
			dumpfile $dpdo_dump_addr_host $ref_file $dpdo_size
			dumpfile $feedback_dump_addr_host $srx_file $feedback_size
		fi
		
		if [ $SYNC == NULL ];then
			echo "$dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len $option_r_s -x $srx_resampling_arg -d 0.00001"
			log_dpdt=$($dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len $option_r_s -x $srx_resampling_arg -d 0.00001)
			ret=$?; echo dpdt return value: $ret
			echo "$log_dpdt"
			#[ $ret -ne 0 ] && { echo DPD training error: error code $ret; read -t 10 -p "Press CTRL+C to abort. ENTER to continue: " yesno; }
			SYNC=$(echo "$log_dpdt" | tail -n 1)
		else
			echo "$dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len $option_r_s -x $srx_resampling_arg -t $SYNC -d 0.00001"
			log_dpdt=$($dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len $option_r_s -x $srx_resampling_arg -t $SYNC -d 0.00001)
			ret=$?; echo dpdt return value: $ret
			echo "$log_dpdt"
			#[ $ret -ne 0 ] && { echo DPD training error: error code $ret; read -t 10 -p "Press CTRL+C to abort. ENTER to continue: " yesno; }
		fi
		if [ $fstop = 1 ];then log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e21ff 0x00040000`; echo Ant $ant is set active after training.
		fi
		nmse=$(echo "$log_dpdt" | grep "NMSE" | tr ' ' '\n' | grep -E '^[+-]?[0-9]*\.?([0-9]+)$')
		[ "$nmse" = "" ] && { nmse=0; read -p "***ERROR NMSE, press ENTER to continue, CTRL+C to quit: " choice1; }
	
	log=`check_error_ant $ant`; echo -e "$log"; [ "$log" != "" ] && exit 1
	[ $ant -ne $ant_feedback ] && { log=`check_error_ant $ant_feedback`; echo -e "$log"; [ "$log" != "" ] && exit 1; }
	
	if [ -f dpd_coeff_vspa.flp ];then
	mv ./dpd_coeff_vspa.flp $dpdpath/dpd_coeff_vspa_ant$ant.flp 
	#output_turn_off $txcore $tid #shut down TX output to AXIQ before applying DPD coeff to avoid PA damage before TX power is checked
	#echo TX signal shut down before applying DPD coeff.
	
	ncvt=0
	addr_phy=$addr_dump
	addr_vir=`phy2vir $addr_phy`
	loadfile $addr_vir $coef_file
	update_dpd_coeff
	
	echo dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
	dump_time_domain_tx_1time $txcore $tid $dpdo_dump_addr_la $dpdo_dump_addr_host $dpdo_size_aligned 1 0 offset=$offset
	[ $flag_deqec = 1 ] && { echo deqec; deqec $txcore $dpdo_dump_addr_host $((dpdo_size/4)); }
	check_sample_power $dpdo_dump_addr_host $((dpdo_size/4))
	pwr=$dbFS
	pwr00=$pwr\00
	argpwr=(${pwr00//./ })
	pwrmpy100=${argpwr[0]}${argpwr[1]:0:2}
	
	flag_power_too_high=0
	if [ $((pwrmpy100-pwrmpy100_ori)) -ge $((dpd_out_power_increase_limit*100)) ];then
		flag_power_too_high=1
		echo ***WARNING: DPD training caused power increase exceeding limit, power before training=$pwr_ori, after traing=$pwr. Set DPD to passthrough.
		mailbox_msg_send_dpd_passthrough $txcore $tid 
		#output_turn_on $txcore $tid 		#resume TX output to AXIQ
		#echo TX signal resumed.
		break;
	fi

	#output_turn_on $txcore $tid 		#resume TX output to AXIQ
	#echo TX signal resumed.
	
	echo dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
	dump_time_domain_rx_1time $rxcore $rid $feedback_dump_addr_la $feedback_dump_addr_host $feedback_size_aligned $dcm offset=$offset_rx_dump
	check_sample_power $feedback_dump_addr_host $((feedback_size/4))

	else
	echo -e "***ERROR: DPD training failed. File $coef_file does not exist, command failed, DPD coeff not updated."
	[ "$yesno" = "" ] && read -t 20 -p "Press CTRL+C to abort. ENTER to continue: " yesno
	yesno=yes
	fi

	if [ $srch = 1 ];then
		nmse_current=$(echo "$nmse * 10000 / 1" | scale=0 bc)
		echo nmse_current=$nmse_current, nmse_pre=$nmse_pre
		if [ $((nmse_current)) -lt $((nmse_pre)) ];then
			nmse_pre=$nmse_current
		else
			max_iteration=$((i-1))
			break
		fi
	fi
done

[ $srch = 0 ] && { echo -e $final_print; exit; }

if [ $flag_power_too_high = 0 ];then
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
