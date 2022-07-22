# Copyright 2022-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only be used strictly
# in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.


# usage:
#        rx_iqimb_extract.py rx_file $Fi $Fs $N $L $rx_ant_id -a
#
# $Fi: tone_freq+ TX_RX_LO_diff
# $Fs: ADC sample rate
# $N : FFT_length
# $L : number of samples to be processed
# -a : appply the imbalance compensate

import numpy as np
import math
import sys
import subprocess
#import imb2qec
import os

def read_bin(file_name):
    data = np.fromfile(file_name, dtype=np.int16)
    sig = data[::2]+1j*data[1::2]
    sig /= float(2**15)
    return sig

def extract_rx_iqimb(sig, L, N, Fi, Fs, ant, A):
	
	if Fi>=0:
		bin = int(Fi/Fs*N)
		Fi_ = bin*Fs/N 
	else:
		bin = int(N + Fi/Fs*N)
		Fi_ = (bin-N)*Fs/N
	
	img_bin = N - bin
		
	gain_imb_mean = 0
	phase_imb_mean = 0
	IMRR = 0
	
	batch_cnt = math.floor(int(L/N))

	for ii in range(batch_cnt):
		x = sig[:N]
		sig = sig[N:]

		I = np.fft.fft(np.real(x))
		Q = np.fft.fft(np.imag(x))

		I = I[bin]
		Q = Q[bin]

		gain_imbalance  = 20*np.log10(np.abs(I/Q))
		phase_imbalance = -(np.angle(Q/I,deg=True) + 90)

		gain_imb_mean += gain_imbalance
		phase_imb_mean += phase_imbalance
		
		X = np.fft.fft(x)
		IMRR += np.abs(X[bin]/X[img_bin])
	
	
	gain_imb_mean /= batch_cnt
	phase_imb_mean /= batch_cnt
	IMRR_mean = 20*np.log10(IMRR/batch_cnt)

	print()
	print()
	print("### Rx IQ Imbalance extraction ###")
	print()
	print("FFT bin frequency: " + str(round(Fi_,2)) + "MHz")
	print("IMRR: " + str(round(IMRR_mean,2)) + " dB")
	print()
	print()
	print(" Gain imbalance: " + str(round(gain_imb_mean,4))  + " dB")
	print("Phase imbalance: " + str(round(phase_imb_mean,4)) + " deg")
	print()

	if A == "-a":
#		rc = subprocess.check_call("./qec_apply.sh -p rx -m dpdh >/dev/null", shell=True)
#		rc = subprocess.check_call("./qec_apply.sh --pt > /dev/null", shell=True)
#		rc = subprocess.check_call("./qec_apply.sh --sg %s --sp %s > /dev/null" % (gain_imb_mean, phase_imb_mean), shell=True)
#		print('gain_imb_mean: '+float(gain_imb_mean))
#		os.system("python imb2qec.py rx gain_imb_mean  phase_imb_mean 0 0 0 1 0 0 0 rx_imb2qec.bin ")

#		rc = subprocess.check_call("./imb2qec_apply.sh -p rx -a 0   ", shell=True)
#		rc = subprocess.check_call("./imb2qec_apply.sh -p rx -a %s   ", % (ant), shell=True)
#		rc = subprocess.check_call("./imb2qec_apply.sh --pt  ", shell=True)        # can skip this step?
#		rc = subprocess.check_call("./imb2qec_apply.sh --sg %s --sp %s  " % (gain_imb_mean, phase_imb_mean), shell=True)
		rc = subprocess.check_call("./qec/imb2qec_apply.sh -p rx -a %s  --sg %s --sp %s  -s " % (ant, gain_imb_mean, phase_imb_mean), shell=True)

## Main

filename = sys.argv[1]
F  = float(sys.argv[2])
Fs = float(sys.argv[3])
N  = int(sys.argv[4])
L  = int(sys.argv[5])
rx_ant_id = int(sys.argv[6])

A = ""
if len(sys.argv)==8:
	A = str(sys.argv[7])

sig = read_bin(filename)
extract_rx_iqimb(sig,L,N,F,Fs,rx_ant_id,A)
