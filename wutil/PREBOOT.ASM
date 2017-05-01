	TITLE	PREBOOT
	PAGE	60,132

;******************************************************************************
;	PREBOOT.ASM
;
;	This file, when built using the procedure in BLDPBOOT.BAT, produces
;	a primary boot loader for a rainbow hard disk.  This program is called
;	by the ROM boot loader when the "W" (boot from Winchester disk) option
;	is chosen from the boot menu.  It runs without an operating system, but
;	does have access to rainbow firmware (INT 28) routines.
;
;	The primary boot loader's job is to load and execute the secondary
;	boot loader.  It initializes the hard disk controller and reads the
;	HOMe block from the beginning of the disk.  This block contains (among
;	many other things) the location of the secondary boot loader.  The
;	secondary boot loader is read from disk starting at address 2000 hex
;	and then executed (provided that it starts with the expected byte).
;
;	If there are any errors, this loader executes a FAR return back to
;	the calling ROM code, which then reports a "non system disk" error.
;	Similarly, the secondary boot loader can return to us if it encounters
;	an error -- if it does, we return also so that an error will be
;	reported.  The secondary boot loader, if it runs successfully,
;	will load and execute an operating system loader, which will start up
;	the operating system for the selected partition.
;
;******************************************************************************

; Some initial definitions

PRECOMP	EQU	50			;Initial value to use for precomp reg
SEC512	EQU	20H			;Bits in SDH reg for 512 byte sectors
READCMD	EQU	20H			;Controller command to read sector

WVECTOR	EQU	94H			;Interrupt vector for winnie (before
					; relocation which may occur on 100B)

SECSEG	EQU	200H			;Segment address of secboot loader

; Definitions of I/O ports for winchester controller

WDATA	EQU	60H			;Data in/out
WERRPRE	EQU	61H			;Error/precompensation reg
WSECCNT	EQU	62H			;Sector count reg
WSECT	EQU	63H			;Sector number reg
WCYLL	EQU	64H			;Cylinder number low order reg
WCYLH	EQU	65H			;Cylinder number high order reg
WSDH	EQU	66H			;Sector/drive/head reg
WCSR	EQU	67H			;Winchester command & status reg
SECCSR	EQU	68H			;Secondary command & status reg

; HOM block offsets
HOM	STRUC

HIDENT	DB	3 DUP (?)		;Block ID
HPFLAG	DB	?			;Flag: partitioned or not
HCKSUM	DW	?			;Checksum
HVOLID	DB	8 DUP (?)		;Volume ID (ASCII)
HSYSID	DW	2 DUP (?)		;System ID
HBATTRK	DW	?			;BAT first track
HBATSEC	DB	?			;BAT first sector
HBATSIZ	DW	?			;BAT size in secotrs
HDPDTRK	DW	?			;DPD first track
HDPDSEC	DB	?			;DPD first sector
HDPDSIZ	DW	?			;DPD size in sectors
HOSNTRK	DW	?			;OSN first track
HOSNSEC	DB	?			;OSN first sector
HOSNSIZ	DW	?			;OSN size in sectors
HBOOTRK	DW	?			;secondary boot first track
HBOOSEC	DB	?			;secondary boot first sector
HBOOSIZ	DW	?			;secondary boot size in sectors
HASTTRK	DW	?			;AST first track
HASTSEC	DB	?			;AST first sector
HASTSIZ	DW	?			;AST size in sectors
HALTTRK	DW	?			;Alternate sector area first track
HALTSIZ	DB	?			;Alternate sector area size in tracks
HABFLG	DB	?			;Auto boot flag/drive
HABTRK	DW	?			;Auto boot first track
	DB	15 DUP (?)
HCYLS	DW	?			;Geometry: # of cylinders
HTRKSIZ	DB	?			;Geometry: # of sectors/track
HSECSIZ	DW	?			;Geometry: # of bytes/sector
HSURFS	DB	?			;Geometry: # of surfaces (heads)
HMAINT	DW	?			;Cylinder # of maint area
HMFG	DW	?			;Cylinder # of manufacturer info
HPRECMP	DW	?			;Write precomp value
HSTEPR	DB	?			;Step rate
HTYPE	DB	?			;Type code
	DB	49 DUP (?)
HPBLOCK	DB	?			;Physical block # this block (1)
	DB	384 DUP (?)

HOM	ENDS

; This absolute segment describes the area where the secondary boot code will
; be put.  It does not actually end up in the object file.

SECBOOT	SEGMENT	AT SECSEG
	ORG	0
	ASSUME	CS:SECBOOT

SBFRST	DB	?

SBSTART	PROC	FAR
	NOP
SBSTART	ENDP

SECBOOT	ENDS

CODE	SEGMENT
	ORG	1000H

	ASSUME	CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

START:	NOP				;This NOP must be here for ROM boot
	MOV	WORD PTR CS:SAVESP,SP	;Save SP contents at entry time
	CALL	SAVER			;Save all registers & flags
	MOV	AX,0EE00H		;Point to special data segment
	MOV	ES,AX
	MOV	AX,WORD PTR CS:SAVESP	;Get saved SP value (SP on entry)
	MOV	WORD PTR ES:1FF7H,AX	;Store it in special place for others
	PUSH	CS			;Now copy CS to DS
	POP	DS			; ..
	ASSUME	DS:CODE			;Now we can assume that
	MOV	WORD PTR SAVESP,SP	;Save SP value after saved registers

	CALL	SETISR			;Set up to allow / trap interrupts

	MOV	AL,2			;Tell controller to initialize
	OUT	SECCSR,AL		; ..
	MOV	CX,100			;Wait a while while this happens
	NOP
	LOOP	$-1

	MOV	BYTE PTR INTFLG,0	;Initialize interrupt flag to zero

	MOV	AL,PRECOMP		;Get initial precomp value
	OUT	WERRPRE,AL		;Init in controller

	XOR	BX,BX			;HOM block is track 0,
	MOV	CL,2			; sector 2
	XOR	AX,AX			;Point ES at base page
	MOV	ES,AX			; ..
	MOV	DI,1500H		;HOM block gets loaded at address 1500
	CALL	READSC			;Read the sector

;Now we have the home block in memory.  Get the boot area's info from there
; and proceed to read the secondary boot code

	MOV	AX,ES:[DI].HBOOSIZ	;Get size of boot area
	OR	AX,AX			;Nonzero?
	JNZ	RBOOT2			;Yes - continue
	JMP	SHORT ERRRET		;No - return, this is not bootable

RBOOT2:	MOV	BL,ES:[DI].HSURFS	;Get number of surfaces drive has
	XOR	BH,BH			;High order is always zero
	MOV	WORD PTR NUMSURF,BX	;Store for future reads

	MOV	BX,ES:[DI].HBOOTRK	;Get track number of secondary boot
	MOV	CL,ES:[DI].HBOOSEC	;And starting sector number

	MOV	DI,(SECSEG * 10H)	;Point at load location for secboot

RBLOOP:	CALL	READSC			;Read a sector of the boot code
	ADD	DI,0200H		;Point buffer at next sector area
	INC	CL			;Increment sector number
	DEC	AX			;Count down one sector done
	JNZ	RBLOOP			;Continue until all sectors done

	MOV	DI,(SECSEG * 10H)	;Point back at beginning of boot code
	MOV	AL,ES:[DI]		;Get first byte
	CMP	AL,'S'			;Is it ASCII "S" (as in SECBOOT)?
	JZ	CBOOT			;Yes - looks ok, call secondary boot
					; (but skip over the first byte)
	JMP	SHORT ERRRET		;No - error - return

CBOOT:	CALL	SBSTART			;Go to start of secondary boot code
					;(If it returns, we'll continue to
					; error code which follows)

ERRPRC	PROC	FAR			;Routine to end with error, defined as
					; FAR because that's how our whole
					; routine is called.  This is the only
					; return, however.
ERRRET:	CALL	RSTISR			;Put old data back in int vectors
	MOV	SP,CS:SAVESP		;Get back saved stack pointer
	CALL	RESTOR			;Restore saved registers
	RET				;Return to indicate error
ERRPRC	ENDP

;This routine reads a sector from the hard disk into the buffer pointed to
; by ES:DI.  The track number is passed in BX, the sector number in CL.

READSC:	CALL	SAVER			;Save everything

	MOV	AL,1			;We want one sector
	OUT	WSECCNT,AL		;Tell the controller that

	MOV	AL,CL			;Get passed sector number
	OUT	WSECT,AL		;Tell the controller

	MOV	AX,BX			;Get passed track number
	XOR	DX,DX			;Clear high order of dividend

	DIV	WORD PTR NUMSURF	;Divide track # by surfs -> cyl#/surf#

	OUT	WCYLL,AL		;Store resulting cylinder number low
	MOV	AL,AH			; and high in controller
	OUT	WCYLH,AL		; ...

	MOV	AL,DL			;Get remainder (head number)
	OR	AL,SEC512		;Add in flags for 512 byte sectors
	OUT	WSDH,AL			;Send size/drive/head to controller

	MOV	AL,READCMD		;Tell controller to read a sector
	OUT	WCSR,AL			; ..

	CALL	WAITFR			;Wait for completion
	CMP	AL,0FFH			;Did we get a timeout?
	JZ	ERRRET			;If so, give up and return

	IN	AL,WCSR			;Get drive status
	TEST	AL,21H			;Any error bits set?
	JNZ	ERRRET			;If so, return with error

RDOK:	MOV	CX,200H			;Count of bytes to get
	MOV	BP,SP			;Get copy of stack pointer
	MOV	DI,16[BP]		;Get original (passed/saved) DI & ES
	MOV	ES,2[BP]		; ..
RLOOP:	IN	AL,WDATA		;Get next byte
	STOSB				;Store in destination buffer
	LOOP	RLOOP			;Continue until done

	MOV	AL,1			;Set buffer ready bit to say we're done
	OUT	SECCSR,AL		; ..
	MOV	CX,100			;Wait for controller to settle
	NOP				;(Note there should be no command end
	LOOP	$-1			; interrupt as we clear the "I" bit
					; in the read command)

	CALL	RESTOR			;Restore saved registers
	RET				;And return

;This routine waits a while for a hard disk operation to complete.  It returns
; 0 in AX if the operation completed, or 0FF (hex) if the operation timed out.

WAITFR:	MOV	CX,0F000H		;Number of repetitions for wait
WFLOOP:
	DB	0E9H,00,00		;Waste some time (these are long
	DB	0E9H,00,00		; jumps to the next address)
	DB	0E9H,00,00
	DB	0E9H,00,00
	DB	0E9H,00,00
	DB	0E9H,00,00
	DB	0E9H,00,00
	CMP	BYTE PTR INTFLG,0	;Has interrupt occurred yet?
	LOOPZ	WFLOOP			;If not, wait some more or time out
	CMP	BYTE PTR INTFLG,0	;Did interrupt happen?
	JNZ	WFRET			;If so, we're OK - return
	MOV	AL,0FFH			;If not, return nonzero for error
	RET				; ..

WFRET:	MOV	BYTE PTR INTFLG,0	;Reset interrupt flag for next time
	XOR	AL,AL			;Indicate no error (return zero)
	RET				;All done - return

;Here is the interrupt service routine which handles interrupts from the
; winchester drive.

INTSVC:	PUSH	AX			;Save register we will use
	IN	AL,WCSR			;Read command/status reg to clear int
	MOV	BYTE PTR CS:INTFLG,0FFH	;Indicate interrupt happened
	POP	AX			;Restore saved register
	IRET				;Return from interrupt

;SETISR saves the old contents of the winchester interrupt vector and replaces
; it with a pointer to our service routine.  RSTISR sets it back (used if we
; must return because of an error).

SETISR:	XOR	AX,AX			;Point at base page
	MOV	ES,AX			;With ES register
	CLI				;No interrupts while we change stuff
	MOV	AX,WORD PTR ES:WVECTOR	;Get current interrupt vector
	MOV	WORD PTR SAVVEC,AX	;Save in our save area
	MOV	AX,WORD PTR ES:WVECTOR+2;Do both words
	MOV	WORD PTR SAVVEC+2,AX	; ..
	MOV	WORD PTR ES:WVECTOR,OFFSET INTSVC ;Now replace with our routine
	MOV	WORD PTR ES:WVECTOR+2,CS; ..
	STI				;Now interrupts are allowed
	RET				;Back we go

RSTISR:	XOR	AX,AX			;Base page
	MOV	ES,AX
	CLI				;Disallow interrupts
	MOV	AX,WORD PTR SAVVEC	;Get saved interrupt vector value
	MOV	WORD PTR ES:WVECTOR,AX	;And put back in vector
	MOV	AX,WORD PTR SAVVEC+2	;Both words
	MOV	WORD PTR ES:WVECTOR+2,AX; ..
	STI				;Permit interrupts again
	RET				;Done

;SAVER saves all registers (and flags) on the stack.  RESTOR restores them.

SAVER:	PUSHF				;Save flags
	PUSH	DI			;And all registers...
	PUSH	SI
	PUSH	AX
	PUSH	BX
	PUSH	CX
	PUSH	DX
	PUSH	DS
	PUSH	ES
	PUSH	BP
	MOV	BP,SP			;Get copy of stack pointer now
	MOV	AX,20[BP]		;Find original return address on stack
	PUSH	AX			;Push it there
	MOV	AX,12[BP]		;Now get back correct BP value
	RET				;Return to saved address

RESTOR:	POP	AX			;Pop return address
	MOV	BP,SP			;Get copy of stack pointer
	MOV	20[BP],AX		;Replace return address down stack with
					; correct one
	POP	BP			;Now restore all registers
	POP	ES
	POP	DS
	POP	DX
	POP	CX
	POP	BX
	POP	AX
	POP	SI
	POP	DI
	POPF				;And flags
	RET				;And return to the right place

;DATA AREA

INTFLG	DB	0			;Flag set by our interrupt service

NUMSURF	DW	4			;Number of surfaces drive has (init 4)

SAVESP	DW	0			;Saves original SP for error exit
SAVVEC	DW	0			;Saved copy of original interrupt
	DW	0			; vector contents in these two words

	ORG	1200H			;Go to one byte beyond where we end,
					; so that we will fill the remainder
					; of our 512 bytes with zeroes.

CODE	ENDS

	END
