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
 *	
 */

/*
 * Replacement program insipired by PREBOOT.ASM from WUTIL.
 * But one that's slightly more chatty since we have oodles of
 * space
 */

/*
 * We need to load and run the secondary boot loader. We'll load
 * it at 0:2000H. For errors, we do a FAR RETURN back to the BIOS
 * that called us.
 */


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

	.set	wd_int, 0x25
	.set	timer_int, 0x20	# Really vert interrupt, need to chain to real one

	.set	BIOS_SEG, 0xee00
	.set	BIOS_SP, 0x1ff7

	.set	hom_buf, 0x1500

	.globl	start
	.code16
	.arch	i8086		# Note: need clang can't cope
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
	movw	$(timer_int*4), %si
	movw	$timer_sv, %di
	callw	moveisr
	movw	$(wd_int*4), %si
	movw	$wd_sv, %di
	callw	moveisr
est_isr:
	movw	$(timer_int*4), %di
	movw	$timer_isr, %ax
	call	storeisr
	movw	$(wd_int*4), %di
	movw	wd_isr, %ax
	call	storeisr
announce:
	movw	$hello, %si
	callw	puts

read_hom:

wait_wd:

wait_10s:
	movw	$60*10, countdown
1:
	movw	countdown, %ax
	or	%ax, %ax
	jz	1f
	hlt
	jmp	1b
1:

rest_isr:
	xor	%ax, %ax
	movw	%ax, %es			# Restore %es since int 0x28 scrambles it
	movw	$timer_sv, %si
	movw	$(timer_int*4), %di
	call	moveisr
	movw	$wd_sv, %si
	movw	$(wd_int*4), %di
	call	moveisr
bye:
	movw	$crlf, %si
	callw	puts
	movw	%cs:saved_sp, %sp		# Cope with stack bugs. -- assert in assembler?
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
puts:
	push	%di
1:
	lodsb
	or	%al, %al
	je	1f
	xor	%di, %di
	push	%si
	int	$40
	pop	%si
	jmp	1b
1:	
	pop	%di
	ret
timer_isr:
	pushw	%ax
	movw	countdown, %ax
	jz	1f
	decw	%ax
	movw	%ax, countdown
1:
	popw	%ax
	ljmp	*%cs:timer_sv

wd_isr:
	pushw	%ax
	inb	$WCSR, %al
	movb	$0xff, intflg
	popw	%ax
	iret

	.data
saved_sp:	.word 0
countdown:	.word 0
intflg:		.word 0
timer_sv:	.word 0
	.word 0
wd_sv:	.word 0
	.word 0
hello:	.asciz	"\033[H\033[J\033[1mRB-PBOOT: "
crlf:	.asciz	"\r\n"
