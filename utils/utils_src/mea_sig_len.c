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

#define NUM_MEASURE_ENTRIES		128
#define TIMEOUT_FIRST			30   //seconds
#define TIMEOUT_LAST			5   //seconds

#define SIZE_ALIGNED			0x100000
#define ALIGN_SIZE_LOWER(size)	((size)/SIZE_ALIGNED*SIZE_ALIGNED)
#define ALIGN_SIZE_UPPER(size)	(((size)+SIZE_ALIGNED-1)/SIZE_ALIGNED*SIZE_ALIGNED)

unsigned int record[NUM_MEASURE_ENTRIES][3];  //trig value, timestamp, captured value

int main(int argc, char *argv[])
{
	int devmem_fd;
	void *mmap_addr_src, *mmap_addr_dst, *mmap_addr_cap;
	uint32_t bitmask, clock_rate, mea_end=0, timeout=TIMEOUT_FIRST;
	volatile uint32_t *addr_src, *addr_cap, *addr_dst;
	uint32_t size_src_aligned, size_dst_aligned, size_cap_aligned;
	off_t phys_addr_src, phys_addr_cap, phys_addr_dst, phys_addr_src_aligned, phys_addr_cap_aligned, phys_addr_dst_aligned;

	if (argc < 6) {
		printf("mea_sig_len <trig addr> <trig bitmask> <cap addr> <clock_address> <clock rate> [mea_ending]\nMeasuring signal length at specified addres on specified bit\nmea_end:0-record beginning events, 1-record ending records(the last events before sig stopping\n");
		return -1;
	}

	errno = 0;
	phys_addr_src = strtoull(argv[1], NULL, 0);
	if (errno) {
		perror("Error converting sig_address ");
		return -1;
	}
	phys_addr_dst = strtoull(argv[4], NULL, 0);
	if (errno) {
		perror("Error converting clock address ");
		return -1;
	}
	phys_addr_cap = strtoull(argv[3], NULL, 0);
	if (errno) {
		perror("Error converting cap addr ");
		return -1;
	}


	bitmask = strtoul(argv[2], NULL, 0);
	if (errno) {
		perror("Error converting bitmask");
		return -1;
	}

	clock_rate = strtoul(argv[5], NULL, 0);
	if (errno) {
		perror("Error converting clock rate");
		return -1;
	}

	if (argc >= 7)
	{
		mea_end = strtoul(argv[6], NULL, 0);
		if (errno) {
			perror("Error converting mea_end");
			return -1;
		}
	}
	
	devmem_fd = open("/dev/mem", O_RDWR);
	if (-1 == devmem_fd) {
		perror("/dev/mem open failed");
		return -1;
	}

	phys_addr_src_aligned = ALIGN_SIZE_LOWER(phys_addr_src);
	size_src_aligned = ALIGN_SIZE_UPPER(1*4 + phys_addr_src - phys_addr_src_aligned);   //src addr is trigger addr, 32 bit
	mmap_addr_src = mmap(NULL, size_src_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_src_aligned);
	if (MAP_FAILED == mmap_addr_src) {
		perror("Mapping devmem  src failed\n");
		return -1;
	}

	phys_addr_cap_aligned = ALIGN_SIZE_LOWER(phys_addr_cap);
	size_cap_aligned = ALIGN_SIZE_UPPER(1*4 + phys_addr_cap - phys_addr_cap_aligned);   //cap addr is capture addr, 32 bit
	mmap_addr_cap = mmap(NULL, size_cap_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_cap_aligned);
	if (MAP_FAILED == mmap_addr_cap) {
		perror("Mapping devmem  cap failed\n");
		return -1;
	}

	phys_addr_dst_aligned = ALIGN_SIZE_LOWER(phys_addr_dst);
	size_dst_aligned = ALIGN_SIZE_UPPER(2*4 + phys_addr_dst - phys_addr_dst_aligned);   //dst addr is clock counter value addr, 64bit
	mmap_addr_dst = mmap(NULL, size_dst_aligned, PROT_READ | PROT_WRITE,
			MAP_SHARED, devmem_fd, phys_addr_dst_aligned);
	if (MAP_FAILED == mmap_addr_dst) {
		perror("Mapping devmem  dst failed\n");
		return -1;
	}

	addr_src = mmap_addr_src + phys_addr_src - phys_addr_src_aligned;
	addr_dst = mmap_addr_dst + phys_addr_dst - phys_addr_dst_aligned;
	addr_cap = mmap_addr_cap + phys_addr_cap - phys_addr_cap_aligned;

	unsigned int sig_v_new, sig_curr;
	unsigned long clock_hi=addr_dst[0], clock_lo=addr_dst[1];
	unsigned long clock_cur, clock_pre=((clock_hi&0xFFFF)<<32)+clock_lo;
	unsigned long i,total;
	
	if(mea_end)
		printf("Measuring last %d events or sig changes... \n", NUM_MEASURE_ENTRIES);
	else
		printf("Measuring beginning %d events or sig changes...\n", NUM_MEASURE_ENTRIES);
	
	record[0][0] = *addr_src;//sig_v_new;
	record[0][1] = addr_dst[0];
	record[0][2] = *addr_cap;
	i=1; total=1;  //initial value to first record
	unsigned int sig_v_ori = record[0][0]&bitmask;
	
	while(1)
	{
		do
		{
			sig_curr = (*addr_src);
			sig_v_new = sig_curr&bitmask;
			clock_hi = addr_dst[0];
			clock_lo = addr_dst[1];
			clock_cur = ((clock_hi&0xFFFF)<<32)+clock_lo;
			if((clock_cur-clock_pre)>(((unsigned long long)clock_rate)*timeout))   //if no more change in specified num of seconds, exit.
			{
				//record[i][0] = sig_curr;//sig_v_new;
				//record[i][1] = clock_lo;
				//record[i][2] = *addr_cap;
				//i++;
				//total++;
				printf("\nMeasuring stopped after %d seconds because of no more sig changes\n", timeout);
				goto mea_end;
			}
		} while (sig_v_new == sig_v_ori);
		sig_v_ori = sig_v_new;
		clock_pre = clock_cur;
		record[i][0] = sig_curr;//sig_v_new;
		record[i][1] = clock_lo;
		record[i][2] = *addr_cap;
		i++;
		total++;
		if(i==NUM_MEASURE_ENTRIES)
		{
			if(mea_end==1)
			{			
				i=NUM_MEASURE_ENTRIES/2;
			}
			else
			{
				break;
			}
		}
		timeout = TIMEOUT_LAST;
	}
	
mea_end:
	printf("Total %ld records:\n", total);
	if(total>NUM_MEASURE_ENTRIES)
		total=NUM_MEASURE_ENTRIES;
	int num_first=total;
	if(num_first>NUM_MEASURE_ENTRIES/2)
		num_first=NUM_MEASURE_ENTRIES/2;
	
	int count;
	if(num_first)
	{
		printf("First %d records:", num_first);
		for(count=0;count<num_first-1;count++)
		{
			float time_len = (float)(record[count+1][1]-record[count][1])*1000000.0/clock_rate;
			printf("\nEntry %3d: captured_value 0x%08x, trig_value 0x%08x, timestamp 0x%08x, time len %5.1f us", count, record[count][2], record[count][0], record[count][1], time_len);
		}
		printf("\nEntry %3d: captured_value 0x%08x, trig_value 0x%08x, timestamp 0x%08x\n", count, record[count][2], record[count][0], record[count][1]);
	}
	
	int num_last=total-num_first;
	if(num_last>1)
	{
		int mcount,ncount;
		printf("Last %d records:", num_last);
		for(int count=i;count<num_last+i-1;count++)
		{
			mcount=((count-NUM_MEASURE_ENTRIES/2)%(NUM_MEASURE_ENTRIES/2))+NUM_MEASURE_ENTRIES/2;
			ncount=((count+1-NUM_MEASURE_ENTRIES/2)%(NUM_MEASURE_ENTRIES/2))+NUM_MEASURE_ENTRIES/2;
			float time_len = (float)(record[ncount][1]-record[mcount][1])*1000000.0/clock_rate;
			printf("\nEntry %3d: captured_value 0x%08x, trig_value 0x%08x, timestamp 0x%08x, time len %5.1f us", mcount, record[mcount][2], record[mcount][0], record[mcount][1], time_len);
		}
		printf("\nEntry %3d: captured_value 0x%08x, trig_value 0x%08x, timestamp 0x%08x\n", ncount, record[ncount][2], record[ncount][0], record[ncount][1]);
	}
	if(total==1)
		printf("No triggering happened, Entry 0 is the initial value.\n");
	close(devmem_fd);
	return 0;
}
