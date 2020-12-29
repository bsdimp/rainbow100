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

	.set	wd_vec, 0x94

	.set	BIOS_SEG, 0xee00
	.set	BIOS_SP, 0x1ff7

	.globl	start
	.code16
start:
	nop			# Must start with a NOP or BIOS won't jump here
#if 0
	push	%ax
	movw	%sp, %cs:saved_sp
	movw	$0x2000, %ax
	movw	%ax, %sp
	pushf
	push	%di
	push	%si
	push	%bx
	push	%cx
	push	%dx
	push	%ds
	push	%es
	push	%bp

	movw	BIOS_SEG, %ax
	movw	%ax, %es
	movw	saved_sp, %ax
	movw	%ax, %es:BIOS_SP
#endif
	pushw	%ax
	movw	%cs,%ax
	movw	%ax,%ds
	movw	%ax,%es
	mov	$hello, %ax
	call	puts
	/*
	 * Let the message up for a bit
	 */
	movw	$-1, %cx
1:	
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	loop	1b
bye:
	pop	%bp
	pop	%es
	pop	%ds
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%si
	pop	%di
	popf
#	movw	%cs:saved_sp, %sp
	pop	%ax
	lret

puts:
	push	%di
	push	%si
	movw	%ax, %si
1:
	lodsb
	or	%al,%al
	je	1f
	movw	$0, %di
	push	%si
	int	$40
	pop	%si
	jmp	1b
1:	
	pop	%si
	pop	%di
	ret
	.data
saved_sp:	.word 0
hello:	.asciz	"\033[H\033[J\n\n\033[1mHello World!\033[m\r\n"
