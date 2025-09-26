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

#Change boot_tool if it's not correct in users system
boot_tool_yami=/lib/modules/$(uname -r)/extra/yami.ko
boot_tool_shiva=/lib/modules/$(uname -r)/extra/la9310shiva.ko

print_usage()
{
echo "usage: ./boot.sh <vspa_images_file_folder_name> [e200/m4_image_name] [obs983|obs1966] [lsdiv2] [hsdiv2]"
echo "    vspa_images_file_folder_name: one of the vspa image folder names provided in test tool in which vspa images will be used for boot."
echo "    e200/m4_image_name: e200 or m4 image filename in /lib/firmware/ which will be used for boot. If this is not specified, geul_e200_rudemo.elf will be used."
echo "    obs983|obs1966:  enable observation channel on HSADC with sampling rate 1.9G or 983 Msps."
echo "                     If users want to use their own e200 image, specify the file name here. Note that if users run TDD mode and use their own e200 image,"
echo "                     their e200 must have the capability to configure TBGEN to control DCS to work in required TDD mode/pattern,"
echo "    lsdiv2: 	divide LS DAC sampling rate by 2. valid only when DAC sampling rate is double of ADC sampling rate"
echo "    hsdiv2: 	divide HS DAC&ADC sampling rate by 2. valid only when DAC/ADC sampling rate is 1.9Gsps"
echo "    example: ./boot.sh MEvspa_images_LS.4T4R_100M_30K_491_245_TDDFDD		will boot VSPA with the images from this folder"
}

obs_sps=0
malt_firmware_name=""
lsdiv2=0; hsdiv2=0
bwdiv=0
num_counter=0
arg=""

arg_parse()
{
	if ([ $1 = help ] || [ $1 = -help ]);then					print_usage; exit 1;
	elif [ $1 = lsdiv2 ];then									lsdiv2=1
	elif [ $1 = hsdiv2 ];then									hsdiv2=1
	elif [ $1 = bwdiv2 ];then									bwdiv=1
	elif [ $1 = bwdiv4 ];then									bwdiv=2
	elif [ $1 = bwdiv8 ];then									bwdiv=3
	elif [ $1 = obs1966 ];then 									obs_sps=1966 #enable hs1.9Gsps if hs is not specified in vspa image names
	elif [ $1 = obs983 ];then 									obs_sps=983
	elif [ $1 = rudemo ];then									malt_firmware_name=geul_e200_rudemo.elf
	else
		if [ $num_counter = 0 ];then	((num_counter++));		arg=$1
		elif [ $num_counter = 1 ];then	((num_counter++));		malt_firmware_name=$1
		else	echo Wrong Argument: $1; print_usage; exit 1
		fi
	fi
}

for i in "$@"
do
	arg_parse $i
done


if [ "$arg" = "" ];then	echo VSPA image name not specified; exit 1
elif ([ $arg = LS ] || [ $arg = ls ]);then						arg=ADvspa_images_LS.4T4R_100M_30K_491_245_TDDFDD
elif ([ $arg = LS50 ] || [ $arg = ls50 ]);then					arg=ADvspa_images_LS.4T4R_50M_30K_245_122_TDDFDD
elif ([ $arg = LS25 ] || [ $arg = ls25 ]);then					arg=ADvspa_images_LS.4T4R_25M_30K_122_122_TDDFDD
elif ([ $arg = LS10 ] || [ $arg = ls10 ]);then					arg=ADvspa_images_LS.4T4R_10M_30K_61_61_TDDFDD
elif [ $arg = tddinfdd ];then									arg=ADvspa_images_LS.4T4R_100M_30K_491_245_TDDinFDD
elif ([ $arg = LSISC ] || [ $arg = lsisc ]);then				arg=ADvspa_images_LS.4T4R_100M_30K_491_245_TDDFDD_ISC
elif ([ $arg = HS ] || [ $arg = hs ]);then						arg=MEvspa_images_HS.2T2R_400M_120K_1966_1966_TDDFDD
elif ([ $arg = HS800 ] || [ $arg = hs800 ]);then				arg=MEvspa_images_HS.1T1R_800M_120K_1966_1966_TDDFDD
elif ([ $arg = LSHS ] || [ $arg = lshs ]);then					arg=ADvspa_images_LS.2T2R_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD
elif ([ $arg = SINAD ] || [ $arg = sinad ]);then				arg=MEvspa_images_LS.4T4R_100M_30K_491_245_HS.2T2R_400M_120K_1966_1966_TDDFDD_SINAD
elif ([ $arg = SINAD983 ] || [ $arg = sinad983 ]);then			arg=MEvspa_images_LS.4T4R_100M_30K_245_245_HS.2T2R_400M_120K_983_983_TDDFDD_SINAD
elif ([ $arg = DPD ] || [ $arg = dpd ]);then					arg=ADvspa_images_LS.2T2R_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD
elif ([ $arg = DPDT4x ] || [ $arg = dpdt4x ]);then				arg=ADvspa_images_LS.2T2R.T4x_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD
elif ([ $arg = DPDT4x19 ] || [ $arg = dpdt4x19 ]);then			arg=ADvspa_images_LS.2T2R.T4x_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD_DPD19
elif [ $arg = rc15 ];then										arg=MEvspa_images_LS.1T2R_10M_15K_61_61_TDDFDD_LA93
elif [ $arg = rc30 ];then										arg=MEvspa_images_LS.1T2R_25M_30K_61_61_TDDFDD_LA93
elif [ $arg = rc60 ];then										arg=MEvspa_images_LS.1T2R_25M_60K_61_61_TDDFDD_LA93
elif [ ${arg:0:73} = ADvspa_images_LS.2T2R.T4x_100M_30K_491_245_HS.2R_400M_120K_983_983_TDDFDD ];then
																arg=ADvspa_images_LS.2T2R.T4x_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD
																hsdiv2=1
elif [ ${arg:0:69} = ADvspa_images_LS.2T2R_100M_30K_491_245_HS.2R_400M_120K_983_983_TDDFDD ];then
																arg=ADvspa_images_LS.2T2R_100M_30K_491_245_HS.2R_400M_120K_1966_1966_TDDFDD
																hsdiv2=1
elif [ ${arg:0:46} = MEvspa_images_HS.2T2R_400M_120K_983_983_TDDFDD ];then
																arg=MEvspa_images_HS.2T2R_400M_120K_1966_1966_TDDFDD
																hsdiv2=1
fi

[ -f $arg/geul-vspa0.eld ] || { echo VSPA image folder $arg does NOT exist!; exit 1; }

flag_la93="$(echo "$arg" | grep LA93 )"
if [ ${#flag_la93} -ge 6 ];then
	flag_la93=1; boot_tool=$boot_tool_shiva
	[ -f $boot_tool ] || { echo -e "***ERROR: $boot_tool does not exist. OR wrong VSPA image used for current LA device, the images tagged with LA93 can only run on LA9310, ohters can only run on LA12xx.\n"; exit 1; }
	[ "$malt_firmware_name" = "" ] && malt_firmware_name=la9310_dfe.bin
else
	flag_la93=0; boot_tool=$boot_tool_yami
	[ -f $boot_tool ] || { echo -e "***ERROR: $boot_tool does not exist. OR wrong VSPA image used for current LA device, the images tagged with LA93 can only run on LA9310, ohters can only run on LA12xx.\n"; exit 1; }
	[ "$malt_firmware_name" = "" ] && malt_firmware_name=geul_e200_rudemo.elf
fi
malt_firmware_pathname=/lib/firmware/$malt_firmware_name
[ -f $malt_firmware_pathname ] || { echo File $malt_firmware_pathname does not exist; exit 1; }

#Default value for Yami boot argument
#modem_addr_array="0002:01:00.0"
#modem_addr_array="0002:01:00.0","0001:01:00.0"
#modem_addr_array="0004:01:00.0","0003:01:00.0","0001:01:00.0","0000:01:00.0"
if [ -z "$modem_addr_array" ];then
	echo "Using default modem"
else
	mpci_addr_array=(pci_addr_array=$modem_addr_array)
fi

ddr_end=0x`cat /proc/iomem  | grep "System RAM" | tail -n 1 | cut -f 2 -d - | cut -f 1 -d " "`
[ $((ddr_end)) = 0 ] && { echo ***ERROR getting system RAM address.; exit 1; }

mscratch_buf_phys_addr=`printf 0x%x $((ddr_end+1))`
mscratch_buf_size=0x20000000
mshare_buf_size=0xe000000
mrf_data_size=0x4000000
malt_vspa_fw_name_prefix=fr1_fr2_test_tool_vspa

num_copied=0
for ((i=0;i<8;i++))
do
	[ -f $arg/geul-vspa$i.eld ] && { cp $arg/geul-vspa$i.eld /lib/firmware/fr1_fr2_test_tool_vspa$i.eld; ((num_copied++)); }
done
echo $num_copied vspa eld files copied to /lib/firmware/

lshs=000
lshs1=000
bandwidth1=0
dcs_enable_arg=""
dcs1_enable_arg=""
arg1=(${arg//_/ })
lshs=${arg1[2]:0:2}
bandwidth_ori=$(($(echo ${arg1[3]} | cut -d "M" -f1)))
bandwidth=$(((bandwidth_ori>>bwdiv)/5*5))                #align to multiple of 5Mhz
scs=$(($(echo ${arg1[4]} | cut -d "K" -f1)))
dac_sps=${arg1[5]}
adc_sps=${arg1[6]}
if [ ${#arg1[@]} -gt 10 ];then
lshs1=${arg1[7]:0:2}
bandwidth1_ori=$(($(echo ${arg1[8]} | cut -d "M" -f1)))
bandwidth1=$(((bandwidth1_ori>>bwdiv)/5*5))                #align to multiple of 5Mhz
scs1=$(($(echo ${arg1[9]} | cut -d "K" -f1)))
dac1_sps=${arg1[10]}
adc1_sps=${arg1[11]}
fi

update_env_bandwidth_ls()
{
	./utils/memrw w 32 $test_tool_env_bw_ls $1
	./utils/memrw w 32 $test_tool_env_scs_ls $2
	./utils/memrw w 32 $test_tool_env_txdcs_sps_ls $3
	./utils/memrw w 32 $test_tool_env_rxdcs_sps_ls $4
}
update_env_bandwidth_hs()
{
	./utils/memrw w 32 $test_tool_env_bw_hs $1
	./utils/memrw w 32 $test_tool_env_scs_hs $2
	./utils/memrw w 32 $test_tool_env_txdcs_sps_hs $3
	./utils/memrw w 32 $test_tool_env_rxdcs_sps_hs $4
}

if [ $lshs = LS ];then
	dac_sps=$((dac_sps>>(lsdiv2+bwdiv)))
	adc_sps=$((adc_sps>>(bwdiv)))
	if ([ $dac_sps != 491 ] && [ $dac_sps != 245 ] && [ $dac_sps != 122 ] && [ $dac_sps != 61 ]);then
		echo LSDAC SPS $dac_sps not supported.
		echo
		exit 1
	fi
	if ([ $adc_sps != 30 ] && [ $adc_sps != 245 ] && [ $adc_sps != 122 ] && [ $adc_sps != 61 ]);then
		echo LSADC SPS $adc_sps not supported.
		echo
		exit 1
	fi
	dcs_enable_arg="ls_dac_sps=$dac_sps ls_adc_sps=$adc_sps"
elif [ $lshs = HS ];then
	dac_sps=$((dac_sps>>(hsdiv2+bwdiv)))
	adc_sps=$((adc_sps>>(hsdiv2+bwdiv)))
	if ([ $dac_sps != 1966 ] && [ $dac_sps != 983 ]);then
		echo HSDCS SPS $dac_sps not supported.
		echo
		exit 1
	fi
	if [ $dac_sps != $adc_sps ];then
		echo HSDAC and HSADC must work in the same SPS in current BSP.
		echo
		exit 1
	fi
	dcs_enable_arg="hsdcs_enable=1 hsdcs_sps=$dac_sps"
fi

if [ $lshs1 = LS ];then
	dac1_sps=$((dac1_sps>>(lsdiv2+bwdiv)))
	adc1_sps=$((adc1_sps>>(bwdiv)))
	if ([ $dac1_sps != 491 ] && [ $dac1_sps != 245 ] && [ $dac1_sps != 122 ] && [ $dac1_sps != 61 ]);then
		echo LSDAC SPS $dac1_sps not supported.
		echo
		exit 1
	fi
	if ([ $adc1_sps != 30 ] && [ $adc1_sps != 245 ] && [ $adc1_sps != 122 ] && [ $adc1_sps != 61 ]);then
		echo LSADC SPS $adc1_sps not supported.
		echo
		exit 1
	fi
	dcs1_enable_arg="ls_dac_sps=$dac1_sps ls_adc_sps=$adc1_sps"
elif [ $lshs1 = HS ];then
	dac1_sps=$((dac1_sps>>(hsdiv2+bwdiv)))
	adc1_sps=$((adc1_sps>>(hsdiv2+bwdiv)))
	if ([ $dac1_sps != 1966 ] && [ $dac1_sps != 983 ]);then
		echo HSDCS SPS $dac1_sps not supported.
		echo
		exit 1
	fi
	if [ $dac1_sps != $adc1_sps ];then
		echo HSDAC and HSADC must work in the same SPS in current BSP. Command failed
		echo
		exit 1
	fi
	dcs1_enable_arg="hsdcs_enable=1 hsdcs_sps=$dac1_sps"
fi

if ([ "${dcs_enable_arg:0:1}" != h ] && [ "${dcs1_enable_arg:0:1}" != h ]);then
	[ $obs_sps != 0 ] && dcs1_enable_arg="hsdcs_enable=1 hsdcs_sps=$obs_sps"
else
	obs_sps=0
fi

echo Booting VSPA images $arg + $malt_firmware_pathname

if [ $flag_la93 = 1 ];then
	log=`lsmod | grep la9310shiva`
	if [ "$log" != "" ];then
		curpwd=`pwd`
		cd /home/root/
		./rmmod_la9310shiva.sh     #could be causing system hang
		sleep 1
		cd $curpwd
	fi
	echo "1" > /sys/bus/pci/rescan
	echo 7 > /proc/sys/kernel/printk
	gpioget 2 9
	gpioget 2 14
	gpioset 0 1=1
	mount -t hugetlbfs none /dev/hugepages
	echo 24 > /sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages

	if [ $dac_sps = 61 ];then
		dac_rate_tag="dac_rate_mask=0x1"
	elif [ $dac_sps = 122 ];then
		dac_rate_tag="dac_rate_mask=0x0"
	else
		echo -e "***ERROR: Illegal DAC sampling rate config $dac_sps\n"; exit 1
	fi
	if [ $adc_sps = 61 ];then
		adc_rate_tag="adc_rate_mask=0xf"
	elif [ $dac_sps = 122 ];then
		adc_rate_tag="adc_rate_mask=0x0"
	else
		echo -e "***ERROR: Illegal ADC sampling rate config $adc_sps\n"; exit 1
	fi
	
	boot_cmd="insmod $boot_tool scratch_buf_size=0x4000000 scratch_buf_phys_addr=0x92400000 adc_mask=0xf $adc_rate_tag dac_mask=0x1 $dac_rate_tag alt_firmware_name=$malt_firmware_name alt_vspa_fw_name=fr1_fr2_test_tool_vspa0.eld"
	echo "$boot_cmd"
	$boot_cmd
	[ $? -ne 0 ] && { echo -e "***ERROR: Failure in insmod $boot_tool, need reboot."; exit 1; }

	sleep 1
	tag="\nNext step: run ./channels_start.sh\n"
else
	while [ 1 ];
	do
		log=`lsmod | grep yami`
		[ "$log" != "" ] && { rmmod yami; sleep 1; }
		echo 1 > /sys/bus/pci/rescan
		echo 8 > /proc/sys/kernel/printk
		#tail -f /var/log/syslog &
		boot_cmd="insmod $boot_tool scratch_buf_size=$mscratch_buf_size share_buf_size=$mshare_buf_size scratch_buf_phys_addr=$mscratch_buf_phys_addr $dcs_enable_arg $dcs1_enable_arg rf_data_size=$mrf_data_size rfic_disable=0 alt_firmware_name=$malt_firmware_name alt_vspa_fw_name_prefix=$malt_vspa_fw_name_prefix $mpci_addr_array"
		echo "$boot_cmd"
		$boot_cmd
		ret=$? 
		out=$(modem_info)
		[ "$out" != "" ] && [ $ret -eq 0 ] && break
		echo "***ERROR: Boot failed, trying again..."
	done
	var=$(cat /sys/yami/yami_status |grep -A3 "Devices Detected" |grep "="|cut -d"=" -f2|tr -d ' '|head -1)
	modem_num=$((var))
	tag="\nNo. of LA12xx Modem Detected: $modem_num \nNext step: run ./channels_start.sh\n"
fi
boot_cmd_hist=0
source ./boot_vspa_log.txt
echo -e "boot_cmd_hist=\"$boot_cmd\"\nvspa_image_folder_name=$arg\nobs_sps=$obs_sps\n" > ./boot_vspa_log.txt
rm backup_filter_coeff*.bin > /dev/null 2>&1  #remove leftover files from previous image
[ "$boot_cmd_hist" != "$boot_cmd" ] && { echo Different boot from previous boot, remove runtime_config.txt; rm runtime_config.*  > /dev/null 2>&1; } #keep runtime config if boot arg is same, this will allow user app boot to use test tool commands for debugging
rm phcom_coeff_*.bin  > /dev/null 2>&1

source ./config.dat

if [ $vspa_dev_type = LA12xx ];then
	source ./rfg_ctrl.sh
	put_hsadc_in_low_power_mode
fi

./utils/memrw w 32 $test_tool_env_boot_vspa_ind 0x1234abcd  #a flag indication VSPA images are boot by vspa_boot.sh
./utils/memrw w 32 $test_tool_env_lsdiv2 $lsdiv2
./utils/memrw w 32 $test_tool_env_hsdiv2 $hsdiv2
./utils/memrw w 32 $test_tool_env_bwdiv $bwdiv

log=`echo $arg | grep T4x`
[ $? = 0 ] && T4x=1 || T4x=0
log=`echo $arg | grep T2x`
[ $? = 0 ] && T2x=1 || T2x=0

if [ $lshs = LS ];then
	update_env_bandwidth_ls $(((bandwidth_ori<<16)|bandwidth|(T4x<<31)|(T2x<<15))) $scs $(((dac_sps+1)*1000/30720*30720)) $(((adc_sps+1)*1000/30720*30720))
elif [ $lshs = HS ];then
	update_env_bandwidth_hs $(((bandwidth_ori<<16)|bandwidth)) $scs $(((dac_sps+1)*1000/30720*30720)) $(((adc_sps+1)*1000/30720*30720))
fi
if [ $lshs1 = LS ];then
	update_env_bandwidth_ls $(((bandwidth1_ori<<16)|bandwidth1|(T4x<<31)|(T2x<<15))) $scs1 $(((dac1_sps+1)*1000/30720*30720)) $(((adc1_sps+1)*1000/30720*30720))
elif [ $lshs1 = HS ];then
	update_env_bandwidth_hs $(((bandwidth1_ori<<16)|bandwidth1)) $scs1 $(((dac1_sps+1)*1000/30720*30720)) $(((adc1_sps+1)*1000/30720*30720))
fi
echo -e "\nParameters configured by boot:\nBandwidth: $bandwidth Mhz, SCS $scs Khz\nDAC SPS:   $dac_sps MSPS\nADC SPS:   $adc_sps MSPS"
[ $bandwidth1 -ne 0 ] && echo -e "\nParameters configured by boot:\nBandwidth: $bandwidth1 Mhz, SCS $scs1 Khz\nDAC SPS:   $dac1_sps MSPS\nADC SPS:   $adc1_sps MSPS"
echo -e "$tag"

mkdir -p /usr/local/etc
echo -e "$modembase_phy\n$VDRAMaddr_vir\n$DDR_host_vspa_view_offset\n"> /usr/local/etc/fr1_fr2_test_tool_modem_bar0.cfg  #for vspa_mbox, right after boot vspa, users can use mbox tool to send msg to vspa

exit 0
