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
import getopt, sys

acp_band_offset = 55 # 60mhz for 100mhz waveform
noise_floor_band = 65

def calculate_aclr(samples, fs):
    sample_rate = fs
    (S, f) = psd(samples, Fs= sample_rate/float((10**6)), NFFT=128)
    #print(f)
    
    wt_b = f[(f < acp_band_offset) & (f > -acp_band_offset)] 

    wt_b_left_loc = np.where(f == wt_b[0])[0][0]
    wt_b_right_loc = np.where(f == wt_b[-1])[0][0]
    
    aclr_upperb_loc = np.where(f == f[(f > noise_floor_band)][0])[0][0]
    aclr_lowerb_loc = np.where(f == f[(f < -noise_floor_band)][-1])[0][0]
    
    wanted_rms = np.sqrt(np.mean(S[wt_b_left_loc:wt_b_right_loc]**2))
    upperb_rms = np.sqrt(np.mean(S[aclr_upperb_loc:]**2))
    lowerb_rms = np.sqrt(np.mean(S[:aclr_lowerb_loc]**2))
    aclr_upperb = 10 * np.log10(upperb_rms) - 10 * np.log10(wanted_rms) 
    aclr_lowerb = 10 * np.log10(lowerb_rms) - 10 * np.log10(wanted_rms) 

    print('ACP Upper =', round(aclr_upperb, 2))
    print('ACP Lower =', round(aclr_lowerb, 2))
    
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
          print ('Input file is "', inputfile)
      elif opt in ("-f", "--fs"):
          fs = int(arg)
          
   samples = []
   samples = np.fromfile(inputfile, dtype=np.int16)
   s = samples[::2] / float(2**15) + 1j * samples[1::2] / float(2**15)
   
   calculate_aclr(s, fs)
   
if __name__ == '__main__':
   main(sys.argv[1:])
    