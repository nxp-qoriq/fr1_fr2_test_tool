// Copyright 2023 NXP
//
// NXP Confidential. This software is owned or controlled by NXP and may only
// be used strictly in accordance with the applicable license terms. By expressly accepting
// such terms or by downloading, installing, activating and/or otherwise using
// the software, you are agreeing that you have read, and that you agree to
// comply with and are bound by, such license terms. If you do not agree to
// be bound by the applicable license terms, then you may not retain,
// install, activate or otherwise use the software.

#define MMAP_ALIGNMENT	4096
#define ALIGN_LOW(x,y)	((x)&(~((y)-1)))
#define ALIGN_HIGH(x,y)	(((x)+(y)-1)&(~((y)-1)))

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

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr;
	uint32_t num_words;
	uint32_t value, size_aligned, skip=0, repeat=1;
	uint32_t *addr;
	off_t phys_addr, phys_addr_align_low, phys_addr_offset;

	if (argc < 4) {
		printf("memset <physical addr> <num_32bit_words> <value> [skip repeat]\n");
		printf("  physical addr:   starting physical address to set\n");
		printf("  num_32bit_words: num of 32 bit words from address\n");
		printf("  value:           value to be written\n");
		printf("  skip repeat: 	   for 2D memset, skip is num of 32 bit words to be skipped from the last set value, repeat is the num of 1D\n");
		return -1;
	}

	errno = 0;
	phys_addr = strtoull(argv[1], NULL, 0);
	if (errno) {
		perror("Error converting physical address ");
		return -1;
	}


	num_words = strtoul(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting num_32bit_words");
		return -1;
	}

	value = strtoul(argv[3], NULL, 0);
	if (errno) {
		perror("Error converting value");
		return -1;
	}

	if (argc == 6) {
		skip = strtoul(argv[4], NULL, 0);
		if (errno) {
			perror("Error converting skip");
			return -1;
		}
		repeat = strtoul(argv[5], NULL, 0);
		if (errno) {
			perror("Error converting repeat");
			return -1;
		}
	}

	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	phys_addr_align_low = ALIGN_LOW(phys_addr, MMAP_ALIGNMENT);
	phys_addr_offset = phys_addr - phys_addr_align_low;
	int size = (num_words+skip)*repeat*4 + phys_addr_offset;
	mmap_addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_align_low);
	if (MAP_FAILED == mmap_addr) {
		perror("Mapping devmem failed\n");
		return -1;
	}

	addr = mmap_addr + phys_addr_offset;
	for (int r = 0; r<repeat; r++)
	{
		for (int count = 0; count < num_words; count++) 
		{
			*addr++ = value;
		}
		addr+=skip;
	}
	close(devmem_fd);
	return 0;
}
