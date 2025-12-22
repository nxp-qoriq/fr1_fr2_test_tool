#!/usr/bin/python

# Copyright 2020-2024 NXP
#
# NXP Confidential. This software is owned or controlled by NXP and may only
# be used strictly in accordance with the applicable license terms. By expressly accepting
# such terms or by downloading, installing, activating and/or otherwise using
# the software, you are agreeing that you have read, and that you agree to
# comply with and are bound by, such license terms. If you do not agree to
# be bound by the applicable license terms, then you may not retain,
# install, activate or otherwise use the software.

import sys
import os
import matplotlib.pyplot as plt
from numpy.fft import fft, fftshift
import matplotlib
import numpy as np
import scipy.fftpack
from fractions import gcd
import json
import struct
import csv
import copy
import math
import warnings
import getopt

class Slot:
    def __init__(self, index):
        self.index = index
        self.size_samples = 0
        self.size_us = 0
        self.start_extra_samples = 0
        self.stop_extra_samples = 0
        self.size_bytes = 0
        self.half_frame_bytes = 0

    def get_samples(self):
        return self.size_samples

    def get_us(self):
        return self.size_us


def plot_dump(dump_file='./waveforms/rx0_dump.bin', fs=122880000*2, swap_en=False, conj_en=False, sign_mag=False):

    upsamp = fs/61440000
    fs=upsamp*61440000
    fft_window =512*upsamp
    figure_list = []

    print('upsamp ' + str(upsamp) )
    print('Sampling rate ' + str(fs) )
    print('fft_window ' + str(fft_window) )

    if sign_mag:
        data = np.fromfile(dump_file, dtype=np.uint16)
        samples = np.array([(((-1) ** ((0x8000 & item) >> 15)) * (0x7FFF & item)) for item in data])
    else:
        samples = np.fromfile(dump_file, dtype=np.int16)
    iq_samples = samples[::2] / float(2**15) + 1j * samples[1::2] / float(2**15)
    if swap_en:
        iq_samples = 1j * np.real(iq_samples) + np.imag(iq_samples)
    if conj_en:
        iq_samples = np.real(iq_samples) - 1j * np.imag(iq_samples)
    figure_list.append({'x': np.arange(0, len(iq_samples) / float(fs), 1 / float(fs)) * 10**6,
                        'y': np.real(iq_samples),
                        'title': 'Time domain I samples',
                        'xlabel': 'time [us]',
                        'ylabel': 'Amplitude',
                        'draw_slot_boundaries': True,
                        'fs': fs})
    figure_list.append({'x': np.arange(0, len(iq_samples) / float(fs), 1 / float(fs)) * 10 ** 6,
                        'y': np.imag(iq_samples),
                        'title': 'Time domain Q samples',
                        'xlabel': 'time [us]',
                        'ylabel': 'Amplitude',
                        'draw_slot_boundaries': True,
                        'save_plot': '',
                        'fs': fs})

    freq = np.empty([len(iq_samples) // int(fft_window), int(fft_window)])
    iq_samples = iq_samples[:(len(iq_samples) // int(fft_window)) * int(fft_window)]

    for i in range(0, len(iq_samples), int(fft_window)):
        freq[i//int(fft_window)] = np.abs(fftshift(fft(iq_samples[i:i + int(fft_window)])))

    freq = np.mean(freq, axis=0)
    figure_list.append({'x': np.arange(-fs/float(2)/float(10**6), fs/float(2)/float(10**6),
                                       fs/float(fft_window)/float(10**6)),
                        'y': 20 * np.log10(np.divide(np.abs(freq), fft_window) + np.spacing([10**(-5)]*len(freq))),
                        'title': 'FFT received signal',
                        'xlabel': 'Frequency [MHz]',
                        'ylabel': 'Magnitude [dbFS]'})
    return figure_list

def plot_figures(figures_list):
    ax = None
    for idx, figure in enumerate(figures_list):
        if idx == 0 or (figure['title'] != figures_list[idx-1]['title']):
            fig, ax = plt.subplots(num=figure['title'])
        print (figure['title'])
        print (len(figure['x']), len(figure['y']))
        data = ax.plot(figure['x'], figure['y'])

        plt.title(figure['title'])
        plt.xlabel(figure['xlabel'])
        plt.ylabel(figure['ylabel'])
        plt.grid(True, linestyle='--')

        if 'time' in figure['xlabel']:
            plt.ylim(-1, 1)
        figure_copy = copy.deepcopy(figure)
        for key in ['x', 'y', 'title', 'xlabel', 'ylabel', 'slot_start_count', 'fs', 'save_plot']:
            try:
                figure_copy.pop(key)
            except KeyError:
                pass

    plt.show()
    plt.close('all')

def main(argv):
   try:
      opts, args = getopt.getopt(argv,"hi:f:",["ifile=","fs="])
   except getopt.GetoptError:
      print ('plotdump.py -i <inputfile>-f <samplig rate>')
      print ('python plotdump.py -i waveforms\\tone0.bin -f 491520000')
      sys.exit(2)
   for opt, arg in opts:
      if opt == '-h':
         print ('plotdump.py -i <inputfile> -f <samplig rate>')
         sys.exit()
      elif opt in ("-i", "--ifile"):
         inputfile = arg
      elif opt in ("-f", "--fs"):
         fs = int(arg)
   print ('Input file is "', inputfile)

   figures = plot_dump(inputfile,fs)
   plot_figures(figures)

if __name__ == '__main__':
   main(sys.argv[1:])

