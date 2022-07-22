#!/usr/bin/python

# Copyright 2023-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

import numpy as np
from matplotlib.mlab import psd
#import matplotlib.pyplot as plt
import getopt, sys
#from scipy.signal import welch
#from scipy.signal import decimate, resample_poly, resample

acp_band_offset = 50 # 60mhz for 100mhz waveform

def calculate_pwr(samples, fs):
                            
    (S, f) = psd(samples, Fs= fs / float(10**6), NFFT=16384)
    wanted_band_start = list(np.where((f >= - acp_band_offset) & (f <= acp_band_offset)))[0][0]
    higher_band_start = list(np.where(f > acp_band_offset))[0][0]
    
    wanted_rms = np.sqrt(np.mean(S[wanted_band_start:higher_band_start -1]**2))

    aclr_upperb = 10 * np.log10(wanted_rms) 

    print('Wanted signal power (db) =', round(aclr_upperb, 2))
    
def main(argv):
   try:
      opts, args = getopt.getopt(argv,"hi:f:",["ifile=","fs="])
   except getopt.GetoptError:
      print ('python calc_aclr.py -i <inputfile> -f <fs>')
      print ('python calc_aclr.py -i waveform_file\\tone0.bin -f 245760000')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
          print ('calc_papr.py -i <inputfile> -f 245760000')
          sys.exit()
      elif opt in ("-i", "--ifile"):
          inputfile = arg
          #print ('Input file is "', inputfile)
      elif opt in ("-f", "--fs"):
          fs = int(arg)
          
   samples = []
   samples = np.fromfile(inputfile, dtype=np.int16)
   s = samples[::2] / float(2**15) + 1j * samples[1::2] / float(2**15)
   s = s.flatten()
   calculate_pwr(s, fs)
   
if __name__ == '__main__':
   main(sys.argv[1:])




    