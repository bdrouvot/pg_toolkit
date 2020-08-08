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
                perror(argv[1]);        \
                exit(errno);            \
        }

#ifdef printf
#undef printf
#endif
#ifdef fprintf
#undef fprintf
#endif
#ifdef strerror
#undef strerror
#endif

uint16 compute_checksum(const char *page);
uint16 open_file_flip_and_compute(const char *filepath, int bit);
static const char *progname;

static void
usage(void)
{
	printf("%s: Flip one bit one by one and compute the checksum.\n", progname);
	printf("%s: The bit that has been flipped is displayed if the computed checksum matches the one in argument.\n\n", progname);
	printf("Usage:\n");
	printf("  %s [OPTION] <block_path>\n", progname);
	printf("  -c, --checksum=CHECKSUM to look for\n");
}

uint16
compute_checksum(const char *page)
{
	PageHeader	phdr = (PageHeader) page;
	uint16 checksum;

	checksum = pg_checksum_page((char *)page, 0);

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

uint16
open_file_flip_and_compute(const char *filepath, int bit)
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
	return compute_checksum(page);
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


	static struct option long_options[] = {
		{"help", no_argument, NULL, '?'},
		{"checksum", required_argument, NULL, 'c'},
		{NULL, 0, NULL, 0}
	};

	progname = argv[0];

	if (argc <= 3)
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

	while ((option = getopt_long(argc, argv, "c:",
							long_options, &optindex)) != -1)
	{
		switch (option)
		{
			case 'c':
				checksum = atoi(optarg);
				break;
			default:
				usage();
				exit(0);
		}
	}

	errno = 0;
	HANDLE_ERR(stat(argv[optind], &st));
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

	file = argv[optind];

	for (i=0; i < 8 * BLCKSZ; i++)
		if (open_file_flip_and_compute(file, i) == checksum) {
			printf("Warning: Keep in mind that numbering starts from 0 for both bit and byte\n");
			printf("checksum %x (%d) found while flipping bit %d (bit %d in byte %d)\n", checksum, checksum, i, i%8, i/8);
		}
	return 0;
}
