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

print_usage()
{
  echo Arguments wrong.
  echo "usage ./txrx_en.sh <limetx/limerx/limetdd/limeloopback>"
}

if [ $# -eq 0 ];then
  print_usage
  exit 1
else
  if [ $1 = tx ];then
    echo "Setting up Tx"
    echo sma_b > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 50 > /sys/kernel/rfnm_primary/tx0/iq_lpf_bw
    echo 20 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply
    echo "Done Setting up Tx"

  elif [ $1 = rx ];then 
    echo "Setting up Rx"
    echo sma_b > /sys/kernel/rfnm_primary/rx1/path
    echo 3400000000 > /sys/kernel/rfnm_primary/rx1/freq
    echo 100 > /sys/kernel/rfnm_primary/rx1/iq_lpf_bw
    echo 40 > /sys/kernel/rfnm_primary/rx1/gain
    echo 1 > /sys/kernel/rfnm_primary/rx1/apply
    echo "Done Setting up Rx"

  elif [ $1 = tddtx ];then
    echo "Setting up TDD Tx"

    #tx	
    echo tdd > /sys/kernel/rfnm_primary/tx0/enable
    echo sma_b > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 50 > /sys/kernel/rfnm_primary/tx0/iq_lpf_bw
    echo 20 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply

  elif [ $1 = tddrx ];then
    echo "Setting up TDD Rx"

    #rx
    echo tdd > /sys/kernel/rfnm_primary/rx1/enable
    echo sma_b > /sys/kernel/rfnm_primary/rx1/path
    echo 3400000000 > /sys/kernel/rfnm_primary/rx1/freq
    echo 100 > /sys/kernel/rfnm_primary/rx1/iq_lpf_bw
    echo 40 > /sys/kernel/rfnm_primary/rx1/gain

  elif [ $1 = grtdd ];then
    echo "Setting up TDD "

    #tx	
    echo tdd > /sys/kernel/rfnm_primary/tx0/enable
    echo sma_b > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 50 > /sys/kernel/rfnm_primary/tx0/iq_lpf_bw
    echo 20 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply

    #rx
    echo tdd > /sys/kernel/rfnm_primary/rx1/enable
    echo sma_b > /sys/kernel/rfnm_primary/rx1/path
    echo 3400000000 > /sys/kernel/rfnm_primary/rx1/freq
    echo 100 > /sys/kernel/rfnm_primary/rx1/iq_lpf_bw
    echo 40 > /sys/kernel/rfnm_primary/rx1/gain
    echo 1 > /sys/kernel/rfnm_primary/rx1/apply

  elif [ $1 = limetx ];then
    echo "Setting up LIME Tx FDD "

    #tx	
    echo sma_b > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 100 > /sys/kernel/rfnm_primary/tx0/rfic_lpf_bw
    echo 28 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply

  elif [ $1 = limerx ];then
    echo "Setting up LIME Rx FDD "

    #rx
    echo sma_a > /sys/kernel/rfnm_primary/rx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/rx0/freq
    echo 100 > /sys/kernel/rfnm_primary/rx0/rfic_lpf_bw
    echo 10 > /sys/kernel/rfnm_primary/rx0/gain
    echo 1 > /sys/kernel/rfnm_primary/rx0/apply

  elif [ $1 = limetdd ];then
    echo "Setting up LIME TDD "

    #rx
    echo tdd > /sys/kernel/rfnm_primary/rx0/enable
    echo sma_a > /sys/kernel/rfnm_primary/rx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/rx0/freq
    echo 100 > /sys/kernel/rfnm_primary/rx0/rfic_lpf_bw
    echo 30 > /sys/kernel/rfnm_primary/rx0/gain
    echo 1 > /sys/kernel/rfnm_primary/rx0/apply

    #tx	
    echo tdd > /sys/kernel/rfnm_primary/tx0/enable
    echo sma_b > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 100 > /sys/kernel/rfnm_primary/tx0/rfic_lpf_bw
    echo 28 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply
  elif [ $1 = limeloopback ];then
    # rx
    echo on > /sys/kernel/rfnm_primary/rx0/enable
    echo loopback > /sys/kernel/rfnm_primary/rx0/path
    echo 3385000000 > /sys/kernel/rfnm_primary/rx0/freq
    echo 100 > /sys/kernel/rfnm_primary/rx0/rfic_lpf_bw
    echo 30 > /sys/kernel/rfnm_primary/rx0/gain

    echo 1 > /sys/kernel/rfnm_primary/rx0/apply

    # tx
    echo on > /sys/kernel/rfnm_primary/tx0/enable
    echo loopback > /sys/kernel/rfnm_primary/tx0/path
    echo 3400000000 > /sys/kernel/rfnm_primary/tx0/freq
    echo 100 > /sys/kernel/rfnm_primary/tx0/rfic_lpf_bw
    echo 28 > /sys/kernel/rfnm_primary/tx0/power
    echo 1 > /sys/kernel/rfnm_primary/tx0/apply

  else
    print_usage
  fi
fi
