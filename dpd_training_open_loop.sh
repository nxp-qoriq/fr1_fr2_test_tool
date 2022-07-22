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


#After users have captured the PA output by equipment, they can use this script to do open loop training.
#The script will train DPD coefficients and apply the coefficients to DPD accuator.
#capture file data format: I0, Q0, I1, Q1, ...  (I and Q are 16 bit 2's complement, little endian, binary)
#the catpure should have at least 256K samples.
#users should provide PA output capture filename and sampling rate to this script.
#example: to do DPD training on ant 0, PA output catpure filename PA_out.bin, sampling rate 245.76Msps.
#./dpd_training_open_loop.sh 0 PA_out.bin 245760

source ./check_dfe_cap_core_map.sh

print_usage()
{
echo "usage ./dpd_training_open_loop.sh <ant_id> <PA_capture_file> <PA_capture_SPS> [offset=X]"
echo "  ant_id:          ant_id on which DPD training will be applied"
echo "  PA_capture_file: PA_output_capture done by equipment, must be aligned to PPS"
echo "  PA_capture_SPS:  PA_output_SPS are sampling rate of the PA output capture file, possible values(KSPS): 245760, 491520, 983040, 1966080 etc"
echo "  offset=x:        DPD output dump offset from boundary, x=1-0x7F, num of 64KB. For example offset=5 will set the dump to start from offset 320KB after the boundary"
echo "  example: to do DPD training on ant 0, PA output catpure filename PA_out.bin, sampling rate 245.76Msps"
echo "  ./dpd_training_open_loop.sh 0 PA_out.bin 245760"
echo
}

echo
if [ $# -lt 3 ];then
	print_usage
	echo
	exit
fi
training_len=16384 #16384 #8192 #
training_tool_delay=256 #$training_len #16384 # 256 512         #provided by training tool designer
physical_delay=256

dpdpath=./dpd_training
setool=1
fstop=1
dpd_out_power_increase_limit=2	#must be integer.
offset=10 #default offset about 5 symbols 491Msps

if [ $# -ge 4 ];then
	arg=$4
	if [ ${arg:0:7} = offset= ]; then			
		offset=${arg:7}; offset=$((offset))
		[ $offset -gt $((0x3F)) ] && { echo -e "***ERROR: offset must be no larger than $((0x3F))\n"; exit 1; }
	else
		echo -e "***ERROR: Wrong Argument $4\n"; print_usage; exit 1;
	fi
fi


[ -f $2 ] || { echo File $2 does not exist, command failed.; echo; exit; }

check_ant_enable_tx $ant #[ $((ant_enable[ant]&BITMASK_ANT_ENABLE_TX)) = 0 ] && { echo ***ERROR: Current TX ant $ant is not enabled.; exit 1; }

((ant=$1%6))
txcore=${anttx[$ant]}
tid=${tidant[$ant]}

get_chan_para $ant $txcore
ant_buf_size_tx=$(((block_size*upsampling_ratio)>>lsdiv2))
[ $(((offset*32768)%ant_buf_size_tx)) -ne 0 ] && { echo -e "***ERROR: offset must be multiple of $ant_buf_size_tx for DPD dump, set offset to multiple of 5\n"; exit 1; }
[ $((dpd_model_id)) -eq 0 ] && { echo DPD is disabled in current VSPA image, command failed.; echo; exit 1; }
dpd_model_get_para
dpd=`dpd_model_num_coeff`	

str1="${dpd_model_id_para[@]}"
str2="${dpd_model_id_para_pre[@]}"
if [ "$str1" != "$str2" ];then
	echo DPD model changed, set DPD to passthrough; 
	./update_dpd_coeff.sh $ant dis; 
	echo "dpd_model_id_para_pre=(${dpd_model_id_para[@]})" >> ./runtime_config.txt
fi
num_coeff=$dpd
((dpdo_sps=baseband_txsps*dpd_sps_ratio))

dpd_model_spec_file_gen

dpdo_size=$(((training_len+training_tool_delay)*4))
dpdo_file=tx_timedomain_$dpdo_size\_DPDoutput_$dpdo_sps\ksps_dump_ant$ant.bin
feedback_file=$2
feedback_sps=$3
feedback_122880_ratio=$((feedback_sps/122880))
([ $feedback_122880_ratio -eq 0 ] || [ $feedback_122880_ratio -gt 16 ] || [ $((feedback_122880_ratio*122880)) -ne $feedback_sps ]) && { echo ***ERROR: error feedback sampling rate. Command failed; echo; exit; }
feedback_size=$(((dpdo_size+physical_delay*4)*feedback_sps/dpdo_sps))
filesize=$(stat --format=%s $feedback_file)
[ $filesize -lt $feedback_size ] && echo -e "***WARNING: Feedback dump file size $filesize is smaller than expected $feedback_size.\n"

coef_file=$dpdpath/dpd_coeff_vspa.flp
[ -f $dpdpath/dpd_training_tool ] || setool=0

[ -f $coef_file ] && rm $coef_file

echo ./dump_time_domain_tx.sh $ant dpdo $dpdo_size HRAM offset=$offset
./dump_time_domain_tx.sh $ant dpdo $dpdo_size HRAM offset=$offset

log=`python3 ./utils/calc_pwr.py -i $dpdo_file -f $((1000*dpdo_sps))`  #get the power of DPD output
pwr_ori=${log:${#log}-6}
pwr00=$pwr_ori\00
argpwr=(${pwr00//./ })
pwrmpy100_ori=${argpwr[0]}${argpwr[1]:0:2}

if [ $fstop = 1 ];then log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e0000 0x00040000`; echo Ant $ant is set idle before training.
fi

if [ $setool = 1 ];then
	echo $dpdpath/dpd_training_tool $dpdpath/dpd_spec.cfg $training_len $dpdo_file $feedback_file $dpdo_sps $feedback_sps
	$dpdpath/dpd_training_tool $dpdpath/dpd_spec.cfg $training_len $dpdo_file $feedback_file $dpdo_sps $feedback_sps
else
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

	echo $dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -d 0.00001
	$dpdpath/dpdt -c $dpdpath/dpd_spec.cfg -b $training_len -r $dpdo_file -s $feedback_file -x $srx_resampling_arg -d 0.00001
	cp ./dpd_coeff_vspa.flp ./dpd_coeff_vspa_ant$ant.flp  
fi

if [ $fstop = 1 ];then log=`vspa_mbox send $txcore $host_vspa_mbox_id 0x0a0e21ff 0x00040000`; echo Ant $ant is set active after training.
fi

[ -f dpd_coeff_vspa.flp ] || { echo ***ERROR: DPD training failed; exit 1; }
mv dpd_coeff_*.* $dpdpath/
cp $coef_file $dpdpath/dpd_training_record_file_coef_ant$ant.bin

output_turn_off $txcore $tid #shut down TX output to AXIQ before applying DPD coeff to avoid PA damage before TX power is checked
echo TX signal shut down before applying DPD coeff.

./update_dpd_coeff.sh $ant $coef_file

echo ./dump_time_domain_tx.sh $ant dpdo $dpdo_size HRAM offset=$offset
./dump_time_domain_tx.sh $ant dpdo $dpdo_size HRAM offset=$offset
log=`python3 ./utils/calc_pwr.py -i $dpdo_file -f $((1000*dpdo_sps))`   #check TX power after DPD coeff is updated
pwr=${log:${#log}-6}
pwr00=$pwr\00
argpwr=(${pwr00//./ })
pwrmpy100=${argpwr[0]}${argpwr[1]:0:2}

if [ $((pwrmpy100-pwrmpy100_ori)) -ge $((dpd_out_power_increase_limit*100)) ];then  #power too high after training
	mailbox_msg_send_dpd_passthrough $txcore $tid 
	echo "***WARNING: DPD out power before training=$pwr_ori, after traing=$pwr, Power increase exceeding limit. DPD set to passthrough."
fi

output_turn_on $txcore $tid $ant		#resume TX output to AXIQ
echo TX signal resumed.
	
echo -e "\nDPD Training done.\n"
./check_error.sh
