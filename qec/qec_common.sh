# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

# usage: ./qec_common.sh  tx_ant    rx_ant

# tx_ant/rx_ant:  	antenna ID, legal values are 0,1,2,3,4,5 representing the 6 antenna channels.
 


#source ./qec_init.cfg

# RX dump file name
source ./check_dfe_cap_core_map.sh

tx_ant=$1    
rx_ant=$2
ant_feedback=$(($rx_ant%6))	
rxcore=${antrx[$ant_feedback]}
rid=${ridant[$ant]}
feedback_size=$((cap_size/32768*32))	# unit: KB
get_chan_para $ant_feedback $rxcore
[ $verbose_en = 1 ] && echo ant_feedback: $ant_feedback
#feedback_sps=$rxdcs
feedback_sps=$rxaxiq
[ $verbose_en = 1 ] && echo feedback_sps: $feedback_sps
feedback_file=rx_timedomain_$feedback_size\KB_$feedback_sps\ksps_dump_ant$ant_feedback.bin

