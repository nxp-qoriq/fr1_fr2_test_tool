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

#define SIZE_ALIGNED			4096
#define ALIGN_SIZE_LOWER(size)	((size)/SIZE_ALIGNED*SIZE_ALIGNED)
#define ALIGN_SIZE_UPPER(size)	(((size)+SIZE_ALIGNED-1)/SIZE_ALIGNED*SIZE_ALIGNED)

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr;
	uint64_t value;
	uint32_t size_aligned, num_words=2;   //this app only access max 64 bit, 2 words
	uint32_t *addr;
	off_t phys_addr, phys_addr_aligned;

	if (argc < 4) {
		printf("memrd <r> <bitwidth> <physical addr> [physical addr] ...\n");
		printf("  Read one or multiple values from one or multiple physical addr.  bitwidth: 8,16,32,64\n");
		printf("memrd <w> <bitwidth> <physical addr> <value> [physical addr] [value]...\n");
		printf("  Write one or multiple values to one or multiple physical addr.  bitwidth: 8,16,32,64\n");
		return -1;
	}

	unsigned int rw=0;
	if(argv[1][0] == 'r')
		rw = 0;
	else if(argv[1][0] == 'w')
		rw = 1;
	else
	{
		printf("Error rw\n");
		return -1;
	}

	errno = 0;
	unsigned int bitw = strtoul(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting bitwidth ");
		return -1;
	}
		
	phys_addr = strtoull(argv[3], NULL, 0);
	if (errno) {
		perror("Error converting physical address ");
		return -1;
	}

	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	phys_addr_aligned = ALIGN_SIZE_LOWER(phys_addr);
	size_aligned = ALIGN_SIZE_UPPER(num_words*4 + phys_addr - phys_addr_aligned);
	mmap_addr = mmap(NULL, size_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_aligned);
	if (MAP_FAILED == mmap_addr) {
		perror("Mapping devmem failed\n");
		return -1;
	}

	addr = mmap_addr + phys_addr - phys_addr_aligned;
	

	if(rw==0)  //read
	{
		if(bitw == 8)
		{
			printf("0x%02x", (*(unsigned char*)addr)&0xFF );
			for(int i=4;i<argc;i++)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				printf(" 0x%02x ", (*(unsigned char*)addr)&0xFF );
			}
			printf("\n");
		}
		else if(bitw == 16)
		{
			printf("0x%04x", (*(unsigned short*)addr)&0xFFFF );
			for(int i=4;i<argc;i++)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				printf(" 0x%04x ", (*(unsigned short*)addr)&0xFFFF );
			}
			printf("\n");
		}
		else if(bitw == 32)
		{
			printf("0x%08x", (*(unsigned int*)addr) );
			for(int i=4;i<argc;i++)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				printf(" 0x%08x ", (*(unsigned int*)addr) );
			}
			printf("\n");
		}
		else if(bitw == 64)
		{
			printf("0x%016llx", (*(unsigned long long*)addr) );
			for(int i=4;i<argc;i++)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				printf(" 0x%016llx ", (*(unsigned long long*)addr) );
			}
			printf("\n");
		}
		else
			printf("Error bitwidth\n");

	}
	else
	{
		if (argc > 4) 
		{
			value = strtoull(argv[4], NULL, 0);
			if (errno) {
				perror("Error converting value");
				return -1;
			}
		}
		if(bitw == 8)
		{
			*(unsigned char*)addr = value;
			for(int i=5;i<(argc-3)/2*2+3;i+=2)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				value = strtoull(argv[i+1], NULL, 0);
				if (errno) {
					perror("Error converting value");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				*(unsigned char*)addr = value;
			}
		}
		else if(bitw == 16)
		{
			*(unsigned short*)addr = value;
			for(int i=5;i<(argc-3)/2*2+3;i+=2)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				value = strtoull(argv[i+1], NULL, 0);
				if (errno) {
					perror("Error converting value");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				*(unsigned short*)addr = value;
			}
		}
		else if(bitw == 32)
		{
			*(unsigned int*)addr = value;
			for(int i=5;i<(argc-3)/2*2+3;i+=2)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				value = strtoull(argv[i+1], NULL, 0);
				if (errno) {
					perror("Error converting value");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				*(unsigned int*)addr = value;
			}
		}
		else if(bitw == 64)
		{
			*(unsigned long long*)addr = value;
			for(int i=5;i<(argc-3)/2*2+3;i+=2)
			{
				phys_addr = strtoull(argv[i], NULL, 0);
				if (errno) {
					perror("Error converting physical address");
					return -1;
				}
				value = strtoull(argv[i+1], NULL, 0);
				if (errno) {
					perror("Error converting value");
					return -1;
				}
				addr = mmap_addr + phys_addr - phys_addr_aligned;
				*(unsigned long long*)addr = value;
			}
		}
		else
			printf("Error bitwidth\n");

	}
	
	close(devmem_fd);
	return 0;
}
