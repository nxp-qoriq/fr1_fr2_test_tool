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

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr_src;
	void *mmap_addr_dst;
	uint32_t num_words, reorg_period, reorg_len;
	uint32_t *addr_src;
	uint32_t *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned;
	off_t phys_addr_src, phys_addr_dst, phys_addr_src_aligned, phys_addr_dst_aligned;

	if (argc < 4) {
		printf("memcpy <physical addr_src> <physical addr_dst> <num_32bit_words> [reorg_period reorg_len]\n");
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
	
	reorg_period=1; reorg_len=1;
	if (argc >= 5) {
	reorg_period = strtoul(argv[4], NULL, 0);
	if (errno) {
		perror("Error converting num_32bit_words");
		return -1;
	}
	}
	
	if (argc >= 6) {
	reorg_len = strtoul(argv[5], NULL, 0);
	if (errno) {
		perror("Error converting num_32bit_words");
		return -1;
	}
	}
	
	if((reorg_period < reorg_len) || (reorg_period == 0) || (reorg_len == 0) || ((reorg_period%reorg_len) != 0))
	{
		printf("Error values in reorg_period %d or reorg_len %d\n", reorg_period, reorg_len);
		return -1;
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
	uint32_t num_blocks = reorg_period/reorg_len;
	uint32_t block_len = num_words/num_blocks;
	
	for (int block = 0; block < num_blocks; block++) 
	{
		uint32_t *psrc = addr_src+block*reorg_len;
		uint32_t *pdst = addr_dst+block*block_len;
		for(int period=0;period<num_words/reorg_period;period++)
		{
			for(int len=0; len<reorg_len; len++)
			{
				*pdst++ = psrc[len];
			}
			psrc += reorg_period;
		}
	}
	close(devmem_fd);
	return 0;
}
