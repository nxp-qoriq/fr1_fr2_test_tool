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

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr;
	uint32_t num_words;
	uint32_t value;
	uint32_t *addr;
	off_t phys_addr;

	if (argc < 3) {
		printf("memset <physical addr> <num_32bit_words> [value]\n");
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

	if (argc > 3) {
		value = strtoul(argv[3], NULL, 0);
		if (errno) {
			perror("Error converting value");
			return -1;
		}
	}

	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	mmap_addr = mmap(NULL, sizeof(uint32_t) * num_words, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr);
	if (MAP_FAILED == mmap_addr) {
		perror("Mapping devmem failed\n");
		return -1;
	}

	addr = mmap_addr;
	for (int count = 0; count < num_words; count++) {
		*addr &= value;
		addr++;
	}
	close(devmem_fd);
	return 0;
}
