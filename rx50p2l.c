/*
 * Quick program to read a phyiscal RX-50 dump and turn it into a
 * logical dump that can be used.
 *
 * Tracks 0 and 1 have no interleave.
 * Tracks 2-79 have an interlave of 2, so the logical tracks are
 * stored in the following physical tracks:
 *	Physical	Logical
 *	1		1
 *	2		6
 *	3		2
 *	4		7
 *	5		3
 *	6		8
 *	7		4
 *	8		9
 *	9		5
 *	10		10
 *
 *	Physical	Logical
 *	1		1
 *	3		2
 *	5		3
 *	7		4
 *	9		5
 *	2		6
 *	4		7
 *	6		8
 *	8		9
 *	10		10
 */

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <err.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/uio.h>

#define NSECTORS 10
#define SECTOR_LEN 512
#define TOTAL_TRACKS 80

#define Z80_DI		0xf3	/* Z80 encoding for DI mnemonic */
#define RX50_BLANK	0xe5	/* bytes on a blank RX-50 */
#define RB_MEDIA_ID	0xfa	/* Rainbow used media ID 0xfa for its media ID */

/*
 * Identity mapping
 */
int same[NSECTORS] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};

/*
 * If we have a logical dump, how do we turn it into a physical one?
 */
int p2l[NSECTORS] = {1, 3, 5, 7, 9, 2, 4, 6, 8, 10};

/*
 * If we have a physical dump, how do we turn it into a logical one?
 */
int l2p[NSECTORS] = {1, 6, 2, 7, 3, 8, 4, 9, 5, 10};

uint8_t track_buffer[SECTOR_LEN * NSECTORS];

struct iovec twiddle_vect[NSECTORS];

int span = 0;
int skip_tracks = 0;
int identity_tracks = 2;
int do_dos = 0;
int do_cpm = 0;

/*
 * The MS-DOS media check routine reads sector 2 and checks ot see if
 * the first byte is 0xfa and declares it Rainbow formatted if it
 * finds that. There's a hack for 0xe5 for blank media I don't think
 * we need since DOS's FORMAT program always put a boot loader onto
 * the floppy, even if it was the crappy 'This is not a system disk'
 * one. MS-DOS needed to do this so it could format blank floppies,
 * a situation we won't encounter.
 */
uint8_t sec2magic[4] = { 0xfa,			/* cli  -- also the rainbow media ID */
			 0xe9, 0xd6, 0x00 };	/* jmp .+0xd6 -- start of secondary boot loader */
uint8_t fat12_start[3] = { RB_MEDIA_ID, 0xff, 0xff };	 /* Standard FAT start */


struct pc_dos_bootsector {
	uint8_t		jump[3];		/* Jump instruction E9 xx xx */
	uint8_t		oem_name[8];		/* Name of OEM + Version */

	uint8_t		bpb_bytes_per_sec[2];	/* Bytes per sector */
	uint8_t		bpb_sec_per_clust;	/* Sectors in each cluster */
	uint8_t		bpb_res_sec[2];		/* Number of reserved sectors */
	uint8_t		bpb_n_fat;		/* Number of FATs total */
	uint8_t		bpb_root_ents[2];	/* Number of entries in root dir */
	uint8_t		bpb_secs[2];		/* Total number of sectors */
	uint8_t		bpb_media;		/* Media ID */
	uint8_t		bpb_fat_sec[2];		/* Number of sectors per FAT */
	uint8_t		bpb_sec_per_track[2];	/* Sectors per track */
	uint8_t		bpb_heads[2];		/* Number of heads */
	uint8_t		bpb_hidden_sec[2];	/* Number of hidden sectors */
	
	uint8_t		drive_no;		/* drive number (0x80) */
	uint8_t		boot_code[479];		/* Who cares -- boot code / data */
	uint8_t		magic_55;
	uint8_t		magic_aa;
};

struct pc_dos_bootsector dummy_bs = {
	.jump = { 0xe9, 'r', 'b' },		/* Jump to boot code */
						/* not really, but easy to ID */
	.oem_name = { 'D', 'E', 'C', ' ', '3', '.', '1', '0' },
	/*
	 * Values taken from Disk definition tables for MSDOS 2.00, page 1-4 in
	 * Microsoft MS-DOS Operating System BIOS Listing
	 * AA-X432A-TV
	 * June 1983
	 * Published in the Digital Rainbow 100 MS-DOS Technical Reference Manual
	 */
	.bpb_bytes_per_sec = { 0x00, 0x02 },	/* 512 bytes per sector */
	.bpb_sec_per_clust = 0x01,		/* 1 sector per cluster */
	.bpb_res_sec = { 2 * 10, 0 },		/* 2 tracks (20 sectors) reserved */
	.bpb_n_fat = 2,				/* 2 FATs */
	.bpb_root_ents = { 96, 0 },		/* 96 root directory entries */
	.bpb_secs = { 0x20, 0x03 },		/* 800 sectors total */
	.bpb_media = RB_MEDIA_ID,		/* Rainbow media ID */
	.bpb_fat_sec = { 3, 0 },		/* 3 sectors for each FAT */
	/* End of MS-DOS 2.0 BPB values from trm */
	.bpb_sec_per_track = { 10, 0 },		/* 10 sectors per track */
	.bpb_heads = { 1, 0 },			/* Single sided */
	.bpb_hidden_sec = { 0, 0 },		/* Unused in FreeBSD, but nothing hidden */
	/* End of MS-DOS 3.3 BPB */
	.drive_no = 0x80,			/* This is a lie */
	.magic_55 = 0x55,			/* Last two bytes are 0x55 and */
	.magic_aa = 0xaa,			/*    0xaa per DOS signature */
};

_Static_assert(sizeof(struct pc_dos_bootsector) == SECTOR_LEN, "pc_dos_bootsector wrong size");

void
setup_twiddle_buf(struct iovec *iov, int *xlate, int n, int offset)
{
	int i, new;

	for (i = 0; i < n; i++) {
		/* Sectors are 1-based */
		new = xlate[(i + offset) % n] - 1;
//		fprintf(stderr, "Moving %d to %d\n", i, new);
		iov[new].iov_base = track_buffer + i * SECTOR_LEN;
		iov[new].iov_len = SECTOR_LEN;
//		fprintf(stderr, "%d offset %llx\n", new, (long long) ((uint8_t *)iov[new].iov_base - track_buffer));
	}
}

void
usage(void)
{
	errx(1, "[-i infile] [-o outfile] [-l]");
}

/*
 * Read the entire track in so we work in pipelines that write < 5k at a time.
 */
size_t
read_track(int in)
{
	size_t len, tot, rv;

	tot = 0;
	len = sizeof(track_buffer);
	do {
		rv = read(in, track_buffer, len);
		if (rv == -1) {
			if (tot == 0)
				tot = -1;
			break;
		}
		len -= rv;
		tot += rv;
	} while (len > 0);

	return tot;
}

void
print_disk_type(int in)
{
	/*
	 * OK look at track 0
	 */
	read_track(in);				// Track 0
	if (track_buffer[0] == Z80_DI)
		printf("Found Z80 boot code in sector 0\n");
	else if (track_buffer[0] == RX50_BLANK)
		printf("Found Blank RX-50 media\n");
	if (memcmp(track_buffer + SECTOR_LEN, sec2magic, sizeof(sec2magic)) == 0)
		printf("Found MS-DOS secondary boot loader\n");
	if (track_buffer[SECTOR_LEN] == 0xe9)
		printf("Found CP/M 86 secondary boot loader\n");

	/*
	 * Look at track 2
	 */
	read_track(in);				// Track 1
	read_track(in);				// Track 2
	if (memcmp(track_buffer, fat12_start, sizeof(fat12_start)) == 0)
		printf("Found MS-DOS FAT in the right place\n");
	else if (track_buffer[0] == 0x00 && track_buffer[1] != 0xe5)
		printf("Possible CP/M directory\n");
}

int
main(int argc, char **argv)
{
	int ch, i, in, out, lflag, wflag;
	ssize_t len;
	int offset;

	in = STDIN_FILENO;
	out = STDOUT_FILENO;
	lflag = 1;
	wflag = 0;
	while ((ch = getopt(argc, argv, "cdI:i:lo:ps:w")) != -1) {
		switch (ch) {
		case 'c':
			do_cpm = 1;
			do_dos = 0;
			break;
		case 'd':
			do_dos = 1;
			do_cpm = 0;
			break;
		case 'i':
			if (in != STDIN_FILENO)
				close(in);
			in = open(optarg, O_RDONLY);
			if (in == -1)
				err(1, "Can't open %s for reading\n", optarg);
			break;
		case 'I':
			/* Number of tracks to identity map */
			identity_tracks = strtol(optarg, NULL, 0);
			break;
		case 'l':
			lflag = 1;
			break;
		case 'o':
			if (out != STDOUT_FILENO)
				close(out);
			out = open(optarg, O_WRONLY| O_CREAT);
			if (out == -1)
				err(1, "Can't open %s for reading\n", optarg);
			break;
		case 'p':
			lflag = 0;
			break;
		case 's':
			/* Span per track, 0 DOS or CP/M 7 Venix */
			span = strtol(optarg, NULL, 0);
			break;
		case 't':
			skip_tracks = strtol(optarg, NULL, 0);
			break;
		case 'w':
			wflag = 1;
			break;
		default:
			usage();
			break;
		}
	}
	argc -= optind;
	argv += optind;
	if (argc > 0)
		usage();

	if (wflag) {
		print_disk_type(in);
		exit(0);
	}

	fprintf(stderr, "Starting\n");
	for (i = 0; i < skip_tracks; i++) {
		fprintf(stderr, "skipping track %d\n", i);
		read_track(in);
	}

	offset = 0;
	for (; i < TOTAL_TRACKS; i++) {
		len = read_track(in);
		if (len == -1)
			err(1, "bad read");
		else if (len != sizeof(track_buffer))
			errx(1, "short read track %d (%zd bytes)", i, len);
		if (i == 0 && do_dos && lflag) {
			/*
			 * When we have MS-DOS, we have to hack the first sector so
			 * mtools works. At present, this is non-reversable.
			 */
			memcpy(track_buffer, &dummy_bs, SECTOR_LEN);
		}
		setup_twiddle_buf(twiddle_vect,
		    i < identity_tracks ? same : (lflag ? l2p : p2l),
		    NSECTORS, offset);
		len = writev(out, twiddle_vect, NSECTORS);
		if (len == -1)
			err(1, "bad write");
		else if (len != sizeof(track_buffer))
			errx(1, "short write");
		offset += span;
	}
	if (in != STDIN_FILENO)
		close(in);
	if (out != STDOUT_FILENO)
		close(out);
}
