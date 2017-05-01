ECHO OFF
IF EXIST PREBOOT.LDX DEL PREBOOT.LDX
ECHO 	Assembling primary boot code
MASM PREBOOT PREBOOT %1 %2;
IF ERRORLEVEL 1 GOTO DONE
ECHO 	Linking primary boot code.  The "no stack segment" message is normal
ECHO 	and no cause for concern.
LINK PREBOOT,PREBOOT;
IF ERRORLEVEL 1 GOTO DONE
ECHO 	The primary boot loader will now be constructed.  Please note any
ECHO 	error messages from this procedure:
DEBUG <BLDPBOOT.DEB
ECHO 	The primary boot loader has been built.
:DONE
IF EXIST PREBOOT.OBJ DEL PREBOOT.OBJ
IF EXIST PREBOOT.EXE DEL PREBOOT.EXE
