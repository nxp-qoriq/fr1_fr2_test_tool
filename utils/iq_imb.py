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
import math, sys
from numpy.fft import fft
import getopt
   
def calc_iqimb(samples):
    
    td_samples_ori = samples
    L = len(td_samples_ori)
    i_samples_td = np.real(td_samples_ori)
    q_samples_td = np.imag(td_samples_ori)
    i_samples_fd = fft(i_samples_td)
    q_samples_fd = fft(q_samples_td)

    pts = int(np.floor(L/2+1)+1)
    
    P2_i_samples = np.array(np.abs(i_samples_fd/L))
    ang_i_samples = np.array(np.angle(i_samples_fd/L))
    P1_i_samples = P2_i_samples[: pts]
    P1_i_samples[1:-1] *= 2
    mag_i_samples = P1_i_samples.max(0)
    idx_i_samples = P1_i_samples.argmax(0)

    P2_q_samples = np.array(np.abs(q_samples_fd/L))
    ang_q_samples = np.array(np.angle(q_samples_fd/L))
    P1_q_samples = P2_q_samples[: pts]
    P1_q_samples[1:-1] *= 2
    mag_q_samples = P1_q_samples.max(0)
    idx_q_samples = P1_q_samples.argmax(0)

    phs = ang_q_samples[idx_q_samples] - ang_i_samples[idx_i_samples]
    phs_deg = np.abs(phs*360/(2*math.pi))

    if phs_deg > 180:
        FD_phase_Imb_deg = 360 - phs_deg
    else:
        FD_phase_Imb_deg = phs_deg

    if mag_q_samples > mag_i_samples:
        amp = mag_q_samples/mag_i_samples
    else:
        amp = mag_i_samples/mag_q_samples
    
    FD_Gain_Imb_dB = 20*math.log10(amp)
    print ("  Phase error --sp " + str(round(FD_phase_Imb_deg-90, 5)) + " Degree")
    print ("  Gain error  --sg " + str(round(FD_Gain_Imb_dB, 5)) + " dB")

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
           #print ('Input file is "', inputfile)

    samples = []
    samples = np.fromfile(inputfile, dtype=np.int16) #two-byte each
    td_samples_ori = samples[::2] / float(2 ** 15) + 1j * samples[1::2] / float(2 ** 15)
    
    calc_iqimb(td_samples_ori[1069:])

if __name__ == '__main__':   
    main(sys.argv[1:])
    
    