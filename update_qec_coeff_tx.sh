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

print_usage()
{                                                                                                                                                                                                        
echo "usage: ./update_qec_coeff_tx/rx.sh [ant id] [dis] [filename|address] [imb=0xAAAAAAAA:0xBBBBBBBB:0xCCCCCCCC] [gain=0xDDDDDDDD:0xEEEEEEEE] [dc=0xFFFFFFFF:0xGGGGGGGG] [inc]"
echo "all the arguments are optional, by default the script will update qec coeff with user coeff defined below in this script."
echo "ant id:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.  "
echo "dis: 		disable qec, set qec back to pass through mode     "
echo "filename:       filename of QEC coeff file. The data struct in the file must be as same struct as in this script. "
echo "address:        address of the QEC coeff struct in host view, must be HEX format with initial 0x. The data struct starting from the address must be as same struct as in this script. "
echo "imb=db:deg      update IQ gain and phase imbalance, db is gain imbalane in dB, deg is phase imbalance in degree, the value are inverse of the values read from equipment"
echo "gain=real:imag  update gain"
echo "dc=real:imag    update DC offset, real and imag must be inverse of values read from equipment"
echo "inc:            incrementally updating QEC coeff. Previous coeff will be loaded and only specified part will be updated. If QEC is in passthrough, then the coeff before passthrough will be loaded."
echo "The script will store the updated coeff to file."
echo "example: ./update_qec_coeff_tx.sh 1                         will update QEC with passthrough coeff to ant 1 "
echo "example: ./update_qec_coeff_tx.sh 0 dis                     will update QEC with passthrough coeff to ant 0 "
echo "example: ./update_qec_coeff_tx.sh 0 f.bin                   will load the coeff from f.bin and update it to QEC. data in the file should be little endian, bin format "
echo "example: ./update_qec_coeff_tx.sh 0 f.bin imb=-3:5          will load the coeff from f.bin, overwrite the IQ imbalance part, then update it to QEC "
echo "example: ./update_qec_coeff_tx.sh 0 imb=-3:5                will update imbalance only, set other coeff to passthrough, then update it to QEC"
echo "example: ./update_qec_coeff_tx.sh 0 dc=0.12:0.05 inc        will update DC offset and keep IQ imbalance and gain unchanged"
echo "example: ./update_qec_coeff_tx.sh 0 0xABCDEFGH              will use the coeff from address 0xABCDEFGHIJ, update it to QEC"
}

#QEC data struct:
#typedef struct{
#    cfloat32_t	iqimb_ssdelayfilt[16];
#    uint32_t 	iqimb_intdelay;
#    uint32_t 	n_ssdelayfilt_taps;
#    float32_t 	iqimb_f1;
#    float32_t 	iqimb_f2;
#    float32_t 	iqimb_f4;
#    cfloat32_t	fegain;	
#    cfloat32_t	dcoff;	
#}qec_params_t;

source ./check_dfe_cap_core_map.sh

[ $# = 0 ] && print_usage
ant=0; dis=0; txrx=0; inc=0
from_file=0
flag_imb=0; flag_gain=0; flag_dc=0
num_counter=0
num_coeff_word=41

arg_parse()
{
	arg=$1
	if ([ $1 = stop ] || [ $1 = dis ]); then		dis=1
	elif [ $1 = inc ]; then 	inc=1
	elif [ $1 = rx ]; then 		txrx=1
	elif [ $1 = tx ]; then 		txrx=0
	elif [ $1 = 0 ]; then 		ant=$1
	elif [ $1 = 1 ]; then 		ant=$1
	elif [ $1 = 2 ]; then 		ant=$1
	elif [ $1 = 3 ]; then 		ant=$1
	elif [ $1 = 4 ]; then 		ant=$1
	elif [ $1 = 5 ]; then 		ant=$1
	elif [ ${arg:0:4} = "imb=" ]; then 		
		arg=${arg:4}; arg=(${arg//:/ }); [ ${#arg[@]} != 2 ] && { echo -e "***ERROR: wrong IQ imbalance parameters\n"; exit 1; }
		flag_imb=1; imb_db=${arg[0]}; imb_deg=${arg[1]}
	elif [ ${arg:0:5} = "gain=" ]; then 	
		arg=${arg:5}; arg=(${arg//:/ }); [ ${#arg[@]} != 2 ] && { echo -e "***ERROR: wrong gain parameters\n"; exit 1; }
		flag_gain=1; gain_re=${arg[0]}; gain_im=${arg[1]}
	elif [ ${arg:0:3} = "dc=" ]; then 		
		arg=${arg:3}; arg=(${arg//:/ }); [ ${#arg[@]} != 2 ] && { echo -e "***ERROR: wrong DC offset parameters\n"; exit 1; }
		flag_dc=1; dc_re=${arg[0]}; dc_im=${arg[1]}
	else
		if [ $num_counter = 0 ];then
			from_file=1; filename=$1
			num_counter=$((num_counter+1))
		else
			echo ***ERROR: wrong argument $1; print_usage; exit 1;
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done

if [ $txrx = 0 ];then	
	check_ant_enable_tx $ant; cmd=0x0A020000; tagtxrx=TX; tagtxrx1=tx; core=${anttx[$ant]}; trid=${tidant[$ant]}
else 					
	check_ant_enable_rx $ant; cmd=0x0A024000; tagtxrx=RX; tagtxrx1=rx; core=${antrx[$ant]}; trid=${ridant[$ant]}
fi

save_filename=./qec/qec_coeff_$tagtxrx1\_ant$ant.bin
addr_phy=$addr_dump
addr_vir=`phy2vir $addr_phy`
[ $dis = 1 ] && { from_file=0; flag_imb=0; flag_gain=0; flag_dc=0; inc=0; }
noupdate=0

if [ $from_file = 0 ];then
	if ([ $inc = 0 ] || [ ! -f $save_filename ]);then
		./utils/memset $addr_vir $num_coeff_word 0         #clear qec coeff memory, set to passthrough coeff
		devmem $((addr_vir+34*4)) w 0x3F800000 #set f1
		devmem $((addr_vir+36*4)) w 0x3F800000 #set f4
		devmem $((addr_vir+37*4)) w 0x3F800000 #set gain real
		[ $((flag_imb+flag_gain+flag_dc)) -eq 0 ] && { dis=1; echo $tagtxrx QEC coeff for antenna $ant is set to passthrough.; }
	else
		echo "Loading previous $tagtxrx QEC coeff to address $addr_vir for antenna $ant from file $save_filename..."
		loadfile $addr_vir $save_filename
		[ $((flag_imb+flag_gain+flag_dc)) -eq 0 ] && noupdate=1
	fi
else
	from_mem_flag=${filename:0:2}
	if ([ $from_mem_flag = 0x ] || [ $from_mem_flag = 0X ]);then
	addr_vir=$filename
	addr_phy=`vir2phy $addr_vir`
	else
	[ -f $filename ] || { echo "***ERROR: File $filename doesn't exist, command failed"; exit 1; }
	filesize=$(stat --format=%s $filename)
	[ $filesize -ne $((num_coeff_word*4)) ] && { echo "***ERROR: File $filename size is not expected, expected size is $((num_coeff_word*4)), command failed"; exit 1; }
	addr_phy=$addr_dump
	addr_vir=`phy2vir $addr_phy`
	loadfile $addr_vir $filename
	echo "Applying $tagtxrx QEC coeff for antenna $ant from file $filename ..."
	fi
fi

if [ $flag_imb = 1 ];then
	if [ $txrx = 0 ];then f124=(`echo $imb_db $imb_deg | awk '{alpha=10^($1/20);   phi_z=$2*3.14159265/180; f1=1/cos(phi_z); f2=-sin(phi_z)/cos(phi_z)/alpha;    f4=1/alpha;        printf("%10.16f %10.16f %10.16f\n", f1,f2,f4);}'`)
	else                  f124=(`echo $imb_db $imb_deg | awk '{gamma=10^($1/20); theta_z=$2*3.14159265/180; f1=1/gamma;      f2=sin(theta_z)/cos(theta_z)/gamma; f4=1/cos(theta_z); printf("%10.16f %10.16f %10.16f\n", f1,f2,f4);}'`)
	fi
	f124=(`./utils/hex2float -r ${f124[0]} ${f124[1]} ${f124[2]}`)
	devmem $((addr_vir+34*4)) w ${f124[0]}; devmem $((addr_vir+35*4)) w ${f124[1]}; devmem $((addr_vir+36*4)) w ${f124[2]}
fi
[ $flag_gain = 1 ] && { gain=(`./utils/hex2float -r $gain_re $gain_im`); devmem $((addr_vir+37*4)) w ${gain[0]}; devmem $((addr_vir+38*4)) w ${gain[1]}; }
[ $flag_dc = 1 ] && { dc=(`./utils/hex2float -r $dc_re $dc_im`); devmem $((addr_vir+39*4)) w ${dc[0]}; devmem $((addr_vir+40*4)) w ${dc[1]}; }

intdel=`devmem $((addr_vir+32*4))`; num_taps=`devmem $((addr_vir+33*4))`
([ $((num_taps)) -eq 0 ] || ([ $((num_taps)) -ge 6 ] && [ $((num_taps)) -le 16 ])) || { echo "***ERROR: Illegal QEC timing skew filter taps $((num_taps)), expected num taps must be 0 or between 6 and 16. command failed"; exit 1; }
([ $((intdel)) -eq 0 ] || [ $((intdel)) -lt $((num_taps)) ]) || { echo "***ERROR: Illegal integar delay $((intdel)), expected delay must be 0 or smaller than num of timing skew filter taps $((num_taps)). command failed"; exit 1; }

vspa_mbox_ifsend $core $host_vspa_mbox_id $((cmd+(trid<<15))) $((addr_phy>>7))

echo "$tagtxrx QEC coeff for antenna $ant on core $core updated from address $addr_vir"
[ $((dis+noupdate)) = 0 ] && { dumpfile $addr_vir $save_filename $((num_coeff_word*4)); echo "Updated coeff saved to file $save_filename"; }

echo
check_error_ant $ant
