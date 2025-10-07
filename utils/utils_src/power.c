// Copyright 2023 NXP
//
// NXP Confidential. This software is owned or controlled by NXP and may only
// be used strictly in accordance with the applicable license terms. By expressly accepting
// such terms or by downloading, installing, activating and/or otherwise using
// the software, you are agreeing that you have read, and that you agree to
// comply with and are bound by, such license terms. If you do not agree to
// be bound by the applicable license terms, then you may not retain,
// install, activate or otherwise use the software.


#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <sys/mman.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <math.h>

#define SIZE_ALIGNED			0x100000
#define ALIGN_SIZE_LOWER(size)	((size)/SIZE_ALIGNED*SIZE_ALIGNED)
#define ALIGN_SIZE_UPPER(size)	(((size)+SIZE_ALIGNED-1)/SIZE_ALIGNED*SIZE_ALIGNED)

#define DATA_TYPE_SHORT	0
#define DATA_TYPE_FLOAT 1

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr_src;
	void *mmap_addr_dst;
	uint32_t num_words, percentage;
	uint32_t *addr_src;
	uint32_t *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned, type=DATA_TYPE_SHORT;
	off_t phys_addr_src, phys_addr_dst, phys_addr_src_aligned, phys_addr_dst_aligned;

	if (argc < 4) {
		printf("power <physical addr_src> <physical addr_dst> <num_32bit_words>\n");
		printf("      physical addr_src: source address of samples\n");
		printf("      physical addr_dst: dest address to store the final result. if dst address is 0, final result will not be stored to memory, but printed on console.\n");
		printf("                         finale result inlcudes: num_samples_valid, Power_I, Power_Q, power_IQ, max_I, max_Q, max_IQ, dc_I, dc_Q\n");
		printf("                         num_samples_valid: unsigned int. other values: float\n");
		return -1;
	}

	errno = 0;
	phys_addr_src = strtoull(argv[1], NULL, 0);
	if (errno) {
		perror("Error converting physical address src ");
		return -1;
	}
	phys_addr_dst = strtoull(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting physical address dst ");
		return -1;
	}


	num_words = strtoul(argv[3], NULL, 0);
	if (errno) {
		perror("Error converting num_32bit_words");
		return -1;
	}

	//percentage = strtoul(argv[4], NULL, 0);
	//if (errno) {
	//	perror("Error converting percentage");
	//	return -1;
	//}
	//
	//if (argc >= 6)
	//{
	//	if(strcmp(argv[5], "float") == 0)
	//	{
	//		type=DATA_TYPE_FLOAT;
	//	}
	//}

	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	phys_addr_src_aligned = ALIGN_SIZE_LOWER(phys_addr_src);
	size_src_aligned = ALIGN_SIZE_UPPER(num_words*4 + phys_addr_src - phys_addr_src_aligned);
	mmap_addr_src = mmap(NULL, size_src_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_src_aligned);
	if (MAP_FAILED == mmap_addr_src) {
		perror("Mapping devmem  src failed\n");
		return -1;
	}

	if(phys_addr_dst != 0)
	{
		phys_addr_dst_aligned = ALIGN_SIZE_LOWER(phys_addr_dst);
		size_dst_aligned = ALIGN_SIZE_UPPER(num_words*4 + phys_addr_dst - phys_addr_dst_aligned);
		mmap_addr_dst = mmap(NULL, size_dst_aligned, PROT_READ | PROT_WRITE,
				MAP_SHARED, devmem_fd, phys_addr_dst_aligned);
		if (MAP_FAILED == mmap_addr_dst) {
			perror("Mapping devmem  dst failed\n");
			return -1;
		}
		
		addr_dst = mmap_addr_dst + phys_addr_dst - phys_addr_dst_aligned;
	}

	addr_src = mmap_addr_src + phys_addr_src - phys_addr_src_aligned;
	
	
	float power_I=0, power_Q=0, max_I=0, max_Q=0, dc_I=0, dc_Q=0;
	unsigned int num_consecutive_zeros=0, total_consecutive_zeros=0;
	int *psrc = (int*)addr_src;
	for (int count = 0; count < num_words; count++) 
	{
		int idata_IQ = *psrc++;
		short sdata_I = idata_IQ&0xFFFF;
		short sdata_Q = idata_IQ>>16;
		
		if((sdata_I==0)&&(sdata_Q==0))
		{
			num_consecutive_zeros++;
		}
		else
		{
			if(num_consecutive_zeros >=128)
				total_consecutive_zeros+=num_consecutive_zeros;
			num_consecutive_zeros=0;
		}
		
		float data_I = (float)sdata_I/32768.0;
		float data_Q = (float)sdata_Q/32768.0;
		
		dc_I+=data_I; dc_Q+=data_Q; 
		
		power_I += data_I*data_I;
		power_Q += data_Q*data_Q;
		
		if(fabs(max_I) < fabs(data_I))
			max_I = data_I;
		if(fabs(max_Q) < fabs(data_Q))
			max_Q = data_Q;
	}
	float max_IQ=max_I;
	if(fabs(max_IQ) < fabs(max_Q))
		max_IQ=max_Q;
	
	unsigned int num_samples_valid=num_words-total_consecutive_zeros;
	dc_I=dc_I/num_samples_valid; dc_Q=dc_Q/num_samples_valid; 
	
	float dbFS = 10*log10((power_I+power_Q)/num_samples_valid);
	
	if(phys_addr_dst != 0)
	{
		float *pdst = (float*)addr_dst;
		unsigned int *psdst = (unsigned int *)addr_dst;
		psdst[0] = num_samples_valid;
		pdst[1] = power_I; 	pdst[2] = power_Q; 	pdst[3] = power_I+power_Q;
		pdst[4] = max_I;	pdst[5] = max_Q; 	pdst[6] = max_IQ; 
		pdst[7] = dc_I; 	pdst[8] = dc_Q; 	pdst[9] = dbFS;
	}
	else
		printf("num_samples_valid=%d; power_I=%f; power_Q=%f; power_IQ=%f; max_I=%f; max_Q=%f; max_IQ=%f; dc_I=%f; dc_Q=%f; dbFS=%f\n", num_samples_valid, power_I, power_Q, power_I+power_Q, max_I, max_Q, max_IQ, dc_I, dc_Q, dbFS);
	
	close(devmem_fd);
	return 0;
}
