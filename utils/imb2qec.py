# Copyright 2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only be used strictly
# in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

import numpy as np
from array import array
from sys import argv

def help():
	print('\n\nSUPPORTED COMANDS: \n')
	print('QEC coefficient computation:')
	print('    imb2qec.py <tx|rx> <iq_gain_imb_dB> <iq_phase_imb_deg> <FD_tap_cnt> <ssfilt_filename> <int_delay> <gain_re> <gain_im> <dc_re> <dc_im> <outfile_name> ')
	print('Help:')
	print('    imb2qec.py help')
	

def imb2qec_tx(iq_gain_imb_dB, iq_phase_imb_deg, FD_tap_cnt, filt_file, int_delay):
	alpha   = 10**(-iq_gain_imb_dB/20)
	phi_z   = iq_phase_imb_deg*np.pi/180
	
	f1 = 1/np.cos(phi_z)
	f2 = np.tan(phi_z)/alpha
	f4 = 1/alpha
	
	if FD_tap_cnt:
		f = open(filt_file, "r")
		filt_m = f.read().split()
		
		ssfilt = [0]*FD_tap_cnt
		for ii in range(FD_tap_cnt):
			ssfilt[ii] = f4*float(filt_m[ii])
	else:
		ssfilt = []
	
	print('\n**Tx QEC coeffs:**')
	print('f1     = ' + str(f1))
	print('f2     = ' + str(f2))
	print('f4     = ' + str(f4))
	print('ssfilt = ' + str(ssfilt))
	print('intdel = ' + str(int_delay))

	
	return [ssfilt, int_delay, FD_tap_cnt, f1, f2, f4]
	
def imb2qec_rx(iq_gain_imb_dB, iq_phase_imb_deg, FD_tap_cnt, filt_file, int_delay):
	alpha   = 10**(iq_gain_imb_dB/20)
	phi_z   = -iq_phase_imb_deg*np.pi/180
	
	f1 = 1/alpha
	f2 = -np.tan(phi_z)/alpha
	f4 = 1/np.cos(phi_z)
	
	if FD_tap_cnt:
		f = open(filt_file, "r")
		filt_m = f.read().split()
		
		ssfilt = [0]*FD_tap_cnt
		for ii in range(FD_tap_cnt):
			ssfilt[ii] = f4*float(filt_m[ii])
	else:
		ssfilt = []
	
	print('\n**Rx QEC coeffs:**')
	print('f1     = ' + str(f1))
	print('f2     = ' + str(f2))
	print('f4     = ' + str(f4))
	print('ssfilt = ' + str(ssfilt))
	print('intdel = ' + str(int_delay))
	
	return [ssfilt, int_delay, FD_tap_cnt, f1, f2, f4]	
	
def qec2file(qec_coeffs, gain_re, gain_im, dc_re, dc_im, filename):
	
	print('cgain  = ' + str(gain_re) + ' + j*' + str(gain_im))
	print('cdc    = ' + str(dc_re) + ' + j*' + str(dc_im))
	
	f = open(filename, "wb")
	
	ssfilt = qec_coeffs[0]
	ssfilt_v = [0]*32					#a whole DMEM line must be written
	
	if len(ssfilt) != 1:
	    ssfilt = ssfilt[::-1]				#QEC ss taps are flipped in VSPA
	    for ii in range(qec_coeffs[2]):
	        ssfilt_v[2*ii+1] = ssfilt[ii]  #coeffs are the imaginary part of the cfloat32 DMEM line

	arr = array('f', ssfilt_v)         #Write the filter taps
	arr.tofile(f)
	
	arr = array('I', qec_coeffs[1:3])           #Integer delay and number of taps         
	arr.tofile(f)
	
	coeff_v = qec_coeffs[3:6] + [gain_re, gain_im, dc_re, dc_im]
	
	arr = array('f', coeff_v)
	arr.tofile(f)
	
	f.close()

#Main#

if argv[1] == 'help':
	help()
elif argv[1] == 'tx':
	tx_qec_coeffs = imb2qec_tx(float(argv[2]), float(argv[3]), int(argv[4]), argv[5], int(argv[6]))
	qec2file(tx_qec_coeffs, float(argv[7]), float(argv[8]), float(argv[9]), float(argv[10]), argv[11])
	print('\nTX QEC coefficients computed successfully!')
elif argv[1] == 'rx':
	rx_qec_coeffs = imb2qec_rx(float(argv[2]), float(argv[3]), int(argv[4]), argv[5], int(argv[6]))
	qec2file(rx_qec_coeffs, float(argv[7]), float(argv[8]), float(argv[9]), float(argv[10]), argv[11])
	print('\nRX QEC coefficients computed successfully!')	
else:
	raise Exception('\n\nWrong input! Type imb2qec.py help')
