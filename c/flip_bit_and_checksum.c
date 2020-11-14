/*
 * flip_bit_and_checksum.c
 * 	flip one bit one by one and compute the checksum
 * 	only one bit is different compare to the original page
 * 	we are looking for a bit flip that could generate the checksum
 *
 * Bertrand Drouvot, 2020-08-01
 */

#define FRONTEND 1
#include <stdio.h>
#include <unistd.h>
#include <sys/stat.h>

#include "c.h"
#include "pg_config.h"
#include "storage/checksum.h"
#include "storage/checksum_impl.h"
#include "getopt.h"

#define HANDLE_ERR(a)                   \
        if ((a) == -1) {                \
                perror(argv[argc - 1]);        \
                exit(errno);            \
        }

#ifdef printf
#undef printf
#endif
#ifdef snprintf
#undef snprintf
#endif
#ifdef fprintf
#undef fprintf
#endif
#ifdef strerror
#undef strerror
#endif

uint16 compute_checksum(const char *page, BlockNumber blockno);
void open_file_flip_and_compute(const char *filepath, int bit, BlockNumber blockno, int checksum);
static const char *progname;
int isPowerOfTwo(unsigned n);
int findBitSetPosition(unsigned n);
int flippdupper(const char *filepath);

static void
usage(void)
{
	printf("\n");
	printf("%s:\n", progname);
	printf("Flip one bit one by one and compute the checksum.\n");
	printf("The bit that has been flipped is displayed if the computed checksum matches the one in argument.\n\n");
	printf("Usage:\n");
	printf("  %s -c checksum -b blockno [-d] <block_path>\n", progname);
	printf("  -c, --checksum to look for\n");
	printf("  -b, --blockno block offset from relation (as a result of segmentno * RELSEG_SIZE + blockoffset) \n");
}

int isPowerOfTwo(unsigned n)
{
	return n && (!(n & (n - 1)));
}

int findBitSetPosition(unsigned n)
{
	unsigned i;
	unsigned pos;

	if (!isPowerOfTwo(n))
		return -1;

	i = pos = 1;

	// Iterate through bits of n till we find a set bit
	// i&n will be non-zero only when 'i' and 'n' have a set bit
	// at same position
	while (!(i & n)) {
		// Unset current bit and set the next bit in 'i'
		i = i << 1;
		// increment position
		++pos;
	}
	return pos;
}

int
flippdupper(const char *filepath)
{

	int fd;
	unsigned char pd_upper[2];
	uint16 p_upper;
	unsigned pos;

	fd = open(filepath, O_RDONLY);

	if (fd <= 0)
	{
		fprintf(stderr, "%s: %s\n", strerror(errno), filepath);
		exit(2);
	}

	// pd_upper starts at bit 112
	lseek(fd, 112 / 8, SEEK_SET);
	read(fd, &pd_upper, 2);
	close(fd);

	p_upper = *(uint16*) pd_upper;

	pos = findBitSetPosition(p_upper);

	if (pos != -1)
	{
		pos = pos + 111;
		printf("bit %d will not be flipped to avoid current pd_upper (%u) to become 0\n", pos, *(uint16*) pd_upper);
		printf("as that would trigger an assert on PageIsNew (aka pd_upper == 0)\n");
		printf("\n");
	}

	return pos;
}

uint16
compute_checksum(const char *page, BlockNumber blockno)
{
	PageHeader	phdr = (PageHeader) page;
	uint16 checksum;

	checksum = pg_checksum_page((char *)page, blockno);

	/*
	 * In 9.2 or lower, pd_checksum is 1 since data checksums are not supported.
	 */
	if (phdr->pd_checksum == 1)
	{
		printf("Data checksums are not supported. (9.2 or lower)\n");
		exit(2);
	}

	/*
	 * pd_checksum is 0 if data checksums are disabled.
	 */
	if (phdr->pd_checksum == 0)
	{
		printf("Data checksums are disabled.\n");
		exit(2);
	}

	return checksum;
}

void
open_file_flip_and_compute(const char *filepath, int bit, BlockNumber blockno, int checksum)
{
	int fd;
	char page[BLCKSZ];
	char mask;
	char byte;

	fd = open(filepath, O_RDONLY);
  
	if (fd <= 0)
	{
		fprintf(stderr, "%s: %s\n", strerror(errno), filepath);
		exit(2);
	}

	read(fd, page, BLCKSZ);
	close(fd);
	mask = 0x01 << (bit % 8);
	byte = page [bit / 8];
	byte ^= mask;
	memset(page + (bit / 8), byte, 1);

	if (compute_checksum(page, blockno) == checksum)
	{
		char fpath[MAXPGPATH];
		FILE *file;

		printf("Warning: Keep in mind that numbering starts from 0 for both bit and byte\n");
		printf("checksum %x (%d) found while flipping bit %d (bit %d in byte %d)\n", checksum, checksum, bit, bit%8, bit/8);

		snprintf(fpath, MAXPGPATH, "%s_with_bit_%d_flipped", filepath, bit);
		printf("Dumping block with flipped bit to: %s\n", fpath);
		file = fopen(fpath, "wb");
		fwrite(page, BLCKSZ, 1, file);
		fclose(file);
	}
}

int
main(int argc, char *argv[])
{
	char *file = NULL;
	struct stat st;
	int i;
	int                     option;
	int                     optindex = 0;
	int checksum = 0;
	uint32 blockno = 0;
	int bit_pos;

	static struct option long_options[] = {
		{"help", no_argument, NULL, '?'},
		{"checksum", required_argument, NULL, 'c'},
		{"blockno", required_argument, NULL, 'b'},
		{NULL, 0, NULL, 0}
	};

	progname = argv[0];

	if (argc <= 4)
	{
		usage();
		exit(0);
	}

	if (argc > 1)
	{
		if (strcmp(argv[optind], "--help") == 0 || strcmp(argv[optind], "-?") == 0)
		{
			usage();
			exit(0);
		}
	}

	while ((option = getopt_long(argc, argv, "c:b:",
							long_options, &optindex)) != -1)
	{
		switch (option)
		{
			case 'c':
				checksum = atoi(optarg);
				break;
			case 'b':
				blockno = atoi(optarg);
				break;
			default:
				usage();
				exit(0);
		}
	}

    if (optind >= argc) {
        printf ("Block path has not been provided\n");
		exit (1);
    }

	errno = 0;
	HANDLE_ERR(stat(argv[argc - 1], &st));

	if (!S_ISREG(st.st_mode))
	{
		fprintf(stderr, "The block must be a regular file\n");
		exit(1);
	}

	if (st.st_size != BLCKSZ)
	{
		fprintf(stderr, "The file size must be %d\n",BLCKSZ);
		exit(1);
	}

	file = argv[argc - 1];

	// check if pd_upper has only one bit set
	// get its position if that's the case
	// -1 if not the case
	// to avoid the assert on PageIsNew (aka pd_upper == 0)
	// in checksum_impl.h
	bit_pos = flippdupper (file);

	for (i=0; i < 8 * BLCKSZ; i++)
	{
		if (i == bit_pos)
			continue;

		open_file_flip_and_compute(file, i, blockno, checksum);
	}
	return 0;
}
