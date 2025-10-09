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
	uint32_t size_bytes, dump_flag=0, dump_to_console=0, bitw='w';
	uint8_t *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned;
	off_t phys_addr_dst, phys_addr_dst_aligned;

	if (argc < 3) {
		printf("loadmem <filename> <physical_addr> [load_size]|[-r dump_size bitw]\n");
		printf("  function:      load data into memory from bin file, or dump data from memory to bin file or console\n");
		printf("  filename:      binary file name as source data for loading memory, or dest data for dumping memory. In case of dumping and filename is set to null, data will be printed on console\n");
		printf("  physical_addr: physical address of memory\n");
		printf("  load_size:     byte size to load memory, if load_size is less than file size, only load_size will be loaded\n");
		printf("  -r:            dump memory from memory to file or console\n");
		printf("  dump_size:     dump size in byte size\n");
		printf("  bitw:          bit width in case dumping to console, b or h or w or l, for byte half-word, word, long\n");
		return -1;
	}

	char* filename=argv[1];
	FILE *fp;
	
	errno = 0;
	phys_addr_dst = strtoull(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting physical address dst ");
		return -1;
	}

	if (argc > 3) 
	{
		if(argv[3][0] != '-')
		{
			size_bytes = strtoul(argv[3], NULL, 0);
			if (errno) {
				perror("Error converting load size");
				return -1;
			}
			if ((fp = fopen(filename, "rb")) == NULL)
			{
				printf("File open failure, filename = %s.\n", filename);
				return -1;
			}
			unsigned int filesize = file_size(filename);
			if(size_bytes > filesize)
				size_bytes = filesize;
		}
		else
		{
			dump_flag = 1;
			if (argc < 5)
			{
				perror("Error arguments");
				return -1;
			}
			
			size_bytes = strtoul(argv[4], NULL, 0);
			if (errno) {
				perror("Error converting dump size");
				return -1;
			}
			
			if(argc == 6)
				bitw = argv[5][0];
			
			if((0 == strcmp(filename, "null")) || (0 == strcmp(filename, "NULL")))
			{
				dump_to_console = 1;
			}
			else
			{
				if ((fp = fopen(filename, "wba")) == NULL)
				{
					printf("File open failure, filename = %s.\n", filename);
					return -1;
				}
			}
		}
	}
	else
	{
		if ((fp = fopen(filename, "rb")) == NULL)
		{
			printf("File open failure, filename = %s.\n", filename);
			return -1;
		}
		size_bytes = file_size(filename);
	}
	
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
		perror("Mapping devmem  failed\n");
		return -1;
	}

	addr_dst = mmap_addr_dst + phys_addr_dst - phys_addr_dst_aligned;

	unsigned int blk_size=4096;
	unsigned int num_blk = size_bytes / blk_size;
	unsigned int num_remain = size_bytes % blk_size;
	
	if(dump_flag == 0)
	{
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
	}
	else if(dump_to_console == 0)
	{
		for(unsigned int i=0;i<num_blk;i++)
		{
			fwrite(addr_dst, blk_size, 1, fp);
			addr_dst += blk_size;
		}
		for(unsigned int i=0;i<num_remain;i+=4)
		{
			fwrite(addr_dst, 4, 1, fp);
			addr_dst += 4;
		}
		fclose(fp);
	}
	else
	{
		if(bitw == 'b')
		{
			for(unsigned int i=0;i<size_bytes;i+=16)
				printf("%08X:  %02X %02X %02X %02X %02X %02X %02X %02X   %02X %02X %02X %02X %02X %02X %02X %02X\n", i, *(uint8_t*)(addr_dst+i+0), *(uint8_t*)(addr_dst+i+1), *(uint8_t*)(addr_dst+i+2), *(uint8_t*)(addr_dst+i+3),
																													  *(uint8_t*)(addr_dst+i+4), *(uint8_t*)(addr_dst+i+5), *(uint8_t*)(addr_dst+i+6), *(uint8_t*)(addr_dst+i+7),
																													  *(uint8_t*)(addr_dst+i+8), *(uint8_t*)(addr_dst+i+9), *(uint8_t*)(addr_dst+i+10), *(uint8_t*)(addr_dst+i+11),
																													  *(uint8_t*)(addr_dst+i+12), *(uint8_t*)(addr_dst+i+13), *(uint8_t*)(addr_dst+i+14), *(uint8_t*)(addr_dst+i+15)
																													  );
		}
		else if(bitw == 'h')
		{
			for(unsigned int i=0;i<size_bytes;i+=16)
				printf("%08X:  %04X %04X %04X %04X   %04X %04X %04X %04X\n", i, *(uint16_t*)(addr_dst+i), *(uint16_t*)(addr_dst+i+2), *(uint16_t*)(addr_dst+i+4), *(uint16_t*)(addr_dst+i+6), *(uint16_t*)(addr_dst+i+8), *(uint16_t*)(addr_dst+i+10), *(uint16_t*)(addr_dst+i+12), *(uint16_t*)(addr_dst+i+14));
		}
		else if(bitw == 'l')
		{
			for(unsigned int i=0;i<size_bytes;i+=16)
				printf("%08X:  %016lX %016lX\n", i, *(uint64_t*)(addr_dst+i), *(uint64_t*)(addr_dst+i+8));
		}
		else
		{
			for(unsigned int i=0;i<size_bytes;i+=16)
				printf("%08X:  %08X %08X %08X %08X\n", i, *(uint32_t*)(addr_dst+i), *(uint32_t*)(addr_dst+i+4), *(uint32_t*)(addr_dst+i+8), *(uint32_t*)(addr_dst+i+12));
		}
	}
	
	close(devmem_fd);
	return 0;
}
