// Copyright 2023-2025 NXP
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

void complex_mpy(float I1_src, float Q1_src, float I2_src, float Q2_src, float* I_dst, float* Q_dst)
{
	*I_dst = I1_src * I2_src - Q1_src * Q2_src;
	*Q_dst = I1_src * Q2_src + Q1_src * I2_src;
}
void complex_div(float I1_src, float Q1_src, float I2_src, float Q2_src, float* I_dst, float* Q_dst)
{
	float tempI, tempQ, factor;
	complex_mpy(I1_src, Q1_src, I2_src, -Q2_src, &tempI, &tempQ);
	factor = I2_src * I2_src + Q2_src * Q2_src;
	tempI = tempI / factor;
	tempQ = tempQ / factor;
	*I_dst = tempI;
	*Q_dst = tempQ;
}
void deqec(void* buffer, unsigned int num_samples, float f1, float f2, float f4, float gain_I, float gain_Q, float dcoff_I, float dcoff_Q);

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr;
	uint32_t num_samples,f1,f2,f4,gainI,gainQ,dcoffI,dcoffQ;
	short *addr;
	off_t phys_addr;

	if (argc < 6) {
		printf("deqec <physical addr> <num_samples> <f1_hex> <f2_hex> <f4_hex> [gainI_hex] [gainQ_hex] [dcoffI_hex] [dcoffQ_hex]\n");
		return -1;
	}

	errno = 0;
	phys_addr = strtoull(argv[1], NULL, 0);
	if (errno) {
		perror("Error converting physical address ");
		return -1;
	}


	num_samples = strtoul(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting num_samples");
		return -1;
	}

	f1 = strtoul(argv[3], NULL, 0);
	if (errno) {
		perror("Error converting f1");
		return -1;
	}

	f2 = strtoul(argv[4], NULL, 0);
	if (errno) {
		perror("Error converting f2");
		return -1;
	}

	f4 = strtoul(argv[5], NULL, 0);
	if (errno) {
		perror("Error converting f4");
		return -1;
	}

	gainI = 0x3f800000;
	if (argc > 6) {
		gainI = strtoul(argv[6], NULL, 0);
		if (errno) {
			perror("Error converting gainI");
			return -1;
		}
	}

	gainQ = 0x3f800000;
	if (argc > 7) {
		gainQ = strtoul(argv[7], NULL, 0);
		if (errno) {
			perror("Error converting gainQ");
			return -1;
		}
	}

	dcoffI = 0;
	if (argc > 8) {
		dcoffI = strtoul(argv[8], NULL, 0);
		if (errno) {
			perror("Error converting dcoffI");
			return -1;
		}
	}

	dcoffQ = 0;
	if (argc > 9) {
		dcoffQ = strtoul(argv[9], NULL, 0);
		if (errno) {
			perror("Error converting dcoffQ");
			return -1;
		}
	}

	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	mmap_addr = mmap(NULL, sizeof(uint32_t) * num_samples, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr);
	if (MAP_FAILED == mmap_addr) {
		perror("Mapping devmem failed\n");
		return -1;
	}

	addr = mmap_addr;
	//for(int i=0;i<num_samples*2;i++)
	//	addr[i] = (addr[i]+8)&0xFFF0;
	
	deqec(addr,num_samples,*(float*)&f1,*(float*)&f2,*(float*)&f4,*(float*)&gainI,*(float*)&gainQ,*(float*)&dcoffI,*(float*)&dcoffQ);
	close(devmem_fd);
	return 0;
}
