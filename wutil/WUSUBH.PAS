{** file wusubh.pas © Copyright 1986 Anthony G. Camas, all rights reserved **}

{ **************************************************************************
                          MS-DOS INTERFACE ROUTINES
  ************************************************************************** }

{ GetPATHString - Finds definition of PATH in environment and stores globally }
procedure GetPATHString;
type
  PATHTagArray = Array [0..4] of Char;
const
  PATHTag = 'PATH=';
var
  PATHPtr :^PATHTagArray;
  sg, off :Integer;
  Current :String [255];
begin
  { Set up segment pointer to area containing environment variables }
  sg := MemW[Cseg:$2C];
  { Start at the beginning of this area }
  off := 0;
  PATHPtr := Ptr(sg, off);
  while (Mem[sg:off] <> 0) and (PATHPtr^ <> PATHTag) do
  begin
    repeat
      off := off + 1;
    until Mem[sg:off] = 0;
    off := off + 1;
    PATHPtr := Ptr(sg, off);
  end;
  { When we get here, we've either found the PATH= string, or we've found
    the end of the environment strings area. }
  If Mem[sg:off] = 0 then
  begin
    { No PATH= entry found.  Use nothing. }
    PATHString := '';
    Exit;
  end;
  { Found it.  Copy it to the global string which will keep the data. }
  off := off + 5;               { skip PATH= }
  PATHString[0] := Char(0);     { initial length of zero }
  While Mem[sg:off] <> 0 do
  begin
    PATHString[0] := Succ(PATHString[0]); { increment length }
    PATHString[Ord(PathString[0])] := Char(Mem[sg:off]); { copy character }
    off := off + 1; { next position in memory }
  end;
  { Get current directory and then append to the beginning of the path string }
  GetDir (0, Current);
  If Length(PATHString) > 0 then
    PathString := Concat (Current, ';', PATHString)
  else
    PathString := Current;
end {GetPATHString};

{ FindOnPATH - Locates arbitrary file using PATH string in global variable.
  This procedure searches for a file, whose name is passed, using first the
  current working directory and then the various directories making up the
  current PATH.  It returns, in the string variable passed to it, the expanded
  file specification of the file that was found, including the path spec.  If
  the file was not found in any of the specified places, it returns a null
  string.  }
procedure FindOnPATH (Var FileName :Str255);
var
  I, J        :Integer;
  CurrentPath :String [255];
  FileSpec    :String [255];
  PathsLeft   :String [255];
  DummyFile   :File;
begin
  PathsLeft := PATHString;
  While Length (PathsLeft) > 0 do
  begin
    { Find semicolon delimiting end of next path entry. }
    I := Pos (';', PathsLeft);
    { If we found nothing, copy the whole thing.  Otherwise, extract the
      individual directory path and remove it (and the semicolon) from the
      list. }
    If I = 0 then
    begin
      CurrentPath := PathsLeft;
      PathsLeft := '';
    end
    else
    begin
      CurrentPath := Copy (PathsLeft, 1, I-1);
      Delete (PathsLeft, 1, I);
    end;
    { If the current path we extracted is blank or just a dot (current
      directory), skip it.  We've already checked it previously. }
    If (CurrentPath <> '') and (CurrentPath <> '.') then
    begin
      { If path does not end with a backslash, add it so we can append our
        filename }
      If Copy (CurrentPath, Length(CurrentPath), 1) <> '\' then
        CurrentPath := Concat (CurrentPath, '\');
      { Now try and find the specified file. }
      FileSpec := Concat (CurrentPath, FileName);
{$I-}
      Assign (DummyFile, FileSpec);
      Reset (DummyFile);
{$I+}
      If IOResult = 0 then
      begin
        { We found the file!  Return the full filespec. }
        FileName := FileSpec;
        Close (DummyFile);
        Exit;
      end;
    end;
  end;
  { If we get here, we did not find the file!  Return a null string. }
  FileName := '';
end {FindOnPATH};

{ FindOverlay - Locates overlay file and sets overlay path there }
procedure FindOverlay;
const
  OverlayName = 'WUTIL.000';
  OverlayNameLength = 9;
var
  OvrSpec       :Str255;
begin
  { Try to find the overlay file using the usual path stuff }
  OvrSpec := OverlayName;
  FindOnPATH (OvrSpec);
  { If we found it, strip off the file name part and set the overlay path
    appropriately.  If not, print an error and abort.  We can't run without our
    overlay. }
  If Length (OvrSpec) > 0 then
  begin
    OvrSpec := Copy (OvrSpec, 1, Length(OvrSpec)-9);
    { Now set the overlay path according to what we got and exit.  We have
      to remove the trailing backslash from this path unless it is the only
      one (indicating top level directory). }
    If Pos ('\', OvrSpec) <> Length (OvrSpec) then
      OvrSpec[0] := Pred(OvrSpec[0]); { Shorten by one char }
    OvrPath (OvrSpec);
    Exit;
  end;
  { If we get here, we did not find the overlay file!  Say so and exit. }
  WriteLn (^G'UNABLE TO LOCATE OVERLAY FILE WUTIL.000!');
  WriteLn ('This file must be in your current directory or on your PATH');
  Halt (1);
end {FindOverlay};

{ **************************************************************************
                   SPECIAL MS-DOS BIOS INTERFACE FUNCTIONS
  ************************************************************************** }

{ FindHDDriver - Step through the device driver chain and locate the hard
  disk drivers.  First step through the user loaded drivers to see, if the
  CHS driver is present.  Set the TwoDrives flag accordingly (TRUE if present,
  FALSE if not present).  Then continue with the standard drivers and locate
  the standard hard disk driver.  Set up pointers to both hard disk driver's
  entry points.  The code attempts to make sure it finds what is expected (in
  the standard driver chain) and returns a function value indicating whether
  it succeeded or not.  It returns TRUE if it succeeded in finding the expected
  standard drivers or FALSE if it failed.  If this function fails, calls to
  DoHDFunction will not work; in other words, if this fails, it is impossible
  to continue. }
function FindHDDriver :Boolean;
const
  CHSString :String[25] = 'C.H.S. External Hard Disk';
type
  DeviceTableEntry = record
    NextOffset, NextSegment     :Integer; { Ptr to next driver }
    Flags                       :Integer;
    Strategy                    :Integer;
    Interrupt                   :Integer;
    DeviceName                  :Array [0..7] of Char;
  end;
var
  EntryPtr                      :^DeviceTableEntry;
  CHSStringLength               :Integer;
  SysVarSeg                     :Integer;
  SysVarOfs                     :Integer;
  Segment                       :Integer;
  Offset                        :Integer;
  Limit                         :Integer;
  I                             :Integer;
begin
  TwoDrives        := FALSE;
  CHSStringLength  := Length(CHSString);
  If MSDOSVersion < 3 then I := 23 else I := 34;
  { We'll find the beginning of the device driver list by means of an undocu-
    mented function call 52H of INT21H.  The call returns a pointer to the
    SYSVAR block in ES:BX.  At offset 34D (23D in MSDOS version 2) this block
    contains a far pointer to the first device driver in the list. }
  Registers.AX     := $5200;
  MSDOS(Registers);
  SysVarSeg        := Registers.ES;
  SysVarOfs        := Registers.BX;
  Offset           := MemW[SysVarSeg:SysVarOfs+I];
  Segment          := MemW[SysVarSeg:SysVarOfs+I+2];
  EntryPtr         := Ptr(Segment,Offset);
  { Now we'll step through the list until we either hit the CHS driver or hit
    the first standard device driver in the BIOS segment. }
  while (Seg(EntryPtr^) <> BIOSSeg) and (not TwoDrives) do
  begin
    if EntryPtr^.Flags = CHSAttrib then
    begin
      { Got a driver with the same attribute as the CHS driver.  Now make sure
        it really is the CHS driver. }
      Offset := Ofs(EntryPtr^) + $800;
      Limit  := Offset + $100;
      while (Offset < Limit) and (not TwoDrives) do
      begin
        if Chr(Mem[Seg(EntryPtr^):Offset]) <> CHSString[1] then
          Offset := Offset + 1
        else
        begin
          I := 2;
          while (I < CHSStringLength)
            and (Chr(Mem[Seg(EntryPtr^):Offset+I-1]) = CHSString[I]) do I:=I+1;
          if I <> CHSStringLength then Offset := Offset + 1
          else
          begin
            TwoDrives := TRUE;
            HDStrategy[2] := Ptr(Seg(EntryPtr^),EntryPtr^.Strategy);
            HDInterrupt[2] := Ptr(Seg(EntryPtr^),EntryPtr^.Interrupt);
          end;
        end;
      end;
    end;
    EntryPtr := Ptr(EntryPtr^.NextSegment,EntryPtr^.NextOffset);
  end;
  { We're pointing at the first standard driver now.  We'll step through
    the chain now to make sure everything is the way we expect it.  Depen-
    ding on the MS-DOS version we expect to find, in turn, either AUX, PRN,
    CLOCK, floppy (for all MS-DOS versions prior V3.10, including V3.10 test
    versions prior V3.10.017), or AUX, COM1, PRN, LPT1, CLOCK, floppy (for
    MS-DOS V3.10).  The floppy driver will have a small number in the first
    byte of the device name field. }
  If EntryPtr^.DeviceName <> 'CON     ' then
  begin
    WriteLn ('**ERROR FindHDDriver - CON');
    FindHDDriver := False;
    Exit;
  end;
  EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
  If EntryPtr^.DeviceName <> 'AUX     ' then
  begin
    WriteLn ('**ERROR FindHDDriver - AUX');
    FindHDDriver := False;
    Exit;
  end;
  { If the next entry is COM1, we're running on MS-DOS V3.10.  In this case
    we'll set a flag to look for the LPT1 entry later, as well. }
  EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
  If EntryPtr^.DeviceName = 'COM1    ' then
    begin
      LongChain := TRUE;
      EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
    end
    else LongChain := FALSE;

  If EntryPtr^.DeviceName <> 'PRN     ' then
  begin
    WriteLn ('**ERROR FindHDDriver - PRN');
    FindHDDriver := False;
    Exit;
  end;
  { If we have found COM1 earlier, the next driver must be LPT1 }
  If LongChain = TRUE then
  begin
    EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
    If EntryPtr^.DeviceName <> 'LPT1    ' then
    begin
      WriteLn ('**ERROR FindHDDriver - LPT1');
      FindHDDriver := False;
      Exit;
    end;
  end;
  EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
  If (EntryPtr^.DeviceName <> 'CLOCK   ') and
     (EntryPtr^.DeviceName <> 'CLOCK$  ') then
  begin
    WriteLn ('**ERROR FindHDDriver - CLOCK/CLOCK$');
    FindHDDriver := False;
    Exit;
  end;
  EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset);
  If Ord(EntryPtr^.DeviceName[0]) > 4 then
  begin
    WriteLn ('**ERROR FindHDDriver - Floppy Driver');
    FindHDDriver := False;
    Exit;
  end;
  { We've found the floppy driver entry.  If the hard disk driver was installed
    in MS-DOS, we'll have an entry for it next.  If it wasn't (because the
    disk wasn't initialized or didn't have MS-DOS partitions), we'll assume
    it immediately follows the floppy entry.  In either case, we'll then check
    what we have to make sure it looks like what we want. }
  If (EntryPtr^.NextSegment <> -1) then
    EntryPtr := Ptr (EntryPtr^.NextSegment, EntryPtr^.NextOffset)
  else
    EntryPtr := Ptr (Seg(EntryPtr^), Ofs(EntryPtr^) + 18);
  { Now see if what we found appears to be the right thing. }
  If ((EntryPtr^.Flags AND $E00F) <> $6000) or
     (Ord(EntryPtr^.DeviceName[0]) > 4) then
  begin
    WriteLn ('**ERROR FindHDDriver - Hard Disk Driver');
    FindHDDriver := False;
    Exit;
  end;
  { Looks like we found the hard disk driver.  Copy the pointers from the
    entry to our global storage locations. }
  HDStrategy[1]  := Ptr (Seg(EntryPtr^), EntryPtr^.Strategy);
  HDInterrupt[1] := Ptr (Seg(EntryPtr^), EntryPtr^.Interrupt);
  { Now we have to check, if our hard disk driver contains code, which prevents
    us from reading the disks HOM block.  This code has been added to the driver
    with MS-DOS V3.10 (and all test versions after V3.10.016).  Since the long
    device driver chain was implemented at the same time, we just use that flag
    to determine, if the code is there.  If it is we have to patch in a JMP
    instruction to skip that code. }
  If LongChain = TRUE then
  begin
    PatchLocation := EntryPtr^.Interrupt + 21;
    MemW[BIOSSeg:PatchLocation] := $10EB;
  end;
  { Now indicate we succeeded, and return. }
  FindHDDriver := True;
end {FindHDDriver};

{ FindISRFlag - Set up pointer to BIOS Winchester "Done" flag.
  This procedure tries to find the flag set by the MS-DOS Winchester Disk
  interrupt service routine by looking through the code in the routine to find
  the instruction which increments it.  It is passed the interrupt vector to
  trace to the service routine and returns TRUE if it finds the location and
  FALSE if it doesn't.  Global pointer variables ISRSeg and ISRFlag are
  set appropriately if the routine completes successfully. }
function FindISRFlag (Vector :Integer) :Boolean;
const
  ExpectedCodeLength = 4;
  ExpectedCode :array[1..ExpectedCodeLength] of Byte = ($50, $2E, $FE, $06);
var
  Segment    :Integer;
  ISROffset  :Integer;
  VectorAddr :Integer;
  I          :Integer;
begin
  { Determine location of interrupt vector and find the offset and segment
    for the service routine.  Note that if the CHS driver is loaded we end
    up at the flag of the CHS driver first. }
  if TwoDrives then CurrentDrive := 2 else CurrentDrive := 1;
  VectorAddr := Vector * 4;
  ISROffset := MemW[0:VectorAddr];
  Segment := MemW[0:VectorAddr+2];
  { Now trace through ISR and find the code we expect to see.  If we fail at
    any point to find what we expect, return FALSE and get out.  If we succeed,
    then after we're done the word we retrieve will be the offset of the flag
    we want. }
  for I := 1 to ExpectedCodeLength DO
  begin
    if Mem[Segment:ISROffset] <> ExpectedCode[I] THEN
    begin
      FindISRFlag := FALSE;
      Exit;
    end
    ELSE
      ISROffset := ISROffset + 1;
  end;
  { If we get here, we've found what we want. As a sanity check we'll make
    sure it's in the segment we expect it to be in. }
  ISRFlag[CurrentDrive] := Ptr(Segment, MemW[Segment:ISROffset]);
  if TwoDrives then Segment := Seg(HDStrategy[2]^) else Segment := BIOSSeg;
  if Seg(ISRFlag[CurrentDrive]^) <> Segment then
  begin
    FindISRFlag := FALSE;
    Exit;
  end;
  { If the CHS driver is loaded we have found it's flag before.  Now we need
    to find the flag of the standard HD driver. }
  if TwoDrives then
    begin
      CurrentDrive := 1;
      I := Segment;
      Segment := MemW[I:ISROffset-10];
      ISROffset := MemW[I:ISROffset-8];
      for I := 1 to ExpectedCodeLength DO
      begin
        if Mem[Segment:ISROffset] <> ExpectedCode[I] THEN
        begin
          FindISRFlag := FALSE;
          Exit;
        end
        ELSE
          ISROffset := ISROffset + 1;
      end;
      { If we get here, we've found what we want. As a sanity check we'll make
        sure it's in the segment we expect it to be in. }
      ISRFlag[CurrentDrive] := Ptr(Segment, MemW[Segment:ISROffset]);
      if Seg(ISRFlag[CurrentDrive]^) <> BIOSSeg then
      begin
        FindISRFlag := FALSE;
        Exit;
      end;
    end;
  FindISRFlag := TRUE;
end {FindISRFlag};

{ FindHDData - Set up pointers to certain BIOS data locations.
  This procedure tries to find various data items in the hard disk driver
  by searching for a specific routine that references them.  The routine
  searches for the hard disk BIOS routine "LDTSKF", which references a
  data item called MAXTRK.  Once the location of MAXTRK is found, then
  the locations of STEPRATE and PRECOMP, which follow MAXTRK, are computed.
  When this routine completes, it fills in pointer variables as appropriate
  if it succeeds in finding what it is looking for.  If it cannot find what
  it wants, it returns FALSE as a function value, else it returns TRUE. }
function FindHDData :Boolean;
const
  { This is the code which starts LDTSKF }
  ExpectedCodeLength = 5;
  ExpectedCode :array[0..ExpectedCodeLength] of Byte = ($B8, $01, $10,
                                                        $3B, $16, $00);
var
  Segment    :Integer;
  Offset     :Integer;
  I, J, Limit:Integer;
  Done       :Boolean;
begin
  { Search through the segment containing the hard disk driver for the first
    byte of the expected code.  When we find it, then look for the remaining
    bytes.  Continue to do this until we find the code sequence we want or
    until we hit the location where the ISR Flag is.  If we find this, we have
    gone too far. }
  Offset := 0;
  Segment := Seg(ISRFlag[CurrentDrive]^);
  Limit := Ofs(ISRFlag[CurrentDrive]^);
  Done := FALSE;
  WHILE (NOT Done) AND (Offset < Limit) DO
  begin
    IF Mem[Segment:Offset] <> ExpectedCode[0] THEN
      Offset := Offset + 1
    ELSE
    begin
      I := 1;
      WHILE (I < ExpectedCodeLength) AND
            (Mem[Segment:Offset+I] = ExpectedCode[I]) DO I := I + 1;
      IF I <> ExpectedCodeLength THEN Offset := Offset + 1 ELSE Done := TRUE;
    end;
  end;
  IF NOT Done THEN
  begin
    FindHDData := FALSE;
    EXIT;
  end;
  { We seem to have found the code we want.  Now pick up the next word, which
    is the offset of the first data word we are locating.  Then, as a sanity
    check, make sure it is less than the address where we found the reference
    to it, because if it's not, something is not the way we expect.  NOTE THAT
    THIS CODE USES SIGNED ARITHMETIC AND THAT THINGS WILL GO SERIOUSLY WRONG
    IF THE SEGMENT CONTAINING THE HARD DISK SERVICE IS BIGGER THAN 32K.
    However, this is not considered likely to ever happen in a million years,
    so we'll ignore this problem. }
  Offset := Offset + I;
  I := MemW[Segment:Offset];
  IF I >= Offset THEN
  begin
    FindHDData := FALSE;
    EXIT;
  end;
  { OK, it looks like we've found the address we're looking for.  Note that
    this is the address of MAXTRK, that STEPRATE follows in the next byte
    (I + 2) and PRECOMP follows in the next word (I + 3).  Set up all the
    pointers and then return to show we are OK. }
  HDMAXTRK[CurrentDrive] := Ptr(Segment, I);
  HDSTEPR[CurrentDrive] := Ptr(Segment, I + 2);
  HDPRECOMP[CurrentDrive] := Ptr(Segment, I + 3);
  FindHDData := TRUE;
end {FindHDData};

{ HDDone - Return TRUE when hard disk "done" interrupt occurs, FALSE if timeout.
  This procedure waits for the hard disk interrupt service routine to set
  its "done" flag.  It waits a maximum of about 8 second (the timeout
  period used by Rainbow MS-DOS).  Note that this timeout is dependent on
  execution of instructions and that the timeout constant may have to be
  adjusted if you are running on an NEC V20 chip.  Routine returns TRUE if
  completion was seen, FALSE if there was a timeout. }
function HDDone :Boolean;
const
  NumSec = 8;          { Number of seconds to wait }
  OneSec = 26000;      { (very) approx number of iterations per second }
var
  I, J :Integer;
begin
  FOR I := 1 TO NumSec DO FOR J := 1 TO OneSec DO IF ISRFlag[CurrentDrive]^ <> 0 THEN
  begin
    HDDone := TRUE;
    EXIT;
  end;
  HDDone := FALSE;
end {HDDone};

{ ManualSeek - Manually commands controller to seek to given cylinder.
  This procedure is used by the "park heads for shipping" option.  It tells
  the controller to seek to a given cylinder, which would normally be one
  greater than the maximum data cylinder.  A step rate is also passed, which
  should be retrieved from the HOM block so that the correct value is used. }
procedure ManualSeek (Cylinder :Integer; StepRate :Byte);
var
  Temp :Boolean;
begin
  { Load "task file" registers for command }
  Port[SectorCountPort]         := 1;
  Port[SectorNumberPort]        := 1;
  Port[CylinderLowPort]         := Lo(Cylinder);
  Port[CylinderHighPort]        := Hi(Cylinder);
  if (TwoDrives = TRUE) and (CurrentDrive = 2)
     then Port[SDHPort] := $28  { Head 0, Drive 1, 512 bytes/sector }
     else Port[SDHPort] := $20; { Head 0, Drive 0, 512 bytes/sector }
  { Set done flag to false }
  ISRFlag[CurrentDrive]^ := 0;
  { Send seek command to controller, wait for completion.  Status is
    inconsequential. }
  Port[CommandPort]             := ($70 OR (StepRate AND $0F));
  Temp := HDDone;
end {ManualSeek};


{ **************************************************************************
                    HIGHER-LEVEL PROCEDURES AND FUNCTIONS
  ************************************************************************** }

{ ReadMajorBlocks - Read HOM/OSN/DPD/BAT blocks into global buffers.
  Reads the four major blocks from the disk into the global buffer areas
  HOMBlock, OSNBlock, and DPDBlock, and loads the array SectorTable with
  information about good/bad sectors from the various BAT Blocks.  If all
  this succeeds, returns with function value TRUE.  Else, displays an error
  screen, waits for a key to be pressed, and then returns FALSE.   This routine
  will also check a few pieces of information about the disk's geometry.  Even
  if reading the HOM block succeeds, an error screen will be displayed and
  the value FALSE will be returned if some of the paremters do not match what
  we expect.  It is not necessary for the BAT and AST information to be correct.
  If there is a problem with this information, we'll warn the user but try
  to continue. }

function ReadMajorBlocks :Boolean;
var
  I, J          :Integer;
  ErrorSeen     :Boolean;
  BATError      :Boolean;
  ASTError      :Boolean;
  Trk           :Integer;
  Sec           :Byte;
  SaveDPD       :DPDEntry;
  TempString    :Str80;
begin
  { Set number of surfaces in home block to 4 until we have a chance
    to read the REAL number of surfaces.  This will let us do initial
    computations so we can read the home block, which is in track 0. }
  HOMBlock.HOM.Surfaces := 4;

  { Read home block and OSN/DPD blocks.  Exit if all OK. }

  ErrorSeen := Not(ReadHOMBlock (0, 2, HOMBlock));

  IF (Not ErrorSeen) then
  With HOMBlock.HOM do
  If (PartFlag <> $00) or
     (DPDLocation.Length <> 1) or
     (OSNLocation.Length <> 1) or
     (SectorsPerTrack <> 16) or
     (SectorSize <> 512) or
     (NumAltTracks > 50) or
     (Surfaces*Cylinders > (TrackLimit+1)) then
  begin
    DrawOutline;
    StartFastVideo (10, 4, AtBold, 78, 23);
    Center ('Your disk is incompatible with WUTIL');
    WriteLn;
    WriteLn;
    FVAttribute := AtNormal;
    WriteFastLn ('Sorry, but some parameters of your disk (according to data in');
    WriteFastLn ('the disk''s HOMe block) are incompatible with WUTIL.  In order');
    WriteFastLn ('for WUTIL to be used with a disk, the following must be true:');
    FVLMargin := 12;  FVAttribute := AtBold;
    WriteLn;
    WriteFastLn ('- The disk must have 512 byte sectors and 16 sectors/track');
    WriteFastLn ('- There can be no more than 50 alternate sector tracks');
    Str (TrackLimit+1, TempString);
    WriteFastLn (Concat ('- The entire disk capacity can be no more than ',
                         TempString,
                         ' tracks'));
    WriteFastLn ('- There must be exactly 1 DPD block and 1 OSN block');
    FVLMargin := 10;  FVAttribute := AtNormal;
    WriteLn;
    WriteFastLn ('If you believe all the above are true about your disk, then');
    WriteFastLn ('you should use the "Format and Initialize disk" option from');
    WriteFastLn ('the main menu.  This will write correct information on the');
    WriteFastLn ('disk and allow you to use it with WUTIL.');
    FVRow := 22;  FVAttribute := AtBold;
    Center ('Press any key to continue');
    I := RawChar;
    ReadMajorBlocks := FALSE;
    Exit;
  end;

  If not ErrorSeen then
    ErrorSeen := Not(ReadDPDBlock (HOMBlock.HOM.DPDLocation.Track,
                                   HOMBlock.HOM.DPDLocation.Sector, DPDBlock));

  If not ErrorSeen then
    ErrorSeen := Not(ReadOSNBlock (HOMBlock.HOM.OSNLocation.Track,
                                   HOMBlock.HOM.OSNLocation.Sector, OSNBlock));

  { Make sure the entries in the DPD block are in track order.  We don't like
    them any other way.  We'll sort them with a little shell sort here if
    we have to to get 'em right. }
  If Not ErrorSeen then
    With DPDBlock.DPD do For I := 1 To EntryCount-1 do
      For J := I + 1 to EntryCount do
        If Entry[I].FirstTrack > Entry[J].FirstTrack then
        begin
          SaveDPD := Entry[I];
          Entry[I] := Entry[J];
          Entry[J] := SaveDPD;
        end;

  { Check the OSN block's storage of operating system names.  If we find
    any names which contain nulls rather than spaces (other than in the
    first position), we'll change those to spaces so that the names will
    be space-padded on the right rather than null-padded.  This code is
    here to try and make OSN data written by "other" partitioning programs
    conform to the DEC standard and to WUTIL. }
  If Not ErrorSeen then
    With OSNBlock.OSN do for I := 0 to 30 do if Entry[I][0] <> #0 then
      For J := 1 to 15 do if Entry[I][J] = #0 then Entry[I][J] := ' ';

  { Read all the BAT blocks, one at a time, and load their data into our
    internal table of block data.  If any of this fails, we'll attempt to
    continue, but we'll warn the person that this is happening. }

  BATError := False;
  FillChar (SectorTable, 2*(TrackLimit+1), 0); { Initialize data to all zeroes }
  I := 0;
  Trk := HOMBlock.HOM.BATLocation.Track;
  Sec := HOMBlock.HOM.BATLocation.Sector;
  While (I < HOMBlock.HOM.BATLocation.Length) and (Not ErrorSeen)
    and (Not BATError) do
  begin
    BATError := Not(ReadBATBlock (Trk, Sec, I, TempBlock));
    If Not BATError then With TempBlock.BAT do For J := 0 to 249 do
      SectorTable[FirstSector.Track + J] := Entry[J];
    I := I + 1;
    NextSector (Trk, Sec);
  end;

  { Read all the AST blocks, one at a time, and load their data into our
    internal table of alternate sector data. }

  ASTError := False;
  FillChar (ASTVector, 3*800, 0); { Initialize data to all zeroes }
  I := 0;
  Trk := HOMBlock.HOM.ASTLocation.Track;
  Sec := HOMBlock.HOM.ASTLocation.Sector;
  While (I < HOMBlock.HOM.ASTLocation.Length) and (Not ErrorSeen)
    and (Not ASTError) do
  begin
    ASTError := Not(ReadASTBlock (Trk, Sec, I, TempBlock));
    If Not ASTError then With TempBlock.AST do For J := 0 to EntryCount-1 do
      With Entry[J] do if GoodSector <> 0 then
        ASTData[GoodTrackOffset, GoodSector] := BadSectorAddress;
    I := I + 1;
    NextSector (Trk, Sec);
  end;

  IF Not ErrorSeen then
  begin
    IF BATError then
    begin
      DrawOutline;
      Write (^G);
      StartFastVideo (3, 10, AtBold, 78, 23);
      Center ('Bad sector information could not be read from your disk.');
      FVAttribute := AtNormal;
      Center ('This means that either your disk is damaged in some way');
      Center ('or it has not been properly formatted and initialized.');
      Center ('WUTIL will attempt to continue this processing,');
      Center ('but any information about bad sectors is suspect.');
      FVRow := 22;  FVAttribute := AtBold;
      Center ('Press any key to continue');  
      I := RawChar;
    end;
    IF ASTError then
    begin
      DrawOutline;
      Write (^G);
      StartFastVideo (3, 10, AtBold, 78, 23);
      Center ('Alternate sector information could not be read from your disk.');
      FVAttribute := AtNormal;
      Center ('This means that either your disk is damaged in some way');
      Center ('or it has not been properly formatted and initialized.');
      Center ('WUTIL will attempt to continue this processing,');
      Center ('but any information about bad sectors is suspect.');
      FVRow := 22;  FVAttribute := AtBold;
      Center ('Press any key to continue');  
      I := RawChar;
    end;
    ReadMajorBlocks := TRUE;
    Exit;
  end;

  { We get here only if something failed (otherwise we would have executed
    the Exit, above.  Display an error screen and wait for a key to be hit.
    Then return FALSE. }

  DrawOutline;
  StartFastVideo (3, 10, AtBold, 78, 23);
  Center ('Your disk does not appear to be properly initialized');
  FVAttribute := AtNormal;
  Center ('Major information/partitioning data structures could not be read');
  Center ('from the disk.  This means that either your disk is damaged in');
  Center ('some way or it has not been formatted and initialized.  You must');
  Center ('use the "Format and Initialize disk" option from the main menu');
  Center ('with this disk before you can perform this function.');
  FVRow := 22;  FVAttribute := AtBold;
  Center ('Press any key to continue');  
  I := RawChar;

  ReadMajorBlocks := FALSE;

end {ReadMajorBlocks};

{ PrintGeneralDiskInfo - Prints data about disk from HOM block.
  This procedure prints much of the data which appears in the "general
  information" section of the output of the "print disk info" function.  It
  is incorporated as a procedure here because it is also used by the format
  disk routine to confirm that the desired format is being used. }
procedure PrintGeneralDiskInfo;
begin
  With HOMBlock.HOM do
  begin
    WriteFastLn (Concat('Volume ID: ',VolumeID));
    WriteFast ('System ID: ');
    WriteLn (SystemID[0],',',SystemID[1]);
    WriteFast ('Disk type is ');
    Write (TypeCode);
    CASE TypeCode OF
       6:  WriteFast (' (RD53), ');
       8:  WriteFast (' (RD52), ');
      10:  WriteFast (' (RD51), '); { Only these three values }
      12:  WriteFast (' (RD50), '); { have been defined }
      14:  WriteFast (' (RD31), '); { by DEC }
      16:  WriteFast (' (RD32), ');
      ELSE WriteFast (' (Unknown), ');
    end;
    if PartFlag = 0 then
      WriteFastLn ('Partitioned')
    else
      WriteFastLn ('Not Partitioned');
    Write ('Disk contains ',Cylinders,' (');
    WriteHex4 (Cylinders);  Write ('H) cylinders on ',Surfaces,' surfaces');
    WriteLn (' (', (Cylinders * Surfaces), ' logical tracks)');
    WriteFastLn
('There are 16 (decimal) sectors per track and 512 (decimal) bytes per sector');
    WriteLn;
    Write ('BAT:  '); WriteTSL (BATLocation);  WriteLn;
    Write ('DPD:  '); WriteTSL (DPDLocation);  WriteLn;
    Write ('OSN:  '); WriteTSL (OSNLocation);  WriteLn;
    Write ('BOOT: '); WriteTSL (BOOTLocation);  WriteLn;
    Write ('AST:  '); WriteTSL (ASTLocation);  WriteLn;
    WriteLn;
    WriteFast ('Alternate sector tracks: ');
    if NumAltTracks = 0 then
      WriteFast ('None')
    else
    begin
      WriteFast (Concat(Hex4Digit (FirstAltTrack), 'H thru ',
                        Hex4Digit (FirstAltTrack + NumAltTracks - 1), 'H'));
    end;
    WriteLn;
    WriteFastLn (Concat ('Maintenence tracks:      ',
                         Hex4Digit (MaintCylinder * Surfaces),
                         'H thru ',
                         Hex4Digit
                          ((MaintCylinder * Surfaces) + Surfaces - 1),
                         'H'));
    WriteFastLn (Concat ('Manufacturing tracks:    ',
                         Hex4Digit  (MfgCylinder * Surfaces),
                         'H thru ',
                         Hex4Digit
                          ((MfgCylinder * Surfaces) + Surfaces - 1),
                         'H'));
    WriteLn;
    WriteFast ('Write pre-comp starts at cylinder ');
    Write (PreCompValue * 4);
    WriteFast ('; Step rate = ');
    If StepRate = 0 then WriteFastLn ('35 µs')
                    else WriteLn ((0.5 * StepRate):1:1, ' ms');
  end;
end {PrintGeneralDiskInfo};

{ WriteASTBlocks - Write current AST data in internal array to disk.
  This procedure takes the information in memory about alternate sectors and
  writes it to the disk in the places appropriate for AST blocks.  It is
  expected that the block in HOMBlock contains a current Home block for the
  disk.  Also, TempBlock is used by this routine. }
procedure WriteASTBlocks;
var
  Trk           :Integer;
  Sec           :Byte;
  I, J, K       :Integer;
begin
  { Make sure the number of sectors allocated for alternate sector information
    is sufficient.  If it isn't, we'll skip writing this stuff and warn the
    user that we're doing this. }
  With HOMBlock.HOM do
  If ASTLocation.Length < ComputeASTBlocks (NumAltTracks * 16) then
  begin
    DrawOutline;
    FVRow := 10;  FVAttribute := AtBold;
    Center ('Insufficient space for Alternate Sector Table');
    WriteLn;
    FVAttribute := AtNormal;
    Center ('Your hard disk was initialized with insufficient space to hold');
    Center ('the Alternate Sector Table (AST).');
    Center ('The writing of the Alternate Sector Table is being bypassed.');
    Center ('Correct operation of your disk cannot be guaranteed');
    Center ('under these circumstances.');
    WriteLn;
    Center ('NOTE:  If your disk was formatted with WUTIL, this indicates');
    Center ('a serious error condition.  Please report this bug.');
    FVRow := 22; FVAttribute := AtBold;
    Center ('Press any key to continue...');
    I := RawChar;
    Exit;
  end;

  { Everything looks OK.  Initialize and begin writing AST data. }

  TempBlock.AST.LBN := $FF;
  TempBlock.AST.MaxEntries := 0;
  TempBlock.AST.EntryCount := 0;
  { Start "Trk" and "Sec" pointing one sector before AST area }
  Trk := HOMBlock.HOM.ASTLocation.Track;
  Sec := HOMBlock.HOM.ASTLocation.Sector;
  PrevSector (Trk, Sec);
  { Loop for each sector in each alternate track }
  For I := 0 to (HOMBlock.HOM.NumAltTracks - 1) do For J := 1 to 16 do
  begin
    { If we have filled current block, write it out and then set up another
      one.  Don't write out logical block $FF, this is a dummy entry to start
      us off! }
    If TempBlock.AST.EntryCount >= TempBlock.AST.MaxEntries then
    begin
      If TempBlock.AST.LBN <> $FF then WriteMajorBlock (Trk, Sec, TempBlock);
      K := Lo(TempBlock.AST.LBN + 1);
      NextSector (Trk, Sec);
      FillChar (TempBlock, 512, 0);
      With TempBlock.AST do
      begin
        ID := 'AST';
        LBN := K;
        MaxEntries := 100;
      end;
    end;
    { Now add entry to current AST block }
    With TempBlock.AST do
    begin
      With Entry[EntryCount] do
      begin
        BadSectorAddress := ASTData[I, J];
        GoodTrackOffset := I;
        GoodSector := J;
      end;
      EntryCount := EntryCount + 1;
    end;
  end;
  { Write the last AST block }
  If TempBlock.AST.LBN <> $FF then WriteMajorBlock (Trk, Sec, TempBlock);
end {WriteASTBlocks};

{ WriteBATBlocks - Write current BAT data in internal array to disk.
  This procedure takes the information in memory about good/bad sectors and
  writes it to the disk in the places appropriate for BAT blocks.  It is
  expected that the block in HOMBlock contains a current Home block for the
  disk.  Also, TempBlock is used by this routine. }
procedure WriteBATBlocks;
var
  Trk           :Integer;
  Sec           :Byte;
  I, J          :Integer;
begin
  { Make sure the number of sectors allocated for BAT area is sufficient
    If it isn't, we'll skip writing this stuff and warn the user that we're
    doing this. }
  With HOMBlock.HOM do
  If BATLocation.Length < ComputeBATBlocks (Cylinders*Surfaces) then
  begin
    DrawOutline;
    FVRow := 10;  FVAttribute := AtBold;
    Center ('Insufficient space for Bad Sector Information');
    WriteLn;
    FVAttribute := AtNormal;
    Center ('Your hard disk was initialized with insufficient space to hold');
    Center ('the Bad Address Table (BAT).');
    Center ('The writing of the Bad Address Table is being bypassed.');
    Center ('Correct operation of your disk cannot be guaranteed');
    Center ('under these circumstances.');
    WriteLn;
    Center ('NOTE:  If your disk was formatted with WUTIL, this indicates');
    Center ('a serious error condition.  Please report this bug.');
    FVRow := 22; FVAttribute := AtBold;
    Center ('Press any key to continue...');
    I := RawChar;
    Exit;
  end;

  { Everything looks OK.  Initialize and begin writing AST data. }

  I := 0;
  Trk := HOMBlock.HOM.BATLocation.Track;
  Sec := HOMBlock.HOM.BATLocation.Sector;
  While I < HOMBlock.HOM.BATLocation.Length do
  begin
    FillChar (TempBlock, 512, 0);
    With TempBlock.BAT do
    begin
      ID := 'BAT';
      LBN := I;
      FirstSector.Track := 250 * I;
      FirstSector.Sector := 1;
      LastSector.Track := (250 * (I + 1)) - 1;
      LastSector.Sector := 16;
      For J := 0 to 249 do Entry[J] := SectorTable[FirstSector.Track + J];
    end;
    WriteMajorBlock (Trk, Sec, TempBlock);
    I := I + 1;
    NextSector (Trk, Sec);
  end;
end {WriteBATBlocks};

{ GetMenuSelection - Displays menu and returns value of selection.
  This function clears the screen, displays a menu according to the information
  in the "menu" structure passed to it, and waits for the user to select an
  item from the menu.  The value of the selected item (of type MenuFunction)
  is returned as a function value.  If the global variable EXITAllowed is
  set to TRUE, the RawChar function which this routine calls will allow
  exit by hitting the EXIT key; this fact will be noted in the instructions
  at the bottom of the screen.  Up to three additional lines of data can be
  passed, which are displayed, centered, on the menu screen in addition to the
  menu.  A set is also passed which describes additional function keys which
  may be typed other than DO, ENTER, or RETURN.  The terminator key code is
  returned, or a zero is returned for DO, ENTER, or RETURN.  NOTE THAT THIS
  ROUTINE TURNS ON FAST VIDEO I/O MODE IF IT HAS NOT ALREADY BEEN TURNED ON
  (IT CALLS StartFastVideo); IT IS ASSUMED ACTUALLY THAT THIS HAS ALREADY BEEN
  CALLED; THIS ROUTINE WILL EXIT WITH FAST VIDEO MODE ENABLED WHETHER IT WAS
  PREVIOUSLY ENABLED OR NOT. }

function GetMenuSelection (VAR M:Menu;
                           Functions :KeysAllowed;
                           LineOne, LineTwo, LineThree :Str80;
                           VAR Terminator :Integer) :MenuFunction;
var
  Current     :Integer;         { Currently selected item }
  ItemLength  :Integer;         { Length of descriptive text items }
  I, J, K     :Integer;         { Temporary values }
  Confirmed   :Boolean;         { TRUE once a menu selection has been
                                  confirmed with RETURN, DO, or ENTER }
begin
  { Determine the length items in the menu will have.  Account for four extra
    characters (one digit, a period, and two spaces) }

  ItemLength := Length (M.Selection[1].Name) + 4;

  { Draw a box around the perimiter of the screen and display the menu
    itself.  Also set up margins, etc. for the menu items. }

  DrawOutline;
  StartFastVideo (2, 3, AtNormal, 79, 23);
  Center (LineOne);
  If LineTwo = 'MX' then
    If TwoDrives then
      begin
        FVAttribute := AtBold;
        Center ('Press CTRL-SHIFT-SELECT to select physical drive');
      end
    else
  else Center (LineTwo);
  Center (LineThree);
  FVAttribute := AtBold;
  Center (M.MenuHeader);
  StartFastVideo (((80 - ItemLength) DIV 2 + 1), 8, AtNormal, 79, 24);
  DrawBox (FVLMargin - 2, FVTMargin-1, FVLmargin + ItemLength + 1,
           FVTMargin + M.NumberOfSelections, AtBold);
  FVAttribute := AtNormal;
  for I := 1 TO M.NumberOfSelections do
    WriteFastLn (Concat (Chr(I+Ord('0')), '.  ', M.Selection[I].Name));

  FVRow := 20; FVAttribute := AtBold;
  Center ('Use the arrow keys or the number keys to select an item.');
  Center ('Then press RETURN, DO, or ENTER to confirm your selection.');
  if EXITAllowed then
  begin
    if MainScreenKeyVal IN Functions then
      Center ('(Or press MAIN SCREEN for main menu, EXIT to return to MS-DOS)')
    else
      Center ('(Or press EXIT to return to MS-DOS)');
  end
  else if MainScreenKeyVal in Functions then
    Center ('(Or press MAIN SCREEN for main menu)');

  { Now the menu has been displayed.  The big loop below starts by highlighting
    the currently-selected item.  Then it waits for a key to be pressed.  After
    the key is pressed, it is acted upon (in some cases by just ringing the
    bell and doing nothing). }

  Current := 1;                 { Initially, first choice is "current" }
  Confirmed := FALSE;           { But not yet confirmed }
  While not Confirmed do
  begin
    { Redisplay current item in reverse video }
    FVColumn := FVLMargin;  FVRow := FVTMargin + Current - 1;
    FVAttribute := AtReverse;
    WriteFast (Concat (Chr(Current+Ord('0')), '.  ', M.Selection[Current].Name));

    { Get a key }
    K := (RawChar AND CapsLockMask);

    { Perform some translations.  Keypad 0-9 is translated to digits 0-9.
      Enter and DO are translated to RETURN }

    if ((K = DoKeyCode) or (K = KeypadEnterKeyCode)) then
      K := ReturnKeyCode
    else if ((K >= Keypad0KeyCode) and (K <= Keypad9KeyCode)) then
      K := ((K - Keypad0KeyCode) div 3) + Digit0KeyCode;

    { Return to normal video for current item, it may be changed }
    FVColumn := FVLMargin;
    FVAttribute := AtNormal;
    WriteFast (Concat (Chr(Current+Ord('0')), '.  ', M.Selection[Current].Name));

    { Now see what we got for a key and process accordingly }

    if K = 13 then                      { return or equivalent }
    begin
      Terminator := 0;
      Confirmed := TRUE;
    end
    else if (K >  Digit0KeyCode)
        and (K <= Digit0KeyCode + M.NumberOfSelections) then
      Current := K - Digit0KeyCode
    else if K = UpArrowKeyCode then
    begin
      Current := Current - 1;
      if Current < 1 then Current := M.NumberOfSelections;
    end
    else if K = DownArrowKeyCode then
    begin
      Current := Current + 1;
      if Current > M.NumberOfSelections then Current := 1;
    end
    else if (K-$100) IN Functions then
    begin
      Terminator := K;
      Confirmed := TRUE;
    end
    else if TwoDrives and (LineTwo = 'MX') and (K = Ctrl+Shift+SelectKeyCode)
    then
    begin
      CurrentDrive := CurrentDrive + 1;
      if CurrentDrive = 3 then CurrentDrive := 1;
      HDStrat      := HDStrategy[CurrentDrive];
      HDInter      := HDInterrupt[CurrentDrive];
      FVRow := 24; FVAttribute := AtBold;
      Center (Concat(' Physical Drive ',Chr($30+CurrentDrive),' selected '));
    end
    else                                { invalid key - ring the bell }
      Write (^G);
  end;

  { When we get here, a choice has been confirmed!  Return with the
    value for the one we selected }

  GetMenuSelection := M.Selection[Current].Value;

end {GetMenuSelection};

{ FormatCPMPartition - Builds structures necessary for a (C)CP/M partition.
  This procedure is passed the starting and ending track numbers for a
  partition which is to be initialized for use by either CP/M or CCP/M.
  It is also passed the name of the partition, in case an error message must
  be printed.  The procedure then performs the actions necessary to build the
  partition on disk. }
procedure FormatCPMPartition (StartTrack, EndTrack :Integer; Name :Str60);
var
  Data :SectorBlock;
  I, J, K, Count :Integer;
  NumAltSectors :Integer;
begin
  { First, we want to make sure the alternate sector table jives with this
    partition and the bad sectors within it.  We'll start by scanning the
    current AST for sectors falling within the range of tracks which makes
    up this partition.  We'll delete each of them.  Then we'll go through
    all the sectors in our partition, find the bad ones, and create entries
    in the AST (up to a maximum of 100, since that's the most we can fit in
    our private PAS block). }
  NumAltSectors := (HOMBlock.HOM.NumAltTracks * 16);
  For I := 0 to (NumAltSectors - 1) do
  begin
    J := ASTVector[I].Track;
    If (J >= StartTrack) and (J <= EndTrack) then
    begin
      ASTVector[I].Track := 0;
      ASTVector[I].Sector := 0;
    end;
  end;

  Count := 0;

  For I := StartTrack to EndTrack do
    If SectorTable[I].Num <> 0 then
      For J := 1 to 16 do
        If SectorIsBad (I, J) then
        begin
          Count := Count + 1;
          If Count < 101 then
          begin
            K := 0;
            While (K < NumAltSectors)
              and (ASTVector[K].Sector <> 0) do K := K + 1;
            { If we couldn't find an available slot in the AST area, then
              set the count of bad sectors to a high value, which will force
              an error message when we leave this loop.  Otherwise, use the
              slot we found to record this bad sector information. }
            If K = NumAltSectors then Count := 101
            else With ASTVector[K] do
            begin
              Track := I;
              Sector := J;
            end;
          end;
        end;
 {end..end}

 { We have a value in "Count" which indicates how many bad sectors we found
   (or it has been dummied to "101" if we filled the alternate sector table).
   If its value exceeds 100, this means we were not able to create alternate
   sector entries for all the bad sectors in this partition.  Print a warning
   message. }

  If Count > 100 then
  begin
    DrawOutline;
    StartFastVideo (10, 10, AtBold, 79, 23);
    Write (^G);
    Center ('Too many bad sectors in CP/M or CCP/M partition');
    WriteLn;
    FVAttribute := AtDefault;
    WriteFastLn (Concat ('Partition:  ', Name));
    WriteLn;
    WriteFastLn ('Either (1) The partition named above had more than 100 bad sectors');
    WriteFastLn ('Or     (2) All available alternate sectors have been used');
    WriteLn;
    WriteFastLn ('In either case, the partition may not be usable.');
    WriteLn;
    FVAttribute := AtBold;
    Center ('Press any key to continue');
    I := RawChar;
  end;

  { Now we're ready to build the PAS block, which contains information about
    alternate sectors to be used by this partition.  We'll build it using
    data in our alternate sector table.  We'll use the definition for the AST
    block, because they are actually identical except for the block ID they
    contain and the scope of the data within them. }
  FillChar (Data, 512, 0);
  With Data.AST do
  begin
    ID := 'PAS';
    MaxEntries := 100;
    For I := 0 to (HOMBlock.HOM.NumAltTracks - 1) do
    For J := 1 to 16 do
    begin
      K := ASTData[I, J].Track;
      If (K >= StartTrack) and (K <= EndTrack) then
      begin
        With Entry[EntryCount] do
        begin
          BadSectorAddress := ASTData[I, J];
          GoodTrackOffset := I;
          GoodSector := J;
        end;
        EntryCount := EntryCount + 1;
      end;
    end;
  end;

  { We've built all the data for the PAS block.  Now compute a checksum for
    it and write it to disk (first sector of first track of partition). }
  Data.AST.Checksum := -(Checksum(Data));
  WriteNoError (StartTrack, 1, Data);

  { Now we want to fill the remainder of the first two tracks of the
    partition with zeroes (the boot area).  }
  FillChar (Data, 512, 0);
  For I := StartTrack to StartTrack + 1 do
  For J := 1 to 16 do
  If (I > StartTrack) or (J > 1) then { Don't rewrite PAS block! }
    WriteNoError (I, J, Data);

  { Now initialize the directory.  We have to set all the directory entries
    to unused and then write all 16 directory blocks with these entries. }
  With Data do For I := 0 to 15 do SectorBytes[I*32] := $E5;
  For J := 1 to 16 do WriteNoError ((StartTrack + 2), J, Data);

  { The CP/M or CCP/M partition has been built!  Return now. }
end {FormatCPMPartition};

{ FormatMSDOSPartition - Builds structures necessary for an MS-DOS partition.
  This procedure is passed the starting and ending track numbers for a
  partition which is to be initialized for use by MS-DOS.  It is also passed
  the name of the partition, in case an error message must be printed.
  The procedure then performs the actions necessary to build the partition
  on disk. }
procedure FormatMSDOSPartition (StartTrack, EndTrack :Integer; Name :Str60);
var
  Data :SectorBlock;
  I, J, K :Integer;
  Temp :Real;
  FATValue :Integer;
  FATSize :Integer;
  DirSize :Integer;
  NibbleBuffered :Boolean;
  NibbleBuffer :Byte;
  FATTrack :Integer;
  FATSector :Byte;
  BytesWritten :Integer;
  BigFAT :Boolean;

  {sub}procedure WriteFATBlock;
  var
    FAT2Track :Integer;
    FAT2Sector :Byte;
  begin
    If FATTrack = -1 then
    begin
      FATTrack := StartTrack +2;
      FATSector := 1;
    end
    else
    begin
      WriteNoError (FATTrack, Xlate(FATSector), Data);
      FAT2Track := FATTrack;
      FAT2Sector := FATSector + FATSize;
      While FAT2Sector > 16 do
      begin
        FAT2Track := FAT2Track + 1;
        FAT2Sector := FAT2Sector - 16;
      end;
      WriteNoError (FAT2Track, Xlate(FAT2Sector), Data);
      FATSector := FATSector + 1;
      If FATSector = 17 then
      begin
        FATTrack := FATTrack + 1;
        FATSector := 1;
      end;
    end;
    FillChar (Data, 512, 0);
    BytesWritten := 0;
  end {WriteFATBlock};

  {sub}procedure WriteFATByte (Value :Byte);
  begin
    If BytesWritten >= 512 then WriteFATBlock;
    Data.SectorBytes[BytesWritten] := Value;
    BytesWritten := BytesWritten + 1;
  end {WriteFATByte};

  {sub}procedure WriteFATEntry (Value :Integer);
  begin
    If BigFAT then
    begin
      WriteFATByte (Lo (Value));
      WriteFATByte (Hi (Value));
    end
    else If NibbleBuffered then
    begin
      WriteFATByte (((Value Mod $10) * $10) + NibbleBuffer);
      WriteFATByte (Value Div $10);
      NibbleBuffered := False;
    end
    else
    begin
      WriteFATByte (Lo(Value));
      NibbleBuffer := Hi (Value);
      NibbleBuffered := True;
    end;
  end {WriteFATEntry};

  {sub}procedure FinishFATOutput;
  begin
    If NibbleBuffered then WriteFATEntry (0);
    If BytesWritten > 0 then WriteFATBlock;
  end {FinishFATOutput};

begin {FormatMSDOSPartition}
  { Determine whether we will be using a 16-bit FAT or a 12-bit FAT.  We
    use the 12-bit version whenever the partition has 1025 or fewer tracks
    (approx. 8MB or less of data space), which is always the case with DOS
    versions before 3.0.  If we are told to format a partition bigger than
    1025 tracks, we will assume this is DOS version 3.0 or better, and we
    will use 16-bit FAT entries. }
  BigFAT := ((EndTrack - StartTrack + 1) > 1025);

  { First, we want to make sure the alternate sector table jives with this
    partition and the bad sectors within it.  We'll start by scanning the
    current AST for sectors falling within the range of tracks which makes
    up this partition.  We'll delete each of them.  MS-DOS doesn't use
    alternate sectors, so there's no use wasting them here. }
  For I := 0 to ((HOMBlock.HOM.NumAltTracks * 16)- 1) do
  begin
    J := ASTVector[I].Track;
    If (J >= StartTrack) and (J <= EndTrack) then
    begin
      ASTVector[I].Track := 0;
      ASTVector[I].Sector := 0;
    end;
  end;

  { Compute size of FAT in sectors }
  { **warning** do not change this algorithm.  It must duplicate the
                one used by MS-DOS or the disk will not be usable. }
  If MSDOSVersion < 3 then
  begin
    I := ((EndTrack-StartTrack+1)*16)-50;  { Number of data sectors }
    I := I Div 4;                          { Number of clusters }
    I := ((I * 3) div 2) + 4;              { Number of FAT bytes }
    FatSize := (I Div 512) + 1;            { Number of FAT Sectors }
    DirSize := 1;                          { Number of directory *TRACKS* }
  end
  else
  begin
    { The algorithm used by version 3.0 and above of MS-DOS is different,
      and pretty weird, too.  But we'll do what it says.  Note that we
      will be converting to real and then back to integer, because the
      numbers here can get to be pretty big and cause nasty integer
      overflows, which botch the calculation. }
    If BigFAT then DirSize := 2 else DirSize := 1; { directory tracks }
    Temp := (EndTrack-StartTrack-1-DirSize)*16.0; { Number of data sectors }
    If BigFAT then J := 1026                 { Magic number for 16-bit FATs }
              else J := 1368;                { Magic number for 12-bit FATs }
    Temp := Temp / J;                        { Compute real quotient }
    FATSize := Trunc (Temp);                 { Put back in integer variable }
    If Frac (Temp) <> 0 then
      FATSize := FATSize + 1;                { Round up if any fraction }
  end;
  NumFATSectors := FATSize;           { Write # of FAT sectors into DPD block }

  { Initialize FAT pointers }
  FATTrack := -1;
  FATSector := 0;
  NibbleBuffered := False;
  BytesWritten := 512;

  { FAT always starts with two entries, containing the values "FF8" and
    "FFF" (or FFF8 and FFFF, depending on the type of FAT).  Write these
    before we go on. }

  If BigFAT then
  begin
    WriteFATEntry ($FFF8);
    WriteFATEntry ($FFFF);
  end
  else
  begin
    WriteFATEntry ($FF8);
    WriteFATEntry ($FFF);
  end;

  { Now determine where the data starts, which will be right after the
    directory.  The directory is always either 16 sectors (exactly one track)
    or 32 sectors (exactly two tracks), so all we do is compute the location
    by starting with the start track plus 2 tracks of boot stuff, plus the
    proper number of directory tracks; then we adjust by the number of FAT
    sectors. }

  I := StartTrack + 2 + DirSize + ((FATSize * 2) div 16);
  J := 1 + ((FATSize * 2) mod 16);

  { Now cycle through all the sectors in the partition, determining if there
    are any bad sectors.  We do this four sectors at a time (the size of an
    MS-DOS cluster), and write one FAT entry for each cluster.  We'll write
    a zero (unused) if the cluster contains no bad sectors; we'll write an
    $FF7 or $FFF7 (bad cluster) if the cluster contains one or more bad
    sectors.  The process of doing this may actually write one or more FAT
    blocks to the disk along the way. }

  Repeat {Until I > EndTrack}
    FATValue := 0; { Initially, assume block is OK }
    For K := 1 to 4 do
    begin
      If I <= EndTrack then If SectorIsBad (I, Xlate(J)) then FATValue := $FF7;
      J := J + 1;
      If J = 17 then
      begin
        I := I + 1;
        J := 1;
      end;
    end;
    If (FATValue = $FF7) and (BigFAT) then FATValue := $FFF7;
    WriteFATEntry (FATValue);
  Until I > EndTrack;

  { Finish up the last blocks of the FAT still in internal buffers }

  FinishFATOutput;

  { Now create the directory, which is always either 16 or 32 sectors.  All
    we have to do is write this many sectors containing zero.  We'll compute
    its location by using double the number of FAT sectors and adding that to
    the location of the FAT (start track plus 2, sector 1). }

  I := StartTrack + 2 + ((FATSize * 2) div 16);
  J := 1 + ((FATSize * 2) mod 16);
  FillChar (Data, 512, 0);
  For K := 1 to DirSize*16 do
  begin
    WriteNoError (I, Xlate(J), Data);
    J := J + 1;
    If J = 17 then
    begin
      I := I + 1;
      J := 1;
    end;
  end;

  { That's it -- the MS-DOS partition has been built. }

end {FormatMSDOSPartition};
