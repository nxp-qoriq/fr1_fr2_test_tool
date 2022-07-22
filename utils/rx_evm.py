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

# usage:
#       python3 rx_evm.py -r ref_file -i input_file (-s)
# Input Parameters:
#       -r ref_file: reference source waveform file (TM1.1 QPSK)
#       -i input_file: Rx measured input file
#       -s save .png
#
# example:
#       python3 utils/rx_evm.py -r test_vectors/TM1.1_100MHz_30kHz_FDD_timedomain_491520ksps.bin \
#       -i rx_timedomain_960KB_245760ksps_dump_ant0.bin -s

#import matplotlib
#matplotlib.use('Agg') 

import sys, math
import numpy as np
import getopt
from scipy.signal import resample_poly, correlate
import matplotlib.pyplot as plt

basic_sampling_rate = 122.88 * (10**6)

first_cp_length = 352
cp_length = 288
fft_window = 4096
n_fft = 3276
slot_length = n_fft * 14
sym_with_cp_size = cp_length + fft_window
    
def time_to_frequency_domain(td_samples, n_subcarriers):
	
    td_samples_tmp = list(td_samples)
    full_fft_output = np.fft.fft(td_samples_tmp, axis=0)
    fd_samples_shift = np.zeros(n_subcarriers, dtype='complex64')

    fd_samples_shift[:int(n_subcarriers / 2)] = full_fft_output[-int(n_subcarriers / 2):]
    fd_samples_shift[int(n_subcarriers / 2):] = full_fft_output[:int(n_subcarriers/2)]
 
    return fd_samples_shift

def power_normalize_waveform(fd_samples, ref_pwr):

    cur_pwr = np.mean(np.abs(fd_samples)**2)
    scaling_factor = np.sqrt(ref_pwr / cur_pwr)
    normalized_samples = fd_samples * scaling_factor
    
    return normalized_samples
    
def calculate_evm(received_signal, reference_signal):
    
    iq_error = received_signal - reference_signal
    rx_magnitude = np.mean(np.sqrt(np.abs(iq_error ** 2)))
    ref_magnitude = np.mean(np.sqrt(np.abs(reference_signal ** 2)))
    evm = rx_magnitude / ref_magnitude
    evm_percentage = (evm) * 100
    
    return evm_percentage
    
def tm11_evm(fd_samples, ref_fd_samples, nslots):
    
    #nslot = 1
    rms_evm = []
    peak_evm = []
    
    for i in range(0, nslots, 1):                
        for n_sym in range (0, 14, 1):
            
            sym_evm = []
            
            rb_offset = 134
            rb_start =  rb_offset + (n_sym * 273) #273rb
            sample_start = (slot_length * i) + rb_start * 12
            
            rb_end_offset = rb_end_offset = (136 - rb_offset) * 2
            rb_end =  rb_start + rb_end_offset
            sample_end = (slot_length * i) + rb_end * 12         
                
            for n in range(0, 12*rb_end_offset, 1):
                
                evm_symbols = calculate_evm(fd_samples[sample_start:sample_end][n], ref_fd_samples[sample_start:sample_end][n])     
                
                #if ((sample_start+n) % 1638 == 0):
                #    print("slot-{}, symbol-{}, rb-{}, sample-{}: EVM (DC) = {:.2f}%".format(nslots, n_sym, rb_offset+(n // 12), sample_start+n, evm_symbols))
                #else:
                #    print("slot-{}, symbol-{}, rb-{}, sample-{}: EVM = {:.2f}%".format(nslots, n_sym, rb_offset+(n // 12), sample_start+n, evm_symbols))
                
                sym_evm = np.append(sym_evm, evm_symbols)
            
            sym_rms_evm = np.mean(sym_evm)
            rms_evm = np.append(rms_evm, sym_rms_evm)
            
            sym_peak_evm = np.max(sym_evm)
            peak_evm = np.append(peak_evm, sym_peak_evm)
            print("Symbol-{}, RB-{}-to-{}: EVM (rms) = {:.3f} %, EVM (peak) = {:.3f} %".format(n_sym,\
                        rb_offset, rb_offset+rb_end_offset, sym_rms_evm, sym_peak_evm))          
        
        rms_evm = np.mean(rms_evm)
        peak_evm = np.max(peak_evm)
        
    figure_list = dict(rms_evm = rms_evm, peak_evm = peak_evm)
    
    return figure_list
                
def find_first_symbol(ref_td_samples, input_td_samples, first_cp):
    
    cp = first_cp
    ref_samples = ref_td_samples[:cp]
    input_samples = input_td_samples[:cp]
    corr = np.abs(correlate(input_samples, ref_samples[:first_cp], mode="full"))
    detect_point = np.argmax(corr[:4096])
    offset = detect_point -(len(ref_samples)) + 1 # +1
    
    #print('samples offset =', offset)

    return offset

def check_fs(name):

    file_name = name
    
    if "122880" in file_name:
        fs = 122880000
    elif "245760" in file_name:
        fs = 245760000
    elif "491520" in file_name:
        fs = 491520000
    elif "983040" in file_name:
        fs = 983040000
    elif "1966080" in file_name:
        fs = 1966080000
    else:
        print("undefined fs.")
        sys.exit(1)
    
    return fs
    
def plot_constellation(I, Q, n_slots, dc_on, clour, label):
    
    freq_samples_I = I
    freq_samples_Q = Q
    
    nslots = n_slots
    cl = clour
    lbl = label
    ignore_dc = dc_on
    
    for i in range(0, nslots, 1):
        for n_sym in range (0, 14, 1):
            rb_offset = 134
            rb_start =  rb_offset + (n_sym * 273)
            sample_start = (slot_length * i) + rb_start * 12
            
            rb_end_offset = (136 - rb_offset) * 2
            rb_end =  rb_start + rb_end_offset
            sample_end = (slot_length * i) + rb_end * 12
            
            if ignore_dc:
                freq_samples_I[sample_start:sample_end][6] = 0
                freq_samples_Q[sample_start:sample_end][6] = 0
                
            for n in range(0, 12*rb_end_offset, 1):
                
                plt.plot(freq_samples_I[sample_start:sample_end][n], freq_samples_Q[sample_start:sample_end][n], str(cl)+'*', markersize=2.5)
                       
    ax = plt.gca()
    for axis in ['top','bottom','left','right']:
        ax.spines[axis].set_linewidth(2.5)

    plt.axhline(color='black', linestyle='--', lw=0.5)
    plt.axvline(color='black', linestyle='--', lw=0.5)
                
    plt.xlabel('Real part')
    plt.ylabel('Imaginary part') 
        
    plt.plot([], [], 'o', label=str(lbl), color=str(cl))
    plt.axis('equal')
    plt.legend(loc='best')
        
    return plt.gcf()

def calc_fr1_constellation(ref_inputfile, dump_file, fs):    
   
    ref_samples = []
    ref_samples = np.fromfile(ref_inputfile, dtype=np.int16) #two-byte each
    ref_iq_samples_orig = ref_samples[::2] / float(2 ** 15) + 1j * ref_samples[1::2] / float(2 ** 15)
    ref_iq_resamples = resample_poly(ref_iq_samples_orig, up=1, down=4)[:]
    
    samples = []
    samples = np.fromfile(dump_file, dtype=np.int16) #two-byte each
    iq_samples_orig = samples[::2] / float(2 ** 15) + 1j * samples[1::2] / float(2 ** 15)
    
    iq_samples_orig = iq_samples_orig[:]
    iq_samples = iq_samples_orig.flatten()
    iq_resamples = resample_poly(iq_samples, up=1, down=(fs//basic_sampling_rate))[:]
    
    samples_offset = find_first_symbol(ref_iq_resamples, iq_resamples, first_cp_length)
    iq_resamples = iq_resamples[samples_offset:]
    
    n_slots_max = math.floor(len(iq_resamples)//61440)
    n_slots = n_slots_max
    
    fd_samples_1d = []
    fd_samples_3276_tmp = np.zeros(n_fft, dtype='complex64')
    
    current_sample_pos = 0

    for z in range(0, n_slots, 1):
           
        td_samples = []
        td_samples = iq_resamples[current_sample_pos+first_cp_length: current_sample_pos+first_cp_length+fft_window]
            
        fd_samples_3276_tmp = time_to_frequency_domain(td_samples, n_fft)
        fd_samples_1d = np.append(fd_samples_1d, fd_samples_3276_tmp)     
        
        current_sample_pos += (first_cp_length+fft_window)

        for i in range(0, 13*sym_with_cp_size, sym_with_cp_size):

            td_samples = []
            td_samples = iq_resamples[current_sample_pos+i+cp_length:current_sample_pos+i+cp_length+fft_window]
                
            fd_samples_3276_tmp = time_to_frequency_domain(td_samples, n_fft)
            fd_samples_1d = np.append(fd_samples_1d, fd_samples_3276_tmp)              
            
        current_sample_pos += (i+cp_length+fft_window)
        
    figure_list = dict(n_slots = n_slots, fd_samples_1d = fd_samples_1d)

    return figure_list
    
def main(argv):
   
   save_fig = 0
   
   try:
      opts, args = getopt.getopt(argv,"hr:hi:s",["rfile=","ifile="])
   except getopt.GetoptError:
      print ('python3 ./rx_evm.py -r <ref-file> -i <inputfile> -s')
      print ('python3 ./rx_evm.py -r ref.bin -i input.bin -s')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
          print ('python3 ./rx_evm.py -r <ref-file> -i <inputfile> -s')
          sys.exit()
      elif opt in ("-r", "--rfile"):
          ref_inputfile = arg
          #print ('Reference file is "', ref_inputfile)
      elif opt in ("-i", "--ifile"):
          inputfile = arg
          #print ('Input file is "', inputfile)
      elif opt in ("-s"):
          save_fig = 1
      
   tx_fs = check_fs(ref_inputfile)
   figures1 = calc_fr1_constellation(ref_inputfile, ref_inputfile, tx_fs)
   IQ_samples_ref = figures1.get('fd_samples_1d')[:]
   
   obs_fs = check_fs(inputfile)
   figures = calc_fr1_constellation(ref_inputfile, inputfile,obs_fs)
   IQ_samples = figures.get('fd_samples_1d')[:]
   IQ_samples = power_normalize_waveform(IQ_samples, np.mean(np.abs(IQ_samples_ref)**2))
   
   evm_figures =  tm11_evm(IQ_samples, IQ_samples_ref, figures.get('n_slots'))
   rms_evm = evm_figures.get('rms_evm')
   peak_evm = evm_figures.get('peak_evm')
   print("EVM (rms) = {:.3f} %, EVM (peak) = {:.3f} %".format(rms_evm, peak_evm))
   
   plot_constellation(IQ_samples.real, IQ_samples.imag, figures.get('n_slots'), 0, 'r', 'obs samples')         
   plot_constellation(IQ_samples_ref.real, IQ_samples_ref.imag, 1, 1, 'g', 'reference samples')
   plt.title("EVM (rms) = {:.3f}%\nEVM (peak) = {:.3f} %".format(rms_evm, peak_evm))
   
   if save_fig == 1:
       plt.savefig('./qec/trx_meas.png')

   plt.show()

if __name__ == '__main__':   
    main(sys.argv[1:])