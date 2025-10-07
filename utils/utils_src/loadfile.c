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

unsigned int file_size(char* filename)

{
	struct stat statbuf;
	int ret;
	ret = stat(filename, &statbuf);
	if (ret != 0) return -1;
	return statbuf.st_size;
}

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr_dst;
	uint32_t size_bytes;
	uint8_t *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned;
	off_t phys_addr_dst, phys_addr_dst_aligned;

	if (argc < 3) {
		printf("loadfile <filename> <physical addr_dst> [size bytes]\n");
		return -1;
	}

	char* filename=argv[1];
	FILE *fp;
	if ((fp = fopen(filename, "rb")) == NULL)
	{
		printf("File open failure, filename = %s.\n", filename);
		return -1;
	}
	
	errno = 0;
	phys_addr_dst = strtoull(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting physical address dst ");
		return -1;
	}

	unsigned int filesize = file_size(filename);
	if (argc > 3) 
	{
		size_bytes = strtoul(argv[3], NULL, 0);
		if (errno) {
			perror("Error converting num_32bit_words");
			return -1;
		}
		if(size_bytes > filesize)
			size_bytes = filesize;
	}
	else
		size_bytes = filesize;
	
	 
	
	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	phys_addr_dst_aligned = ALIGN_SIZE_LOWER(phys_addr_dst);
	size_dst_aligned = ALIGN_SIZE_UPPER(size_bytes + phys_addr_dst - phys_addr_dst_aligned);
	mmap_addr_dst = mmap(NULL, size_dst_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_dst_aligned);
	if (MAP_FAILED == mmap_addr_dst) {
		perror("Mapping devmem  dst failed\n");
		return -1;
	}

	addr_dst = mmap_addr_dst + phys_addr_dst - phys_addr_dst_aligned;

	unsigned int blk_size=4096;
	unsigned int num_blk = size_bytes / blk_size;
	unsigned int num_remain = size_bytes % blk_size;
	
	for(unsigned int i=0;i<num_blk;i++)
	{
		fread(addr_dst, blk_size, 1, fp);
		addr_dst += blk_size;
	}
	for(unsigned int i=0;i<num_remain;i+=4)
	{
		fread(addr_dst, 4, 1, fp);
		addr_dst += 4;
	}

	fclose(fp);
	close(devmem_fd);
	return 0;
}
