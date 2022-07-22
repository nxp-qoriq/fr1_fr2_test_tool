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

# usage
# python3 rx_meas_fr1_tiny.py -r ref_file -i input_file -f fs -s 4
# ref_file: reference source waveform file
# input_file: measured input file
# fs: sample rate 245760000

import sys
import numpy as np
import getopt
from scipy.signal import resample_poly, correlate

ignore_dc = 0
incr_scale = 4.35
incr = 0.001

basic_sampling_rate = 122880000
first_cp_length = 352
cp_length = 288
fft_window = 4096
n_fft = 3276
sym_with_cp_size = cp_length + fft_window

def time_to_frequency_domain(td_samples, n_subcarriers):
	
    td_samples_tmp = list(td_samples)
    full_fft_output = np.fft.fft(td_samples_tmp, axis=0)
    
    fft_size = np.size(full_fft_output)
    #print(fft_size)
    fd_samples_shift = np.zeros(n_subcarriers, dtype='complex64')
    if fft_size >= np.size(fd_samples_shift):
        fd_samples_shift[:int(n_subcarriers / 2)] = full_fft_output[-int(n_subcarriers / 2):]
        fd_samples_shift[int(n_subcarriers / 2):] = full_fft_output[:int(n_subcarriers/2)]
        return fd_samples_shift
    else:
        print('Error')
        sys.exit()      
        
def find_first_symbol(ref_td_samples, input_td_samples, first_cp):
    
    cp = first_cp
    ref_samples = ref_td_samples[:cp]
    input_samples = input_td_samples[:]
    corr = np.abs(correlate(input_samples, ref_samples, mode="full"))
    detect_point = np.argmax(corr[:4096])
    offset = detect_point -(len(ref_samples)) + 1
    
    #print('samples offset =', offset)

    return offset

def plot_constellation(I, Q, n_slots, scale):

    PDSCH_01_DC = 1
       
    freq_samples_I = I[:]
    freq_samples_Q = Q[:]
    
    incr_scale = scale
    
    for i in range(0, 1, 1):
        #print('slot number i =' + str(i))
        if PDSCH_01_DC:
            for n_sym in range (0, 1, 1):
                #print('n_sym =' + str(n_sym))
                rb_offset = 136
                rb_start =  rb_offset + (n_sym * 273)
                sample_start = (45864 * i) + rb_start * 12
                #print('sample_start=',sample_start)
                        
                rb_end_offset = 1
                rb_end =  rb_start + rb_end_offset
                sample_end = (45864 * i) + rb_end * 12
                #print('sample_end=',sample_end)
                
                if ignore_dc:
                    freq_samples_I[sample_start:sample_end][6] = 0
                    freq_samples_Q[sample_start:sample_end][6] = 0            
               
                i_offset = freq_samples_I[sample_start:sample_end][2]-freq_samples_I[sample_start:sample_end][6]
                q_offset = freq_samples_Q[sample_start:sample_end][2]-freq_samples_Q[sample_start:sample_end][6]
                
                a = np.array([freq_samples_I[sample_start:sample_end][2], freq_samples_Q[sample_start:sample_end][2]])
                b = np.array([freq_samples_I[sample_start:sample_end][6], freq_samples_Q[sample_start:sample_end][6]])
                                
                print(freq_samples_I[sample_start:sample_end][6])
                dre = ( i_offset / incr_scale ) * incr
                dre *= 100000
                print(int(dre))
                
                #print('(i) 2 - 6 =', q_offset)
                dim = ( q_offset / incr_scale ) * incr
                dim *= 100000
                print(int(dim))                
                
                print(int((np.linalg.norm(a-b))*1000))
                  
def calc_fr1_constellation(ref_inputfile, dump_file, fs):
    
    # Reference file TM1.1_100MHz_30kHz_FDD_timedomain_491520ksps.bin
    ref_samples = []
    ref_samples = np.fromfile(ref_inputfile, dtype=np.int16) #two-byte each
    ref_iq_samples_orig = ref_samples[::2] / float(2 ** 15) + 1j * ref_samples[1::2] / float(2 ** 15)
    ref_iq_resamples = resample_poly(ref_iq_samples_orig, up=1, down=4)[:]
    
    # Dump Input file 245.76msps
    samples = []
    samples = np.fromfile(dump_file, dtype=np.int16) #two-byte each
    iq_samples_orig = samples[::2] / float(2 ** 15) + 1j * samples[1::2] / float(2 ** 15)
    
    iq_samples_orig = iq_samples_orig[:]
    iq_samples = iq_samples_orig.flatten()
    #print(fs//basic_sampling_rate)
    iq_resamples = resample_poly(iq_samples, up=1, down=(fs//basic_sampling_rate))[:]
    
    # sync first symbol
    samples_offset = find_first_symbol(ref_iq_resamples, iq_resamples, first_cp_length)
    iq_resamples = iq_resamples[samples_offset:]
    
    n_slots = 1
    
    fd_samples_1d = []
    fd_samples_3276_tmp = np.zeros(n_fft, dtype='complex64')
    
    current_sample_pos = 0

    for z in range(0, n_slots, 1):

        """Symbol-0 with longer CP """ 
            
        td_samples = []
        td_samples = iq_resamples[current_sample_pos+first_cp_length: current_sample_pos+first_cp_length+fft_window]
            
        fd_samples_3276_tmp = time_to_frequency_domain(td_samples, n_fft)
        fd_samples_1d = np.append(fd_samples_1d, fd_samples_3276_tmp)     
        
        current_sample_pos += (first_cp_length+fft_window)

        """symbol 1-13 with normal CP """
        for i in range(0, 13*sym_with_cp_size, sym_with_cp_size):

            td_samples = []
            td_samples = iq_resamples[current_sample_pos+i+cp_length:current_sample_pos+i+cp_length+fft_window]
            #fd_samples_3276_tmp = fd_samples_3276_tmp / windows.cosine(len(fd_samples_3276_tmp))
                
            fd_samples_3276_tmp = time_to_frequency_domain(td_samples, n_fft)
            fd_samples_1d = np.append(fd_samples_1d, fd_samples_3276_tmp)              
            
        current_sample_pos += (i+cp_length+fft_window)
        
    figure_list = dict(n_slots = n_slots, fd_samples_1d = fd_samples_1d)

    return figure_list
   
def main(argv):
      
   try:
      opts, args = getopt.getopt(argv,"hr:hi:f:s:",["rfile=","ifile="])
   except getopt.GetoptError:
      print ('python3 rx_meas_fr1_tiny.py -r <ref_file> -i <input_file> -f <fs> -s 4')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
          print ('python3 rx_meas_fr1_tiny.py -r <ref_file> -i <input_file> -f <fs> -s 4')
          sys.exit()
      elif opt in ("-r", "--rfile"):
          ref_inputfile = arg
          #print ('Reference file is "', ref_inputfile)
      elif opt in ("-i", "--ifile"):
          inputfile = arg
          #print ('Input file is "', inputfile)
      elif opt in ("-f", "--fs"):
          fs = int(arg)
      elif opt in ("-s", "--scale"):
          incr_scale = float(arg)
          #print('incr_scale=',incr_scale)

   figures = calc_fr1_constellation(ref_inputfile, inputfile, fs)
   
   IQ_samples = figures.get('fd_samples_1d')[:]
   I_fd_samples = (IQ_samples.real)
   Q_fd_samples = (IQ_samples.imag)
   
   plot_constellation(I_fd_samples, Q_fd_samples, figures.get('n_slots'), incr_scale)

if __name__ == '__main__':   
    main(sys.argv[1:])
    