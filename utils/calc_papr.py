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

import sys
import numpy as np
import scipy.signal as signal
import getopt

def calculate_papr(x):
    """Calculate the PAPR of a complex waveform x."""
    # Calculate the peak power and average power of x
    peak_power = np.max(np.abs(x))**2
    avg_power = np.mean(np.abs(x)**2)

    # Calculate the PAPR
    papr = peak_power / avg_power

    return papr

def main(argv):
   try:
      opts, args = getopt.getopt(argv,"hi:",["ifile="])
   except getopt.GetoptError:
      print ('calc_papr.py -i <inputfile>')
      print ('python calc_papr.py -i waveform_file\\tone0.bin')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
         print ('calc_papr.py -i <inputfile>')
         sys.exit()
      elif opt in ("-i", "--ifile"):
         inputfile = arg
   print ('Input file is "', inputfile)

   samples = []
   samples = np.fromfile(inputfile, dtype=np.int16)
   s = samples[::2] / float(2**15) + 1j * samples[1::2] / float(2**15)

   papr = calculate_papr(s)

   print(f"papr before CFR: {papr:.2f}")
   print(f"papr before CFR: {10*np.log10(papr):.2f} db")


if __name__ == '__main__':
   main(sys.argv[1:])
