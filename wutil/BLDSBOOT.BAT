ECHO OFF
IF EXIST SECBOOT.LDX DEL SECBOOT.LDX
IF EXIST Z80CODE.DAT DEL Z80CODE.DAT
ECHO 	Assembling secondary boot code
MASM SECBOOT SECBOOT %1 %2;
IF ERRORLEVEL 1 GOTO DONE
ECHO 	Linking secondary boot code.  The "no stack segment" message is
ECHO 	normal and no cause for concern.
LINK SECBOOT,SECBOOT;
IF ERRORLEVEL 1 GOTO DONE
ECHO 	**********************************************************************
ECHO 	Please put a current BOOTABLE MS-DOS system disk (your current
ECHO 	version, version 2.05 or later) in drive A.
ECHO 	**********************************************************************
PAUSE
ECHO 	The secondary boot loader will now be constructed.  Please note any
ECHO 	error messages from this procedure:
DEBUG <BLDSBOOT.DEB
ECHO 	The secondary boot loader has been built.
:DONE
IF EXIST Z80CODE.DAT DEL Z80CODE.DAT
IF EXIST SECBOOT.OBJ DEL SECBOOT.OBJ
IF EXIST SECBOOT.EXE DEL SECBOOT.EXE
