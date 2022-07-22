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

import numpy as np
import matplotlib.pyplot as plt
import sys, math
import os, struct
import csv
import getopt
import datetime
from numpy.fft import fft, fftshift, ifft
from scipy.signal import resample_poly

"""
numerology - 0, 1 radio frame = 10 subframe = 10 slots = 10ms
numerology - 1, 1 radio frame = 10 subframe = 20 slots = 10ms
numerology - 2, 1 radio frame = 10 subframe = 40 slots = 10ms
numerology - 3, 1 radio frame = 10 subframe = 80 slots = 10ms
numerology - 4, 1 radio frame = 10 subframe = 160 slots = 10ms

60 kHz SCS , numerology - 2
Channel bandwidth = 50MHz, fft_window = 1024, cp_length = 72, cp_long = 144
Channel bandwidth = 100MHz, fft_window = 2048, cp_length = 144, cp_long = 208
Channel bandwidth = 200MHz, fft_window = 4096, cp_length = 288, cp_long = 416

120 kHz SCS , numerology - 3
Channel bandwidth = 50MHz, fft_window = 512, cp_length = 36
Channel bandwidth = 100MHz, fft_window = 1024, cp_length = 72, cp_long = 135
Channel bandwidth = 200MHz, fft_window = 2048, cp_length = 144, cp_long = 270
Channel bandwidth = 400MHz, fft_window = 4096, cp_length = 288, cp_long = 544

"""
class convert_to_csv:
    
    iq_swap = 0 # if iq swapped
    fr1_padded_3296 = 1 # fr1 zero-padded to 3296

    def __init__(self, n_slots, fft_size, n_subcarriers, cp_long, cp_normal, scs_khz, mode):
                
        self.n_slots = n_slots
        self.fft_size = fft_size
        self.mode = mode
        self.n_subcarriers = n_subcarriers
        
        if self.mode == 'fr1':
            
            if self.fr1_padded_3296:
                self.sym_data_size = 3296 # 3296
            else:
                self.sym_data_size = n_subcarriers 
            
            self.dcs_fs = 245760000 # 491520000 : 245760000 : 122880000
            
        elif self.mode == 'fr2':
            
            self.sym_data_size = n_subcarriers
            self.dcs_fs = 983040000 # 1966080000 : 983040000 : 491520000
        
        self.cp_long = cp_long
        self.cp_normal = cp_normal
        
        self.scs_khz = scs_khz
        
        self.numerology = math.log(self.scs_khz // 15, 2)
        self.long_cp_cycle = int(2**(self.numerology-1))
        
        self.fd_length_per_cycle = self.sym_data_size * 14 * self.long_cp_cycle
        self.fd_length = self.fd_length_per_cycle * (self.n_slots // self.long_cp_cycle)
        #print(self.sym_data_size)

        self.td_length_per_cycle = self.cp_long + self.cp_normal * ( self.long_cp_cycle * 14 - 1) + (self.fft_size * self.long_cp_cycle * 14)
        self.td_length = self.td_length_per_cycle * (self.n_slots // self.long_cp_cycle)
        self.fs = (self.scs_khz*1000) * self.fft_size
        
        self.td_1st_sym_len = self.cp_long + self.fft_size
        self.td_oth_sym_len = self.cp_normal + self.fft_size
        self.td_1st_slot_len =  self.td_1st_sym_len +  (self.td_oth_sym_len * 13)

    def load_wave_file(self, wave_file):
        samples = []
        samples = np.fromfile(wave_file, dtype=np.int16)
        iq_samples = samples[::2] / float(2**15) + 1j * samples[1::2] / float(2**15)   
       
        return iq_samples
    
    def frequency_to_time_domain(self, freq_samples):
        """Convert the frequency domain symbol to time domain via IFFT
        Args:
            fd_symbol: One frequency domain symbol
            fft_size: fft size : 4096
            n_subcarriers: sub-carriers numbers : 3276
            Returns:
                time domain signal
                """
        fd_samples = freq_samples[:]
        ifft_scale = 256/4
        sym_data_size = len(fd_samples)
        #print(sym_data_size)
        if sym_data_size < self.fft_size:
            zero_append = np.zeros(self.fft_size-sym_data_size, dtype='complex')
            fd_samples = np.append(fd_samples, zero_append)
            fd_samples_shift = np.roll( fd_samples , -(self.n_subcarriers // 2)) # rotate fft
            tmp = np.zeros(self.fft_size, dtype='complex')
            tmp = ifft( fd_samples_shift ) * ifft_scale
            td_samples_4096 = tmp
        return td_samples_4096
                
    def add_cyclic_prefix(self, timedomain_waveform, cp_length):
        """Adds cyclic prefix
        Adds by taking the last few samples and appending it to the beginning of the signal
        Args:
            td_waveform: IFFT output signal.
            cp_length: cp length
            Returns:
                time domain signal with a cyclic prefix
        """
        td_waveform = timedomain_waveform[:]   
        td_samples_with_cp = np.zeros(len(td_waveform) + cp_length, dtype='complex64')
        td_samples_with_cp[cp_length:] = td_waveform
        td_samples_with_cp[:cp_length] = td_waveform[-cp_length:]
        return td_samples_with_cp
                                
    def calc_spectrum(self, iq_resampled_td, upsample_rate = 1):
        """ Calculate spectrum from TD samples returned from calc_constellation
        Args:
            iq_td: input TD samples
            fs: waveform sampling rate
            fft_window: fft window for calculation
            Returns:
                Frequency
                Magnitude
        """
	
        figure_list = {}

        iq_td_samples = []
        iq_td_samples = iq_resampled_td[:].flatten()
        
        upsamp = upsample_rate
        fft_size = self.fft_size * upsamp
        freq_range = np.arange(-self.dcs_fs/float(2)/float(10**6), self.dcs_fs/float(2)/float(10**6), self.dcs_fs/float(fft_size)/float(10**6))

        freq_domain_y = np.empty([len(iq_td_samples) // int(fft_size), int(fft_size)])
        iq_td_samples = iq_td_samples[:(len(iq_td_samples) // int(fft_size)) * int(fft_size)]
    		
        for i in range(0, len(iq_td_samples), fft_size):
            #print(i)
            #print(len(iq_td_samples))
            freq_domain_y[i//int(fft_size)] = np.abs(fftshift(fft(iq_td_samples[i:i + int(fft_size)])))
        freq_domain_y = np.mean(freq_domain_y, axis=0)
        y_amp = 20 * np.log10(np.divide(freq_domain_y, fft_size) + np.spacing([10**(-5)]*len(freq_domain_y)))
            
        figure_list = dict(x = freq_range, y = y_amp)
        return figure_list
	
    def plot_spectrum(self, freq, mag):
        """ Plot spectrum from calc_spectrum
        Args:
            freq: Frequency points
            mag: Magnitude points
        """            
        plt.rcParams['ytick.labelright'] = 'True'
        plt.rcParams['ytick.labelleft'] = 'False'

        plt.subplot2grid((3,3), (0, 1), rowspan=3, colspan=3)
        plt.plot(freq, mag)
    
        plt.title("Spectrum Plot", fontsize=8)
        plt.xlabel('Frequency [MHz]', fontsize=8)
        plt.ylabel('Magnitude [dbFS]', fontsize=8)
        
        plt.autoscale()
        plt.grid(True, linestyle='--', lw=0.5)
        
        plt.show()

    def calc_td_waveform(self, samples):
    
        figure_list = []
        iq_td_samples = samples[:] 
        upsamp = self.dcs_fs // (self.fs)
        print('resample from ' + str(self.dcs_fs) + ' to ' + str(self.fs))
        iq_td_resample_data = resample_poly(iq_td_samples, up=1, down=upsamp)
    
        # cut
        iq_td_resample_data = iq_td_resample_data[:self.td_length].flatten()
        print(self.td_length)
        print('>> Original TD waveform length in ' + str(self.n_slots) + ' slots' + ' = ' + str(len(iq_td_resample_data)))
        
        figure_list = dict(iq_samples_td = iq_td_samples, iq_resamples_td = iq_td_resample_data, upsamp_x = upsamp)
        return figure_list


    def calc_fd_waveform(self, samples):
    
        figure_list = []
        iq_fd_samples = samples[:]
    
        # cut
        iq_fd_samples = iq_fd_samples[:self.fd_length].flatten()
        print('>> Original FD waveform length in ' + str(self.n_slots) + ' slots' + ' = ' + str(len(iq_fd_samples))) 
    
        iq_samples_td = np.zeros(self.td_length, dtype='complex')
    
        current_sample_pos = 0 
        current_sample_pos_td = 0
        
        for z in range(0, self.n_slots, 1):
            #print('Slot ' + str(z))    
        
            if (z % self.long_cp_cycle) == 0:
                tmp = iq_fd_samples[current_sample_pos: current_sample_pos+self.sym_data_size]
                tmp_4096 = self.frequency_to_time_domain(tmp)
                tmp1 = self.add_cyclic_prefix(tmp_4096, self.cp_long)
                iq_samples_td[ current_sample_pos_td: current_sample_pos_td + self.cp_long + self.fft_size] = tmp1
                #print('iq_fd_samples Symbol ' + str(0) + ' range from = ' + str(current_sample_pos) + ' ~ ' + str(current_sample_pos+self.sym_data_size))
                #print('iq_samples_td Symbol ' + str(0) + ' range from = ' + str(current_sample_pos_td) + ' ~ ' + str(current_sample_pos_td+ self.cp_long + self.fft_size))
                current_sample_pos += (self.sym_data_size)
                current_sample_pos_td += (self.cp_long + self.fft_size)
                #print(current_sample_pos_td)

                for i in range(0, 13*self.sym_data_size, self.sym_data_size):
                    tmp = iq_fd_samples[current_sample_pos+i:current_sample_pos+i+self.sym_data_size]
                    tmp_4096 = self.frequency_to_time_domain(tmp)
                    tmp1 = self.add_cyclic_prefix(tmp_4096, self.cp_normal)
                    #print(tmp1.size)
                    #print('iq_fd_samples Symbol ' + str((i//int(self.sym_data_size))+1) + ' range from = ' + str(current_sample_pos+i) + ' ~ ' + str(current_sample_pos+i+self.sym_data_size))         
                    #print('iq_samples_td Symbol ' + str((i//int(self.sym_data_size))+1) + ' range from = ' + str(current_sample_pos_td) + ' ~ ' + str(current_sample_pos_td + tmp1.size))

                    iq_samples_td[current_sample_pos_td : current_sample_pos_td  + tmp1.size] = tmp1
                    current_sample_pos_td += tmp1.size
                    #print(current_sample_pos_td)
                current_sample_pos += (i+self.sym_data_size)
                #print(current_sample_pos)

            else:

                for i in range(0, 14*self.sym_data_size, self.sym_data_size):
                    tmp = iq_fd_samples[current_sample_pos+i:current_sample_pos+i+self.sym_data_size]
                    tmp_4096 = self.frequency_to_time_domain(tmp)
                    tmp1 = self.add_cyclic_prefix(tmp_4096, self.cp_normal)
                    #print('iq_fd_samples Symbol ' + str((i//int(self.sym_data_size))+1) + ' range from = ' + str(current_sample_pos+i) + ' ~ ' + str(current_sample_pos+i+self.sym_data_size))         
                    #print('iq_samples_td Symbol ' + str((i//int(self.sym_data_size))+1) + ' range from = ' + str(current_sample_pos_td) + ' ~ ' + str(current_sample_pos_td + tmp1.size))

                    iq_samples_td[current_sample_pos_td : current_sample_pos_td  + tmp1.size] = tmp1
                    current_sample_pos_td += tmp1.size
                    #print((current_sample_pos_td))
                current_sample_pos += (i+self.sym_data_size)
                #print(current_sample_pos)
        #print(str(current_sample_pos_td) + ' td samples end here')
    
        figure_list = dict(iq_samples_td = iq_samples_td)
        return figure_list

    def conv_to_csv(self, input_td_samples, inputfile, plt_n):

        iq_td_in = input_td_samples[:]
    
        time = np.arange(0, len(iq_td_in) / float(self.fs), 1 / float(self.fs)) 
        time *= 10**3
    
        Y = []
        i_signal = np.array(np.real(iq_td_in))
        i_signal = i_signal.astype('float32')
        q_signal = np.array(np.imag(iq_td_in))
        q_signal = q_signal.astype('float32')

        if self.iq_swap == 1:
            Y = [q_signal , i_signal]
        else:
            Y = [i_signal , q_signal]
    
        Y = np.transpose(Y)
        
        plot = plt_n
        
        if plot:
            plt.rcParams['ytick.labelsize'] = 'small'
            plt.rcParams['xtick.labelsize'] = 'small'

            plt.subplot(3,3,1)
            plt.plot(time, np.real(iq_td_in))
            plt.ylabel('I')
            plt.xlabel('millisecond', fontsize=8)
            plt.subplot(3,3,7); 
            plt.plot(time, np.imag(iq_td_in))
            plt.ylabel('Q');
            plt.xlabel('millisecond', fontsize=8)
    
        time_now  = datetime.datetime.now().strftime('%Y%m%d%H%M%S') 

        dir_path = os.path.dirname(os.path.realpath(inputfile))
        output_name = os.path.splitext(os.path.basename(inputfile))[0]	
        file_out = str(dir_path) + '/' + str(output_name) + '_' +  str(time_now) + '.csv'
            
        ks_header = (['InputZoom' , ' TRUE'],
                     ['XDelta' , str(1/(self.fs))],
                     ['Y'])

        with open(file_out, 'w') as csvfile:    
            writer = csv.writer(csvfile, lineterminator='\n')
            writer.writerows(ks_header)
            csvfile.close()
        with open(file_out, 'a') as f:    
            writer = csv.writer(f, lineterminator='\n')
            writer.writerows(Y)
            print('>> Output .csv location = ' + os.path.realpath(f.name))
            f.close()
        

def main(argv):
    
    plot = 0
    
    try:
        opts, args = getopt.getopt(argv,"hi:d:m:p",["ifile=","input_domain=","{mode}"])
    except getopt.GetoptError:
        print ('python3 conv_bin2csv_v1.0.py -i rx_freqdomain20ms_dump_fr2_ant4.bin -d fd -m fr2')
        sys.exit(2)
    for opt, arg in opts:       
        if opt == '-h':
            print ('python3 conv_bin2csv_v1.0.py -i <inputfile> -d <input_domain> -m <mode>')
            sys.exit()
        elif opt in ("-i", "--ifile"):
            inputfile = arg
        elif opt in ("-d", "--input_domain"):
            input_domain = arg
        elif opt in ("-m", "--mode"):
            mode = arg
        elif opt in ("-p"):
            plot = 1
    
    if mode == 'fr1':
        kwargs = {'n_slots': 20,
                  'fft_size': 4096,
                  'n_subcarriers': 3276,      
                  'cp_long': 352,
                  'cp_normal': 288,
                  'scs_khz': 30,
                  'mode': 'fr1'}
    elif mode == 'fr2':
        kwargs = {'n_slots': 20,
                  'fft_size': 4096,
                  'n_subcarriers': 3168, # 3168     
                  'cp_long': 544,
                  'cp_normal': 288,
                  'scs_khz': 120,
                  'mode': 'fr2'}
    
    f = convert_to_csv(**kwargs)
    if (f.n_slots % f.long_cp_cycle != 0):
        sys.exit("n_slots must be multiple of " + str(f.long_cp_cycle))
        
    #inputfile = './waveforms/fr2/fr2_tool/lpbk/NR-FR2-TM3.1_100MHz_120kHz_TDD_fd_3168_20ms.bin'
    #input_domain = 'fd'
    print('\nLoading...', os.path.realpath(inputfile))
    iq_ori_samples = f.load_wave_file(inputfile)


    if input_domain == 'fd':
        print('>> FD Waveform sampling rate ' + str(f.fs))
        figures = f.calc_fd_waveform(iq_ori_samples)
        upsampling_x = 1
    elif input_domain == 'td':
        print('>> TD Waveform sampling rate ' + str(f.dcs_fs))
        figures = f.calc_td_waveform(iq_ori_samples)    
        upsampling_x = figures.get('upsamp_x')
        
    iq_td_data = figures.get('iq_samples_td')[:]
    
    if input_domain == 'fd':
        iq_td_resampled_data = iq_td_data
    elif input_domain == 'td':
        iq_td_resampled_data =  figures.get('iq_resamples_td')[:]

    f.conv_to_csv(iq_td_resampled_data, inputfile, plot)
    
    #td_time = (len(iq_td_data) / f.fs)*10**3 
    
    #print('>> Output TD waveform length = ' + str(len(iq_td_data)) + ' = ' + str(round(td_time, 2)) + 'ms\n')
    figures1 = f.calc_spectrum(iq_td_data, upsampling_x)
    freq = figures1.get('x')
    mag = figures1.get('y')
    if plot:
        f.plot_spectrum(freq, mag)
           
if __name__ == '__main__':   
    main(sys.argv[1:])
	
    