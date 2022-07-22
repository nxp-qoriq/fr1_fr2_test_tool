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

#./regression_test.sh [image_folder_name]
# Test tool regression test script, if the test passes it means test tool is functioning well with current BSP
# Regression test should be done after new features are added in test tool, or added in BSP which may impact test tool.
# If image_folder_name is specified, the test will be performed only on the specified image. otherwise the test will be performed on all images listed below

[ $# = 0 ] && { echo "usage: ./regression_test.sh <image_folder_name> [fdd|tdd]"; exit 1; }

channel_start_arg=""
if [ $# -ge 1 ];then
	images=($1)
	image_name=$1
	start_fddtdd=0
	end_fddtdd=1
	
	if [ $# -ge 2 ];then
		if [ $2 = fdd ];then
			start_fddtdd=0
			end_fddtdd=0  #test FDD only	
		elif [ $2 = tdd ];then
			start_fddtdd=1
			end_fddtdd=1  #test FDD only	
		else
			channel_start_arg="$channel_start_arg $2"
		fi
		
		if [ $# -ge 3 ];then
			channel_start_arg="$channel_start_arg $3"
		fi
	fi
fi

qec_coeff=(
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x3F812F32
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x00000000    0x00000000
0x00000000    0x00000000    0x3F814CAB    0x3E1248AA
0x3F800000    0x3F800000    0x00000000    0x00000000
0x00000000 )

qec_coeff_update() #$1=tx or rx  $2=ant_id
{
	local i=0;
	for((i=0;i<${#qec_coeff[@]};i++))
	do
		./utils/memrw w 32 $((addr_dump_vir+i*4)) ${qec_coeff[i]}
	done
	./update_qec_coeff_$1.sh $2 $addr_dump_vir >> $log_file
}

phcom_coeff_update()  #$1=tx or rx  $2=ant_id
{
	local i=0;
	for((i=0;i<14;i++))
	do
		./utils/memrw w 32 $((addr_dump_vir+i*8+0)) `./utils/hex2float -r 1.25`
		./utils/memrw w 32 $((addr_dump_vir+i*8+4)) 0
	done
	./update_phase_compensation_coeff.sh $2 $addr_dump_vir $1 >> $log_file
}

num_pass=0; num_fail=0; item_idx=1
md5sum_value_pre=""
log_file=./regression_test_log.txt
echo "#" > $log_file

item_test() #$1=tag, $2 command
{
	sleep 0.1        #wait for previous command to take effective, for example prevous command send single subcarrier, current command is dumping
	local str="${FDDTDD[fddtdd]} Test $item_idx: $1"
	local log=`$2`; echo "$log" >> $log_file
	local error=`echo "$log" | grep ERROR`
	local correct=`echo $log | grep CORRECT`
	md5sum_value=`echo $log | grep md5sum`
	if [ "$correct" = "" ];then
		((num_fail++))
		str="$str FAIL***"
		echo "$str"; echo -e "$str\n\n*************************************************" >> $log_file
	elif [ "$error" = "" ];then
		if [ "$md5sum_value_pre" = "$md5sum_value" ];then
			((num_fail++))
			str="$str FAIL with same md5sum***"
			echo "$str"; echo -e "$str\n\n*************************************************" >> $log_file
			echo -e "$log"
		else
			((num_pass++))
			str="$str PASS"
			echo "$str"; echo -e "$str\n\n*************************************************" >> $log_file
		fi
	else
		((num_fail++))
		str="$str FAIL with error***"
		echo "$str"; echo -e "$str\n\n*************************************************" >> $log_file
		echo -e "$log"
	fi
	md5sum_value_pre="$md5sum_value"
	((item_idx++))
}

echo -e "\nTest Tool Regression Test. \nThe Test will take some time, please be patient..."
FDDTDD=(FDD TDD)
tddtddmode=("" tdd)
for((n=0;n<${#images[@]};n++))
do
arg=${images[n]}
echo -n ./boot_vspa.sh $arg; ./boot_vspa.sh $arg >> $log_file
[ $? -ne 0 ] && { echo -e "***ERROR: Failure in booting VSPA, need reboot."; exit 1; }
[ -f ./boot_vspa_log.txt ] && source ./boot_vspa_log.txt || { echo ***ERROR: boot_vspa_log.txt does not exist, command failed.; exit 1; }
echo "   ### VSPA IMAGE Being Tested: $vspa_image_folder_name"
hs=`echo $vspa_image_folder_name | grep _HS`
AD_ME=${vspa_image_folder_name:0:2}

source ./config.dat

for((fddtdd=start_fddtdd;fddtdd<=$end_fddtdd;fddtdd++))
do
	echo Testing ${FDDTDD[fddtdd]}
	
	[ "$hs" != "" ] && { lb=lb; } || { lb=lb; }
	
	dcs=""
	([ $vspa_dev_type = LA9310 ] && [ $fddtdd = 0 ]) && dcs=dcs1
	
	echo ./channels_start.sh restart ${tddtddmode[fddtdd]} $lb $dcs idle $channel_start_arg
	chlog=`./channels_start.sh restart ${tddtddmode[fddtdd]} $lb $dcs idle $channel_start_arg`
	[ $? != 0 ] && { echo -e "***ERROR: Failure in starting channels, need reboot."; exit 1; }
	echo "$chlog" >> $log_file
	source ./config.dat #channels_start.sh will update parameters in runtime_config.txt which is included in config.dat
	
	for ((i=0;i<num_T_LS_enabled;i++))
	do
		core=$((anttx[i]))
		./send_single_tone.sh $i stop >> $log_file   #get out of idle
		item_test "Ant $i TX time domain TM waveform dump : " "./dump_time_domain_tx.sh $i"
		phcom_coeff_update tx $i #; read -p "press a key" yesno
		item_test "Ant $i TX phase compensation dump      : " "./dump_time_domain_tx.sh $i"
		./update_phase_compensation_coeff.sh $i dis >> $log_file
		./update_fine_cfo_nco_freq.sh $i 30000 >> $log_file 
		item_test "Ant $i TX FINE CFO dump                : " "./dump_time_domain_tx.sh $i"
		./update_fine_cfo_nco_freq.sh $i 0 >> $log_file 
		./send_single_tone.sh $i >> $log_file
		item_test "Ant $i TX time domain single tone dump : " "./dump_time_domain_tx.sh $i"
		if [ $fddtdd = 0 ];then #two tones test only in FDD
		./send_single_tone.sh $i 10000000 add >> $log_file
		item_test "Ant $i TX time domain two tones dump   : " "./dump_time_domain_tx.sh $i"
		fi
		./send_single_tone.sh $i stop >> $log_file
		./send_single_subcarrier.sh $i 1 >> $log_file
		item_test "Ant $i TX single sub-carrier dump      : " "./dump_time_domain_tx.sh $i"
		./send_single_subcarrier.sh $i 2 add >> $log_file
		item_test "Ant $i TX two sub-carriers dump        : " "./dump_time_domain_tx.sh $i"
		./send_single_subcarrier.sh $i stop >> $log_file
		qec_coeff_update tx $i
		item_test "Ant $i TX QEC IQ imbalance update dump : " "./dump_time_domain_tx.sh $i"
		./update_qec_coeff_tx.sh $i inc dc=-0.125:0.125 >> $log_file
		item_test "Ant $i TX QEC DC offset update dump    : " "./dump_time_domain_tx.sh $i"
		./update_qec_coeff_tx.sh $i dis >> $log_file
		if [ $fddtdd = 0 ];then
		./utils/vspa_mbox send $core 0 0x08000000 0x00000001
		item_test "Ant $i TX timing offset delay1 dump    : " "./dump_time_domain_tx.sh $i"
		./utils/vspa_mbox send $core 0 0x08000000 0x80000001
		fi
		./scale_percent.sh $i 125 >> $log_file
		item_test "Ant $i TX scaling dump                 : " "./dump_time_domain_tx.sh $i"
		./scale_percent.sh $i 100 >> $log_file
		item_test "Ant $i TX time domain TM waveform dump : " "./dump_time_domain_tx.sh $i"
		
		if [ $AD_ME = AD ];then
		item_test "Ant $i DPD dump                        : " "./dump_time_domain_tx.sh $i dpdo"
		fi
		./send_single_tone.sh $i 0 0 >> $log_file   #get into idle
	done
	
	([ $vspa_dev_type = LA9310 ] && [ $fddtdd = 0 ]) && num_R_LS=1  #LA9310 supports only 1T1R for FDD
	for ((i=0;i<num_R_LS_enabled;i++))
	do
		core=$((antrx[i]))
		if ([ $vspa_dev_type = LA9310 ] && [ $i -lt $((num_T_LS)) ] && [ $fddtdd = 0 ]);then #if TX is enabled, LA9310, FDD, test loopback
		./send_single_tone.sh $i stop >> $log_file   #get TX out of idle
		item_test "Ant $i RX loopback from TX dump        : " "./dump_time_domain_rx.sh $i"
		
		./utils/vspa_mbox send $core 0 0x08000000 0x00000001
		./utils/vspa_mbox send $core 0 0x08800000 0x00000001
		item_test "Ant $i RX timing offset delay1 dump    : " "./dump_freq_domain_rx.sh $i"
		./utils/vspa_mbox send $core 0 0x08000000 0x80000001
		./utils/vspa_mbox send $core 0 0x08800000 0x80000001
		
		./update_test_vector.sh ./test_vectors/NR-FR1-TM3.3_20MHz_30kHz_1ssb_pss5_sss7_FDD_fd_640.bin >> $log_file
		item_test "Ant $i RX cell tracking                : " "./set_dfe_state.sh $i track"
		./send_single_tone.sh $i 0 0 >> $log_file   #get TX into idle
		fi
		./send_single_tone.sh rx $i >> $log_file
		item_test "Ant $i RX time domain single tone dump : " "./dump_time_domain_rx.sh $i"
		item_test "Ant $i RX freq domain single tone dump : " "./dump_freq_domain_rx.sh $i"
		phcom_coeff_update rx $i
		item_test "Ant $i RX phase compensation dump      : " "./dump_freq_domain_rx.sh $i"
		./update_phase_compensation_coeff.sh $i dis rx >> $log_file
		./update_fine_cfo_nco_freq.sh $i 30000 rx >> $log_file 
		item_test "Ant $i RX FINE CFO dump                : " "./dump_freq_domain_rx.sh $i"
		./update_fine_cfo_nco_freq.sh $i 0 rx >> $log_file 
		./send_single_tone.sh rx $i stop >> $log_file
	done
	
	hsdump_len=1ms
	for ((i=4;i<(4+num_T_HS_enabled);i++))
	do
		./send_single_tone.sh $i stop >> $log_file   #get out of idle
		item_test "Ant $i TX time domain TM waveform dump : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./send_single_tone.sh $i >> $log_file
		item_test "Ant $i TX time domain single tone dump : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./send_single_tone.sh $i stop >> $log_file
		qec_coeff_update tx $i
		item_test "Ant $i TX QEC IQ imbalance update dump : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./update_qec_coeff_tx.sh $i inc dc=-0.125:0.125 >> $log_file
		item_test "Ant $i TX QEC DC offset update dump    : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./update_qec_coeff_tx.sh $i dis >> $log_file
		./scale_percent.sh $i 125 >> $log_file
		item_test "Ant $i TX scaling dump                 : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./scale_percent.sh $i 100 >> $log_file
		item_test "Ant $i TX time domain TM waveform dump : " "./dump_time_domain_tx.sh $i $hsdump_len"
		./send_single_tone.sh $i 0 0 >> $log_file   #get into idle
	done
	
	for ((i=4;i<(4+num_R_HS_enabled);i++))
	do
		if ([ $i -lt $((4+num_T_HS)) ] && [ $fddtdd = 0 ]);then
		./send_single_tone.sh $i stop >> $log_file   #get out of idle
		item_test "Ant $i RX loopback from TX dump        : " "./dump_time_domain_rx.sh $i $hsdump_len"
		qec_coeff_update rx $i
		item_test "Ant $i RX loopback QEC IQ imb dump     : " "./dump_time_domain_rx.sh $i $hsdump_len"
		./update_qec_coeff_rx.sh $i inc dc=-0.125:0.125 >> $log_file
		item_test "Ant $i RX loopback QEC DC offset dump  : " "./dump_time_domain_rx.sh $i $hsdump_len"
		./send_single_tone.sh $i 0 0 >> $log_file   #get into idle
		fi
		./send_single_tone.sh rx $i >> $log_file
		item_test "Ant $i RX time domain single tone dump : " "./dump_time_domain_rx.sh $i $hsdump_len"
		item_test "Ant $i RX freq domain single tone dump : " "./dump_freq_domain_rx.sh $i"
		./send_single_tone.sh rx $i stop >> $log_file
	done
done

done
echo -e "num_pass=$num_pass; num_fail=$num_fail \n" >> $log_file
echo -e "\n--- Total num of items tested $((num_pass+num_fail)), PASS $num_pass, FAIL $num_fail"
echo -e "--- Test Tool Regression Test Finished, Test log is kept in $log_file\n"

echo -e "\n********************************************************************************"
if ([ $num_fail = 0 ] && [ $num_pass != 0 ]);then
echo    "***  OVERALL TEST RESULT:  PASS !"
else
echo    "***  OVERALL TEST RESULT:  FAIL !"
echo    "***  Failed items:"
grep FAIL $log_file
fi
echo -e "********************************************************************************\n"
