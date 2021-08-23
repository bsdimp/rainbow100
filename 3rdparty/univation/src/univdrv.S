#
# This file is patched into MS-DOS directly (over the original
# driver?). So start there, and then dig out 0x580 bytes...
#

# The patch script reads in sectors 20-39, then splats this into offset
# 0x980 and then patches some other stuff to create a diskette that will
# quickly boot off of the hard drive.

# nuniv211.bin				Set univ211.bin to read in
# l					Load this file at cs:0x100
# lcs:800 0 20 20			Read in sector 32 through 64 [*]
# mcs:100L580 cs:1180			Deposit 580H(1408) bytes at offset 980H in blocks read
# ecs:86c
# 20 87 09 92				Drop 4 bytes at offset 6c into track2 sector 1 off 6c
# ecs:2c84
# 90 90 90 90 90 90 90 e8 f2 e4		NOPs and jump at 2484 of buffer (track 3 sector 1 off 84)
# wcs:800 0 20 20			Write it out
# q
#
# 0xf80 and higher (we copy from offset 0x980 to 0xf00 in IO.SYS) is preserved verbatim.
# It's isn't at all clear what this is for, where it's intended to load, etc.
#
# [*] This just happens to be IO.SYS since on an RX-50 FORMAT/S puts IO.SYS in the first
# sectors after the directory which land here.
# So... time to get/find the BIOS sources that are out there for the 2.11 BIOS to see whta
# gets stomped to make this happen...
#


# Note: it appears that the disk(s) are attached via a SCSI-1 cable that
# uses a subset of the pins (devices can't assert unit attention). This is
# late SASI/Early SCSI 1. We send SCSI CCBs, but don't seem to be doing the
# other inquiry stuff to see if things are there or not...  The adaptec ADC-4000A
# card that is used to translate MFM to SCSI is fully SCSI compliant, but also can
# be made to support SASI hosts. The manual is dated April 1986.
#

# Note: we use AT&T syntax for this file.

# Note: Appendix B of http://bitsavers.org/pdf/xebec/104524C_S1410Man_Aug83.pdf
# has the reference code for the reference design this is almost certainly
# based on.

# Note, this is a reconstructed driver from a disassembled driver. gas
# is better at producing code so we have some padding instructions to
# work through the issues
	.macro pad
	nop
	.endm

	# These seem to be a general data port
	# Port 71 is twiddled and/or we wait for bits to be set
	# and then we transfer data to/from this port.
	.set	sasi_data_r, 0x70	# AKA WPORT0
	.set	sasi_data_w, 0x70	# AKA RPORT0

	# This seems to be a status / ISR port.
	# There's only 1 write of port 71, and that's whatever bits
	# are set on startup when bit1 (0x2) is set.
	.set	sasi_status, 0x71	# AKA RPORT1
	.set	sasi_status_req, 0x01
	.set	sasi_status_bsy, 0x02
	.set	sasi_status_msg, 0x04	# Unused in this driver...
	.set	sasi_status_cd, 0x08	# 1 control, 0 data
	.set	sasi_status_io, 0x10	# 1 input, 0 output
	# bit 5 appears unused -- unwired in xebec reference design
	# bit 6 appears unused -- unwired in xebec reference design
	# bit 7 appears unused -- unwired in xebec reference design
	.set	sasi_bus_reset, 0x71	# Writes toggle ~RST AKA WPORT1

	# Toggle ~SEL line
	.set	sasi_bus_select, 0x72	# AKA WPORT2

	# SCSI op codes
	.set OP_REQUEST_SENSE, 0x3
	.set OP_READ, 0x8
	.set OP_WRITE, 0xa
	.set OP_TRANSLATE, 0xf

	# MS-DOS request packet defines
	.set rp_len, 0
	.set rp_unit, 1
	.set rp_cmd, 2
	.set rp_status, 3
	.set rp_media_ret, 14
	.set rp_rw_media, 13
	.set rp_rw_buffer, 14
	.set rp_rw_count, 18
	.set rp_rw_lba, 20
	.set rp_bbpb_off, 18
	.set rp_bbpb_seg, 20

	.set err_unknown, 0x3
	.set err_write_fault, 0xa
	.set err_read_fault, 0xb

	.code16
        .arch   i8086           # Note: need binutils as clang8 can't cope
start:		jmp u_init
u_pkt:
u_pkt_off:	.word 0x00
u_pkt_seg:	.word 0x00

u_strategy:	mov	%bx,%cs:u_pkt_off
		mov	%es,%cs:u_pkt_seg
		lret

u_interrupt:	push	%si
		push	%ax
		push	%cx
		push	%dx
		push	%di
		push	%bp
		push	%ds
		push	%es
		push	%bx
# ds:bx is our packet from DOS
		lds	%cs:u_pkt,%bx
		mov	rp_cmd(%bx),%al
		cmp	$0xb,%al
		ja	badcmd
		cbw
		shl	$0x1,%ax
		mov	%ax,%si
		mov	rp_unit(%bx),%al	# %al = Unit
		mov	rp_rw_media(%bx),%ah	# %ah = media byte
		mov	rp_rw_count(%bx),%cx	# %cx = sector count
		mov	rp_rw_lba(%bx),%dx	# %ds = lba
		les	rp_rw_buffer(%bx),%di	# %es:%di = transfer address
		push	%cs
		pop	%ds
		jmp	*u_req_sw(%si)

# DOS packet code dispatch table
u_req_sw:	.word u_drv_init		# init
		.word u_media_check		# media check
		.word u_build_bpb		# build bpb
		.word badcmd			# ioctl -- bad command
		.word u_read			# read
		.word u_done			# input peek no wait -- u_done
		.word u_done			# input status -- u_done
		.word u_done			# input flush -- u_done
		.word u_write			# output
		.word u_write			# output with verify
		.word u_done			# output status -- u_done
		.word u_done			# output flush -- u_done
		.word badcmd			# ioctl -- bad command

badcmd:		mov	$err_unknown,%al
errout:		mov	$0x81,%ah
		lds	%cs:u_pkt,%bx
		movw	$0x0,rp_rw_count(%bx)
		jmp	1f
u_done:		mov	$0x1,%ah		# request done
1:		lds	%cs:u_pkt,%bx
		mov	%ax,rp_status(%bx)	# Store result in packet
		pop	%bx
		pop	%es
		pop	%ds
		pop	%bp
		pop	%di
		pop	%dx
		pop	%cx
		pop	%ax
		pop	%si
		lret

	.ascii "media check"
u_media_check:	lds %cs:u_pkt,%bx
		movb $0x1,rp_media_ret(%bx)
		jmp u_done

	.ascii	"build bpb"
u_build_bpb:	cbw
		shl $0x1,%ax
		mov %ax,%bx
		mov bpb_ptr(%bx),%di
		lds %cs:u_pkt,%bx
		mov %di,rp_bbpb_off(%bx)
		mov %cs,rp_bbpb_seg(%bx)
		jmp u_done

	.ascii "BIOS param. block "
	# Start of BPBs
.macro bpb bps, spau, rsvd, nofat, rootdir, logsec, media, fat_sec
	.word \bps
	.byte \spau
	.word \rsvd
	.byte \nofat
	.word \rootdir
	.word \logsec
	.byte \media
	.word \fat_sec
.endm
	.set bpb_bps, 0		# w: bytes per sector
	.set bpb_spau, 2	# b: sectors per allocation unit
	.set bpb_rsvd, 3	# w: Number of reserved sectors ????
	.set bpb_nofat, 5	# b: Number of FATs at start of disk
	.set bpb_rootdir, 6 	# w: Number of dir entries
	.set bpb_logsec, 8	# w: Number of sectors in the logical image
	.set bpb_media, 10	# b: media descritor byte
	.set bpb_fat_sec, 11	# w: number of FAT sectors
	.set bpb_len, 13
bpbs:
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	bpb 512, 8, 0, 2, 256, 0, 0xf8, 9
	# end of BPBs
bpb_ptr: .word bpbs		# 0xaae
	.word bpbs + bpb_len
	.word bpbs + 2 * bpb_len
	.word bpbs + 3 * bpb_len
	.word bpbs + 4 * bpb_len
	.word bpbs + 5 * bpb_len
	.word bpbs + 6 * bpb_len
	.word bpbs + 7 * bpb_len
lun0_parts:	.byte 0x00
curr_op:	.byte 0x00
last_status:	.byte 0x00
xferd:		.word 0
curr_direction:	.byte 0x00
curr_lun:	.byte 0x00		# shifted left 4 for easy encoding

sense_buf:		# SENSE BUFFER for REQUEST SENSE
	.byte 0		# Error byte: AdValid:1 | ErrClass:3 |ErrCode:4
	.byte 0		# Vendor:3 | LBA:5 (MSB)
	.byte 0		# LBA
	.byte 0		# LBA (LSB)

# Data returned from TRANSLATE CDB
xlate_rsp:		# (pg 5-18 Adaptec 400003-00A)
	.byte 0x00	# MSB cylinder (always 0 for us)
curr_cylinder:		# Cylinder
	.word 0		# Cylinder LSB
curr_side:
	.byte 0x00	# Head number
	.byte 0x00	# Index MSB (also zeros for us)
	.byte 0x00	# Index
curr_offset:
	.word 0		# index / index lsb
cdb_sense:
	.byte OP_REQUEST_SENSE	# REQUEST SENSE op
	.byte 0x00
	.byte 0x00
	.byte 0x00
	.byte 0x04	# Allocation Length (sense buffer size)
	.byte 0x00
scsi_cdb:
	.byte 0x00	# Read or write
	.byte 0x00	# LUN + MSB LBA
	.byte 0x00	# LBA
	.byte 0x00	# LBA LSB
	.byte 0x01	# number of sectors to read
	.byte 0x00	# Control
translate_cdb:
	.byte OP_TRANSLATE # Translate opcode from ACB-4000A manual
	.byte 0x00	# To translate LBA to CHS
	.byte 0x00	# Used in error reporting only
	.byte 0x00	# Non-standard command
	.byte 0x00	# Same format as READ/WRITE CDB
	.byte 0x00

	.ascii "INPUT"
u_read:		movb $OP_READ,curr_op		# READ OPCODE
		jmp 1f
	pad

	.ascii "OUTPUT"
u_write:	movb $OP_WRITE,curr_op		# WRITE opcode
1:		cmp lun0_parts,%al
		mov $0x0,%al
		jc 1f
		mov $0x20,%al
1:		mov %al,curr_lun
		mov $scsi_cdb,%bx
		mov curr_op,%al
		mov %al,(%bx)			# Store OP_WRITE (0xa)
		xchg %dh,%dl
		mov %dx,0x2(%bx)		# LBA (bottom 16 bits)
		mov %cl,0x4(%bx)		# Count
		call do_xxx_xfer
		testb $0xff,last_status
		jz 2f
		call print_error
		mov $err_read_fault,%al
		cmpb $OP_READ,curr_op
		je 1f
		mov $err_write_fault,%al
1:		jmp errout
2:		jmp u_done
print_error:	call puts_immed
	.asciz "\r\nDisk error while "
		cmpb $OP_READ,curr_op
		jne 2f
		call puts_immed
	.asciz "read"
		jmp 1f
	pad
2:		call puts_immed
	.asciz "writ"
1:		call puts_immed
	.asciz "ing.\r\nStatus byte = "
		mov last_status,%al
		call puthex
		call puts_immed
	.asciz "\r\nError  code = "
		mov sense_buf,%al	# 0x219
		and $0x7f,%al
		call puthex
		mov sense_buf,%al
		test $0x80,%al		# 0x224
		jz 9f
		mov $translate_cdb,%bx
		mov sense_buf+2,%ax
		mov %ax,0x2(%bx)
		mov $xlate_rsp,%di
		mov %ds,%ax
		mov %ax,%es
		call do_xxx_xfer
		call puts_immed
	.asciz"\r\n, cyl="
		mov curr_cylinder, %ax
		xchg   %al,%ah
		call putdec
		call puts_immed
	.asciz ", side="
		movb curr_side, %al
		mov $0x0, %ah
		call putdec
		call puts_immed
	.asciz ", offset="
		mov curr_offset, %ax
		xchg %al, %ah
		call putdec
9:		call puts_immed
	.asciz "\r\n"
		ret 			#0x27d

puthex:		mov %al,%bl		#27e
		mov $0x4,%cl
		shr %cl,%al
		call 1f
		mov %bl,%al
		and $0xf,%al
1:		add $'0',%al
		cmp $'9',%al
		jna putchar
		add $0x7,%al
		jmp putchar
	pad
putdec:		mov $0x0,%bl		#296
		mov $10000,%cx
		call 1f
		mov $1000,%cx
		call 1f
		mov $100,%cx
		call 1f
		mov $10,%cx
		call 1f
		mov $0x1,%bl
		mov $1,%cx
1:		xor %dx,%dx
		div %cx
		add %al,%bl
		add $'0',%al
		cmp $0,%bl
		je 1f
		push %dx
		call putchar
		pop %dx
1:		mov %dx,%ax		#c47
		ret
	#
	# Prints the NUL terminated string that follows
	# the call. Assume no regsiters are preserved.
	#
puts_immed:	pop %bx
1:		mov %cs:(%bx),%al
		inc %bx
		test %al,%al
		jnz 3f
		jmp *%bx
3:		call putchar
		jmp 1b

putchar:	mov %al,%cl
		push %bx
		xor %di,%di
		int $0x18
		pop %bx
		ret

	# %bx is cdb
	# %di is buffer
do_xxx_xfer:	push %bx
		push %di
		call claim_bus
		call xfer_cdb
		mov %ax,xferd		# number of bytes xfer'd
		call wait_for_sasi_req
		in $sasi_status,%al
		test $sasi_status_cd,%al
		mov $0x0,%ax
		jnz 2f			# jump if 71_bit8 is set
		mov %di,%bx	#2fa
		in $sasi_status,%al		# if bit 0x10 set, don't xfer from card..
		test $sasi_status_io,%al
		jz 1f
		call read_from_card
		movb $0x1,curr_direction
		jmp 2f
	pad
1:		call write_to_card
		movb $0x0,curr_direction
2:		push %ax
		call wait_not_busy
		mov %al,last_status
		pop %ax
		pop %di
		pop %bx
		jc do_xxx_xfer
		jz 1f
		push %ax
		call claim_bus
		mov $cdb_sense,%bx
		call xfer_cdb
		call wait_for_sasi_req
		mov $sense_buf,%bx
		push %es
		mov %ds,%ax
		mov %ax,%es
		call read_from_card
		pop %es
		call wait_not_busy
		pop %ax
1:		ret

claim_bus:	in $sasi_status,%al
		test $sasi_status_bsy,%al
		jnz claim_bus
		mov $0x1,%al
		out %al,$sasi_data_w
		mov $0x1,%al			# Note for SCSI, this needs to be level not a pulse
		out %al,$sasi_bus_select
1:		in $sasi_status,%al
		test $sasi_status_bsy,%al
		jz 1b
		sub %al,%al
		out %al,$sasi_bus_select
		ret
# 35a
	# I think %bx points to the cdb/bytes to send to card
xfer_cdb:	push %bx
		mov 0x1(%bx),%al
		and $0x1f,%al
		or curr_lun,%al
		mov %al,0x1(%bx)
1:		in $sasi_status,%al
		test $sasi_status_req,%al
		jz 1b
		test $sasi_status_cd,%al	# some if not set
		jz ret_xferd
		test $sasi_status_io,%al	# some other error if set
		jnz ret_xferd
		mov (%bx),%al
		out %al,$sasi_data_w		# Write CDB byte
		inc %bx
		jmp 1b

	# and %di points to the data buffer
read_from_card:
		push %bx
		push %dx
		mov $sasi_status_req,%dh
		mov $(sasi_status_req | sasi_status_cd),%dl
		xchg %di,%bx
	# Loop until the next data is read
	# and read it in (4 bytes at a time)
	# or get out if no more data to transfer
1:		in $sasi_status,%al
		test $sasi_status_req,%al
		jz 1b			# Wait for bit1 to turn on
		test $sasi_status_cd,%al
		jnz rfc_done		# bit 8 set -> we're done
2:		in $sasi_data_r,%al		# Transfer out 4 bytes of card's buffer to host buffer
		stosb
		in $sasi_data_r,%al
		stosb
		in $sasi_data_r,%al
		stosb
		in $sasi_data_r,%al
		stosb
		in $sasi_status,%al
		and %dl,%al		# Bits 0 and 3
		cmp %dh,%al		# only bit 3 set
		jz 2b
		jmp 1b
rfc_done:	xchg %bx,%di
		pop %dx
		jmp ret_xferd
	pad
write_to_card:	push %bx
		push %dx
		push %ds
		push %es
		pop %ds
		mov $sasi_status_req,%dh
		mov $(sasi_status_req | sasi_status_cd),%dl
		xchg %si,%bx

1:		in $sasi_status,%al
		test $sasi_status_req,%al
		jz 1b			# Wait for bit1 to turn on
		test $0x8,%al		# Bit 8 set -> we're done?
		jnz wtc_done
2:		lodsb
		out %al,$sasi_data_w
		in $sasi_status,%al
		and %dl,%al		# mask out all but 8 bit and 1 bit
		cmp %dh,%al		# if 8 set and 1 clear, get more data to send
		jz 2b
		jmp 1b
wtc_done:	xchg %bx,%si
		pop %ds
		pop %dx
#3d0
ret_xferd:	mov %bx,%ax			# Return number of bytes transferred
		pop %bx
		sub %bx,%ax
		ret
	# XXX figure out what is going on here...
	# I think we're reading the status of the bus: from the standard.
	# ==============================================================================
	#   Bit|   7    |   6    |   5    |   4    |   3    |   2    |   1    |   0    |
	# Byte |        |        |        |        |        |        |        |        |
	# ==============================================================================
	# 0   |Reserved|  Vendor Unique  |        Status Byte Code           |   V    |
	# ==============================================================================
	# Bits of Status Byte
	# -----------------------------
	# 7   6   5   4   3   2   1   0    Status(es) Represented
	# ------------------------------------------------------------------------------
	# R   V   V   0   0   0   0   V    GOOD
	# R   V   V   0   0   0   1   V    CHECK CONDITION
	# R   V   V   0   0   1   0   V    CONDITION MET/GOOD
	# R   V   V   0   0   1   1   V    Reserved
	# R   V   V   0   1   0   0   V    BUSY				XXX
	# R   V   V   0   1   0   1   V    Reserved			XXX
	# R   V   V   0   1   1   0   V    Reserved			XXX
	# R   V   V   0   1   1   1   V    Reserved			XXX
	# R   V   V   1   0   0   0   V    INTERMEDIATE/GOOD
	# R   V   V   1   0   0   1   V    Reserved
	# R   V   V   1   0   1   0   V    INTERMEDIATE/CONDITION MET/GOOD
	# R   V   V   1   0   1   1   V    Reserved
	# R   V   V   1   1   0   0   V    RESERVATION CONFLICT 	XXX
	# R   V   V   1   1   0   1   V    Reserved			XXX
	# R   V   V   1   1   1   0   V    Reserved			XXX
	# R   V   V   1   1   1   1   V    Reserved			XXX
	# ==============================================================================
	# So it's either BUSY or RESERVATION CONFLICT, both of which will cause us
	# to do_xxx_xfer, though... is that a retry?
	# 0 causes us to do nothing...
wait_not_busy:	call wait_for_sasi_req		# Or maybe get bus status?
		in $sasi_data_r,%al
		mov %al,%ah
		call wait_for_sasi_req
		in $sasi_data_r,%al
		mov %ah,%al
		test $0x8,%al			# Bit 3 means 'BUSY' for the disks we care about
		jz 1f
		stc
		ret
1:		test %al,%al
		ret

	# Waits for the sasi ~REQ bit to assert itself
wait_for_sasi_req:
		in $sasi_status,%al
		test $sasi_status_req,%al
		jz wait_for_sasi_req
		ret

u_drv_init:	mov num_units,%al
		lds %cs:u_pkt,%bx
		mov %al,0xd(%bx)
		movw $u_drv_init,0xe(%bx)
		mov %cs,0x10(%bx)
		movw $bpb_ptr,0x12(%bx)
		mov %cs,0x14(%bx)
		jmp u_done

	# Store 0xe000 into 0x4000:0 to 0xdfff:f.
	# Older versions of DOS (Rainbow BIOS too?) didn't initialize this
	# memory, leading to problems. Since this HBA is piggy backed on the
	# memory board, this is a workaround for that issue.
u_init:		mov $0xe000,%ax
		mov $0x4000,%di
1:		mov %di,%es
		mov $0x0,%di
		mov $0x8000,%cx
		rep stosw
		mov %es,%di
		add $0x1000,%di
		cmp %ax,%di
		jc 1b

	#
	# Sanity check the HBA to see if it's there. We look at what appears
	# to be the 'BUS BUSY' bit (though maybe it's an initiator busy bit)
	# and if it's clear, we assume life is good. Then we write the value
	# back and re-read. The Xebec reference design toggle the ~RST line
	# of the SASI bus. Resetting the bus should change what's driven
	# on the bus. We re-read and if it is still 'ff' then
	# we'll exit without setting up the BPB array. Otherwise, we proceed
	# to reading in and parsing the 'hi' or 'ho' block defining Univation's
	# partioning scheme.
	#
	# It appears that they sold a unit that responded to both LUN 0 and
	# LUN 1 (which is encoded in the CDB as 0x20). Note that they don't
	# walk through the list of all possible SCSI IDs here.
	#
		in $sasi_status,%al
		test $sasi_status_bsy,%al
		jz 1f
		out %al,$sasi_bus_reset	# Any write will toggle the ~RST line
		in $sasi_status,%al
		sub $0xff,%al
		jz 2f			# 0xff means no device decoding
1:		mov $bpbs,%di
	# Try LUN0 first
		movb $0x0,curr_lun
		call read_hom
		mov num_units,%al	# Look at the latest partition
		mov %al,lun0_parts
	# Then LUN1...
		movb $0x20,curr_lun
		call read_hom
2:		mov num_units,%al
		or %al,%al
		jz 1f
		mov %sp,%bp
		cmpw $0x0,0x2(%bp)
		jnz 1f
		movw $0x4,0x2(%bp)
1:		ret

read_hom:	push %di
		mov $scsi_cdb,%bx
		movw $OP_READ,(%bx)		# READ6 opcode + LUN0 / 4msb LBA 0
		movw $0x0,0x2(%bx)		# LBA 0
		movb $0x1,0x4(%bx)		# Transfer Length 1
		mov $home_block,%di
		mov %ds,%ax
		mov %ax,%es
		call do_xxx_xfer
		pop %di
		testb $0xff,last_status
		jz 1f				# it worked!
		ret

	# Look for hi or ho block -- ho is 'newer' and allows up to 4 parts, hi is
	# older and allows only one.

	# hi Block:
	# ==============================================================================
	#   Bit|   7    |   6    |   5    |   4    |   3    |   2    |   1    |   0    |
	# Byte |        |        |        |        |        |        |        |        |
	# ==============================================================================
       	#   0  |                      0x68 'h'                                         |
	# -----|-----------------------------------------------------------------------|
       	#   1  |                      0x69 'i'                                         |
	# -----|-----------------------------------------------------------------------|
       	#   2  |                         Start LSB                                     |
	# -----|-----------------------------------------------------------------------|
       	#   3  |                         Start MSB                                     |
	# -----|-----------------------------------------------------------------------|
       	#   4  |                  Length of Boot blocks? LSB                           |
       	# -----|-----------------------------------------------------------------------|
       	#   5  |                  Length of Boot blocks? MSB                           |
	# -----|-----------------------------------------------------------------------|
       	#   6  |                       Data Length LSB                                 |
       	# -----|-----------------------------------------------------------------------|
       	#   7  |                       Data Length MSB                                 |
	# ==============================================================================
	#
	# Whatever these units are, we multiply them by 0x24 (36)
	#
1:		cmpw $0x6968,home_block		# Look for hi block 1
		jnz 1f
		mov (home_block+2),%ax		# Process hi block
		add (home_block+4),%ax
		mov $0x24,%cx
		mul %cx
		push %ax
		mov (home_block+6),%ax
		mov $0x24,%cx
		mul %cx
		pop %cx
		jmp decode_part
	pad #4ac
1:		cmpw $0x6f68,home_block		# Look for ho in block 1
		jz ho_blk
		ret
	# ho Block:
	# ==============================================================================
	#   Bit|   7    |   6    |   5    |   4    |   3    |   2    |   1    |   0    |
	# Byte |        |        |        |        |        |        |        |        |
	# ==============================================================================
       	#   0  |                      0x68 'h'                                         |
	# -----|-----------------------------------------------------------------------|
       	#   1  |                      0x6f 'o'                                         |
	# -----|-----------------------------------------------------------------------|
       	#   2  |                             01     start lsb?                         |
	# -----|-----------------------------------------------------------------------|
       	#   3  |                             00	    start msb?                         |
	# -----|-----------------------------------------------------------------------|
       	#   4  |                             00     rsvd lsb                           |
       	# -----|-----------------------------------------------------------------------|
       	#   5  |                             00     rsvd msb                           |
	# -----|-----------------------------------------------------------------------|
       	#   6  |                             63                                        |
       	# -----|-----------------------------------------------------------------------|
       	#   7  |                             02                                        |
	# ==============================================================================
       	#      |                  Partition Descriptor Entries (8 max)                 |
 	# ==============================================================================
	#   Bit|   7    |   6    |   5    |   4    |   3    |   2    |   1    |   0    |
	# Byte |        |        |        |        |        |        |        |        |
	# ==============================================================================
       	#   0  |              partition type name                                      |
	# -----|-----------------------------------------------------------------------|
       	#   1  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#   2  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#   3  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#   4  |                             .                                         |
       	# -----|-----------------------------------------------------------------------|
       	#   5  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#   6  |                             .                                         |
       	# -----|-----------------------------------------------------------------------|
       	#   7  |              partition type name                                      |
	# -----|-----------------------------------------------------------------------|
       	#   8  |              partition type display name                              |
	# -----|-----------------------------------------------------------------------|
       	#   9  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#  10  |                             .                                         |
 	# -----|-----------------------------------------------------------------------|
       	#  11  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#  12  |                             .                                         |
       	# -----|-----------------------------------------------------------------------|
       	#  13  |                             .                                         |
	# -----|-----------------------------------------------------------------------|
       	#  14  |                             .                                         |
       	# -----|-----------------------------------------------------------------------|
       	#  15  |              partition type display name                              |
       	# -----|-----------------------------------------------------------------------|
       	#  16  |                     Must be 0?                                        |
	# -----|-----------------------------------------------------------------------|
       	#  17  |                     Must be 0?                                        |
	# -----|-----------------------------------------------------------------------|
       	#  18  |                     Must be 0?                                        |
	# -----|-----------------------------------------------------------------------|
       	#  19  |                     Must be 0?                                        |
	# ==============================================================================
       	#      |                  Partition Entries (4 of these)                       |
 	# ==============================================================================
	#   Bit|   7    |   6    |   5    |   4    |   3    |   2    |   1    |   0    |
	# Byte |        |        |        |        |        |        |        |        |
	# ==============================================================================
       	#   0  |                  Start of partition LSB (sector)                      |
	# -----|-----------------------------------------------------------------------|
       	#   1  |                  Start of partition MSB                               |
	# -----|-----------------------------------------------------------------------|
       	#   2  |                  Length of partition LSB (sector)                     |
	# -----|-----------------------------------------------------------------------|
       	#   3  |                  Length of partition MSB                              |
	# ==============================================================================
	#
	# or in a packed C structure:
	# struct ho {
	#	char magic[2];
	#	uint16_t rsvd_sectors; /* ? */
	#	uint16_t start_sector ; /* ? */
	#	uint16_t tracks; /* ? */
	# 	struct part_desc {
	#		char part_name[8];
	#		char display_name[8];
	#		uint16_t mbz1;
	#		uint16_t mbz2;
	#		struct info {		/* In sectors */
	#			uint16_t start;
	#			uint16_t len;
	#		} info[4];
	#	} parts[8];
	# };
	#
	# Note: this couldn't describe more than 32MB drive
	#
# Example ho block:
# 00000000  68 6f 01 00 00 00 63 02  43 50 2f 4d 20 20 20 20  |ho....c.CP/M    |
# 00000010  63 70 2f 6d 38 36 38 30  00 00 00 00 01 00 23 00  |cp/m8680......#.|
# 00000020  24 00 00 00 24 00 00 00  24 00 00 00 4d 53 44 4f  |$...$...$...MSDO|
# 00000030  53 20 20 20 6d 73 2d 64  6f 73 20 20 00 00 00 00  |S   ms-dos  ....|
# 00000040  24 00 ec 55 00 00 00 00  00 00 00 00 00 00 00 00  |$..U............|
# 00000050  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00  |................|
#
# 20944 seectors from mfm_read
# Geometry in manual given as:
# Heads: 4
# Cylinders: 306
# Google search for drive gives 17 sectors per track
# 4*306*17 = 20808
# This suggests a slight underformatting of the MFM drive
# To account for mfg tracks. The math works out if we have 2 mfg tracks.
#
# 0x263 = 611 or 306*2-1 -- Unclear if this was done in error (entering the paramters
# for the 20MB at HDSETUP time) or not.
#
# So, CP/M starts at sector 1, end at sector 35 (and then there's 3 more that start
# at 36, but have 0 length so are ignored). This is too small for a real CP/M partition.
#
# MSDOS partition: starts at sector 36 ends at sector 21996+36-1 which is past the end
# of the media, suggesting the 611 number was in error and this partition was too big
# but nobody ever noticed. It seems to have about 5MB of data on it.
#
	# %di has current bpb in it
ho_blk:		mov $home_block+8,%si		# Process ho block
		mov $0x8,%cx			# up to 8 partitions
		push %di
		cld
1:		mov $msdos_str,%di		# Look for MS DOS partitions
		push %cx
		push %si
		mov $0x8,%cx
		rep cmpsb
		pop %si
		pop %cx
		je 2f
		add $0x24,%si	#4dd
	pad
		loop 1b
		pop %di
		ret

2:		pop %di
		add $0x14,%si
	pad
		mov $0x4,%cx

1:		push %cx
		mov 0x0(%si),%cx
	pad
	pad
		mov 0x2(%si),%ax
	pad
		call decode_part
		pop %cx
		add $0x4,%si
	pad
		loop 1b
		ret

	#
	# %cx Has the number of reserved sectors in this partition
	# %ax has the number of data sectors in this partition
	# %di points to the bpb we're filling in.
	#
	# Note: we have a maximum size of 32MB (2^16 blocks) and
	# we report to DOS the number of 'reserved' sectors as just
	# the effective starting point for this partition.
	#
decode_part:	test %ax,%ax
		jz 2f
		mov %cx,bpb_rsvd(%di)
	pad
		add %ax,%cx
		mov %cx,bpb_logsec(%di)
	pad
	# Compute how many FAT sectors we'll need for all
	# these sectors.
	# (Sectors * 24 + 1) / 2^16 == # FAT sectors
	# with a minimum of 9
		mov $0x18,%cx
		mul %cx
		addw $0xffff,%ax
		adc $0x0,%dx
		cmp $0x9,%dx
		jna 1f
		mov %dx,bpb_fat_sec(%di)
	pad
1:		add $bpb_len,%di
	pad
		incb num_units
2:		ret
	# Literal string we look for in the home block
msdos_str:	.ascii "MSDOS   "
num_units:	.byte 0x00
home_block:	.byte 0x00	# 0xea4
data_00000ea5:	.byte 0x00
data_00000ea6:	.byte 0x00
data_00000ea7:	.byte 0x00
data_00000ea8:	.byte 0x00
data_00000ea9:	.byte 0x00
data_00000eaa:	.byte 0x00
data_00000eab:	.byte 0x00
	.byte 0x00
data_00000ead:	.byte 0x00
data_00000eae:	.byte 0x00
data_00000eaf:	.byte 0x00
data_00000eb0:	.byte 0x00
data_00000eb1:	.byte 0x00
data_00000eb2:	.byte 0x00
data_00000eb3:	.byte 0x00
data_00000eb4:	.byte 0x00
data_00000eb5:	.byte 0x00
data_00000eb6:	.byte 0x00
data_00000eb7:	.byte 0x00
data_00000eb8:	.byte 0x00
data_00000eb9:	.byte 0x00
data_00000eba:	.byte 0x00
data_00000ebb:	.byte 0x00
data_00000ebc:	.byte 0x00
data_00000ebd:	.byte 0x00
data_00000ebe:	.byte 0x00
data_00000ebf:	.byte 0x00
data_00000ec0:	.byte 0x00
data_00000ec1:	.byte 0x00
data_00000ec2:	.byte 0x00
data_00000ec3:	.byte 0x00
data_00000ec4:	.byte 0x00
data_00000ec5:	.byte 0x00
data_00000ec6:	.byte 0x00
data_00000ec7:	.byte 0x00
data_00000ec8:	.byte 0x00
data_00000ec9:	.byte 0x00
data_00000eca:	.byte 0x00
data_00000ecb:	.byte 0x00
data_00000ecc:	.byte 0x00
data_00000ecd:	.byte 0x00
data_00000ece:	.byte 0x00
data_00000ecf:	.byte 0x00
data_00000ed0:	.byte 0x00
data_00000ed1:	.byte 0x00
data_00000ed2:	.byte 0x00
data_00000ed3:	.byte 0x00
data_00000ed4:	.byte 0x00
data_00000ed5:	.byte 0x00
data_00000ed6:	.byte 0x00
data_00000ed7:	.byte 0x00
data_00000ed8:	.byte 0x00
data_00000ed9:	.byte 0x00
data_00000eda:	.byte 0x00
data_00000edb:	.byte 0x00
data_00000edc:	.byte 0x00
data_00000edd:	.byte 0x00
data_00000ede:	.byte 0x00
data_00000edf:	.byte 0x00
data_00000ee0:	.byte 0x00
data_00000ee1:	.byte 0x00
data_00000ee2:	.byte 0x00
data_00000ee3:	.byte 0x00
data_00000ee4:	.byte 0x00
data_00000ee5:	.byte 0x00
data_00000ee6:	.byte 0x00
data_00000ee7:	.byte 0x00
data_00000ee8:	.byte 0x00
data_00000ee9:	.byte 0x00
data_00000eea:	.byte 0x00
data_00000eeb:	.byte 0x00
data_00000eec:	.byte 0x00
data_00000eed:	.byte 0x00
data_00000eee:	.byte 0x00
data_00000eef:	.byte 0x00
data_00000ef0:	.byte 0x00
data_00000ef1:	.byte 0x00
data_00000ef2:	.byte 0x00
data_00000ef3:	.byte 0x00
data_00000ef4:	.byte 0x00
data_00000ef5:	.byte 0x00
data_00000ef6:	.byte 0x00
data_00000ef7:	.byte 0x00
data_00000ef8:	.byte 0x00
data_00000ef9:	.byte 0x00
data_00000efa:	.byte 0x00
data_00000efb:	.byte 0x00
data_00000efc:	.byte 0x00
data_00000efd:	.byte 0x00
data_00000efe:	.byte 0x00
data_00000eff:	.byte 0x00
data_00000f00:	.byte 0x00
data_00000f01:	.byte 0x00
data_00000f02:	.byte 0x00
data_00000f03:	.byte 0x00
data_00000f04:	.byte 0x00
data_00000f05:	.byte 0x00
data_00000f06:	.byte 0x00
data_00000f07:	.byte 0x00
data_00000f08:	.byte 0x00
data_00000f09:	.byte 0x00
data_00000f0a:	.byte 0x00
data_00000f0b:	.byte 0x00
data_00000f0c:	.byte 0x00
data_00000f0d:	.byte 0x00
data_00000f0e:	.byte 0x00
data_00000f0f:	.byte 0x00
data_00000f10:	.byte 0x00
data_00000f11:	.byte 0x00
data_00000f12:	.byte 0x00
data_00000f13:	.byte 0x00
data_00000f14:	.byte 0x00
data_00000f15:	.byte 0x00
data_00000f16:	.byte 0x00
data_00000f17:	.byte 0x00
data_00000f18:	.byte 0x00
data_00000f19:	.byte 0x00
data_00000f1a:	.byte 0x00
data_00000f1b:	.byte 0x00
data_00000f1c:	.byte 0x00
data_00000f1d:	.byte 0x00
data_00000f1e:	.byte 0x00
data_00000f1f:	.byte 0x00
data_00000f20:	.byte 0x00
data_00000f21:	.byte 0x00
data_00000f22:	.byte 0x00
data_00000f23:	.byte 0x00
data_00000f24:	.byte 0x00
data_00000f25:	.byte 0x00
data_00000f26:	.byte 0x00
data_00000f27:	.byte 0x00
data_00000f28:	.byte 0x00
data_00000f29:	.byte 0x00
data_00000f2a:	.byte 0x00
data_00000f2b:	.byte 0x00
data_00000f2c:	.byte 0x00
data_00000f2d:	.byte 0x00
data_00000f2e:	.byte 0x00
data_00000f2f:	.byte 0x00
data_00000f30:	.byte 0x00
data_00000f31:	.byte 0x00
data_00000f32:	.byte 0x00
data_00000f33:	.byte 0x00
data_00000f34:	.byte 0x00
data_00000f35:	.byte 0x00
data_00000f36:	.byte 0x00
data_00000f37:	.byte 0x00
data_00000f38:	.byte 0x00
data_00000f39:	.byte 0x00
data_00000f3a:	.byte 0x00
data_00000f3b:	.byte 0x00
data_00000f3c:	.byte 0x00
data_00000f3d:	.byte 0x00
data_00000f3e:	.byte 0x00
data_00000f3f:	.byte 0x00
data_00000f40:	.byte 0x00
data_00000f41:	.byte 0x00
data_00000f42:	.byte 0x00
data_00000f43:	.byte 0x00
data_00000f44:	.byte 0x00
data_00000f45:	.byte 0x00
data_00000f46:	.byte 0x00
data_00000f47:	.byte 0x00
data_00000f48:	.byte 0x00
data_00000f49:	.byte 0x00
data_00000f4a:	.byte 0x00
data_00000f4b:	.byte 0x00
data_00000f4c:	.byte 0x00
data_00000f4d:	.byte 0x00
data_00000f4e:	.byte 0x00
data_00000f4f:	.byte 0x00
data_00000f50:	.byte 0x00
data_00000f51:	.byte 0x00
data_00000f52:	.byte 0x00
data_00000f53:	.byte 0x00
data_00000f54:	.byte 0x00
data_00000f55:	.byte 0x00
data_00000f56:	.byte 0x00
data_00000f57:	.byte 0x00
data_00000f58:	.byte 0x00
data_00000f59:	.byte 0x00
data_00000f5a:	.byte 0x00
data_00000f5b:	.byte 0x00
data_00000f5c:	.byte 0x00
data_00000f5d:	.byte 0x00
data_00000f5e:	.byte 0x00
data_00000f5f:	.byte 0x00
data_00000f60:	.byte 0x00
data_00000f61:	.byte 0x00
data_00000f62:	.byte 0x00
data_00000f63:	.byte 0x00
data_00000f64:	.byte 0x00
data_00000f65:	.byte 0x00
data_00000f66:	.byte 0x00
data_00000f67:	.byte 0x00
data_00000f68:	.byte 0x00
data_00000f69:	.byte 0x00
data_00000f6a:	.byte 0x00
data_00000f6b:	.byte 0x00
data_00000f6c:	.byte 0x00
data_00000f6d:	.byte 0x00
data_00000f6e:	.byte 0x00
data_00000f6f:	.byte 0x00
data_00000f70:	.byte 0x00
data_00000f71:	.byte 0x00
data_00000f72:	.byte 0x00
data_00000f73:	.byte 0x00
data_00000f74:	.byte 0x00
data_00000f75:	.byte 0x00
data_00000f76:	.byte 0x00
data_00000f77:	.byte 0x00
data_00000f78:	.byte 0x00
data_00000f79:	.byte 0x00
data_00000f7a:	.byte 0x00
data_00000f7b:	.byte 0x00
data_00000f7c:	.byte 0x00
data_00000f7d:	.byte 0x00
data_00000f7e:	.byte 0x00
data_00000f7f:	.byte 0x00
data_00000f80:	.byte 0x0e
data_00000f81:	.byte 0x1f
data_00000f82:	.byte 0xe9
data_00000f83:	.byte 0x63
data_00000f84:	.byte 0xff
data_00000f85:	.byte 0x8e
data_00000f86:	.byte 0x1e
data_00000f87:	.byte 0xca
data_00000f88:	.byte 0x2c
data_00000f89:	.byte 0xfe
data_00000f8a:	.byte 0x06
data_00000f8b:	.byte 0x81
data_00000f8c:	.byte 0x09
data_00000f8d:	.byte 0xb4
data_00000f8e:	.byte 0x19
data_00000f8f:	.byte 0xcd
data_00000f90:	.byte 0x21
data_00000f91:	.byte 0x04
data_00000f92:	.byte 0x41
data_00000f93:	.byte 0xa2
data_00000f94:	.byte 0x13
data_00000f95:	.byte 0x0a
data_00000f96:	.byte 0xbb
data_00000f97:	.byte 0x05
data_00000f98:	.byte 0x0a
data_00000f99:	.byte 0x88
data_00000f9a:	.byte 0x07
data_00000f9b:	.byte 0x8b
data_00000f9c:	.byte 0xd3
data_00000f9d:	.byte 0x33
data_00000f9e:	.byte 0xc9
data_00000f9f:	.byte 0xb4
data_00000fa0:	.byte 0x3c
data_00000fa1:	.byte 0xcd
data_00000fa2:	.byte 0x21
data_00000fa3:	.byte 0x72
data_00000fa4:	.byte 0xd5
data_00000fa5:	.byte 0x8b
data_00000fa6:	.byte 0xd8
data_00000fa7:	.byte 0xb4
data_00000fa8:	.byte 0x3e
data_00000fa9:	.byte 0xcd
data_00000faa:	.byte 0x21
data_00000fab:	.byte 0xba
data_00000fac:	.byte 0x13
data_00000fad:	.byte 0x0a
data_00000fae:	.byte 0xb4
data_00000faf:	.byte 0x3c
data_00000fb0:	.byte 0xcd
data_00000fb1:	.byte 0x21
data_00000fb2:	.byte 0x72
data_00000fb3:	.byte 0xc6
data_00000fb4:	.byte 0x8b
data_00000fb5:	.byte 0xd8
data_00000fb6:	.byte 0xb4
data_00000fb7:	.byte 0x3e
data_00000fb8:	.byte 0xcd
data_00000fb9:	.byte 0x21
data_00000fba:	.byte 0xe8
data_00000fbb:	.byte 0x01
data_00000fbc:	.byte 0x07
data_00000fbd:	.byte 0xc6
data_00000fbe:	.byte 0x06
data_00000fbf:	.byte 0x77
data_00000fc0:	.byte 0x08
data_00000fc1:	.byte 0x00
data_00000fc2:	.byte 0x8b
data_00000fc3:	.byte 0x36
data_00000fc4:	.byte 0x82
data_00000fc5:	.byte 0x09
data_00000fc6:	.byte 0x83
data_00000fc7:	.byte 0x3e
data_00000fc8:	.byte 0x7c
data_00000fc9:	.byte 0x08
data_00000fca:	.byte 0xff
data_00000fcb:	.byte 0x75
data_00000fcc:	.byte 0x06
data_00000fcd:	.byte 0xc7
data_00000fce:	.byte 0x06
data_00000fcf:	.byte 0x7c
data_00000fd0:	.byte 0x08
data_00000fd1:	.byte 0x00
data_00000fd2:	.byte 0xf0
data_00000fd3:	.byte 0xeb
data_00000fd4:	.byte 0x23
data_00000fd5:	.byte 0xc6
data_00000fd6:	.byte 0x06
data_00000fd7:	.byte 0x77
data_00000fd8:	.byte 0x08
data_00000fd9:	.byte 0x00
data_00000fda:	.byte 0x8b
data_00000fdb:	.byte 0x36
data_00000fdc:	.byte 0x82
data_00000fdd:	.byte 0x09
data_00000fde:	.byte 0xac
data_00000fdf:	.byte 0x3c
data_00000fe0:	.byte 0x7c
data_00000fe1:	.byte 0x75
data_00000fe2:	.byte 0x77
data_00000fe3:	.byte 0x8b
data_00000fe4:	.byte 0x16
data_00000fe5:	.byte 0x21
data_00000fe6:	.byte 0x0a
data_00000fe7:	.byte 0xb8
data_00000fe8:	.byte 0x00
data_00000fe9:	.byte 0x3d
data_00000fea:	.byte 0xcd
data_00000feb:	.byte 0x21
data_00000fec:	.byte 0x72
data_00000fed:	.byte 0x8c
data_00000fee:	.byte 0x8b
data_00000fef:	.byte 0xd8
data_00000ff0:	.byte 0xb0
data_00000ff1:	.byte 0xff
data_00000ff2:	.byte 0x86
data_00000ff3:	.byte 0x47
data_00000ff4:	.byte 0x18
data_00000ff5:	.byte 0xa2
data_00000ff6:	.byte 0x18
data_00000ff7:	.byte 0x00
data_00000ff8:	.byte 0xbf
data_00000ff9:	.byte 0xb5
data_00000ffa:	.byte 0x2b
data_00000ffb:	.byte 0x33
data_00000ffc:	.byte 0xc9
data_00000ffd:	.byte 0x80
data_00000ffe:	.byte 0x3c
data_00000fff:	.byte 0x0d
data_00001000:	.byte 0x75
data_00001001:	.byte 0x03
data_00001002:	.byte 0xe9
data_00001003:	.byte 0x70
data_00001004:	.byte 0xff
data_00001005:	.byte 0x80
data_00001006:	.byte 0x3c
data_00001007:	.byte 0x7c
data_00001008:	.byte 0x74
data_00001009:	.byte 0xf8
data_0000100a:	.byte 0xac
data_0000100b:	.byte 0xaa
data_0000100c:	.byte 0x3c
data_0000100d:	.byte 0x0d
data_0000100e:	.byte 0x74
data_0000100f:	.byte 0x38
data_00001010:	.byte 0x41
data_00001011:	.byte 0x3c
data_00001012:	.byte 0x7c
data_00001013:	.byte 0x75
data_00001014:	.byte 0xf5
data_00001015:	.byte 0x26
data_00001016:	.byte 0xc6
data_00001017:	.byte 0x45
data_00001018:	.byte 0xff
data_00001019:	.byte 0x0d
data_0000101a:	.byte 0x49
data_0000101b:	.byte 0x36
data_0000101c:	.byte 0x88
data_0000101d:	.byte 0x0e
data_0000101e:	.byte 0xb4
data_0000101f:	.byte 0x2b
data_00001020:	.byte 0x4e
data_00001021:	.byte 0x89
data_00001022:	.byte 0x36
data_00001023:	.byte 0x82
data_00001024:	.byte 0x09
data_00001025:	.byte 0x8b
data_00001026:	.byte 0x16
data_00001027:	.byte 0x23
data_00001028:	.byte 0x0a
data_00001029:	.byte 0x51
data_0000102a:	.byte 0x33
data_0000102b:	.byte 0xc9
data_0000102c:	.byte 0xb8
data_0000102d:	.byte 0x00
data_0000102e:	.byte 0x3c
data_0000102f:	.byte 0xcd
data_00001030:	.byte 0x21
data_00001031:	.byte 0x59
data_00001032:	.byte 0x72
data_00001033:	.byte 0xb8
data_00001034:	.byte 0x8b
data_00001035:	.byte 0xd8
data_00001036:	.byte 0xb0
data_00001037:	.byte 0xff
data_00001038:	.byte 0x86
data_00001039:	.byte 0x47
data_0000103a:	.byte 0x18
data_0000103b:	.byte 0xa2
data_0000103c:	.byte 0x19
data_0000103d:	.byte 0x00
data_0000103e:	.byte 0x87
data_0000103f:	.byte 0x16
data_00001040:	.byte 0x21
data_00001041:	.byte 0x0a
data_00001042:	.byte 0x89
data_00001043:	.byte 0x16
data_00001044:	.byte 0x23
data_00001045:	.byte 0x0a
data_00001046:	.byte 0xeb
data_00001047:	.byte 0x0d
data_00001048:	.byte 0x36
data_00001049:	.byte 0x88
data_0000104a:	.byte 0x0e
data_0000104b:	.byte 0xb4
data_0000104c:	.byte 0x2b
data_0000104d:	.byte 0x4e
data_0000104e:	.byte 0x89
data_0000104f:	.byte 0x36
data_00001050:	.byte 0x82
data_00001051:	.byte 0x09
data_00001052:	.byte 0xe8
data_00001053:	.byte 0x8d
data_00001054:	.byte 0x06
data_00001055:	.byte 0x0e
data_00001056:	.byte 0x1f
data_00001057:	.byte 0xe9
data_00001058:	.byte 0x0c
data_00001059:	.byte 0xfb
data_0000105a:	.byte 0xe8
data_0000105b:	.byte 0xfd
data_0000105c:	.byte 0xfe
data_0000105d:	.byte 0x81
data_0000105e:	.byte 0x3e
data_0000105f:	.byte 0x7c
data_00001060:	.byte 0x08
data_00001061:	.byte 0x00
data_00001062:	.byte 0xf0
data_00001063:	.byte 0x75
data_00001064:	.byte 0x06
data_00001065:	.byte 0xc7
data_00001066:	.byte 0x06
data_00001067:	.byte 0x7c
data_00001068:	.byte 0x08
data_00001069:	.byte 0xff
data_0000106a:	.byte 0xff
data_0000106b:	.byte 0xe9
data_0000106c:	.byte 0x96
data_0000106d:	.byte 0xf8
data_0000106e:	.byte 0xe8
data_0000106f:	.byte 0x76
data_00001070:	.byte 0x00
data_00001071:	.byte 0xe8
data_00001072:	.byte 0x04
data_00001073:	.byte 0x01
data_00001074:	.byte 0x56
data_00001075:	.byte 0xe8
data_00001076:	.byte 0xf2
data_00001077:	.byte 0x00
data_00001078:	.byte 0x5e
data_00001079:	.byte 0x75
data_0000107a:	.byte 0x01
data_0000107b:	.byte 0xc3
data_0000107c:	.byte 0xe8
data_0000107d:	.byte 0xda
data_0000107e:	.byte 0x00
data_0000107f:	.byte 0xe8
data_00001080:	.byte 0xe8
data_00001081:	.byte 0x00
data_00001082:	.byte 0xeb
data_00001083:	.byte 0x36
data_00001084:	.byte 0xe8
data_00001085:	.byte 0xe3
data_00001086:	.byte 0x00
data_00001087:	.byte 0x74
data_00001088:	.byte 0x3b
data_00001089:	.byte 0x33
data_0000108a:	.byte 0xdb
data_0000108b:	.byte 0x56
data_0000108c:	.byte 0xac
data_0000108d:	.byte 0x3c
data_0000108e:	.byte 0x0d
data_0000108f:	.byte 0x74
data_00001090:	.byte 0x0f
data_00001091:	.byte 0x3c
data_00001092:	.byte 0x3d
data_00001093:	.byte 0x75
data_00001094:	.byte 0xf7
data_00001095:	.byte 0xfe
data_00001096:	.byte 0xc3
data_00001097:	.byte 0x80
data_00001098:	.byte 0x3c
data_00001099:	.byte 0x0d
data_0000109a:	.byte 0x75
data_0000109b:	.byte 0xf0
data_0000109c:	.byte 0xfe
data_0000109d:	.byte 0xc7
data_0000109e:	.byte 0xeb
data_0000109f:	.byte 0xec
data_000010a0:	.byte 0x5e
data_000010a1:	.byte 0xfe
data_000010a2:	.byte 0xcb
data_000010a3:	.byte 0x74
data_000010a4:	.byte 0x06
data_000010a5:	.byte 0xba
data_000010a6:	.byte 0xe3
data_000010a7:	.byte 0x28
data_000010a8:	.byte 0xe9
data_000010a9:	.byte 0x3d
data_000010aa:	.byte 0xfe
data_000010ab:	.byte 0x53
data_000010ac:	.byte 0xe8
data_000010ad:	.byte 0x3b
data_000010ae:	.byte 0x00
data_000010af:	.byte 0x5b
data_000010b0:	.byte 0xfe
data_000010b1:	.byte 0xcf
data_000010b2:	.byte 0x74
data_000010b3:	.byte 0xc7
data_000010b4:	.byte 0xe8
data_000010b5:	.byte 0xc1
data_000010b6:	.byte 0x00
data_000010b7:	.byte 0xe8
data_000010b8:	.byte 0x9f
data_000010b9:	.byte 0x00
data_000010ba:	.byte 0xac
data_000010bb:	.byte 0x3c
data_000010bc:	.byte 0x0d
data_000010bd:	.byte 0x74
data_000010be:	.byte 0xbc
data_000010bf:	.byte 0xe8
data_000010c0:	.byte 0xe7
data_000010c1:	.byte 0x00
data_000010c2:	.byte 0xeb
data_000010c3:	.byte 0xf6
data_000010c4:	.byte 0x8e
data_000010c5:	.byte 0x1e
data_000010c6:	.byte 0xca
data_000010c7:	.byte 0x2c
data_000010c8:	.byte 0x8e
data_000010c9:	.byte 0x1e
data_000010ca:	.byte 0x25
data_000010cb:	.byte 0x0a
data_000010cc:	.byte 0x33
data_000010cd:	.byte 0xf6
data_000010ce:	.byte 0x80
data_000010cf:	.byte 0x3c
data_000010d0:	.byte 0x00
data_000010d1:	.byte 0x74
data_000010d2:	.byte 0xa8
data_000010d3:	.byte 0x8b
data_000010d4:	.byte 0xd6
data_000010d5:	.byte 0xe8
data_000010d6:	.byte 0x33
data_000010d7:	.byte 0x11
data_000010d8:	.byte 0xe8
data_000010d9:	.byte 0x08
data_000010da:	.byte 0x08
data_000010db:	.byte 0xac
data_000010dc:	.byte 0x0a
data_000010dd:	.byte 0xc0
data_000010de:	.byte 0x75
data_000010df:	.byte 0xfb
data_000010e0:	.byte 0xeb
data_000010e1:	.byte 0xec
data_000010e2:	.byte 0xbe
data_000010e3:	.byte 0x95
data_000010e4:	.byte 0x28
data_000010e5:	.byte 0xeb
data_000010e6:	.byte 0x03
data_000010e7:	.byte 0xbe
data_000010e8:	.byte 0x9a
data_000010e9:	.byte 0x28
data_000010ea:	.byte 0x56
data_000010eb:	.byte 0x1e
data_000010ec:	.byte 0xe8
data_000010ed:	.byte 0x25
code_000010ee:	add %dh,0x10(%bp,%si)
		mov %di,%si
		call 0x1191
		xchg %si,%di
		call 0x11e8
		sub %si,%cx
		push %es
		pop %ds
		rep movsb
		pop %ds
		pop %si
		ret
data_00001104:	.byte 0xbe
data_00001105:	.byte 0x95
data_00001106:	.byte 0x28
data_00001107:	.byte 0xeb
data_00001108:	.byte 0x03
data_00001109:	.byte 0xbe
data_0000110a:	.byte 0x9a
data_0000110b:	.byte 0x28
data_0000110c:	.byte 0xe8
data_0000110d:	.byte 0x05
data_0000110e:	.byte 0x00
data_0000110f:	.byte 0x72
data_00001110:	.byte 0xf2
data_00001111:	.byte 0xeb
data_00001112:	.byte 0x7a
data_00001113:	.byte 0x90
data_00001114:	.byte 0xfc
data_00001115:	.byte 0xe8
data_00001116:	.byte 0x2d
data_00001117:	.byte 0x00
data_00001118:	.byte 0x8e
data_00001119:	.byte 0x06
data_0000111a:	.byte 0xca
data_0000111b:	.byte 0x2c
data_0000111c:	.byte 0x26
data_0000111d:	.byte 0x8e
data_0000111e:	.byte 0x06
data_0000111f:	.byte 0x25
data_00001120:	.byte 0x0a
data_00001121:	.byte 0x33
data_00001122:	.byte 0xff
data_00001123:	.byte 0x51
data_00001124:	.byte 0x56
data_00001125:	.byte 0x57
data_00001126:	.byte 0xac
data_00001127:	.byte 0xe8
data_00001128:	.byte 0x6f
data_00001129:	.byte 0x00
data_0000112a:	.byte 0x47
data_0000112b:	.byte 0x26
data_0000112c:	.byte 0x3a
data_0000112d:	.byte 0x45
data_0000112e:	.byte 0xff
data_0000112f:	.byte 0x75
data_00001130:	.byte 0x02
data_00001131:	.byte 0xe2
data_00001132:	.byte 0xf3
data_00001133:	.byte 0x5f
data_00001134:	.byte 0x5e
data_00001135:	.byte 0x59
data_00001136:	.byte 0x74
data_00001137:	.byte 0xcb
data_00001138:	.byte 0x51
data_00001139:	.byte 0xe8
data_0000113a:	.byte 0x55
data_0000113b:	.byte 0x00
data_0000113c:	.byte 0x59
data_0000113d:	.byte 0x26
data_0000113e:	.byte 0x80
data_0000113f:	.byte 0x3d
data_00001140:	.byte 0x00
data_00001141:	.byte 0x75
data_00001142:	.byte 0xe0
data_00001143:	.byte 0xf9
data_00001144:	.byte 0xc3
data_00001145:	.byte 0x1e
data_00001146:	.byte 0x07
data_00001147:	.byte 0x8b
data_00001148:	.byte 0xfe
data_00001149:	.byte 0x57
data_0000114a:	.byte 0xe8
data_0000114b:	.byte 0x40
data_0000114c:	.byte 0x00
data_0000114d:	.byte 0xeb
data_0000114e:	.byte 0x04
data_0000114f:	.byte 0x57
data_00001150:	.byte 0xe8
data_00001151:	.byte 0x3e
data_00001152:	.byte 0x00
data_00001153:	.byte 0x59
data_00001154:	.byte 0x2b
data_00001155:	.byte 0xf9
data_00001156:	.byte 0x87
data_00001157:	.byte 0xf9
data_00001158:	.byte 0xc3
data_00001159:	.byte 0x80
data_0000115a:	.byte 0x3c
data_0000115b:	.byte 0x0d
data_0000115c:	.byte 0x74
data_0000115d:	.byte 0xfa
data_0000115e:	.byte 0xac
data_0000115f:	.byte 0xe8
data_00001160:	.byte 0x37
data_00001161:	.byte 0x00
data_00001162:	.byte 0xe8
data_00001163:	.byte 0x44
data_00001164:	.byte 0x00
data_00001165:	.byte 0x3c
data_00001166:	.byte 0x3d
data_00001167:	.byte 0x75
data_00001168:	.byte 0xf0
data_00001169:	.byte 0xc3
data_0000116a:	.byte 0xbe
data_0000116b:	.byte 0x80
data_0000116c:	.byte 0x00
data_0000116d:	.byte 0xac
data_0000116e:	.byte 0x0a
data_0000116f:	.byte 0xc0
data_00001170:	.byte 0x74
data_00001171:	.byte 0xf7
data_00001172:	.byte 0xe8
data_00001173:	.byte 0x97
data_00001174:	.byte 0x0e
data_00001175:	.byte 0x3c
data_00001176:	.byte 0x0d
data_00001177:	.byte 0xc3
data_00001178:	.byte 0x8e
data_00001179:	.byte 0x06
data_0000117a:	.byte 0xca
data_0000117b:	.byte 0x2c
data_0000117c:	.byte 0x26
data_0000117d:	.byte 0x8e
data_0000117e:	.byte 0x06
data_0000117f:	.byte 0x25
data_00001180:	.byte 0x0a
data_00001181:	.byte 0x33
data_00001182:	.byte 0xff
data_00001183:	.byte 0xe8
data_00001184:	.byte 0x0b
data_00001185:	.byte 0x00
data_00001186:	.byte 0x26
data_00001187:	.byte 0x80
data_00001188:	.byte 0x3d
data_00001189:	.byte 0x00
data_0000118a:	.byte 0x75
data_0000118b:	.byte 0xf7
data_0000118c:	.byte 0xc3
data_0000118d:	.byte 0xb0
data_0000118e:	.byte 0x3d
data_0000118f:	.byte 0xeb
data_00001190:	.byte 0x02
code_00001191:	xor %al,%al
		mov $0x100,%cx
		repne scasb
		ret
data_00001199:	.byte 0x3c
data_0000119a:	.byte 0x61
data_0000119b:	.byte 0x72
data_0000119c:	.byte 0x06
data_0000119d:	.byte 0x3c
data_0000119e:	.byte 0x7a
data_0000119f:	.byte 0x77
data_000011a0:	.byte 0x02
data_000011a1:	.byte 0x2c
data_000011a2:	.byte 0x20
data_000011a3:	.byte 0x2e
data_000011a4:	.byte 0xff
data_000011a5:	.byte 0x1e
data_000011a6:	.byte 0x57
data_000011a7:	.byte 0x2f
data_000011a8:	.byte 0xc3
data_000011a9:	.byte 0x51
data_000011aa:	.byte 0x53
data_000011ab:	.byte 0xe8
data_000011ac:	.byte 0x3a
data_000011ad:	.byte 0x00
data_000011ae:	.byte 0x8b
data_000011af:	.byte 0xd9
data_000011b0:	.byte 0x83
data_000011b1:	.byte 0xeb
data_000011b2:	.byte 0x02
data_000011b3:	.byte 0x3b
data_000011b4:	.byte 0xfb
data_000011b5:	.byte 0x72
data_000011b6:	.byte 0x28
data_000011b7:	.byte 0x50
data_000011b8:	.byte 0x51
data_000011b9:	.byte 0x53
data_000011ba:	.byte 0xe8
data_000011bb:	.byte 0xdd
data_000011bc:	.byte 0x0b
data_000011bd:	.byte 0x5b
data_000011be:	.byte 0x83
data_000011bf:	.byte 0xc3
data_000011c0:	.byte 0x02
data_000011c1:	.byte 0xb1
data_000011c2:	.byte 0x04
data_000011c3:	.byte 0xd3
data_000011c4:	.byte 0xeb
data_000011c5:	.byte 0x43
data_000011c6:	.byte 0xb4
data_000011c7:	.byte 0x4a
data_000011c8:	.byte 0xcd
data_000011c9:	.byte 0x21
data_000011ca:	.byte 0x9c
data_000011cb:	.byte 0x06
data_000011cc:	.byte 0x8e
data_000011cd:	.byte 0x06
data_000011ce:	.byte 0xca
data_000011cf:	.byte 0x2c
data_000011d0:	.byte 0xe8
data_000011d1:	.byte 0xd2
data_000011d2:	.byte 0x0b
data_000011d3:	.byte 0x07
data_000011d4:	.byte 0x9d
data_000011d5:	.byte 0x59
data_000011d6:	.byte 0x58
data_000011d7:	.byte 0x73
data_000011d8:	.byte 0x06
data_000011d9:	.byte 0xba
data_000011da:	.byte 0x32
data_000011db:	.byte 0x26
data_000011dc:	.byte 0xe9
data_000011dd:	.byte 0x09
data_000011de:	.byte 0xfd
data_000011df:	.byte 0xaa
data_000011e0:	.byte 0x26
data_000011e1:	.byte 0xc7
data_000011e2:	.byte 0x05
data_000011e3:	.byte 0x00
data_000011e4:	.byte 0x00
data_000011e5:	.byte 0x5b
data_000011e6:	.byte 0x59
data_000011e7:	.byte 0xc3
code_000011e8:	push %es
		push %ax
		mov %es,%ax
		dec %ax
		mov %ax,%es
		mov %es:0x3,%ax
		mov $0x4,%cl
		shl %cl,%ax
		mov %ax,%cx
		pop %ax
		pop %es
		ret
data_000011fc:	.byte 0xb4
data_000011fd:	.byte 0x19
data_000011fe:	.byte 0xcd
data_000011ff:	.byte 0x21
data_00001200:	.byte 0x04
data_00001201:	.byte 0x41
data_00001202:	.byte 0xe9
data_00001203:	.byte 0xce
data_00001204:	.byte 0x0f
data_00001205:	.byte 0xe8
data_00001206:	.byte 0x09
data_00001207:	.byte 0x00
data_00001208:	.byte 0xe8
data_00001209:	.byte 0xd8
data_0000120a:	.byte 0x06
data_0000120b:	.byte 0xc3
data_0000120c:	.byte 0xc6
data_0000120d:	.byte 0x06
data_0000120e:	.byte 0x5c
data_0000120f:	.byte 0x00
data_00001210:	.byte 0x00
data_00001211:	.byte 0x8a
data_00001212:	.byte 0x16
data_00001213:	.byte 0x5c
data_00001214:	.byte 0x00
data_00001215:	.byte 0x8a
data_00001216:	.byte 0xc2
data_00001217:	.byte 0x04
data_00001218:	.byte 0x40
data_00001219:	.byte 0x3c
data_0000121a:	.byte 0x40
data_0000121b:	.byte 0x75
data_0000121c:	.byte 0x06
data_0000121d:	.byte 0x02
data_0000121e:	.byte 0x06
data_0000121f:	.byte 0xda
data_00001220:	.byte 0x2c
data_00001221:	.byte 0xfe
data_00001222:	.byte 0xc0
data_00001223:	.byte 0x50
data_00001224:	.byte 0xbe
data_00001225:	.byte 0xbf
data_00001226:	.byte 0x2d
data_00001227:	.byte 0xb4
data_00001228:	.byte 0x47
data_00001229:	.byte 0xcd
data_0000122a:	.byte 0x21
data_0000122b:	.byte 0x73
data_0000122c:	.byte 0x05
data_0000122d:	.byte 0x0e
data_0000122e:	.byte 0x1f
data_0000122f:	.byte 0xe9
data_00001230:	.byte 0x1e
data_00001231:	.byte 0xfa
data_00001232:	.byte 0xbf
data_00001233:	.byte 0xbc
data_00001234:	.byte 0x2d
data_00001235:	.byte 0x8b
data_00001236:	.byte 0xd7
data_00001237:	.byte 0x58
data_00001238:	.byte 0xb4
data_00001239:	.byte 0x3a
data_0000123a:	.byte 0xab
data_0000123b:	.byte 0xa0
data_0000123c:	.byte 0xcf
data_0000123d:	.byte 0x2c
data_0000123e:	.byte 0xaa
data_0000123f:	.byte 0xe9
data_00001240:	.byte 0xc9
data_00001241:	.byte 0x0f
data_00001242:	.byte 0x06
data_00001243:	.byte 0x8e
data_00001244:	.byte 0x06
data_00001245:	.byte 0xca
data_00001246:	.byte 0x2c
data_00001247:	.byte 0x26
data_00001248:	.byte 0xa1
data_00001249:	.byte 0x35
data_0000124a:	.byte 0x08
data_0000124b:	.byte 0x26
data_0000124c:	.byte 0xa3
data_0000124d:	.byte 0x16
data_0000124e:	.byte 0x00
data_0000124f:	.byte 0x07
data_00001250:	.byte 0x8e
data_00001251:	.byte 0x06
data_00001252:	.byte 0xcc
data_00001253:	.byte 0x2c
data_00001254:	.byte 0xb4
data_00001255:	.byte 0x49
data_00001256:	.byte 0xcd
data_00001257:	.byte 0x21
data_00001258:	.byte 0xb8
data_00001259:	.byte 0x00
data_0000125a:	.byte 0x4c
data_0000125b:	.byte 0xcd
data_0000125c:	.byte 0x21
data_0000125d:	.byte 0xe8
data_0000125e:	.byte 0x36
data_0000125f:	.byte 0x0e
data_00001260:	.byte 0xb8
data_00001261:	.byte 0x02
data_00001262:	.byte 0x3d
data_00001263:	.byte 0xcd
data_00001264:	.byte 0x21
data_00001265:	.byte 0x72
data_00001266:	.byte 0x10
data_00001267:	.byte 0x8b
data_00001268:	.byte 0xd8
data_00001269:	.byte 0xb8
data_0000126a:	.byte 0x00
data_0000126b:	.byte 0x44
data_0000126c:	.byte 0xcd
data_0000126d:	.byte 0x21
data_0000126e:	.byte 0xf6
data_0000126f:	.byte 0xc2
data_00001270:	.byte 0x80
data_00001271:	.byte 0x75
data_00001272:	.byte 0x0d
data_00001273:	.byte 0xb4
data_00001274:	.byte 0x3e
data_00001275:	.byte 0xcd
data_00001276:	.byte 0x21
data_00001277:	.byte 0xba
data_00001278:	.byte 0xc0
data_00001279:	.byte 0x28
data_0000127a:	.byte 0xe8
data_0000127b:	.byte 0x89
data_0000127c:	.byte 0x0f
data_0000127d:	.byte 0xeb
data_0000127e:	.byte 0x29
data_0000127f:	.byte 0x90
data_00001280:	.byte 0x32
data_00001281:	.byte 0xf6
data_00001282:	.byte 0x80
data_00001283:	.byte 0xca
data_00001284:	.byte 0x03
data_00001285:	.byte 0xb8
data_00001286:	.byte 0x01
data_00001287:	.byte 0x44
data_00001288:	.byte 0xcd
data_00001289:	.byte 0x21
data_0000128a:	.byte 0x53
data_0000128b:	.byte 0xb9
data_0000128c:	.byte 0x03
data_0000128d:	.byte 0x00
data_0000128e:	.byte 0x33
data_0000128f:	.byte 0xdb
data_00001290:	.byte 0xb4
data_00001291:	.byte 0x3e
data_00001292:	.byte 0xcd
data_00001293:	.byte 0x21
data_00001294:	.byte 0x43
data_00001295:	.byte 0xe2
data_00001296:	.byte 0xf9
data_00001297:	.byte 0x5b
data_00001298:	.byte 0xb4
data_00001299:	.byte 0x45
data_0000129a:	.byte 0xcd
data_0000129b:	.byte 0x21
data_0000129c:	.byte 0xb4
data_0000129d:	.byte 0x45
data_0000129e:	.byte 0xcd
data_0000129f:	.byte 0x21
data_000012a0:	.byte 0xb4
data_000012a1:	.byte 0x45
data_000012a2:	.byte 0xcd
data_000012a3:	.byte 0x21
data_000012a4:	.byte 0xb4
data_000012a5:	.byte 0x3e
data_000012a6:	.byte 0xcd
data_000012a7:	.byte 0x21
data_000012a8:	.byte 0x8e
data_000012a9:	.byte 0x1e
data_000012aa:	.byte 0xca
data_000012ab:	.byte 0x2c
data_000012ac:	.byte 0x1e
data_000012ad:	.byte 0xa1
data_000012ae:	.byte 0x18
data_000012af:	.byte 0x00
data_000012b0:	.byte 0xa3
data_000012b1:	.byte 0x78
data_000012b2:	.byte 0x08
data_000012b3:	.byte 0xb8
data_000012b4:	.byte 0xd0
data_000012b5:	.byte 0x02
data_000012b6:	.byte 0x50
data_000012b7:	.byte 0xcb
data_000012b8:	.byte 0xc6
data_000012b9:	.byte 0x06
data_000012ba:	.byte 0x80
data_000012bb:	.byte 0x08
data_000012bc:	.byte 0x00
data_000012bd:	.byte 0x81
data_000012be:	.byte 0x3e
data_000012bf:	.byte 0x7c
data_000012c0:	.byte 0x08
data_000012c1:	.byte 0x00
data_000012c2:	.byte 0xff
data_000012c3:	.byte 0x75
data_000012c4:	.byte 0x06
data_000012c5:	.byte 0xc7
data_000012c6:	.byte 0x06
data_000012c7:	.byte 0x7c
data_000012c8:	.byte 0x08
data_000012c9:	.byte 0xff
data_000012ca:	.byte 0xff
data_000012cb:	.byte 0xe9
data_000012cc:	.byte 0x36
data_000012cd:	.byte 0xf6
data_000012ce:	.byte 0x80
data_000012cf:	.byte 0x3e
data_000012d0:	.byte 0x07
data_000012d1:	.byte 0x09
data_000012d2:	.byte 0xff
data_000012d3:	.byte 0x74
data_000012d4:	.byte 0x4f
data_000012d5:	.byte 0xba
data_000012d6:	.byte 0xbc
data_000012d7:	.byte 0x2d
data_000012d8:	.byte 0x1e
data_000012d9:	.byte 0x0e
data_000012da:	.byte 0x1f
data_000012db:	.byte 0xb4
data_000012dc:	.byte 0x1a
data_000012dd:	.byte 0xcd
data_000012de:	.byte 0x21
data_000012df:	.byte 0x1f
data_000012e0:	.byte 0xba
data_000012e1:	.byte 0x08
data_000012e2:	.byte 0x09
data_000012e3:	.byte 0xb4
data_000012e4:	.byte 0x12
data_000012e5:	.byte 0x80
data_000012e6:	.byte 0x3e
data_000012e7:	.byte 0x07
data_000012e8:	.byte 0x09
data_000012e9:	.byte 0x00
data_000012ea:	.byte 0x74
data_000012eb:	.byte 0x07
data_000012ec:	.byte 0xb4
data_000012ed:	.byte 0x11
data_000012ee:	.byte 0xc6
data_000012ef:	.byte 0x06
data_000012f0:	.byte 0x07
data_000012f1:	.byte 0x09
data_000012f2:	.byte 0x00
data_000012f3:	.byte 0xcd
data_000012f4:	.byte 0x21
data_000012f5:	.byte 0x0a
data_000012f6:	.byte 0xc0
data_000012f7:	.byte 0x75
data_000012f8:	.byte 0xbf
data_000012f9:	.byte 0x1e
data_000012fa:	.byte 0x07
data_000012fb:	.byte 0x0e
data_000012fc:	.byte 0x1f
data_000012fd:	.byte 0xbe
data_000012fe:	.byte 0xbc
data_000012ff:	.byte 0x2d
data_00001300:	.byte 0xbf
data_00001301:	.byte 0x82
data_00001302:	.byte 0x08
data_00001303:	.byte 0x26
data_00001304:	.byte 0x89
data_00001305:	.byte 0x3e
data_00001306:	.byte 0x05
data_00001307:	.byte 0x09
data_00001308:	.byte 0xac
data_00001309:	.byte 0x04
data_0000130a:	.byte 0x40
data_0000130b:	.byte 0x3c
data_0000130c:	.byte 0x40
data_0000130d:	.byte 0x74
data_0000130e:	.byte 0x0b
data_0000130f:	.byte 0x26
data_00001310:	.byte 0x80
data_00001311:	.byte 0x3e
data_00001312:	.byte 0x81
data_00001313:	.byte 0x08
data_00001314:	.byte 0x00
data_00001315:	.byte 0x74
data_00001316:	.byte 0x03
data_00001317:	.byte 0xb4
data_00001318:	.byte 0x3a
data_00001319:	.byte 0xab
data_0000131a:	.byte 0xe8
data_0000131b:	.byte 0x5f
data_0000131c:	.byte 0x0e
data_0000131d:	.byte 0x26
data_0000131e:	.byte 0xc6
data_0000131f:	.byte 0x45
data_00001320:	.byte 0xff
data_00001321:	.byte 0x0d
data_00001322:	.byte 0x06
data_00001323:	.byte 0x1f
data_00001324:	.byte 0x0e
data_00001325:	.byte 0x07
data_00001326:	.byte 0x8b
data_00001327:	.byte 0x1e
data_00001328:	.byte 0x05
data_00001329:	.byte 0x09
data_0000132a:	.byte 0x80
data_0000132b:	.byte 0x3f
data_0000132c:	.byte 0x00
data_0000132d:	.byte 0x74
data_0000132e:	.byte 0x89
data_0000132f:	.byte 0x8b
data_00001330:	.byte 0xf3
data_00001331:	.byte 0xac
data_00001332:	.byte 0x3c
data_00001333:	.byte 0x0d
data_00001334:	.byte 0x75
data_00001335:	.byte 0xfb
data_00001336:	.byte 0x8b
data_00001337:	.byte 0xd6
data_00001338:	.byte 0xbe
data_00001339:	.byte 0xaa
data_0000133a:	.byte 0x08
data_0000133b:	.byte 0xbf
data_0000133c:	.byte 0xb5
data_0000133d:	.byte 0x2b
data_0000133e:	.byte 0x33
data_0000133f:	.byte 0xc9
data_00001340:	.byte 0xac
data_00001341:	.byte 0x3c
data_00001342:	.byte 0x25
data_00001343:	.byte 0x75
data_00001344:	.byte 0x18
data_00001345:	.byte 0x8a
data_00001346:	.byte 0x26
data_00001347:	.byte 0x04
data_00001348:	.byte 0x09
data_00001349:	.byte 0x3a
data_0000134a:	.byte 0x24
data_0000134b:	.byte 0x75
data_0000134c:	.byte 0x10
data_0000134d:	.byte 0x46
data_0000134e:	.byte 0x56
data_0000134f:	.byte 0x8b
data_00001350:	.byte 0xf3
data_00001351:	.byte 0xac
data_00001352:	.byte 0x3c
data_00001353:	.byte 0x0d
data_00001354:	.byte 0x74
data_00001355:	.byte 0x04
data_00001356:	.byte 0x41
data_00001357:	.byte 0xaa
data_00001358:	.byte 0xeb
data_00001359:	.byte 0xf7
data_0000135a:	.byte 0x5e
data_0000135b:	.byte 0xeb
data_0000135c:	.byte 0xe3
data_0000135d:	.byte 0xaa
data_0000135e:	.byte 0x41
data_0000135f:	.byte 0x3c
data_00001360:	.byte 0x0d
data_00001361:	.byte 0x75
data_00001362:	.byte 0xdd
data_00001363:	.byte 0x49
data_00001364:	.byte 0x2e
data_00001365:	.byte 0x88
data_00001366:	.byte 0x0e
data_00001367:	.byte 0xb4
data_00001368:	.byte 0x2b
data_00001369:	.byte 0x89
data_0000136a:	.byte 0x16
data_0000136b:	.byte 0x05
data_0000136c:	.byte 0x09
data_0000136d:	.byte 0xf6
data_0000136e:	.byte 0x06
data_0000136f:	.byte 0x77
data_00001370:	.byte 0x08
data_00001371:	.byte 0xff
data_00001372:	.byte 0x0e
data_00001373:	.byte 0x1f
data_00001374:	.byte 0x74
data_00001375:	.byte 0x13
data_00001376:	.byte 0x26
data_00001377:	.byte 0xc6
data_00001378:	.byte 0x45
data_00001379:	.byte 0xff
data_0000137a:	.byte 0x24
data_0000137b:	.byte 0xba
data_0000137c:	.byte 0xb5
data_0000137d:	.byte 0x2b
data_0000137e:	.byte 0xe8
data_0000137f:	.byte 0x85
data_00001380:	.byte 0x00
data_00001381:	.byte 0x00
data_00001382:	.byte 0x00
data_00001383:	.byte 0x00
data_00001384:	.byte 0x00
data_00001385:	.byte 0x00
data_00001386:	.byte 0x00
data_00001387:	.byte 0x00
data_00001388:	.byte 0x00
data_00001389:	.byte 0x00
data_0000138a:	.byte 0x00
data_0000138b:	.byte 0x00
data_0000138c:	.byte 0x00
data_0000138d:	.byte 0x00
data_0000138e:	.byte 0x00
data_0000138f:	.byte 0x00
data_00001390:	.byte 0x00
data_00001391:	.byte 0x00
data_00001392:	.byte 0x00
data_00001393:	.byte 0x00
data_00001394:	.byte 0x00
data_00001395:	.byte 0x00
data_00001396:	.byte 0x00
data_00001397:	.byte 0x00
data_00001398:	.byte 0x00
data_00001399:	.byte 0x00
data_0000139a:	.byte 0x00
data_0000139b:	.byte 0x00
data_0000139c:	.byte 0x00
data_0000139d:	.byte 0x00
data_0000139e:	.byte 0x00
data_0000139f:	.byte 0x00
data_000013a0:	.byte 0x00
data_000013a1:	.byte 0x00
data_000013a2:	.byte 0x00
data_000013a3:	.byte 0x00
data_000013a4:	.byte 0x00
data_000013a5:	.byte 0x00
data_000013a6:	.byte 0x00
data_000013a7:	.byte 0x00
data_000013a8:	.byte 0x00
data_000013a9:	.byte 0x00
data_000013aa:	.byte 0x00
data_000013ab:	.byte 0x00
data_000013ac:	.byte 0x00
data_000013ad:	.byte 0x00
data_000013ae:	.byte 0x00
data_000013af:	.byte 0x00
data_000013b0:	.byte 0x00
data_000013b1:	.byte 0x00
data_000013b2:	.byte 0x00
data_000013b3:	.byte 0x00
data_000013b4:	.byte 0x00
data_000013b5:	.byte 0x00
data_000013b6:	.byte 0x00
data_000013b7:	.byte 0x00
data_000013b8:	.byte 0x00
data_000013b9:	.byte 0x00
data_000013ba:	.byte 0x00
data_000013bb:	.byte 0x00
data_000013bc:	.byte 0x00
data_000013bd:	.byte 0x00
data_000013be:	.byte 0x00
data_000013bf:	.byte 0x00
data_000013c0:	.byte 0x00
data_000013c1:	.byte 0x00
data_000013c2:	.byte 0x00
data_000013c3:	.byte 0x00
data_000013c4:	.byte 0x00
data_000013c5:	.byte 0x00
data_000013c6:	.byte 0x00
data_000013c7:	.byte 0x00
data_000013c8:	.byte 0x00
data_000013c9:	.byte 0x00
data_000013ca:	.byte 0x00
data_000013cb:	.byte 0x00
data_000013cc:	.byte 0x00
data_000013cd:	.byte 0x00
data_000013ce:	.byte 0x00
data_000013cf:	.byte 0x00
data_000013d0:	.byte 0x00
data_000013d1:	.byte 0x00
data_000013d2:	.byte 0x00
data_000013d3:	.byte 0x00
data_000013d4:	.byte 0x00
data_000013d5:	.byte 0x00
data_000013d6:	.byte 0x00
data_000013d7:	.byte 0x00
data_000013d8:	.byte 0x00
data_000013d9:	.byte 0x00
data_000013da:	.byte 0x00
data_000013db:	.byte 0x00
data_000013dc:	.byte 0x00
data_000013dd:	.byte 0x00
data_000013de:	.byte 0x00
data_000013df:	.byte 0x00
data_000013e0:	.byte 0x00
data_000013e1:	.byte 0x00
data_000013e2:	.byte 0x00
data_000013e3:	.byte 0x00
data_000013e4:	.byte 0x00
data_000013e5:	.byte 0x00
data_000013e6:	.byte 0x00
data_000013e7:	.byte 0x00
data_000013e8:	.byte 0x00
data_000013e9:	.byte 0x00
data_000013ea:	.byte 0x00
data_000013eb:	.byte 0x00
data_000013ec:	.byte 0x00
data_000013ed:	.byte 0x00
data_000013ee:	.byte 0x00
data_000013ef:	.byte 0x00
data_000013f0:	.byte 0x00
data_000013f1:	.byte 0x00
data_000013f2:	.byte 0x00
data_000013f3:	.byte 0x00
data_000013f4:	.byte 0x00
data_000013f5:	.byte 0x00
data_000013f6:	.byte 0x00
data_000013f7:	.byte 0x00
data_000013f8:	.byte 0x00
data_000013f9:	.byte 0x00
data_000013fa:	.byte 0x00
data_000013fb:	.byte 0x00
data_000013fc:	.byte 0x00
data_000013fd:	.byte 0x00
data_000013fe:	.byte 0x00
data_000013ff:	.byte 0x00
data_00001400:	.byte 0x00
data_00001401:	.byte 0x00
data_00001402:	.byte 0x00
data_00001403:	.byte 0x00
data_00001404:	.byte 0x00
data_00001405:	.byte 0x00
data_00001406:	.byte 0x00
data_00001407:	.byte 0x00
data_00001408:	.byte 0x00
data_00001409:	.byte 0x00
data_0000140a:	.byte 0x00
data_0000140b:	.byte 0x00
data_0000140c:	.byte 0x00
data_0000140d:	.byte 0x00
data_0000140e:	.byte 0x00
data_0000140f:	.byte 0x00
data_00001410:	.byte 0x00
data_00001411:	.byte 0x00
data_00001412:	.byte 0x00
data_00001413:	.byte 0x00
data_00001414:	.byte 0x00
data_00001415:	.byte 0x00
data_00001416:	.byte 0x00
data_00001417:	.byte 0x00
data_00001418:	.byte 0x00
data_00001419:	.byte 0x00
data_0000141a:	.byte 0x00
data_0000141b:	.byte 0x00
data_0000141c:	.byte 0x00
data_0000141d:	.byte 0x00
data_0000141e:	.byte 0x00
data_0000141f:	.byte 0x00
data_00001420:	.byte 0x00
data_00001421:	.byte 0x00
data_00001422:	.byte 0x00
data_00001423:	.byte 0x00
data_00001424:	.byte 0x00
data_00001425:	.byte 0x00
data_00001426:	.byte 0x00
data_00001427:	.byte 0x00
data_00001428:	.byte 0x00
data_00001429:	.byte 0x00
data_0000142a:	.byte 0x00
data_0000142b:	.byte 0x00
data_0000142c:	.byte 0x00
data_0000142d:	.byte 0x00
data_0000142e:	.byte 0x00
data_0000142f:	.byte 0x00
data_00001430:	.byte 0x00
data_00001431:	.byte 0x00
data_00001432:	.byte 0x00
data_00001433:	.byte 0x00
data_00001434:	.byte 0x00
data_00001435:	.byte 0x00
data_00001436:	.byte 0x00
data_00001437:	.byte 0x00
data_00001438:	.byte 0x00
data_00001439:	.byte 0x00
data_0000143a:	.byte 0x00
data_0000143b:	.byte 0x00
data_0000143c:	.byte 0x00
data_0000143d:	.byte 0x00
data_0000143e:	.byte 0x00
data_0000143f:	.byte 0x00
data_00001440:	.byte 0x00
data_00001441:	.byte 0x00
data_00001442:	.byte 0x00
data_00001443:	.byte 0x00
data_00001444:	.byte 0x00
data_00001445:	.byte 0x00
data_00001446:	.byte 0x00
data_00001447:	.byte 0x00
data_00001448:	.byte 0x00
data_00001449:	.byte 0x00
data_0000144a:	.byte 0x00
data_0000144b:	.byte 0x00
data_0000144c:	.byte 0x00
data_0000144d:	.byte 0x00
data_0000144e:	.byte 0x00
data_0000144f:	.byte 0x00
data_00001450:	.byte 0x00
data_00001451:	.byte 0x00
data_00001452:	.byte 0x00
data_00001453:	.byte 0x00
data_00001454:	.byte 0x00
data_00001455:	.byte 0x00
data_00001456:	.byte 0x00
data_00001457:	.byte 0x00
data_00001458:	.byte 0x00
data_00001459:	.byte 0x00
data_0000145a:	.byte 0x00
data_0000145b:	.byte 0x00
data_0000145c:	.byte 0x00
data_0000145d:	.byte 0x00
data_0000145e:	.byte 0x00
data_0000145f:	.byte 0x00
data_00001460:	.byte 0x00
data_00001461:	.byte 0x00
data_00001462:	.byte 0x00
data_00001463:	.byte 0x00
data_00001464:	.byte 0x00
data_00001465:	.byte 0x00
data_00001466:	.byte 0x00
data_00001467:	.byte 0x00
data_00001468:	.byte 0x00
data_00001469:	.byte 0x00
data_0000146a:	.byte 0x00
data_0000146b:	.byte 0x00
data_0000146c:	.byte 0x00
data_0000146d:	.byte 0x00
data_0000146e:	.byte 0x00
data_0000146f:	.byte 0x00
data_00001470:	.byte 0x00
data_00001471:	.byte 0x00
data_00001472:	.byte 0x00
data_00001473:	.byte 0x00
data_00001474:	.byte 0x00
data_00001475:	.byte 0x00
data_00001476:	.byte 0x00
data_00001477:	.byte 0x00
data_00001478:	.byte 0x00
data_00001479:	.byte 0x00
data_0000147a:	.byte 0x00
data_0000147b:	.byte 0x00
data_0000147c:	.byte 0x00
data_0000147d:	.byte 0x00
data_0000147e:	.byte 0x00
data_0000147f:	.byte 0x00
data_00001480:	.byte 0x00
data_00001481:	.byte 0x00
data_00001482:	.byte 0x00
data_00001483:	.byte 0x00
data_00001484:	.byte 0x00
data_00001485:	.byte 0x00
data_00001486:	.byte 0x00
data_00001487:	.byte 0x00
data_00001488:	.byte 0x00
data_00001489:	.byte 0x00
data_0000148a:	.byte 0x00
data_0000148b:	.byte 0x00
data_0000148c:	.byte 0x00
data_0000148d:	.byte 0x00
data_0000148e:	.byte 0x00
data_0000148f:	.byte 0x00
data_00001490:	.byte 0x00
data_00001491:	.byte 0x00
data_00001492:	.byte 0x00
data_00001493:	.byte 0x00
data_00001494:	.byte 0x00
data_00001495:	.byte 0x00
data_00001496:	.byte 0x00
data_00001497:	.byte 0x00
data_00001498:	.byte 0x00
data_00001499:	.byte 0x00
data_0000149a:	.byte 0x00
data_0000149b:	.byte 0x00
data_0000149c:	.byte 0x00
data_0000149d:	.byte 0x00
data_0000149e:	.byte 0x00
data_0000149f:	.byte 0x00
data_000014a0:	.byte 0x00
data_000014a1:	.byte 0x00
data_000014a2:	.byte 0x00
data_000014a3:	.byte 0x00
data_000014a4:	.byte 0x00
data_000014a5:	.byte 0x00
data_000014a6:	.byte 0x00
data_000014a7:	.byte 0x00
data_000014a8:	.byte 0x00
data_000014a9:	.byte 0x00
data_000014aa:	.byte 0x00
data_000014ab:	.byte 0x00
data_000014ac:	.byte 0x00
data_000014ad:	.byte 0x00
data_000014ae:	.byte 0x00
data_000014af:	.byte 0x00
data_000014b0:	.byte 0x00
data_000014b1:	.byte 0x00
data_000014b2:	.byte 0x00
data_000014b3:	.byte 0x00
data_000014b4:	.byte 0x00
data_000014b5:	.byte 0x00
data_000014b6:	.byte 0x00
data_000014b7:	.byte 0x00
data_000014b8:	.byte 0x00
data_000014b9:	.byte 0x00
data_000014ba:	.byte 0x00
data_000014bb:	.byte 0x00
data_000014bc:	.byte 0x00
data_000014bd:	.byte 0x00
data_000014be:	.byte 0x00
data_000014bf:	.byte 0x00
data_000014c0:	.byte 0x00
data_000014c1:	.byte 0x00
data_000014c2:	.byte 0x00
data_000014c3:	.byte 0x00
data_000014c4:	.byte 0x00
data_000014c5:	.byte 0x00
data_000014c6:	.byte 0x00
data_000014c7:	.byte 0x00
data_000014c8:	.byte 0x00
data_000014c9:	.byte 0x00
data_000014ca:	.byte 0x00
data_000014cb:	.byte 0x00
data_000014cc:	.byte 0x00
data_000014cd:	.byte 0x00
data_000014ce:	.byte 0x00
data_000014cf:	.byte 0x00
data_000014d0:	.byte 0x00
data_000014d1:	.byte 0x00
data_000014d2:	.byte 0x00
data_000014d3:	.byte 0x00
data_000014d4:	.byte 0x00
data_000014d5:	.byte 0x00
data_000014d6:	.byte 0x00
data_000014d7:	.byte 0x00
data_000014d8:	.byte 0x00
data_000014d9:	.byte 0x00
data_000014da:	.byte 0x00
data_000014db:	.byte 0x00
data_000014dc:	.byte 0x00
data_000014dd:	.byte 0x00
data_000014de:	.byte 0x00
data_000014df:	.byte 0x00
data_000014e0:	.byte 0x00
data_000014e1:	.byte 0x00
data_000014e2:	.byte 0x00
data_000014e3:	.byte 0x00
data_000014e4:	.byte 0x00
data_000014e5:	.byte 0x00
data_000014e6:	.byte 0x00
data_000014e7:	.byte 0x00
data_000014e8:	.byte 0x00
data_000014e9:	.byte 0x00
data_000014ea:	.byte 0x00
data_000014eb:	.byte 0x00
data_000014ec:	.byte 0x00
data_000014ed:	.byte 0x00
data_000014ee:	.byte 0x00
data_000014ef:	.byte 0x00
data_000014f0:	.byte 0x00
data_000014f1:	.byte 0x00
data_000014f2:	.byte 0x00
data_000014f3:	.byte 0x00
data_000014f4:	.byte 0x00
data_000014f5:	.byte 0x00
data_000014f6:	.byte 0x00
data_000014f7:	.byte 0x00
data_000014f8:	.byte 0x00
data_000014f9:	.byte 0x00
data_000014fa:	.byte 0x00
data_000014fb:	.byte 0x00
data_000014fc:	.byte 0x00
data_000014fd:	.byte 0x00
data_000014fe:	.byte 0x00
data_000014ff:	.byte 0x00
data_00001500:	.byte 0x00
data_00001501:	.byte 0x00
data_00001502:	.byte 0x00
data_00001503:	.byte 0x00
data_00001504:	.byte 0x00
data_00001505:	.byte 0x00
data_00001506:	.byte 0x00
data_00001507:	.byte 0x00
data_00001508:	.byte 0x00
data_00001509:	.byte 0x00
data_0000150a:	.byte 0x00
data_0000150b:	.byte 0x00
data_0000150c:	.byte 0x00
data_0000150d:	.byte 0x00
data_0000150e:	.byte 0x00
data_0000150f:	.byte 0x00
data_00001510:	.byte 0x00
data_00001511:	.byte 0x00
data_00001512:	.byte 0x00
data_00001513:	.byte 0x00
data_00001514:	.byte 0x00
data_00001515:	.byte 0x00
data_00001516:	.byte 0x00
data_00001517:	.byte 0x00
data_00001518:	.byte 0x00
data_00001519:	.byte 0x00
data_0000151a:	.byte 0x00
data_0000151b:	.byte 0x00
data_0000151c:	.byte 0x00
data_0000151d:	.byte 0x00
data_0000151e:	.byte 0x00
data_0000151f:	.byte 0x00
data_00001520:	.byte 0x00
data_00001521:	.byte 0x00
data_00001522:	.byte 0x00
data_00001523:	.byte 0x00
data_00001524:	.byte 0x00
data_00001525:	.byte 0x00
data_00001526:	.byte 0x00
data_00001527:	.byte 0x00
data_00001528:	.byte 0x00
data_00001529:	.byte 0x00
data_0000152a:	.byte 0x00
data_0000152b:	.byte 0x00
data_0000152c:	.byte 0x00
data_0000152d:	.byte 0x00
data_0000152e:	.byte 0x00
data_0000152f:	.byte 0x00
data_00001530:	.byte 0x00
data_00001531:	.byte 0x00
data_00001532:	.byte 0x00
data_00001533:	.byte 0x00
data_00001534:	.byte 0x00
data_00001535:	.byte 0x00
data_00001536:	.byte 0x00
data_00001537:	.byte 0x00
data_00001538:	.byte 0x00
data_00001539:	.byte 0x00
data_0000153a:	.byte 0x00
data_0000153b:	.byte 0x00
data_0000153c:	.byte 0x00
data_0000153d:	.byte 0x00
data_0000153e:	.byte 0x00
data_0000153f:	.byte 0x00
data_00001540:	.byte 0x00
data_00001541:	.byte 0x00
data_00001542:	.byte 0x00
data_00001543:	.byte 0x00
data_00001544:	.byte 0x00
data_00001545:	.byte 0x00
data_00001546:	.byte 0x00
data_00001547:	.byte 0x00
data_00001548:	.byte 0x00
data_00001549:	.byte 0x00
data_0000154a:	.byte 0x00
data_0000154b:	.byte 0x00
data_0000154c:	.byte 0x00
data_0000154d:	.byte 0x00
data_0000154e:	.byte 0x00
data_0000154f:	.byte 0x00
data_00001550:	.byte 0x00
data_00001551:	.byte 0x00
data_00001552:	.byte 0x00
data_00001553:	.byte 0x00
data_00001554:	.byte 0x00
data_00001555:	.byte 0x00
data_00001556:	.byte 0x00
data_00001557:	.byte 0x00
data_00001558:	.byte 0x00
data_00001559:	.byte 0x00
data_0000155a:	.byte 0x00
data_0000155b:	.byte 0x00
data_0000155c:	.byte 0x00
data_0000155d:	.byte 0x00
data_0000155e:	.byte 0x00
data_0000155f:	.byte 0x00
data_00001560:	.byte 0x00
data_00001561:	.byte 0x00
data_00001562:	.byte 0x00
data_00001563:	.byte 0x00
data_00001564:	.byte 0x00
data_00001565:	.byte 0x00
data_00001566:	.byte 0x00
data_00001567:	.byte 0x00
data_00001568:	.byte 0x00
data_00001569:	.byte 0x00
data_0000156a:	.byte 0x00
data_0000156b:	.byte 0x00
data_0000156c:	.byte 0x00
data_0000156d:	.byte 0x00
data_0000156e:	.byte 0x00
data_0000156f:	.byte 0x00
data_00001570:	.byte 0x00
data_00001571:	.byte 0x00
data_00001572:	.byte 0x00
data_00001573:	.byte 0x00
data_00001574:	.byte 0x00
data_00001575:	.byte 0x00
data_00001576:	.byte 0x00
data_00001577:	.byte 0x00
data_00001578:	.byte 0x00
data_00001579:	.byte 0x00
data_0000157a:	.byte 0x00
data_0000157b:	.byte 0x00
data_0000157c:	.byte 0x00
data_0000157d:	.byte 0x00
data_0000157e:	.byte 0x00
data_0000157f:	.byte 0x00
