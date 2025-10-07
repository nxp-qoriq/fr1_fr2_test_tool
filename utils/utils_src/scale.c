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
	uint32_t num_words;
	uint32_t *addr_src;
	uint32_t *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned, type=DATA_TYPE_SHORT;
	off_t phys_addr_src, phys_addr_dst, phys_addr_src_aligned, phys_addr_dst_aligned;

	if (argc < 5) {
		printf("scale <physical addr_src> <physical addr_dst> <num_32bit_words> <percentage|factor> [type]\n");
		printf("  percentage: percent number without %%, valid range 0-0x003FFFFF\n");
		printf("  factor:     HEX float of scaling factor, valid value: any hex float vlaue\n");
		printf("  type:       type of data in src buffer. Can be short, float. default is short if not specified\n");
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
	
	int percentage = 100;
	float factor_float = 1.0;
	
	uint32_t factor = strtoul(argv[4], NULL, 0);
	if (errno) {
		perror("Error converting percentage");
		return -1;
	}
	else
	{
		if (factor & 0xFFC00000)
		{	//treat percentage as HEX float
			*(uint32_t*)&factor_float = factor;
		}
		else
		{
			percentage = factor;
		}
	}
	
	if (argc >= 6)
	{
		if(strcmp(argv[5], "float") == 0)
		{
			type=DATA_TYPE_FLOAT;
		}
	}

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

	phys_addr_dst_aligned = ALIGN_SIZE_LOWER(phys_addr_dst);
	size_dst_aligned = ALIGN_SIZE_UPPER(num_words*4 + phys_addr_dst - phys_addr_dst_aligned);
	mmap_addr_dst = mmap(NULL, size_dst_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_dst_aligned);
	if (MAP_FAILED == mmap_addr_dst) {
		perror("Mapping devmem  dst failed\n");
		return -1;
	}

	addr_src = mmap_addr_src + phys_addr_src - phys_addr_src_aligned;
	addr_dst = mmap_addr_dst + phys_addr_dst - phys_addr_dst_aligned;
	
	unsigned char one_print = 0;
	if(type == DATA_TYPE_SHORT)
	{
		short *psrc = (short*)addr_src;
		short *pdst = (short*)addr_dst;
		
		for (int count = 0; count < num_words*2; count++) {
			int data_src = *psrc;
			int data = data_src*percentage/100*factor_float;
			if((abs(data) > 32767) && (one_print==0))
			{
				printf("***ERROR: overflow after scaling, 16-bit data index %d, value 0x%X, after scaling 0x%X, percentage %d, factor_float %f\n", count, data_src, data, percentage, factor_float);
				one_print = 1;
			}
			
			*pdst = data;
			pdst++; psrc++;
		}
	}
	else if(type == DATA_TYPE_FLOAT)
	{
		float *psrc = (float*)addr_src;
		float *pdst = (float*)addr_dst;
		
		for (int count = 0; count < num_words*1; count++) {
			float data = *psrc;
			data = data*percentage/100*factor_float;
			*pdst = data;
			pdst++; psrc++;
		}
	}
	close(devmem_fd);
	return 0;
}
