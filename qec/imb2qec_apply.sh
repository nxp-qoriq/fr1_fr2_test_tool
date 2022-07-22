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

#example:
#	./imb2qec_apply.sh  -p tx -a $tx_ant   --sg $gain_init --sp $phase_init   --dre $tx_corr_dc_re --dim $tx_corr_dc_im   -s
#	./imb2qec_apply.sh  -p tx --pt -a $tx_ant;



#verbose enable
#verbose_en=0
source check_dfe_cap_core_map.sh
source qec_init.cfg

#Default/passthrough values
path="none"
#mode="none"
#path="tx"
#mode="dpdh"
ant_id=0
iq_gain_imb_dB=0
iq_phase_imb_deg=0
FD_tap_cnt=0
ssfilt_filename=0
int_delay=0
gain_re=1
gain_im=0
dc_re=0
dc_im=0

save_to_file=0

#Default/passthrough values for previous parameters
prev_path="none"
#prev_mode="none"
prev_ant_id=0
prev_iq_gain_imb_dB=0
prev_iq_phase_imb_deg=0
prev_FD_tap_cnt=0
prev_ssfilt_filename=0
prev_int_delay=0
prev_gain_re=1
prev_gain_im=0
prev_dc_re=0
prev_dc_im=0

function set_passthrough_values {
iq_gain_imb_dB=0
iq_phase_imb_deg=0
FD_tap_cnt=0
ssfilt_filename=0
int_delay=0
gain_re=1
gain_im=0
dc_re=0
dc_im=0
}

function update_prev_values {
prev_iq_gain_imb_dB=$iq_gain_imb_dB
prev_iq_phase_imb_deg=$iq_phase_imb_deg
prev_FD_tap_cnt=$FD_tap_cnt
prev_ssfilt_filename=$ssfilt_filename
prev_int_delay=$int_delay
prev_gain_re=$gain_re
prev_gain_im=$gain_im
prev_dc_re=$dc_re
prev_dc_im=$dc_im
}

pt=0


function show_help {
	echo "qec_apply.sh usage:"
	echo
	echo "		imb2qec_apply.sh helps the user configure and load tx/rx QEC parameters for different chains and interfaces."
	echo " 		Available configurable parameters:"
	echo "        -p    Path"
#	echo "        -m    Mode"
	echo "        -a    Ant id"
	echo "       --sg   Static IQ gain imbalance (dB)"
	echo "       --sp   Static IQ phase imbalance (deg)"
	echo "        -c    Q subsampling filter tap count"
	echo "        -f    Q subsampling filter file name"
	echo "        -d    I integer delay"
	echo "       --gre  Gain real"
	echo "       --gim  Gain imag"
	echo "       --dre  DC real"
	echo "       --dim  DC imag"
	echo "        -h    help"
	echo " 		For more info please consult the Digital Frontend release documentation."
	echo
	echo
	echo "./imb2qec_apply.sh <help|h|-h>"
	echo "		Shows this usage information." 
	echo
	echo "./imb2qec_apply.sh --pt"
	echo "		Passthrough QEC coefficients are loaded for the PREVIOUS path and mode."
	echo
#	echo "./imb2qec_apply.sh -p <tx|rx> -m <fr1_tdd0|fr1_tdd1|fr2_tdd0|fr2_tdd1|dpdh> --sg <iq_gain_imb_dB> --sp <iq_phase_imb_deg> -c <FD_tap_cnt> -f <ssfilt_filename> -d <int_delay> --gr <gain_re> --gi <gain_im> --dr <dc_re> --di <dc_im>"
	echo "./imb2qec_apply.sh -p <tx|rx> -a <0...5> --sg <iq_gain_imb_dB> --sp <iq_phase_imb_deg> -c <FD_tap_cnt> -f <ssfilt_filename> -d <int_delay> --gr <gain_re> --gi <gain_im> --dr <dc_re> --di <dc_im>"
	echo "		Computes and loads custom coefficients to the targeted VSPA core."
	echo
}


function apply_qec_coeff {
  if [[  "${path}" == "rx"  ]]; then
      addr_vir=`phy2vir $addr_dump`
    	[ $verbose_en = 1 ] && echo /bin/bash ./$qec_update_func   $ant_id   $addr_vir       
    	/bin/bash ./$qec_update_func   $ant_id   $addr_vir        > /dev/null
  else
      addr_phy=$addr_dump
      txcore=${anttx[$ant_id]}
      tid=${tidant[$ant_id]}
      ((msb=0x0A020000+(tid<<15)))
      ((lsb=addr_phy>>7))
      msb=`printf "0x%08x" $msb`
      lsb=`printf "0x%08x" $lsb`
      vspa_mbox send $txcore $host_vspa_mbox_id $msb $lsb
      echo vspa_mbox send $txcore $host_vspa_mbox_id $msb $lsb

      #addr_vir=`phy2vir $addr_dump`
    	#[ $verbose_en = 1 ] && echo /bin/bash ./$qec_update_func   $ant_id   $addr_vir       
    	#/bin/bash ./$qec_update_func   $ant_id   $addr_vir        > /dev/null     
      
  fi 
}


function choose_interface_params {
	if [[ "${path}" == "tx" || "${path}" == "rx" ]]; then
#		if [[ "${mode}" == "fr1_tdd0" || "${mode}" == "fr1_tdd1" || "${mode}" == "fr2_tdd0" || "${mode}" == "fr2_tdd1" || "${mode}" == "dpdh" ]]; then
		if [[ "${ant_id}" == 0 || "${ant_id}" == 1 || "${ant_id}" == 2 || "${ant_id}" == 3 || "${ant_id}" == 4 || "${ant_id}" == 5 ]]; then
#			addr_name=addr_${path}_${mode}
#			addr=${!addr_name}
			
#			core_name=core_${path}_${mode}
#			core=${!core_name}
			qec_update_func=update_qec_coeff_$path.sh
		else
#			echo "ERROR: Wrong mode = ${mode}!"
#			mode=${old_mode}
			echo "ERROR: Wrong ant_id = ${ant_id}!"
#			ant_id=${old_ant_id}
			echo
			echo
			show_help
			exit
		fi
	else
		echo "ERROR: Wrong path = ${path}!"
		#path=${old_path}
		echo
		echo
		show_help
		exit
	fi
}


function show_prev_config {

echo
echo "Previous configuration"
echo "====================="

	echo "  Static IQ Gain Imbalance (dB)    --sg  ${prev_iq_gain_imb_dB}"
	echo "  Static IQ Phase Imbalance(deg)   --sp  ${prev_iq_phase_imb_deg}"
	echo "  Q subsampling filter tap count    -c   ${prev_FD_tap_cnt}"
	echo "  Q subsampling filter file name    -f   ${prev_ssfilt_filename}"
	echo "  I integer delay                   -d   ${prev_int_delay}"
	echo "  Gain real                        --gre ${prev_gain_re}"
	echo "  Gain imag                        --gim ${prev_gain_im}"
	echo "  DC real                          --dre ${prev_dc_re}"
	echo "  DC imag                          --dim ${prev_dc_im}"

echo "====================="
echo
}

function show_curr_config {

echo
echo "Updated configuration"
echo "====================="

	echo "  Static IQ Gain Imbalance (dB)    --sg  ${iq_gain_imb_dB}"
	echo "  Static IQ Phase Imbalance(deg)   --sp  ${iq_phase_imb_deg}"
	echo "  Q subsampling filter tap count    -c   ${FD_tap_cnt}"
	echo "  Q subsampling filter file name    -f   ${ssfilt_filename}"
	echo "  I integer delay                   -d   ${int_delay}"
	echo "  Gain real                        --gre ${gain_re}"
	echo "  Gain imag                        --gim ${gain_im}"
	echo "  DC real                          --dre ${dc_re}"
	echo "  DC imag                          --dim ${dc_im}"

echo "====================="
echo
}

function show_pm { 

echo
echo "Path and mode"
echo "====================="

	echo "  Path                              -p   ${path}"
	#echo "  RefApp mode                       -m   ${mode}"
	echo "  Antenna id                        -a   ${ant_id}"

echo "====================="
echo
}

##########  
#  MAIN  #
########## 

#Fetch previously configured path (if existing)


#old_path=${path}
#old_mode=${mode}
#old_ant_id=${ant_id}

#optspec=":cdfhmp-:"
optspec=":cdfhaps-:"

#wait_here

while getopts "$optspec" optchar; do
    case "${optchar}" in
        -)
            case "${OPTARG}" in
			    	pt) 
                    			pt=1
                    ;;
                sg)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    iq_gain_imb_dB=${val}
                    ;;
				sp)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    iq_phase_imb_deg=${val}
                    ;;
				gre)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    gain_re=${val}
                    ;;
				gim)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    gain_im=${val}
                    ;;
				dre)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    dc_re=${val}
                    ;;
				dim)
					val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
                    dc_im=${val}
                    ;;
				*)
                    if [ "$OPTERR" = 1 ] && [ "${optspec:0:1}" != ":" ]; then
                        echo "Unknown option --${OPTARG}" >&2
                    fi
					exit 1
                    ;;
            esac;;
		c)
			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
			FD_tap_cnt=${val};;
		d)
			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
			int_delay=${val};;
		f)
			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
			ssfilt_filename=${val};;
		h)
			show_help
			exit 1;;
#		m)
#			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
#			mode=${val};;
		a)
			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
			ant_id=${val} 
			if [ -f $cmd_dir/qec_${path}_ant${ant_id}.cfg ]; then
				source $cmd_dir/qec_${path}_ant${ant_id}.cfg
			fi;;
		s)
			save_to_file=1;;
		p)
			val="${!OPTIND}"; OPTIND=$(( $OPTIND + 1 ))
			path=${val}
			prev_path=$path
			if [[ "${path}" != "tx" && "${path}" != "rx" ]]; then
				echo "ERROR: Invalid path specified! tx or rx should be set !"
			fi;;
        *)
            if [ "$OPTERR" != 1 ] || [ "${optspec:0:1}" = ":" ]; then
                echo "Non-option argument: '-${OPTARG}'" >&2
            fi
			show_help
			exit 1
            ;;
    esac
done

if [[ $pt == 1 ]]; then
	set_passthrough_values
fi

				
[ $verbose_en = 1 ] && show_pm

#show_prev_config 		# ${path} and ${ant_id} are not set correctly in prev_config
[ $verbose_en = 1 ] && show_curr_config

choose_interface_params ${path} ${ant_id}

if [[ $save_to_file == 1 ]]; then
  #	python $cmd_dir/imb2qec.py ${path} ${iq_gain_imb_dB} ${iq_phase_imb_deg} ${FD_tap_cnt} ${ssfilt_filename} ${int_delay} ${gain_re} ${gain_im} ${dc_re} ${dc_im} qec_coeff_${path}_ant${ant_id}.bin

  #	[ $verbose_en = 1 ] && echo  $qec_update_func   $ant_id   qec_coeff_${path}_ant${ant_id}.bin
  
  $cmd_dir/imb2qec --dir=${path} --iq_gain_imb_dB=${iq_gain_imb_dB} --iq_phase_imb_deg=${iq_phase_imb_deg} --FD_tap_cnt=${FD_tap_cnt} --filt_file=${ssfilt_filename} --delay=${int_delay} --gain_re=${gain_re} --gain_im=${gain_im} --dc_re=${dc_re} --dc_im=${dc_im} --out_file=qec_coeff_${path}_ant${ant_id}.bin    > /dev/null
  cp qec_coeff_${path}_ant${ant_id}.bin ./qec/qec_close_loop_coeff_${path}_ant${ant_id}.bin
   
  /bin/bash ./$qec_update_func   $ant_id   qec_coeff_${path}_ant${ant_id}.bin    #> /dev/null
 
else   
  addr_vir=`phy2vir $addr_dump`

  #echo $cmd_dir/imb2qec --dir=${path} --iq_gain_imb_dB=${iq_gain_imb_dB} --iq_phase_imb_deg=${iq_phase_imb_deg} --FD_tap_cnt=${FD_tap_cnt} --filt_file=${ssfilt_filename} --delay=${int_delay} --gain_re=${gain_re} --gain_im=${gain_im} --dc_re=${dc_re} --dc_im=${dc_im} --out_phys=${addr_vir}
  $cmd_dir/imb2qec --dir=${path} --iq_gain_imb_dB=${iq_gain_imb_dB} --iq_phase_imb_deg=${iq_phase_imb_deg} --FD_tap_cnt=${FD_tap_cnt} --filt_file=${ssfilt_filename} --delay=${int_delay} --gain_re=${gain_re} --gain_im=${gain_im} --dc_re=${dc_re} --dc_im=${dc_im} --out_phys=${addr_vir}    > /dev/null

 
  /bin/bash ./$qec_update_func   $ant_id   $addr_vir     > /dev/null
  #apply_qec_coeff   > /dev/null
  
fi

#echo
if [[ $pt == 1 ]]; then
	echo "Passthrough QEC coefficients written to path:$path ant:$ant_id !"
else
	echo "Custom QEC coefficients written to path:$path ant:$ant_id !"
fi

#sleep 0.01

#~/rup/bin/gul_refapp -c "l1c update-coef ${path}qec $core"
#echo "QEC update command sent to VSPA core $core!"
#echo
#echo

if [[ $save_to_file == 1 ]]; then
	declare -p iq_gain_imb_dB iq_phase_imb_deg FD_tap_cnt ssfilt_filename int_delay gain_re gain_im dc_re dc_im >> $cmd_dir/qec_${path}_ant${ant_id}.cfg
	#declare -p path ant_id  > $cmd_dir/qec_pm_${path}_ant${ant_id}.cfg
	#echo "iq_gain_imb_dB=$iq_gain_imb_dB  iq_phase_imb_deg=$iq_phase_imb_deg  FD_tap_cnt=$FD_tap_cnt  ssfilt_filename=$ssfilt_filename  int_delay=$int_delay  gain_re=$gain_re  gain_im=$gain_im  dc_re=$dc_re  dc_im=$dc_im  " >> $cmd_dir/qec_${path}_ant${ant_id}.cfg
fi