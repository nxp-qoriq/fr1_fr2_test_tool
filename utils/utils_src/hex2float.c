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
	if (argc < 2) {
		printf("hex2float [-r] <value> [value ...]\n");
		return -1;
	}

	if (strcmp(argv[1], "-r") == 0)
	{
		unsigned int value_int[16];
		for(int i=0;i<argc-2;i++)
		{
			float value_float = strtof(argv[i+2], NULL);
			value_int[i] = *(unsigned int*)&value_float;
		}
		for(int i=0;i<argc-2;i++)
		{
			printf("0x%08x ",value_int[i]);
		}
	}
	else
	{
		float value_float[16];
		for(int i=0;i<argc-1;i++)
		{
			unsigned int value_int = strtoul(argv[i+1], NULL, 0);
			value_float[i] = *(float*)&value_int;
		}
		for(int i=0;i<argc-1;i++)
		{
			printf("%f ",value_float[i]);
		}
	}
	return 0;
}
