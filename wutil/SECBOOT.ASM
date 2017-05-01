        TITLE   SECBOOT
        PAGE    60,132

;******************************************************************************
;       SECBOOT.ASM
;
;       This file, when built using the procedure in BLDSBOOT.BAT, produces
;       a secondary boot loader for a rainbow hard disk.  This program is called
;       by the primary boot loader (PREBOOT.LDX) when the "W" (boot from
;       Winchester disk) option is chosen from the boot menu.  It runs without
;       an operating system, but does have access to rainbow firmware (INT 28)
;       routines.
;
;       The secondary boot loader's job is to load and execute an operating
;       system boot loader from one of the hard disk partitions.  It uses the
;       HOM block data read (and left in memory) by the primary boot loader
;       to determine what partitions are on the hard disk.  If there is an
;       auto-boot partition configured, it attempts to load the boot loader
;       for that partition.  Otherwise, it reads the OSN and DPD blocks from
;       the disk and displays a menu, allowing the user to select a partition
;       to boot from.  This routine will handle up to the maximum of 15
;       partitions on a hard disk and allow booting from any of them.  The
;       only exception is if there is only one partition on the disk; in this
;       case, the menu is not displayed and the single partition is booted.
;
;       The operating system boot loader is loaded at paragraph address 0C00
;       (hex) and executed provided it starts with the expected JMP
;       instruction.
;
;       If there are any errors, this loader executes a FAR return back to
;       the calling PREBOOT code, which then returns to the ROM code which
;       called it, resulting in the reporting of a "non system disk" error.
;       Similarly, the operating system loader can return to us if it encounters
;       an error -- if it does, we return also so that an error will be
;       reported.  The operating system boot loader, if it runs successfully,
;       will start the operating system and not return to us.
;
;******************************************************************************

; Misc definitions

SEC512  EQU     20H                     ;Bits in SDH reg for 512 byte sectors
READCMD EQU     20H                     ;Controller command to read sector

WVECTOR EQU     94H                     ;Interrupt vector for winnie (before
                                        ; relocation which may occur on 100B)

ZRESET  EQU     80H                     ;Diag port command to reset Z80
ZSTART  EQU     81H                     ;Diag port command to start up Z80
SCREENON EQU    83H                     ;Diag port command to turn on screen

Z80SRC  EQU     1000H                   ;Place in our memory where Z80 code is
Z80DST  EQU     8000H                   ;Place where we put Z80 code
Z80LEN  EQU     800H                    ;Size of Z80 code

OSBSEG  EQU     0C00H                   ;Segment where O/S Boot loader goes

;Function codes (passed in DI) for INT 28 firmware routines

LEV2_INP        EQU     02H             ;Level 2 input
LEV1_INP        EQU     06H             ;Level 1 input
DIS_CURSOR      EQU     08H             ;Disable cursor
ENA_CURSOR      EQU     0AH             ;Enable cursor
WRITE_DATA      EQU     14H             ;Write screen data (fast video)
RING_BELL       EQU     1EH             ;Ring bell (beep)

; Definitions of I/O ports for winchester controller

WDATA   EQU     60H                     ;Data in/out
WERRPRE EQU     61H                     ;Error/precompensation reg
WSECCNT EQU     62H                     ;Sector count reg
WSECT   EQU     63H                     ;Sector number reg
WCYLL   EQU     64H                     ;Cylinder number low order reg
WCYLH   EQU     65H                     ;Cylinder number high order reg
WSDH    EQU     66H                     ;Sector/drive/head reg
WCSR    EQU     67H                     ;Winchester command & status reg
SECCSR  EQU     68H                     ;Secondary command & status reg

; Other I/O ports

DIAGPORT EQU    0AH                     ;Diagnostic write port (Z80 control)

; HOM block offsets
HOM     STRUC

HIDENT  DB      3 DUP (?)               ;Block ID
HPFLAG  DB      ?                       ;Flag: partitioned or not
HCKSUM  DW      ?                       ;Checksum
HVOLID  DB      8 DUP (?)               ;Volume ID (ASCII)
HSYSID  DW      2 DUP (?)               ;System ID
HBATTRK DW      ?                       ;BAT first track
HBATSEC DB      ?                       ;BAT first sector
HBATSIZ DW      ?                       ;BAT size in secotrs
HDPDTRK DW      ?                       ;DPD first track
HDPDSEC DB      ?                       ;DPD first sector
HDPDSIZ DW      ?                       ;DPD size in sectors
HOSNTRK DW      ?                       ;OSN first track
HOSNSEC DB      ?                       ;OSN first sector
HOSNSIZ DW      ?                       ;OSN size in sectors
HBOOTRK DW      ?                       ;secondary boot first track
HBOOSEC DB      ?                       ;secondary boot first sector
HBOOSIZ DW      ?                       ;secondary boot size in sectors
HASTTRK DW      ?                       ;AST first track
HASTSEC DB      ?                       ;AST first sector
HASTSIZ DW      ?                       ;AST size in sectors
HALTTRK DW      ?                       ;Alternate sector area first track
HALTSIZ DB      ?                       ;Alternate sector area size in tracks
HABFLG  DB      ?                       ;Auto boot flag/drive
HABTRK  DW      ?                       ;Auto boot first track
        DB      15 DUP (?)
HCYLS   DW      ?                       ;Geometry: # of cylinders
HTRKSIZ DB      ?                       ;Geometry: # of sectors/track
HSECSIZ DW      ?                       ;Geometry: # of bytes/sector
HSURFS  DB      ?                       ;Geometry: # of surfaces (heads)
HMAINT  DW      ?                       ;Cylinder # of maint area
HMFG    DW      ?                       ;Cylinder # of manufacturer info
HPRECMP DW      ?                       ;Write precomp value
HSTEPR  DB      ?                       ;Step rate
HTYPE   DB      ?                       ;Type code
        DB      49 DUP (?)
HPBLOCK DB      ?                       ;Physical block # this block (1)
        DB      384 DUP (?)

HOM     ENDS

; DPD block offsets
DPD     STRUC

DIDENT  DB      3 DUP (?)               ;Block ID
DBLKNUM DB      ?                       ;Logical block number
DCKSUM  DW      ?                       ;Checksum
DMAXCNT DW      ?                       ;Maximum entry count
DENTCNT DW      ?                       ;Actual entry count
        DB      22 DUP (?)              ;Reserved header area
DENTRY  DB      32*15 DUP (?)           ;Entry area - 15 @ 32 bytes each

DPD     ENDS

; OSN block offsets
OSN     STRUC

OIDENT  DB      3 DUP (?)               ;Block ID
OBLKNUM DB      ?                       ;Logical block number
OCKSUM  DW      ?                       ;Checksum
OMAXCNT DW      ?                       ;Maximum entry count
        DB      8 DUP (?)               ;Reserved header area
OENTRY  DB      16*31 DUP (?)           ;Entry area (ASCII), 31 @ 16 bytes each

OSN     ENDS

; Partition entry (in DPD) offsets
PART    STRUC

PFLAG   DB      ?                       ;Flag: $F0 means initialized
PUNIT   DB      ?                       ;Logical unit code 1=A, 2=B, etc.
PNAME   DB      8 DUP (?)               ;Name (ASCII)
POCCUR  DB      ?                       ;Occurrence number (always zero)
POSINDX DB      ?                       ;Index to O/S in DPD block
PFTRACK DW      ?                       ;First track number
PLTRACK DW      ?                       ;Last track number
PPASBLK DB      ?                       ;Number of PAS blocks (CP/M and CCP/M)
PDIRSIZ DB      ?                       ;Directory size code (CCP/M)
PCLUSTR DB      ?                       ;Cluster size code (MS-DOS)
PFATSIZ DB      ?                       ;# of FAT sectors (MS-DOS)
        DB      12 DUP (?)              ;Reserved for backup/restore (they say)

PART    ENDS

; This absolute segment describes the area where the secondary boot code will
; be put.  It does not actually end up in the object file.

OSBOOT  SEGMENT AT OSBSEG
        ORG     0
        ASSUME  CS:OSBOOT

OSSTART PROC    FAR
        NOP
OSSTART ENDP

OSBOOT  ENDS

CODE    SEGMENT
        ORG     0

        ASSUME  CS:CODE, DS:NOTHING, ES:NOTHING, SS:NOTHING

        DB      'S'                     ;This first byte required by PREBOOT

START:  CALL    SAVER                   ;Save all registers & flags
        PUSH    CS                      ;Now copy CS to DS
        POP     DS                      ; ..
        ASSUME  DS:CODE                 ;Now we can assume that
        MOV     WORD PTR SAVESP,SP      ;Save SP value after saved registers

; Move Z80 code into Z80 and start it up
        MOV     AL,ZRESET               ;Reset Z80
        OUT     DIAGPORT,AL             ; ..
        XOR     AX,AX                   ;Point ES at base page
        MOV     ES,AX                   ; ..
        MOV     DI,Z80DST               ;Point at where (on base page) it goes
        MOV     SI,Z80SRC               ;Point at where Z80 code is
        MOV     CX,Z80LEN               ;How many bytes there are
        CLD                             ;Direction = forward
        REP MOVSB                       ;Move all bytes
        MOV     AL,ZSTART               ;Startup Z80, it will execute new code
        OUT     DIAGPORT,AL             ; ..

        MOV     DI,DIS_CURSOR           ;Disable cursor
        INT     28H                     ; ..

        CALL    SETISR                  ;Set up to allow / trap interrupts
        MOV     BYTE PTR INTFLG,0       ;Initialize interrupt flag to zero

; The primary boot code has left the HOM block data starting at address 1500
; on the base page.  It has also initialized the controller.  Therefore,
; we don't need to initialize the controller or read the HOM block again.
; We'll just point ourselves at the HOM block and go for it.

        XOR     AX,AX                   ;Point at base page
        MOV     ES,AX                   ; ..
        MOV     DI,1500H                ;Place where HOM block is

        MOV     SI,OFFSET HOMTXT        ;Point at block type
        CALL    CHKBLK                  ;Check block type and checksum

        MOV     BL,ES:[DI].HSURFS       ;Get number of surfaces drive has
        XOR     BH,BH                   ;High order is always zero
        MOV     WORD PTR NUMSURF,BX     ;Store for future reads

;See if auto-boot partition is set up.  If there is one, we don't need to
; bother with reading the DPD and OSN blocks, we can just go to it and
; start the boot process.

        MOV     AL,ES:[DI].HABFLG       ;Get auto boot flag/unit number
        CMP     AL,0FFH                 ;Flagged as no autoboot?
        JE      NOAUTO                  ;Yes - go do menu, etc.
        MOV     BX,ES:[DI].HABTRK       ;Get auto boot track number
        OR      BX,BX                   ;Is it zero?
        JE      NOAUTO                  ;If so, no auto boot
        JMP     GOBOOT                  ;Looks like we can autoboot - go do it

NOAUTO: MOV     AX,ES:[DI].HDPDTRK      ;Get DPD track number
        MOV     DPDTRK,AX               ;Store in global area
        MOV     AL,ES:[DI].HDPDSEC      ;Get DPD sector number
        MOV     DPDSEC,AL               ;Store
        MOV     AX,ES:[DI].HDPDSIZ      ;Get DPD length
        MOV     DPDSIZ,AX               ;Store it
        MOV     AX,ES:[DI].HOSNTRK      ;Do the same thing for OSN area
        MOV     OSNTRK,AX
        MOV     AL,ES:[DI].HOSNSEC
        MOV     OSNSEC,AL
        MOV     AX,ES:[DI].HOSNSIZ
        MOV     OSNSIZ,AX

        MOV     AX,CS                   ;Point ES at same page as all else
        MOV     ES,AX                   ; ..

;Now make sure there is exactly one DPD block and one OSN block.  If that's
; not the way it is, we have an error and can't go on.
        CMP     BYTE PTR DPDSIZ, 1      ;Is there exactly one DPD block?
        JE      CMPOSN                  ;Yes - check OSN
        JMP     ERRRET                  ;No - return with error
CMPOSN: CMP     BYTE PTR OSNSIZ, 1      ;Is there exactly one OSN block?
        JE      RDDPD                   ;Yes - continue
        JMP     ERRRET                  ;No - return with error

RDDPD:  MOV     BX,DPDTRK               ;Get DPD track number
        MOV     CL,DPDSEC               ; and sector number
        MOV     DI,OFFSET DPDBUFF       ;Point at buffer for DPD (n.b. ES=DS)
        CALL    READSC                  ;Go read it
        MOV     SI,OFFSET DPDTXT        ;Point at expected block tag
        CALL    CHKBLK                  ;Make sure block checks out

RDOSN:  MOV     BX,OSNTRK               ;Now get OSN track number
        MOV     CL,OSNSEC               ; and sector number
        MOV     DI,OFFSET OSNBUFF       ;Point at buffer for OSN
        CALL    READSC                  ;And go read it
        MOV     SI,OFFSET OSNTXT        ;We expect OSN tag
        CALL    CHKBLK                  ;Check it out

;If we get this far, then we have successfully read the DPD and OSN blocks.
;Now see how many partitions there are.  If there are none, we have an error.
;If there is exactly one, we can essentially do an auto-boot.
;If there's more than one, then we'll have to display the menu and get a
; choice from the user.

        MOV     AX,DPDBUFF.DENTCNT      ;Get partition entry count
        OR      AX,AX                   ;Are there any?
        JNZ     HAVEPART                ;Yes
        JMP     ERRRET                  ;No - can't boot then

HAVEPART:
        CMP     AX,1                    ;Exactly one partition?
        JNE     NEEDMENU                ;No - do menu
        MOV     BX,OFFSET DPDBUFF.DENTRY;Yes - point at first entry
        MOV     AL,BYTE PTR [BX].PUNIT  ;Get unit number
        MOV     BX,WORD PTR [BX].PFTRACK;And starting track number
        JMP     GOBOOT                  ;Go boot from this partition

NEEDMENU:
        ADD     AL,'0'                  ;Add digit bias to number of partitions
        CMP     AL,'9'                  ;Did we pass nine?
        JLE     SHOWMENU                ;No - go show menu
        MOV     AL,'9'                  ;Yes - max digit is nine
SHOWMENU:
        MOV     BYTE PTR HIDIGIT,AL     ;Save computed max digit (in message)
        MOV     SI,OFFSET HEADER        ;Clear & display constant parts of scrn
        CALL    OUTSTR                  ;Do it

;Now we want to display a line for each partition which is availalable.  We'll
; loop here for each partition.
        XOR     DX,DX                   ;Start at first partition (number zero)
SHPART: CLD                             ;Ensure fwd direction for string moves
        MOV     DI,OFFSET MLINE         ;Start by clearing menu line area
        MOV     CX,MLSIZE               ;The size of the area
        MOV     AL,' '                  ;Fill with spaces
        REP STOSB                       ;Fill area with with spaces

        MOV     BX,DX                   ;Get partition number
        MOV     CL,5                    ;Shift left by 5 bits is times 32
        SAL     BX,CL                   ;Form partition index
        ADD     BX,OFFSET DPDBUFF.DENTRY;Point BX at DPD entry

;First, display partition number.  This is the partition number we currently
; have plus 1 (we're zero-based), adjusted for ascii.  We'll put that in the
; display area.  If we are past partition number 9, we'll skip this part and
; just leave spaces.
        MOV     AX,DX                   ;Partition number
        CMP     AL,8                    ;Are we beyond internal # 8 (ext #9)?
        JG      SHPNAME                 ;Yes - just go do partition name
        ADD     AL,'1'                  ;No - adjust into ASCII range.
        MOV     DI,OFFSET MLINE         ;Point at beginning of line
        STOSB                           ;Store byte in string and advance ptr
        MOV     AL,'.'                  ;Follow by a period
        STOSB                           ; ..

SHPNAME:
        MOV     DI,OFFSET MLINE+4       ;Position for partition name
        LEA     SI,WORD PTR [BX].PNAME  ;Point at name in partition entry
        MOV     CX,8                    ;Length of name
        REP MOVSB                       ;Copy partition name

SHDRIVE:
        MOV     DI,OFFSET MLINE+17      ;Where drive indicator goes
        MOV     AL,BYTE PTR [BX].PUNIT  ;Get unit number
        ADD     AL,'A'-1                ;Adjust to make drive letter (1 = A)
        STOSB                           ;Put in output area
        MOV     AL,':'                  ;Follow by a colon
        STOSB                           ;In output area

SHOSNAME:
        MOV     DI,OFFSET MLINE+23      ;Where operating system name goes
        MOV     AL,BYTE PTR [BX].POSINDX;Get operating system name index
        XOR     AH,AH                   ;Clear high order
        MOV     CL,4                    ;Shift left 4 times -> times 16
        SHL     AX,CL                   ;Do it
        ADD     AX,OFFSET OSNBUFF.OENTRY;Adjust to point to OS name in OSN blk
        MOV     SI,AX                   ;Copy to place where we want it
        MOV     CX,16                   ;16 characters to move
        REP MOVSB                       ;Copy it all

SHDISP:
; We've constructed the line for output.  Now just send it to the screen
; at the appropriate line.
        CALL    SAVER                   ;Save registers - INT 28 destroys many
        MOV     AX,2                    ;Output characters only (no attrib)
        MOV     BX,DX                   ;Get partition number
        ADD     BL,7                    ;Add 7 to get line number
        MOV     BH,20                   ;Column number is always twenty
        MOV     CX,MLSIZE               ;Size of menu line
        MOV     SI,OFFSET MLINE         ;Point at beginning of line
        MOV     BP,DS                   ;Copy of DS needed in BP
        MOV     DI,WRITE_DATA           ;Function for "write data to screen"
        INT     28H                     ;Print the line using fast video

        CALL    RESTOR                  ;Get back saved registers
        INC     DX                      ;Next partition
        CMP     DX,WORD PTR DPDBUFF.DENTCNT ;Have we finished?
        JNE     SHPART                  ;If not, continue with next one

;We've built the menu.  Now turn on the display, which has been blanked up to
; now...
        MOV     AL,SCREENON             ;Turn on screen
        OUT     DIAGPORT,AL             ; ..

        XOR     BX,BX                   ;Initially, select first partition

;The main loop for partition selection starts here.  First, we'll set the
; attributes for the lines of the menu -- bold if it is the "selected" item
; and normal if it isn't.

SETATTRIB:
        XOR     DX,DX                   ;Start at the top
SALOOP: CALL    SAVER                   ;Save everything
        MOV     AX,1                    ;Set attributes only
        MOV     SI,OFFSET NORMBUF       ;Assume normal attributes
        CMP     BX,DX                   ;Is this the selected partition?
        JNE     SA2                     ;If not, leave it normal
        MOV     SI,OFFSET BOLDBUF       ;If so, use bold attributes instead
SA2:    MOV     BX,DX                   ;Get partition number
        ADD     BL,7                    ;Add 7 to get line number
        MOV     BH,20                   ;Column number is always twenty
        MOV     CX,MLSIZE               ;Size of menu line
        MOV     DX,SI                   ;Point to attributes
        MOV     BP,DS                   ;Copy of DS needed in BP
        MOV     DI,WRITE_DATA           ;Function for "write data to screen"
        INT     28H                     ;Set attributes using fast video
        CALL    RESTOR                  ;Get back saved registers
        INC     DX                      ;Next partition
        CMP     DX,WORD PTR DPDBUFF.DENTCNT ;Have we finished?
        JNE     SALOOP                  ;If not, continue with next one

;We've set the attributes so that the "current" selection is bolded.  Now
; wait for a character to see if we want to change the current selection
; (pointed to by BX) or if we want to start booting from the selected
; partition.

WAIT:   CALL    RAWCHR                  ;Get command character
        TEST    AH,1                    ;Is it a function key?
        JZ      NOTFUNC                 ;If not, continue
        CMP     AL,1                    ;It is a function - is it the DO key?
        JE      DOKEY                   ;If so, handle it
        CMP     AL,56H                  ;Is it keypad ENTER?
        JNE     NOTDO                   ;If so, handle like DO, else try more
DOKEY:  MOV     CL,5                    ;Multiply BX by 32 to get index
        SHL     BX,CL                   ; (shift left 5 is times 32)
        ADD     BX,OFFSET DPDBUFF.DENTRY;Point at DPD entry
        MOV     AL,BYTE PTR [BX].PUNIT  ;Get unit number
        MOV     BX,WORD PTR [BX].PFTRACK;And starting track number
        JMP     SHORT GOBOOT            ;Go boot from this partition

NOTDO:  CMP     AL,29H                  ;Is it downarrow?
        JNE     NOTDOWN                 ;No - try again
        MOV     AX,BX                   ;DOWNARROW - make copy of current in AX
        INC     AX                      ;Add one
        CMP     AX,WORD PTR DPDBUFF.DENTCNT ;Equal to limit?
        JL      OKDOWN                  ;No - go ahead and move down
BADKEY: CALL    BEEP                    ;Yes - say we can't do that
        JMP     SHORT WAIT              ;And go wait some more
OKDOWN: MOV     BX,AX                   ;Move incremented value
        JMP     SHORT SETATTRIB         ;Move bolded line and continue

NOTDOWN:CMP     AL,27H                  ;Is it uparrow?
        JNE     NOTUP                   ;No - keep trying
        OR      BX,BX                   ;Yes - already at the top?
        JZ      BADKEY                  ;Yes - go handle bad arrow
        DEC     BX                      ;No - move up one slot
        JMP     SHORT SETATTRIB         ;And go to it

NOTUP:  CMP     AL,2FH                  ;Less than keypad zero?
        JL      BADKEY                  ;If so, bad key
        CMP     AL,4AH                  ;If not, higher than kekypad nine?
        JG      BADKEY                  ;If so, bad key
        SUB     AL,2FH                  ;If not, keypad digit - adjust to zero
        XOR     AH,AH                   ;Set high order part to zero
        MOV     CL,3                    ;Divide by 3 to bring values together
        DIV     CL                      ; ..
        ADD     AL,'0'                  ;Add ascii bias to quotient
;       JMP     NOTFUNC                 ;Fall thru to code below, not func key

NOTFUNC:
        CMP     AL,0DH                  ;Is it RETURN key?
        JZ      DOKEY                   ;Handle just like DO key
        CMP     AL,'1'                  ;Is key digit one?
        JL      BADKEY                  ;If less than that, bad key
        CMP     AL,BYTE PTR HIDIGIT     ;See if within range of good digits
        JG      BADKEY                  ;If too high, no good either
        SUB     AL,'1'                  ;Otherwise, adjust to make index
        XOR     AH,AH                   ;Clear high order part
        MOV     BX,AX                   ;Move new index into BX
        JMP     SETATTRIB               ;Go set new attributes and wait more

GOBOOT: MOV     DX,BX                   ;Copy boot track number to DX
        MOV     CL,AL                   ;Get boot drive number indicator
        DEC     CL                      ;Adjust so that A=0, etc.
        XOR     AX,AX                   ;Go to segment 0
        MOV     ES,AX                   ; ..
        MOV     ES:BYTE PTR 0FFAH,CL    ;Store boot indicator for O/S loader

        MOV     AX,OSBSEG               ;Set up segment number for O/S loader
        MOV     ES,AX                   ; ..
        XOR     DI,DI                   ;Clear starting address
        MOV     CL,2                    ;Sector 2 is first real data

BLOOP:  CALL    READSC                  ;Read a sector of boot loader
        ADD     DI,0200H                ;Point buffer at next sector area
        INC     CL                      ;Increment sector number
        CMP     CL,16                   ;Have we done all sectors?
        JLE     BLOOP                   ;Continue until we have
        CMP     BX,DX                   ;Is this the first track?
        JNE     CHKLDR                  ;No - we're done - check the loader
        INC     BX                      ;Yes - go to next track now
        MOV     CL,1                    ;Starting at sector 1
        JMP     SHORT BLOOP             ;Continue now with second track

CHKLDR: XOR     DI,DI                   ;Point back at beginning of O/S loader
        MOV     AL,ES:[DI]              ;Get first byte
        CMP     AL,0E9H                 ;Is it a JMP instruction?
        JZ      CALLOS                  ;Yes - looks ok, call O/S loader
        JMP     SHORT ERRRET            ;No - error - return

CALLOS: MOV     DI,ENA_CURSOR           ;Re-enable cursor
        INT     28H                     ; ..

        CALL    OSSTART                 ;Go to start of O/S loader -- if it
                                        ; returns, continue to error code
                                        ; on next page.

ERRPRC  PROC    FAR                     ;Routine to end with error, defined as
                                        ; FAR because that's how our whole
                                        ; routine is called.  This is the only
                                        ; return, however.
ERRRET: CALL    RSTISR                  ;Put old data back in int vectors
        MOV     SP,CS:SAVESP            ;Get back saved stack pointer
        CALL    RESTOR                  ;Restore saved registers
        RET                             ;Return (far) to indicate error
ERRPRC  ENDP

;This routine reads a sector from the hard disk into the buffer pointed to
; by ES:DI.  The track number is passed in BX, the sector number in CL.

READSC: CALL    SAVER                   ;Save everything

        MOV     AL,1                    ;We want one sector
        OUT     WSECCNT,AL              ;Tell the controller that

        MOV     AL,CL                   ;Get passed sector number
        OUT     WSECT,AL                ;Tell the controller

        MOV     AX,BX                   ;Get passed track number
        XOR     DX,DX                   ;Clear high order of dividend

        DIV     WORD PTR NUMSURF        ;Divide track # by surfs -> cyl#/surf#

        OUT     WCYLL,AL                ;Store resulting cylinder number low
        MOV     AL,AH                   ; and high in controller
        OUT     WCYLH,AL                ; ...

        MOV     AL,DL                   ;Get remainder (head number)
        OR      AL,SEC512               ;Add in flags for 512 byte sectors
        OUT     WSDH,AL                 ;Send size/drive/head to controller

        MOV     AL,READCMD              ;Tell controller to read a sector
        OUT     WCSR,AL                 ; ..

        CALL    WAITFR                  ;Wait for completion
        CMP     AL,0FFH                 ;Did we get a timeout?
        JZ      ERRRET                  ;If so, give up and return

        IN      AL,WCSR                 ;Get drive status
        TEST    AL,21H                  ;Any error bits set?
        JNZ     ERRRET                  ;If so, return with error

RDOK:   MOV     CX,200H                 ;Count of bytes to get
        MOV     BP,SP                   ;Get copy of stack pointer
        MOV     DI,16[BP]               ;Get original (passed/saved) DI & ES
        MOV     ES,2[BP]                ; ..
RLOOP:  IN      AL,WDATA                ;Get next byte
        STOSB                           ;Store in destination buffer
        LOOP    RLOOP                   ;Continue until done

        MOV     AL,1                    ;Set buffer ready bit to say we're done
        OUT     SECCSR,AL               ; ..
        MOV     CX,100                  ;Wait for controller to settle
        NOP                             ;(Note there should be no command end
        LOOP    $-1                     ; interrupt as we clear the "I" bit
                                        ; in the read command)

        CALL    RESTOR                  ;Restore saved registers
        RET                             ;And return

;This routine waits a while for a hard disk operation to complete.  It returns
; 0 in AX if the operation completed, or 0FF (hex) if the operation timed out.

WAITFR: MOV     CX,0F000H               ;Number of repetitions for wait
WFLOOP:
        DB      0E9H,00,00              ;Waste some time (these are long
        DB      0E9H,00,00              ; jumps to the next address)
        DB      0E9H,00,00
        DB      0E9H,00,00
        DB      0E9H,00,00
        DB      0E9H,00,00
        DB      0E9H,00,00
        CMP     BYTE PTR INTFLG,0       ;Has interrupt occurred yet?
        LOOPZ   WFLOOP                  ;If not, wait some more or time out
        CMP     BYTE PTR INTFLG,0       ;Did interrupt happen?
        JNZ     WFRET                   ;If so, we're OK - return
        MOV     AL,0FFH                 ;If not, return nonzero for error
        RET                             ; ..

WFRET:  MOV     BYTE PTR INTFLG,0       ;Reset interrupt flag for next time
        XOR     AL,AL                   ;Indicate no error (return zero)
        RET                             ;All done - return

;Here is the interrupt service routine which handles interrupts from the
; winchester drive.

INTSVC: PUSH    AX                      ;Save register we will use
        IN      AL,WCSR                 ;Read command/status reg to clear int
        MOV     BYTE PTR CS:INTFLG,0FFH ;Indicate interrupt happened
        POP     AX                      ;Restore saved register
        IRET                            ;Return from interrupt

;SETISR saves the old contents of the winchester interrupt vector and replaces
; it with a pointer to our service routine.  RSTISR sets it back (used if we
; must return because of an error).

SETISR: XOR     AX,AX                   ;Point at base page
        MOV     ES,AX                   ;With ES register
        CLI                             ;No interrupts while we change stuff
        MOV     AX,WORD PTR ES:WVECTOR  ;Get current interrupt vector
        MOV     WORD PTR SAVVEC,AX      ;Save in our save area
        MOV     AX,WORD PTR ES:WVECTOR+2;Do both words
        MOV     WORD PTR SAVVEC+2,AX    ; ..
        MOV     WORD PTR ES:WVECTOR,OFFSET INTSVC ;Now replace with our routine
        MOV     WORD PTR ES:WVECTOR+2,CS; ..
        STI                             ;Now interrupts are allowed
        RET                             ;Back we go

RSTISR: XOR     AX,AX                   ;Base page
        MOV     ES,AX
        CLI                             ;Disallow interrupts
        MOV     AX,WORD PTR SAVVEC      ;Get saved interrupt vector value
        MOV     WORD PTR ES:WVECTOR,AX  ;And put back in vector
        MOV     AX,WORD PTR SAVVEC+2    ;Both words
        MOV     WORD PTR ES:WVECTOR+2,AX; ..
        STI                             ;Permit interrupts again
        RET                             ;Done

; CHKBLK checks the block pointed to by ES:DI for correct checksum (all words
; must add to 0) and for block type (3 characters) pointed to by DS:SI.  Jumps
; to error code if this fails, otherwise returns so we can continue.  Preserves
; DI on return, all other (non-segment) registers are considered expendable.

CHKBLK: PUSH    DI                      ;Save address of data
        MOV     CX,3                    ;Three characters to compare
        CLD                             ;Forward direction
        REPZ CMPSB                      ;Compare up to three bytes
        JZ      CHKBLK2                 ;If they match, continue
        JMP     ERRRET                  ;Otherwise, return with error

CHKBLK2:
        MOV     CX,256                  ;256 words in a block
        XOR     AX,AX                   ;Start with zero
        MOV     BP,SP                   ;Get saved block start address
        MOV     DI,[BP]

CBLOOP: ADD     AX,ES:[DI]              ;Add one word
        ADD     DI,2                    ;Next word
        LOOP    CBLOOP                  ;Continue until all 256 words done

        POP     DI                      ;Restore block address
        OR      AX,AX                   ;See what we have left
        JZ      CBOK                    ;If zero, we're OK
        JMP     ERRRET                  ;Otherwise, checksum error

CBOK:   RET

;OUTSTR takes a string pointed to by DS:SI and writes it, a character at a
; time, to the screen using ROM Level-2 output calls.  The string is terminated
; by a byte containing zero.

OUTSTR: CALL    SAVER                   ;Save everything

OUTSL:  CLD                             ;Go forward
        LODSB                           ;Get next character
        OR      AL,AL                   ;Are we done?
        JZ      OSRETN                  ;If so, return
        PUSH    SI                      ;If not, Save address of next item
        XOR     DI,DI                   ;And send character to output
        INT     28H                     ; ..
        POP     SI                      ;Restore saved address
        JMP     SHORT OUTSL             ;And go to next

OSRETN: CALL    RESTOR                  ;Restore saved registers
        RET                             ;Return - done

;BEEP rings the bell (beeps the beeper) on the keyboard.
BEEP:   CALL    SAVER                   ;Save registers
        MOV     DI,RING_BELL            ;Ring bell function
        INT     28H                     ;Go do it
        CALL    RESTOR                  ;Get registers back
        RET                             ;Return

;RAWCHR gets a "raw" (16-bit) keyboard character and returns it in AX
RAWCHR: CALL    SAVER                   ;Save everything
RCLOOP: MOV     DI,LEV1_INP             ;Level 1 input function
        INT     28H                     ;Do it
        OR      CL,CL                   ;Did we get anything?
        JZ      RCLOOP                  ;If not, loop around and wait
        CMP     CL,1                    ;No return due to pending level 2 chrs?
        JNE     RCRETN                  ;Nah...we have data - return
RCEMPT: MOV     DI,LEV2_INP             ;Yes - do a level 2 input to clear buff
        INT     28H                     ; ..
        OR      CL,CL                   ;Did we get anything?
        JZ      RCLOOP                  ;No - now do level 1 input again
        JMP     SHORT RCEMPT            ;Yes - go do more level 2 input

RCRETN: MOV     BP,SP                   ;Get copy of top of stack address
        MOV     WORD PTR 12[BP],AX      ;Copy return value to AX restore slot
        CALL    RESTOR                  ;Restore saved registers (& new AX)
        RET                             ;Done - return now

;SAVER saves all registers (and flags) on the stack.  RESTOR restores them.

SAVER:  PUSHF                           ;Save flags
        PUSH    DI                      ;And all registers...
        PUSH    SI
        PUSH    AX
        PUSH    BX
        PUSH    CX
        PUSH    DX
        PUSH    DS
        PUSH    ES
        PUSH    BP
        MOV     BP,SP                   ;Get copy of stack pointer now
        MOV     AX,20[BP]               ;Find original return address on stack
        PUSH    AX                      ;Push it there
        MOV     AX,12[BP]               ;Now get back correct BP value
        RET                             ;Return to saved address

RESTOR: POP     AX                      ;Pop return address
        MOV     BP,SP                   ;Get copy of stack pointer
        MOV     20[BP],AX               ;Replace return address down stack with
                                        ; correct one
        POP     BP                      ;Now restore all registers
        POP     ES
        POP     DS
        POP     DX
        POP     CX
        POP     BX
        POP     AX
        POP     SI
        POP     DI
        POPF                            ;And flags
        RET                             ;And return to the right place

;DATA AREA

INTFLG  DB      0                       ;Flag set by our interrupt service

NUMSURF DW      4                       ;Number of surfaces drive has (init 4)

SAVESP  DW      0                       ;Saves original SP for error exit
SAVVEC  DW      0                       ;Saved copy of original interrupt
        DW      0                       ; vector contents in these two words

; Saved storage locations for DPD and OSN blocks
DPDTRK  DW      0                       ;DPD Track number
DPDSEC  DB      0                       ;DPD Sector number
DPDSIZ  DW      0                       ;DPD length in sectors
OSNTRK  DW      0                       ;OSN Track number
OSNSEC  DB      0                       ;OSN Sector number
OSNSIZ  DW      0                       ;OSN length in sectors

; Text strings for beginning of the various blocks (block IDs)
HOMTXT  DB      'HOM'
DPDTXT  DB      'DPD'
OSNTXT  DB      'OSN'

; Buffers where DPD and OSN blocks are read
DPDBUFF DB      512 DUP (0)

OSNBUFF DB      512 DUP (0)

;Strings for output to screen...

; This macro expands to a cursor position sequence for the indicated line and
; column.
POSIT   MACRO   LINE,COL
        DB      ESC
        DB      '[&LINE;COL&H'
        ENDM

ESC     EQU     1BH
CR      EQU     0DH
LF      EQU     0AH

HEADER  DB      ESC
        DB      '[H'
        DB      ESC
        DB      '[J'
        POSIT   1,15
        DB      'Rainbow 100 Hard Disk Start-Up Menu (WUTIL version)'
        POSIT   2,5
        DB      70 DUP ('-')
        POSIT   4,15
        DB      'Your hard disk contains the following partitions:'
        POSIT   6,20
        DB      '    Name       Drive   Operating System'
        POSIT   22,5
        DB      70 DUP ('-')
        POSIT   23,4
        DB      'Use the UP and DOWN arrow keys or digits 1 thru '
HIDIGIT DB      '9 to select a partition.'
        POSIT   24,2
        DB      'Then press the DO, RETURN, or keypad ENTER key to boot from'
        DB      ' that partition.'
        DB      0

; This is the area where each menu line is built
MLINE   DB      39 DUP (' ')
MLSIZE  EQU     $-MLINE

; Attribute buffers used to set menu lines to bold or normal
BOLDVAL EQU     0CH
NORMVAL EQU     0EH

BOLDBUF DB      MLSIZE DUP (BOLDVAL)
NORMBUF DB      MLSIZE DUP (NORMVAL)


; Go to place where Z80 code goes and fill it with zeroes.  This will be
; replaced by "real" Z80 data by the BLDSBOOT.BAT procedure.
        ORG     Z80SRC
        DB      Z80LEN DUP (0)

CODE    ENDS

        END
