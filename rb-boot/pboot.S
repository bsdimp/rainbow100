/*
 * Copyright (c) 2020 Warner Losh
 *
 * Redistribution and use in source and binary forms are freely
 * permitted provided that the above copyright notice and this
 * paragraph and the following disclaimer are duplicated in all
 * such forms.
 *
 * This software is provided "AS IS" and without any express or
 * implied warranties, including, without limitation, the implied
 * warranties of merchantability and fitness for a particular
 * purpose.
 */

/*
 * Replacement program insipired by PREBOOT.ASM from WUTIL.
 * But one that's slightly more chatty since we have oodles of
 * space. This is a caller saves what they care about file.
 */

/*
 * We need to load and run the secondary boot loader. We'll load
 * it at 0:2000H. For errors, we do a FAR RETURN back to the BIOS
 * that called us.
 */

#define TIMER
#define VERBOSE
/*
 * Constants for the disk controller
 */

	.set	PRECOMP,50	# Initial PRECOM register
	.set	SEC512,0x20	# Bits in the SDH register for 512-byte sectors
	.set	READCMD,0x20	# Controller read command

/*
 * I/O port for Rainbow Winchester drive
 */
	.set	WDATA,0x60	# Data in/out
	.set	WERRPRE, 0x61	# Error/precompensation reg
	.set	WSECCNT, 0x62	# Sector count reg
	.set	WSECT, 0x63	# Sector number reg
	.set	WCYLL, 0x64	# Cylinder number low order reg
	.set	WCYLH, 0x65	# Cylinder number high order reg
	.set	WSDH, 0x66	# Sector/drive/head reg
	.set	WCSR, 0x67	# Winchester command & status reg
	.set	SECCSR, 0x68	# Secondary command & status reg

	.set	wd_int, 0x25	# Expansion card interrupt
	.set	timer_int, 0x20	# Really vert interrupt, need to chain to real one

	.set	BIOS_SEG, 0xee00
	.set	BIOS_SP, 0x1ff7

	.set	bios, 40
	.set	hom_buf, 0x1500	# Secondary loader expects this here
	.set	sec_load, 0x2000 # Where to put secondary loader

	.set	hom_boot, 33

	.globl	start
	.code16
	.arch	i8086		# Note: need binutils as clang can't cope
start:
	nop			# Must start with a NOP or BIOS won't jump here
	/*
	 * The old PREBOOT.ASM does this. The PREBOOT code is only
	 * 'coy' and says it is a special place for others. But it also
	 * keeps on using the stack that the ROM BIOS setup...
	 * And when I enable the code, boom when I try to store
	 * to saved_sp.
	 */
#	movw	%sp, %cs:saved_sp
	pushf
	pushw	%di
	pushw	%si
	pushw	%bp
	pushw	%ax
	pushw	%bx
	pushw	%cx
	pushw	%dx
	pushw	%ds
	pushw	%es
#if 0
	movw	BIOS_SEG, %ax
	movw	%ax, %es
	movw	saved_sp, %ax
	movw	%ax, %es:BIOS_SP
#endif
	movw	%sp, %cs:saved_sp		# then this value is restored before leaving

	movw	%cs,%ax
	movw	%ax,%ds
	movw	%ax,%es
save_isr:
#ifdef TIMER
	movw	$(timer_int*4), %si
	movw	$timer_sv, %di
	callw	moveisr
#endif
	movw	$(wd_int*4), %si
	movw	$wd_sv, %di
	callw	moveisr
est_isr:
#ifdef TIMER
	movw	$(timer_int*4), %di
	movw	$timer_isr, %ax
	call	storeisr
#endif
	movw	$(wd_int*4), %di
	movw	$wd_isr, %ax
	call	storeisr
#ifdef VERBOSE
announce:
	movw	$hello, %si
	callw	puts
#endif

read_hom:
	xor	%bx, %bx			# Track 0
	mov	$2, %cx				# Sector 2 is HOM block
	movw	$hom_buf, %di			# Shared buffer with secboot
	call	read_sector

	movw	$hom_buf, %si
	movw	%si, %bx
	movw	$512 / 2, %cx
	xor	%dx, %dx
1:	lodsw
	add	%ax, %dx
	loop	1b
	jz	good
1:
#ifdef VERBOSE
	movw	$bad_hom, %si
	call	puts
#endif
	jmp	error_exit
good:
	movw	$0x4f48, %ax			# 'HO'
	cmpw	%ax, 0(%bx)
	jne	1b
	movw	$0x4d, %ax			# 'M<NUL>'
	cmpw	%ax, 2(%bx)
	jne	1b

	# %es already good
	movw	$sec_load, %di
	movw	hom_boot(%bx), %dx		# Move track to DX for the moment
	movb	(hom_boot+2)(%bx), %al		# Move sector to cl
	movw	(hom_boot+3)(%bx), %cx		# length
	movw	%dx, %bx
	movb	%al, sector			# save the current sector
1:
	push	%cx
	movb	sector, %cl			# save the current sector
	# %bx has track alrady
	# %ep:%di has been updated to the new pointer
	# %cl has sector
	call	read_sector			# success or error exit
	incb	sector
	pop	%cx
	loop	1b

	/*
	 * OK. We've read in things. Validate that the secondary
	 * boot starts with 'S' and jump to it if it does
	 */
	movw	$sec_load, %si
	lodsb
	cmp	'S', %al
	jne	1f
	jmp	*%si
1:
#ifdef VERBOSE
	movw	$bad_sec, %si
	call	puts
#endif
rest_isr:
#ifdef TIMER
	movw	$timer_sv, %si
	movw	$(timer_int*4), %di
	call	moveisr
#endif
	movw	$wd_sv, %si
	movw	$(wd_int*4), %di
	call	moveisr

#ifdef VERBOSE
	movw	$crlf, %si
	callw	puts
#endif
	movw	saved_sp, %sp
	popw	%es
	popw	%ds
	popw	%dx
	popw	%cx
	popw	%bx
	popw	%ax
	popw	%bp
	popw	%si
	popw	%di
	popf
	lret

error_exit:
#ifdef TIMER
	call	wait_10s
#endif
	jmp	rest_isr

#ifdef TIMER
wait_10s:
	movw	$60*10, countdown
1:
	movw	countdown, %ax
	or	%ax, %ax
	jz	1f
	hlt
	jmp	1b
1:
	ret
#endif

moveisr:
	cli
	lodsw
	stosw
	lodsw
	stosw
	sti
	ret

storeisr:
	cli
	stosw
	movw	%cs, %ax
	stosw
	sti
	ret
#ifdef VERBOSE
puts:
1:
	lodsb
	or	%al, %al
	je	1f
	xor	%di, %di
	pushw	%si
	pushw	%es
	int	$bios
	popw	%es
	popw	%si
	jmp	1b
1:
	ret
puthexb:
	std
	movw	$hexbuf, %di
	incw	%di
	incw	%di
	movb	%al, %ah
	call	ph_store1
	movb	%ah, %al
	shrb	%al
	shrb	%al
	shrb	%al
	shrb	%al
	call	ph_store1
	cld
	movw	%di, %si
	call	puts
	ret
ph_store1:
	andb	$0xf, %al
	cmp	$9, %al
	ja	1f
	add	'0', %al
	jmp	2f
1:	add	'a', %al
2:	stosb
	ret
#endif
#ifdef TIMER
timer_isr:
	pushw	%ax
	movw	countdown, %ax
	jz	1f
	decw	%ax
	movw	%ax, countdown
1:
	popw	%ax
	ljmp	*%cs:timer_sv
#endif

wd_isr:
	pushw	%ax
	inb	$WCSR, %al
	movb	$0xff, intflg
	popw	%ax
	iret

/*
 * Reads in one sector. Passed in LBA to read.
 * Returns data to %es:%di.
 * Track in %bx, sector in %cl
 * Destorys all non-segment registers
 */
read_sector:
	movb	$1, %al			# One sector
	outb	%al, $WSECCNT
	movb	%cl, %al		# Sector number
	outb	%al, $WSECT
	movw	%bx, %ax
	xor	%dx, %dx
	divw	surfaces		# %ax cylinder dx surface/hd
	outb	%al, $WCYLL		# Program cylninder
	movb	%ah, %al
	outb	%al, $WCYLH
	movb	%dl, %al		# Program head
	orb	$SEC512, %al		# ... and sector length
	outb	%al, $WSDH
	movb	$0, intflg		# Clear interrupt flag
#ifdef TIMER
	movw	$60, countdown		# and start timer
#endif
	movb	$READCMD, %al		# Start the read
	outb	%al, $WCSR
1:					# Wait for the interrupt
	movb	intflg, %al
	orb	%al, %al
	jnz	1f
#ifdef TIMER
	movw	countdown, %ax
	orw	%ax, %ax
	jz	wd_timeout
#endif
	hlt
	jmp	1b
1:
	# It completed
	inb	$WCSR, %al
	test	$0x21, %al
	jz	1f
#ifdef VERBOSE
	push	%ax
	movw	$wd_err, %si
	callw	puts
	pop	%ax
	call	puthexb
#endif
	jmp	error_exit
1:
	movw	$512, %cx
2:	in	$WDATA, %al
	stosb
	loop	2b

	mov	$1, %al
	outb	%al, $SECCSR
	mov	100, %cx
1:	nop
	loop	1b
	ret
#ifdef TIMER
wd_timeout:
#ifdef VERBOSE
	movw	$timeout, %si
	callw	puts
#endif
	jmp	error_exit
#endif
	.data
surfaces:	.word 1
#ifdef VERBOSE
hello:		.asciz	"\033[H\033[JRB-PBOOT: "
timeout:	.asciz  "Timeout"
wd_err:		.asciz	"Err "
bad_hom:	.asciz	"Bad HOM"
bad_sec:	.asciz	"Bad Boot"
crlf:		.asciz	"\r\n"
#endif
saved_sp:	.word 0
#ifdef TIMER
countdown:	.word 0
timer_sv:	.word 0
		.word 0
#endif
wd_sv:		.word 0
		.word 0
intflg:		.byte 0
sector:		.byte 0
#ifdef VERBOSE
hexbuf:		.space 5
#endif
