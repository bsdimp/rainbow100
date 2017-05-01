{** file wuovr.pas © Copyright 1986 Anthony G. Camas, all rights reserved **}
{ Intro - Displays "hello" message and disclaimer and waits for RESUME key }
overlay procedure Intro;
begin

  DrawBox (1, 1, 80, 24, AtNormal);
  DrawBox (6, 10, 75, 19, AtBlink);
  StartFastVideo (8, 3, AtDefault, 78, 23);
  FVAttribute := AtBold;
  Center (HeaderString);
  FVAttribute := AtNormal;
  WriteLn;
  Center ('© Copyright 1986 Anthony G. Camas');
  Center ('© Copyright 1989    Vinzenz Esser');
  Center ('All Rights Reserved');
  Center ('See source program for distribution and licensing information');
  FVRow := 10; FVAttribute := AtBlink;
  Center (' WARNING ');
  FVAttribute := AtNormal;
  Center ('This software  is provided  as is.    It comes with no warranties,');
  Center ('expressed or implied,  including,  but not limited to, any implied');
  Center ('warranties of merchantability or fitness for a particular purpose.');
  Center ('Reasonable care has been taken  to ensure that this program works,');
  Center ('but this cannot be warranted in any way,  especially since you got');
  Center ('it for nothing.   You are expected to use it with reasonable care.');
  Center ('Please be sure  to back up  the contents  of your hard disk before');
  Center ('attempting  to use this program  to format or partition your disk.');
  FVRow := 21; FVAttribute := AtBold;
  Center ('Press RESUME to continue');
  Center ('or press EXIT to return to MS-DOS');
  WaitForResume;

end {Intro};

{ PrPart - Print (display) current partitioning and other info about disk}
overlay procedure PrPart;
type
  ModeType = (FirstMode, GeneralInfo, OpSystems, Partitions, BadSectors,
              LastMode);
var
  Mode     :ModeType;
  I, J, K  :Integer;
  DontDisplay :Boolean;
begin

  { Read HOM/OSN/DPD blocks; if this fails, a message will have been displayed
    already, so just exit }
  if not ReadMajorBlocks then Exit;

  Mode := Succ(FirstMode);
  DontDisplay := False;

  { This loop continues until exit is requested }

  repeat {Until mode = LastMode}
    { Display an appropriate screen based on the mode we are in }
    If not DontDisplay then case Mode of
    GeneralInfo: begin
      DrawOutline;
      StartFastVideo (3, 2, AtBold, 78, 23);
      WITH HOMBlock.HOM DO
      BEGIN
        WriteFastLn ('-- DISK INFORMATION --');
        FVAttribute := AtDefault;
        PrintGeneralDiskInfo;
        if (AutoBoot = $FF) or (BootTrack = 0) then
          WriteFastLn ('No Auto Boot configured')
        else
        begin
          WriteFastLn (Concat ('Auto Boot configured for Track ',
                               Hex4Digit (BootTrack),
                               'H, logical drive ',
                               Chr(AutoBoot+Ord('A')-1)));
        end;
      end;
      WriteLn;
      FVAttribute := AtBold;
      WriteFastLn ('NEXT SCREEN = operating system information');
      WriteFastLn ('MAIN SCREEN = main menu');
     end;
    OpSystems: begin
      DrawOutline;
      StartFastVideo (3, 2, AtBold, 78, 23);
      WITH OSNBlock.OSN DO
      begin
        WriteFastLn ('-- OPERATING SYSTEMS --');
        FVAttribute := AtDefault;
        For I := 0 to 30 DO
          If ORD(Entry[I][0]) <> 0 then WriteLn (I:2,'  ',Entry[I]);
      end;
      WriteLn;
      FVAttribute := AtBold;
      WriteFastLn ('PREV SCREEN = general disk information');
      WriteFastLn ('NEXT SCREEN = partitioning information');
      WriteFastLn ('MAIN SCREEN = main menu');
     end;
    Partitions: begin
      DrawOutline;
      StartFastVideo (3, 2, AtBold, 78, 23);
      WITH DPDBlock.DPD DO
      begin
        WriteFastLn ('-- DEFINED PARTITIONS --');
        FVAttribute := AtDefault;
        WriteLn;
        WriteFastLn ('Start   End   Total              Part');
        WriteFastLn ('Track  Track  Tracks    Size     Name      Drive    O/S            Boot');
        WriteLn;
        For I := 1 to EntryCount DO
          WITH Entry[I] DO
          begin
            Write (' '); WriteHex4 (FirstTrack);
            Write ('   '); WriteHex4 (LastTrack);
            Write ('   '); WriteHex4 (LastTrack-FirstTrack+1);
            Write ('  ');
            Write (((LastTrack-FirstTrack+1) * 8.0 / 1024.0):7:3, 'MB  ');
            For J := 0 to 7 do
              If Name[J] >= ' ' then Write (Name[J]) else Write (' ');
            Write ('     ', Chr(LogicalUnit+Ord('A')-1), ':   ',
                   OSNBlock.OSN.Entry[OSNIndex], '   ');
            IF FirstTrack = HOMBlock.HOM.BootTrack then Write ('*');
            WriteLn;
          end;
          WriteLn;
      end;
      FVAttribute := AtBold;
      WriteFastLn ('PREV SCREEN = operating system information');
      WriteFastLn ('NEXT SCREEN = bad sector information');
      WriteFastLn ('MAIN SCREEN = main menu');
     end;
    BadSectors: begin
      DrawOutline;
      StartFastVideo (3, 2, AtBold, 78, 23);
      WriteFastLn ('-- BAD SECTORS (TRACK/SECTOR; HEX ADDRESSES) --');
      FVRow := 21; FVAttribute := AtBlinkBold;
      WriteFastLn ('Please wait...');
      FVAttribute := AtDefault;
      WriteLn;
      K := 0; { Count of bad sectors }
      For I := 0 to ((HOMBlock.HOM.Cylinders * HOMBlock.HOM.Surfaces) - 1) do
        If SectorTable[I].Num <> 0 then
          For J := 1 to 16 do
            If SectorIsBad (I, J) then
            begin
              if K < 128 then
              begin
                FVColumn := (K div 16)*9 + 5;
                FVRow := (K mod 16) + 4;
                WriteFast (Concat (Hex4Digit(I), '/', Hex2Digit(J)));
              end;
              K := K + 1;
            end;
     {end..end}
      FVRow := 21;  FVColumn := 3;  FVAttribute := AtNormal;
      WriteLn ('Total bad sectors: ', K);
      FVAttribute := AtBold;
      WriteFastLn ('PREV SCREEN = partitioning information');
      WriteFastLn ('MAIN SCREEN = main menu');
     end;
    end;

    { If display was supressed, restore it }
    DontDisplay := False;

    K := (RawChar and CapsLockMask);
    Case K of
     NextScreenKeyCode:
      if Succ(Mode) = LastMode then DontDisplay := True else Mode := Succ(Mode);
     PrevScreenKeyCode:
      if Pred(Mode) = FirstMode then DontDisplay := True else Mode := Pred(Mode);
     BackspaceKeyCode:
      If Pred(Mode) = FirstMode then Mode := LastMode else Mode := Pred(Mode);
     ReturnKeyCode:
      Mode := Succ(Mode);
     MainScreenKeyCode:
      Mode := LastMode;
     else
      DontDisplay := True;
    end;
    { "DontDisplay" flag was set to true if there was some kind of an error.
      Ring the bell in this case and then iterate. }
    if DontDisplay then Write(^G);
  until mode = LastMode;
end {PrPart};

{ FormatAndInitialize - Format and initialize disk. }
overlay procedure FormatAndInitialize (MainMenuFunc :MenuFunction);
Const
  StructureDataFileName = 'WUTILDSK.DAT';
  PriBootFileName = 'PREBOOT.LDX';
  SecBootFileName = 'SECBOOT.LDX';
Type
  StructureDataFileRecord = Record
    Name        :Str35;
    HOMBlock    :SectorBlock
  end;
Var
  PriBootFileSpec,
  SecBootFileSpec,
  StructureDataFileSpec :Str255;
  PriBootFile,
  SecBootFile           :File;
  StructureDataFile     :File of StructureDataFileRecord;
  I, J                  :Integer;
  StructureDataRecord   :StructureDataFileRecord;
  DiskTypeNames         :Array [0..25] of Str35;
  NumDiskTypes          :Integer;
  Trk                   :Integer;
  Sec                   :Byte;
  TrackDisplay          :Str4;
  ZeroesData,
  OnesData              :SectorBlock;
  FormattingMode        :MenuFunction;

  {sub}Procedure CantFind (Name :Str80);
  begin
    DrawOutline;
    Write (^G);
    FVRow := 10;  FVAttribute := AtBold;
    Center (Concat ('Cannot locate file ', Name));
    WriteLn;
    FVAttribute := AtDefault;
    Center ('This file is required in order to perform this function.');
    Center ('It must reside in your current working directory or in');
    Center ('a directory in your PATH list.');
    WriteLn;
    Center ('See your WUTIL documentation for more information.');
    WriteLn;
    FVAttribute := AtBold;
    Center ('Press any key to continue');
    I := RawChar;
  end {CantFind};

  {sub}function GetDiskData :Boolean;
  type
    EntryModeType = (FirstEntryMode, Description, TCode, NumCyl, NumSurf,
                     Precomp, StRate, AltTracks, LastEntryMode);
  var
    I, J :Integer;
    Trk  :Integer;
    Sec  :Byte;
    Mode :EntryModeType;
    Term :Integer;
    Done, Error :Boolean;
    BATOverflow,
    ASTOverflow :Boolean;
    InputData   :Str80;
    ErrorMsg    :Str80;
    Arrows      :KeysAllowed;
  begin
    FillChar (StructureDataRecord, 512+35+1, 0);
    With StructureDataRecord do With HOMBlock.HOM do
    begin
      { Set up constant and initial values. }
      ID := 'HOM';
      VolumeID := 'RAINBOW'#0;
      SectorsPerTrack := 16;
      SectorSize := 512;
      AutoBoot := $FF;
      { Now get the things the user is allowed to enter }
      DrawOutline;
      Center ('Please enter information about your disk below');
      FVAttribute := AtUnderlineBold;
      WriteFastLn ('IDENTIFICATION');
      FVAttribute := AtNormal;
      WriteFastLn ('Description (for future retrieval):');
      WriteFastLn ('Type code for HOM block:             0');
      WriteLn;
      FVAttribute := AtUnderlineBold;
      WriteFast   ('GEOMETRY');
      FVAttribute := AtBold;
      WriteFastLn (' (assumed: 512 bytes/sector, 16 sectors/track)');
      FVAttribute := AtNormal;
      WriteFastLn ('Number of Cylinders:                 100');
      WriteFastLn ('Number of Surfaces (Heads):          4');
      WriteLn;
      FVAttribute := AtUnderlineBold;
      WriteFastLn ('PHYSICAL CHARACTERISTICS');
      FVAttribute := AtNormal;
      WriteFastLn ('Write Precompensation first cyl/4:   1');
      WriteFastLn ('Step Rate (.5ms units, 0 is 35µs):   6');
      WriteLn;
      FVAttribute := AtUnderlineBold;
      WriteFastLn ('OTHER OPTIONS');
      FVAttribute := AtNormal;
      WriteFastLn ('Tracks to reserve for alt. sectors:  1');
      WriteLn;
      Center
     ('Enter requested info, pressing RETURN or up or down arrows after each');
      Center ('Pressing just RETURN or arrows at any item leaves value as is');
      Center ('Pressing MAIN SCREEN at any time aborts and goes to main menu');
      Center ('Refer to WUTIL documentation for further information');
      Mode := Succ(FirstEntryMode);
      Done := False;  Error := False;
      Name := '';  TypeCode := 0;  Cylinders := 100;  Surfaces := 4;
      PreCompValue := 1;  StepRate := 6;  NumAltTracks := 1;
      While not Done do
      begin
        If Pred(Mode) = FirstEntryMode then
          Arrows := [DownArrowKeyVal, MainScreenKeyVal]
        else
          Arrows := [UpArrowKeyVal, DownArrowKeyVal, MainScreenKeyVal];
        FVColumn := 40;
        case Mode of
        Description: begin
          FVRow := 5;
          ReadScreen (FVColumn, FVRow, 35, [' '..'~'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
            Name := InputData
          else
            WriteFast (Name);
          If Length(Name) = 0 then
          begin
            Error := True;
            ErrorMsg := 'Name must not be blank';
          end
          else For I := 0 to NumDiskTypes - 1 do if Name = DiskTypeNames[I] then
          begin
            Error := True;
            ErrorMsg := 'This name is already in use; please choose another';
          end;
         end;
        TCode: begin
          FVRow := 6;
          ReadScreen (FVColumn, FVRow, 3, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If I > 255 then
            begin
              Error := True;
              ErrorMsg := 'Type Code must be between 0 and 255';
            end
            else TypeCode := I;
          end
          else
          begin
            Str (TypeCode, InputData);
            WriteFast (InputData);
          end;
         end;
        NumCyl: begin
          FVRow := 9;
          ReadScreen (FVColumn, FVRow, 4, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If I = 0 then
            begin
              Error := True;
              ErrorMsg := 'Number of cylinders cannot be zero!';
            end
            else if I > 1024 then
            begin
              Error := True;
              ErrorMsg := 'Number of cylinders cannot be > 1024!';
            end
            else if I * Surfaces > (TrackLimit+1) then
            begin
              Error := True;
              Str (TrackLimit+1, ErrorMsg);
              ErrorMsg :=
               Concat ('Number of tracks (cylinders x surfaces) must be <= ',
                       ErrorMsg);
            end
            else Cylinders := I;
          end
          else
          begin
            Str (Cylinders, InputData);
            WriteFast (InputData);
          end;
         end;
        NumSurf: begin
          FVRow := 10;
          ReadScreen (FVColumn, FVRow, 2, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If I = 0 then
            begin
              Error := True;
              ErrorMsg := 'Number of surfaces cannot be zero!';
            end
            else if I > 8 then
            begin
              Error := True;
              ErrorMsg := 'Number of surfaces cannot be > 8!';
            end
            else if I * Cylinders > (TrackLimit+1) then
            begin
              Error := True;
              Str (TrackLimit+1, ErrorMsg);
              ErrorMsg :=
               Concat ('Number of tracks (cylinders x surfaces) must be <= ',
                       ErrorMsg);
            end
            else Surfaces := I;
          end
          else
          begin
            Str (Surfaces, InputData);
            WriteFast (InputData);
          end;
         end;
        Precomp: begin
          FVRow := 13;
          ReadScreen (FVColumn, FVRow, 4, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If I = 0 then
            begin
              Error := True;
              ErrorMsg := 'Write Precompensation Cylinder should not be zero!';
            end
            else PreCompValue := I;
          end
          else
          begin
            Str (PreCompValue, InputData);
            WriteFast (InputData);
          end;
         end;
        StRate: begin
          FVRow := 14;
          ReadScreen (FVColumn, FVRow, 2, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If I > 15 then
            begin
              Error := True;
              ErrorMsg := 'Step rate must be 15 (7.5ms) or less';
            end
            else StepRate := I;
          end
          else
          begin
            Str (StepRate, InputData);
            WriteFast (InputData);
          end;
         end;
        AltTracks: begin
          FVRow := 17;
          ReadScreen (FVColumn, FVRow, 2, ['0'..'9'], Arrows, InputData, Term);
          If Ord(InputData[0]) > 0 then
          begin
            Val (InputData, I, J);
            If (I = 0) or (I > 50) then
            begin
              Error := True;
              ErrorMsg := 'Must have between 1 and 50 alternate sector tracks';
            end
            else NumAltTracks := I;
          end
          else
          begin
            Str (NumAltTracks, InputData);
            WriteFast (InputData);
          end;
         end;
        end;
        If Term = MainScreenKeyCode then
        begin
          GetDiskData := False;
          Exit;
        end;
        FVRow := 23;  FVColumn := 3;
        If Error then
        begin
          FVAttribute := AtBlink;
          Write (^G);
          WriteFast (ErrorMsg);
          Error := False;
        end
        else
        begin
          FVAttribute := AtNormal;
          WriteFast
           ('                                                            ');
          If Term = UpArrowKeyCode then
            Mode := Pred(Mode)
          else
          begin
            Mode := Succ(Mode);
            If Mode = LastEntryMode then Done := True;
          end;
        end;
      end;
      { We get here after all the information about the disk and its geometry
        have been entered.  Now that we know this stuff, we can try to compute
        other values to store on the HOM block.  First, set up the
        manufacturing and maintenance cylinders as the last and second to last
        cylinders on the disk, respectively. }
      MfgCylinder := Cylinders - 1;
      MaintCylinder := Cylinders - 2;
      { Now we have to figure out where to put the various control blocks on
        the disk.  We'll try to come close to what DEC does here for smaller
        drives (this should work for 5, 10, and 20MB winnies).  That means
        minimally that we will always put the DPD block in track 0, sector 3,
        and the OSN block in track 0, sector 4 (DEC sometimes puts it in 4
        and sometimes in 5, but we'll always use 4 and avoid wasting a sector;
        that SHOULDN'T confuse any code which expects things to be in certain
        places because such code couldn't be making assumptions about the OSN
        block, and no one reads it anyway).  We'll try to locate the BAT and AST
        blocks at the end of sector 0 after the OSN block, and the secondary
        boot code at the beginning of track 1.  We also initially assume that
        the alternate sector area starts at track 4.  These last three things
        (BAT and AST locations, secondary boot location, and placement of
        first alternate track) could end up being changed if things don't fit
        nicely, which will be the case for drives much bigger than 20MB. }
      With BOOTLocation DO
      begin
        Track := $01;  Sector := $01;  Length := $0C;
      end;
      With DPDLocation DO
      begin
        Track := $00;  Sector := $03;  Length := $01;
      end;
      With OSNLocation DO
      begin
        Track := $00;  Sector := $04;  Length := $01;
      end;
      With BATLocation DO
      begin
        Track := $00;  Sector := $05;
        Length := ComputeBATBlocks (Cylinders*Surfaces);
        BATOverflow := (Sector + Length > 17);
      end;
      With ASTLocation DO
      begin
        Track := $00;  Sector := BATLocation.Sector + BATLocation.Length;
        Length := ComputeASTBlocks (NumAltTracks * 16);
        ASTOverflow := (Sector + Length > 17);
      end;
      FirstAltTrack := 4;
      { Now see if the AST area fits in track 0.  The variable ASTOverflow was
        set up by the AST placement code to tell us this. }
      If ASTOverflow then
      begin
        { The AST area did not fit.  Try moving the AST area to the end of
          track 1, as far to the end as it will go. }
        With ASTLocation do
        begin
          Track := $01;  Sector := 17-Length;
        end;
        { The AST area cannot overlay the secondary boot code.  If it does,
          we'll have to move the boot code somewhere (to track 4, in our
          case).  We know, by the way, that the AST area cannot be more than
          16 sectors, because we limit the configuration to 50 alternate
          sector tracks (more than anyone will ever need, anyway) and we only
          need 8 AST blocks to track the resulting maximum of 800 alternate
          sectors.
          ** NOTE ** THIS CODE IS ASSUMING THAT THE BOOT AREA IS STILL LOCATED
          AT TRACK 1, SECTOR 1 WHERE WE INITIALLY PLACED IT.  DON'T PUT ANY
          CODE BEFORE HERE WHICH MOVES IT, PLEASE! }
        If ASTLocation.Sector <= BOOTLocation.Length then with BOOTLocation do
        begin
          BOOTLocation.Track := FirstAltTrack;
          FirstAltTrack := FirstAltTrack + 1;
        end;
        { Now, let's see how we are doing regarding the BAT area.  We have
          moved the AST area out of its way at the end of track 0, but it's
          still possible that the BAT area didn't fit there, even by itself.
          We have a flag that tells us this, and if it says this problem
          exists, we have to do something with the BAT area. }
        If BATOverflow then
        begin
          { The BAT doesn't fit either (sigh).  Try and find a home for it.
            If it is 16 sectors or smaller, then we will move it to track
            1 and kick out the secondary boot code, if we haven't already
            done that.  Then we'll move the AST area back into track 0.  We
            know it will fit there because there are 12 sectors of space
            after the OSN block in track 0 and the AST can't be more than 8. }
          If BATLocation.Length < 17 then
          begin
            If BOOTLocation.Track = $01 then
            begin
              BOOTLocation.Track := FirstAltTrack;
              FirstAltTrack := FirstAltTrack + 1;
            end;
            With BATLocation do
            begin
              Track := $01;  Sector := $01;
            end;
            ASTLocation.Track := $00; { Leave sector and length as is }
            BATOverflow := False;
          end;
          If BATOverflow then
          begin
            { We continue here if the BAT is bigger than 16 sectors.  If
              this is the case, then we can't make the BAT contiguous, like
              we wanted to.  Instead, we'll (are you ready for this?) move
              the AST area back into track 0, move the secondary boot code
              back into track 1 (if it isn't there now), and put the BAT
              starting at track 4.  Then we'll let the BAT go for as long as
              it has to, crossing track boundaries, until it is done.  Ugh. }
            ASTLocation.Track := $00; { Leave sector as is, should fit fine }
            If BOOTLocation.Track <> $01 then
            begin
              FirstAltTrack := BOOTLocation.Track;
              BOOTLocation.Track := $01;
            end;
            With BATLocation do
            begin
              Track := FirstAltTrack;
              Sector := $01;
              { Determine first free sector after BAT }
              Trk := Track;  Sec := Sector;
              For I := 1 to Length do NextSector (Trk, Sec);
              If Sec = 1 then FirstAltTrack := Trk
                         else FirstAltTrack := Trk + 1;
            end;
          end;
        end;
      end;
      { That's it.  We have placed all the stuff on the disk in places where
        it will fit.  We think. }
    end;
    { We've built ourselves an appropriate HOM block for the specified disk
      geometry.  Now put a checksum in it. }
    StructureDataRecord.HOMBlock.HOM.Checksum :=
                                       -Checksum(StructureDataRecord.HOMBlock);
    { Now we've formatted a new record for the file.  This is the one we
      are going to use; it's also going to be added now to the file for
      future reference. }
    Seek (StructureDataFile, FileSize(StructureDataFile));
    Write (StructureDataFile, StructureDataRecord);
    GetDiskData := True;
  end {GetDiskData};

  {sub}Procedure WriteBootCode;
  begin
    { Primary boot file first.  This should be just one block. }
    FillChar (TempBlock, 512, 0);
    BlockRead (PriBootFile, TempBlock, 4); { 4 128-byte records = 512 bytes }
    WriteNoError (0, 1, TempBlock);
    WriteNoError (2, 1, TempBlock); { Remember duplicate at track 2 }

    { Now secondary boot file.  There will be a few blocks here. }
    Trk := HOMBlock.HOM.BOOTLocation.Track;
    Sec := HOMBlock.HOM.BOOTLocation.Sector;
    J := HOMBlock.HOM.BOOTLocation.Length;
    For I := 0 to J-1 do
    begin
      FillChar (TempBlock, 512, 0);
      If not EOF (SecBootFile) then BlockRead (SecBootFile, TempBlock, 4);
      WriteNoError (Trk, Sec, TempBlock);
      If Trk <= 1 then WriteNoError (Trk+2, Sec, TempBlock);
      NextSector (Trk, Sec);
    end;

  end {WriteBootCode};

begin
  { Find and open the boot loader files we will need for this function. }

  PriBootFileSpec := PriBootFileName;
  SecBootFileSpec := SecBootFileName;
  StructureDataFileSpec := StructureDataFileName;

  FindOnPATH (PriBootFileSpec);
  If Length(PriBootFileSpec) = 0 then
  begin
    CantFind (PriBootFileName);
    Exit;
  end;
  Assign (PriBootFile, PriBootFileSpec);
  Reset (PriBootFile);

  FindOnPATH (SecBootFileSpec);
  If Length(SecBootFileSpec) = 0 then
  begin
    CantFind (SecBootFileName);
    Close (PriBootFile);
    Exit;
  end;
  Assign (SecBootFile, SecBootFileSpec);
  Reset (SecBootFile);

  { If we were called just to copy boot loaders to disk, do that and exit.
    Only continue if we actually are going to initialize a disk. }
  If MainMenuFunc = MMCopyBoot then
  begin
    { Read the major structures from the disk.  They must be there in order
      for us to proceed (the disk must have been initialized). }
    If Not ReadMajorBlocks then Exit;
    { All looks good.  Now say what we're doing and go to it. }
    DrawOutline;
    FVRow := 12;
    Center ('Copying boot loaders PREBOOT.LDX and SECBOOT.LDX to the hard disk');
    Center ('Please wait...');
    WriteBootCode;
    Close (PriBootFile);
    Close (SecBootFile);
    { We've finished.  Say so, wait for acknowledgement, and get out. }
    FVRow := 20;  FVAttribute := AtBold;
    Center ('Boot loaders have been written to disk -- press any key to go on');
    I := RawChar;
    Exit;
  end;

  { We'll continue here only if we were called in order to actually initialize
    a disk.  We'll get the file containing information about our disk types
    and read it and then continue from there. }
  FindOnPATH (StructureDataFileSpec);
  If Length(StructureDataFileSpec) = 0 then
  begin
    CantFind (StructureDataFileName);
    Close (SecBootFile);
    Close (PriBootFile);
    Exit;
  end;
  Assign (StructureDataFile, StructureDataFileSpec);
  Reset (StructureDataFile);

  { Read the disk structure data file to get the names of each of the entries
    stored there.  A maximum of 26 is permitted.  Any more will be ignored. }
  NumDiskTypes := Min (FileSize (StructureDataFile), 26);
  For I := 0 to NumDiskTypes - 1 do
  begin
    Seek (StructureDataFile, I);
    Read (StructureDataFile, StructureDataRecord);
    DiskTypeNames[I] := StructureDataRecord.Name;
  end;

  { Display the formatting menu and decide how we will do this formatting }
  FormattingMode := GetMenuSelection 
                    (FormatMenu,
                     [MainScreenKeyVal],
                     'Please select the type of formatting you want.',
                     'Selections nearer the top are slower but more reliable.',
                     '', I);
  If I = MainScreenKeyCode then
  begin
    Close (StructureDataFile);
    Close (PriBootFile);
    Close (SecBootFile);
    Exit;
  end;

  { Draw the disk selection screen and wait for a selection }
  DrawOutline;
  Center ('-- DISK TYPE MENU --');
  For I := 0 to NumDiskTypes - 1 do
  begin
    FVColumn := ((I div 13)*39) + 3;
    FVRow    :=  (I mod 13)     + 5;
    FVAttribute := AtBold;
    WriteFast (Char(Ord('A')+I));
    FVAttribute := AtNormal;
    WriteFast (Concat ('  ', DiskTypeNames[I]));
  end;
  FVRow := 19;
  FVAttribute := AtBold;
  Center
    ('Press the letter corresponding to the type of disk you are initializing');
  Center
    ('If your disk type is not shown above, press ADDTNL OPTIONS');
  Center
    ('Or press MAIN SCREEN to abort and return to the main menu');

  Repeat
    { Get a key.  If not a function key, eliminate shift/ctrl bits. }
    I := (RawChar and CapsLockMask);
    If (I and $100) = 0 then I := (I and not (Shift or Ctrl));
    { Turn lower case to upper case }
    If Char(I) in ['a'..'z'] then I := I - $20;
    J := I - Ord('A');
    If I = MainScreenKeyCode then
    begin
      Close (StructureDataFile);
      Close (PriBootFile);
      Close (SecBootFile);
      Exit;
    end
    else if (I <> AddtnlOptionsKeyCode) and ((J < 0) or (J >= NumDiskTypes))
      then Write (^G);
  Until (I = AddtnlOptionsKeyCode) or ((J >= 0) and (J < NumDiskTypes));

  { If the user pressed the additional options key, then we must collect our
    own information about the disk's geometry.  Otherwise, get the information
    from the record in the file which was selected. }
  If I = AddtnlOptionsKeyCode then 
  begin
    { Display screen to get disk geometry info and get it.  Exit if MAIN SCREEN
      was pressed during this operation. }
    If not GetDiskData then
    begin
      Close (StructureDataFile);
      Close (PriBootFile);
      Close (SecBootFile);
      Exit;
    end;
  end
  else
  begin
    Seek (StructureDataFile, J);
    Read (StructureDataFile, StructureDataRecord);
  end;

  { We can close the structure data file now.  We're done with it. }
  Close (StructureDataFile);

  { We are now ready to start the formatting and initialization process.  But
    before we do, we'd better make sure this is REALLY what we want. }
  HOMBlock := StructureDataRecord.HOMBlock;

  DrawOutline;
  FVAttribute := AtBold;
  WriteFastLn ('These parameters will be used to format your disk:');
  FVAttribute := AtNormal;
  WriteFastLn (Concat ('Description: ',
                       StructureDataRecord.Name));
  PrintGeneralDiskInfo;
  WriteLn;
  FVAttribute := AtBold;
  WriteFastLn ('Press any key to continue...');
  I := RawChar;
  If I = MainScreenKeyCode then
  begin
    Close (PriBootFile);
    Close (SecBootFile);
    Exit;
  end;

  DrawOutline;
  FVAttribute := AtBold;
  Center (Concat ('About to format and initialize disk as ',
                  StructureDataRecord.Name));
  DrawBox (4, 5, 77, 11, AtBlinkBold);
  FVRow := 5; FVAttribute := AtDefault;
  Write (^G^G);
  Center (' WARNING ');
  FVAttribute := AtBold;
  Center ('You are about to format and initialize your hard disk.');
  Center ('This action will result in the LOSS of ALL data currently on');
  Center ('the disk.  You should not attempt this operation unless you do');
  Center ('not want any of your hard disk data or you have backed up');
  Center ('whatever you wish to save.');
  FVRow := 14;
  Center ('Press RESUME to continue');
  Center ('or Press MAIN SCREEN to cancel formatting/initializing');
  Repeat
    I := (RawChar and CapsLockMask);
    If I = MainScreenKeyCode then
    begin
      Close (PriBootFile);
      Close (SecBootFile);
      Exit;
    end
    else if I <> ResumeKeyCode then Write (^G);
  Until I = ResumeKeyCode;

  DrawBox (4, 14, 77, 18, AtBlinkBold);
  FVRow := 14; FVAttribute := AtDefault;
  Write (^G^G);
  Center (' SECOND WARNING ');
  FVAttribute := AtBold;
  Center ('If you press RESUME now, you will start formatting and initializing.');
  Center ('There will be no turning back.');
  Center ('Have you backed up everything you intend to save?');
  FVRow := 21;  FVAttribute := AtBold;
  Center ('Press RESUME to begin formatting');
  Center ('or Press MAIN SCREEN to cancel and return to main menu');
  Repeat
    I := (RawChar and CapsLockMask);
    If I = MainScreenKeyCode then
    begin
      Close (PriBootFile);
      Close (SecBootFile);
      Exit;
    end
    else if I <> ResumeKeyCode then Write (^G);
  Until I = ResumeKeyCode;

  { We have been authorized to start formatting.  First of all, let's make
    sure we can't exit from here on. }
  EXITAllowed := False;

  { Now set up some initial things. }
  FillChar (SectorTable, 2*(TrackLimit+1), 0);{ Initially, all sectors good }
  FillChar (ASTVector, 3*800, 0);             { No alternate sectors initially }

  With HOMBlock.HOM do
  begin
    { Initialize the controller, since we can't be sure this was done properly
      before.  Also fill in the appropriate fields in the BIOS. }
    HDMAXTRK[CurrentDrive]^  := (Cylinders * Surfaces) - 1;
    HDSTEPR[CurrentDrive]^   := StepRate;
    HDPRECOMP[CurrentDrive]^ := PreCompValue;
    { Initialize controller, then wait a bit for it to settle }
    Port[Command2Port] := 2;
    J := 1; For I := 1 to 500 do j := j + 1;
    { Set precomp and SDH registers }
    Port[PrecompPort] := PreCompValue;
    Port[SDHPort] := $20; { 512 byte sectors, head 0, drive 0 }
    { Set task file registers for track 0, sector 1 }
    Port[CylinderLowPort] := 0;
    Port[CylinderHighPort] := 0;
    Port[SectorNumberPort] := 1;
    Port[SectorCountPort] := 1;
    { Issue "restore" command with correct step rate, then wait for it
      to finish }
    ISRFlag[CurrentDrive]^ := 0;
    Port[CommandPort] := (StepRate and $0F) + $10;
    If not HDDone then
    begin
      DrawOutline;
      Write (^G);
      FVRow := 10;  FVAttribute := AtBold;
      Center ('FATAL ERROR -- UNABLE TO RESET HARD DISK');
      WriteLn;
      Center ('Something appears to be wrong with your hard disk hardware');
      Center ('It cannot be formatted and initialized');
      WriteLn;
      Center ('Press any key to continue');
      I := RawChar;
      Close (PriBootFile);
      Close (SecBootFile);
      Exit;
    end;
  end;

  { Now it's time to actually format the disk.  We'll do calls to the
    BIOS formatting routines to do this.  We'll start at the last track
    number (after subtracting enough tracks for one cylinder) and format
    each track in turn, working toward track 0.  After each track is
    formatted, we may also attempt to do a write (with verify) of up to two
    different types of data for each sector (depending on the formatting mode
    selected).  We'll mark bad sectors wherever this fails.  We'll also mark
    all sixteen sectors in a track as bad if the format fails.  Note that we
    skip the last cylinder in formatting because, for most manufacturers of
    hard disks, there is special data there which describes manufacturing
    defects.  We don't want to write over it or change its format (it is
    written using 256-byte sectors). }

  DrawOutline;
  FVAttribute := AtNormal;
  If FormattingMode <> FMInitializeOnly then
  begin
    J := 0; { Accumulated bad sector count }
    FillChar (ZeroesData, 512, 0);
    FillChar (OnesData, 512, $5A); { 0 1 0 1 1 0 1 0 }
    For Trk := (HDMAXTRK[CurrentDrive]^ - HOMBlock.HOM.Surfaces) downto 0 do
    begin
      FVRow := 12;
      Str (Trk:4, TrackDisplay);
      Center (Concat ('Now formatting track: ', TrackDisplay));
      If not FormatTrack (Trk) then
      begin
        SectorTable[Trk].Num := $FFFF;
        J := J + 16;
      end
      else if FormattingMode <> FMNoVerify then For Sec := 1 to 16 do
      begin
        If FormattingMode = FMDoubleVerify then
        begin
          If (not WriteSector (Trk, Sec, OnesData)) or
             (not WriteSector (Trk, Sec, ZeroesData)) then
          begin
            MarkSectorBad (Trk, Sec);
            J := J + 1;
          end;
        end
        else
        begin
          If (not WriteSector (Trk, Sec, ZeroesData)) then
          begin
            MarkSectorBad (Trk, Sec);
            J := J + 1;
          end;
        end;
      end {For each sector If not no verify mode};
      If J > 0 then { If bad sectors, display count so far }
      begin
        Str (J, TrackDisplay);
        Center (Concat ('Bad sectors detected: ', TrackDisplay));
      end {If bad sectors};
    end {For each track};
  end {If not just initializing};

  { We have completed formatting.  Now it's time to initialize the disk with
    the data we've set up.  First, write the HOM block. }
  FVRow := 12;
  Center ('Formatting completed; Now initializing disk...');
  WriteMajorBlock (0, 2, HOMBlock);
  { Write the AST and BAT blocks, because we have routines which do that.
    Note that the AST blocks will always indicate no alternate sectors
    assigned, even if there are bad sectors.  This is because the assignment
    of alternate sectors is done in the partitioning phase for CP/M and CCP/M
    partitions. }
  WriteBATBlocks;
  WriteASTBlocks;
  { Build and write a DPD block.  The block will show no partitions built. }
  FillChar (TempBlock, 512, 0);
  With TempBlock.DPD do
  begin
    ID := 'DPD';
    MaxEntries := 15;
  end;
  With HOMBlock.HOM.DPDLocation do WriteMajorBlock (Track, Sector, TempBlock);
  { Build and write an OSN block.  This block will show the standard operating
    systems in positions 1, 2, and 3.  Additionally, position 7 will show the
    VENIX/Rainbow operating system (don't know why they choose 7 instead of 4).
    Postition zero and all between 3 and 7 will be nulls. }
  FillChar (TempBlock, 512, 0);
  With TempBlock.OSN do
  begin
    ID := 'OSN';
    MaxEntries := 31;
    Entry[1] := 'CP/M-86/80      ';
    Entry[2] := 'MS-DOS          ';
    Entry[3] := 'CCP/M-86        ';
    Entry[7] := 'VENIX/Rainbow   ';
  end;
  With HOMBlock.HOM.OSNLocation do WriteMajorBlock (Track, Sector, TempBlock);

  { We've written almost everything.  The remainder of what we will write comes
    from the boot files (.LDX) we have.  Note that there is a potential
    problem here: these files could have been found on the hard disk!  If this
    is the case, this will probably not work, but this serves the person right,
    I suppose. }
  WriteBootCode;
  Close (PriBootFile);
  Close (SecBootFile);

  { We've finished the formatting and initializing process.  Now tell the
    guy we're done, and we can return. }
  DrawOutline;
  FVRow := 8;  FVAttribute := AtBold;
  Center ('Your disk has been formatted and initialized.');
  FVAttribute := AtNormal;
  WriteLn;
  Center ('However, your hard disk does not yet have any partitions');
  Center ('defined.  You should now proceed to the "repartition disk"');
  Center ('function to install partitions on your disk and make it usable.');
  FVRow := 20;  FVAttribute := AtBold;
  Center ('Press any key to continue');
  I := RawChar;
end {FormatAndInitialize};

{ SetAutoBoot - Sets/changes auto boot partition. }
overlay procedure SetAutoBoot;
var
  Current :Integer;
  Pointer :Integer;
  I, J    :Integer;
begin
  If Not ReadMajorBlocks then Exit;
  DrawOutline;
  FVAttribute := AtBold;
  FVRow := 2;
  Center ('Boot Partition Selection');
  FVRow := 23;
  Center
   ('Use arrows to select, then press DO to set; press MAIN SCREEN when done');
  StartFastVideo (15, 4, AtDefault, 79, 23);
  WriteFastLn ('Partition  Drive  Operating System');
  WriteLn;
  WriteFastLn (' (no auto boot)');
  Current := 0;
  With DPDBlock.DPD do For I := 1 to EntryCount do With Entry[I] do
  begin
    WriteFastLn (Concat (Name, '     ',
                         Chr (Ord('A')+LogicalUnit-1), ':   ',
                         OSNBlock.OSN.Entry[OSNIndex]));
    If HOMBlock.HOM.BootTrack = FirstTrack then Current := I;
  end;
  Pointer := Current;

  while True do { Repeat until main screen key or exit key }
  begin
    StartFastVideo (9, 6, AtBold, 79, 24);
    For I := 0 to DPDBlock.DPD.EntryCount do
    begin
      If I = Pointer then
      begin
        If I = Current then WriteFastLn ('--> *')
                       else WriteFastLn ('-->  ');
      end
      else
      begin
        If I = Current then WriteFastLn ('    *')
                       else WriteFastLn ('     ');
      end;
    end;
    J := (RawChar and CapsLockMask);
    If (J = UpArrowKeyCode) and (Pointer > 0) then
      Pointer := Pointer - 1
    else if (J = DownArrowKeyCode) and (Pointer < DPDBlock.DPD.EntryCount) then
      Pointer := Pointer + 1
    else if (J = DoKeyCode) then
    begin
      Current := Pointer;
      If Current = 0 then
      begin
        HOMBlock.HOM.BootTrack := 0;
        HOMBlock.HOM.AutoBoot := $FF;
      end
      else
      begin
        HOMBlock.HOM.BootTrack := DPDBlock.DPD.Entry[Current].FirstTrack;
        HOMBlock.HOM.AutoBoot := DPDBlock.DPD.Entry[Current].LogicalUnit;
      end;
      WriteMajorBlock (0, 2, HOMBlock);
    end
    else if (J = MainScreenKeyCode) then Exit
    else Write (^G);
  end;
end {SetAutoBoot};

{ DumpSector - Dumps the contents of a sector to the screen. }
overlay procedure DumpSector;
var
  Track         :Integer;
  MaxTracks     :Integer;
  Sector        :Byte;
  StartLine     :Integer;
  I, J          :Integer;
  K             :Byte;
  HaveSector    :Boolean;
  DisplayNeeded :Boolean;
  XlateMode     :Boolean;
  DisplayAttribute :Integer; { Attribute used to display dump data }
  TSRadix       :Integer; { Radix in which track & sector are displayed 10/16 }
  LineOfDump    :Array [0..31] OF Str80;
begin
  { Try to read the HOM block from the disk in order to determine the number
    of surfaces the disk has.  If we fail, we'll still try to process things
    and continue to assume 4 surfaces on the disk, but we'll warn that this
    may be problematical. }
  HOMBlock.HOM.Surfaces := 4;
  If not ReadHOMBlock (0, 2, HOMBlock) then
  begin
    DrawOutline;
    FVRow := 7;
    FVAttribute := AtBold;
    Write (^G);
    Center ('Your disk is not initialized!');
    FVAttribute := AtNormal;
    WriteLn;
    Center ('Your disk does not appear to be properly initialized.');
    Center ('WUTIL is unable to read the disk''s HOM block in order to');
    Center ('determine information about the disk''s geometry.');
    Center ('Specifically, WUTIL cannot determine how many surfaces (heads)');
    Center ('your disk has.  This information is required in order to map');
    Center ('track numbers into their Cylinder/Surface equivalents.');
    Center ('WUTIL will continue processing with the assumption that');
    Center ('your disk drive, like most Rainbow winchester disks, has four');
    Center ('surfaces.  If this is not the case, the data from this');
    Center ('dump facility will be unreliable.');
    WriteLn;
    FVAttribute := AtBold;
    Center ('Press any key to continue...');
    I := RawChar;
    { Since we couldn't read the HOM block, it is unlikely that MS-DOS could
      either.  The value of MAXTRK in the BIOS, therefore, is suspect: It may
      be too low.  We'll set it to an artificially high value in order to
      guarantee that we always TRY to read the track specified.  This is,
      perhaps, not ideal, but it is the best we can do under the
      circumstances. }
    HDMAXTRK[CurrentDrive]^ := 1023;
  end;

  { Now, various initializations. }
  HaveSector := FALSE;
  DisplayNeeded := TRUE;
  XlateMode := FALSE;
  Track := 0;
  MaxTracks := HOMBlock.HOM.Cylinders * HOMBlock.HOM.Surfaces - 1 - HOMBlock.HOM.Surfaces;
  Sector := 1;
  TSRadix := 16;
  DrawOutline;
  StartFastVideo (2, 6, AtDefault, 79, 23);
  DrawBox (11, 2, 20, 4, AtBold);  DrawBox (61, 2, 70, 4, AtBold);
  FVAttribute := AtBold; FVRow := 4;
  FVColumn := 14; WriteFast ('Track');
  FVColumn := 63; WriteFast ('Sector');
  DrawBox (3, 6, 78, 23, AtBold);
  StartFastVideo (6, 7, AtDefault, 77, 22);
  FVRow := 6; FVColumn := 6;
  WriteFastLn
   ('xF xE xD xC xB xA x9 x8|x7 x6 x5 x4 x3 x2 x1 x0  offs  0123456789ABCDEF');
  { Note: The loop which follows displays stuff and handles function keys.
    The display area is exactly 16 lines long, and the routines here will
    be entered with the current position at the upper left of the display
    area.  Routines which display things should always display exactly 16
    lines, so that previous data will be overwritten. }
  while TRUE do { loop forever (until EXIT or MAIN SCREEN key) }
  begin
    { First update track and sector fields }
    FVAttribute := AtBold; FVRow := 3;
    FVColumn := 14;
    if TSRadix = 16 then WriteFast (Hex4Digit (Track))
                    else Write (Track:4);
    FVColumn := 63;
    if not XlateMode then
    begin
      WriteFast ('  ');
      if TSRadix = 16 then WriteFast (Hex2Digit (Sector))
                      else Write (Sector:2);
      WriteFast (' ');
    end
    else
    begin
      if TSRadix = 16 then WriteFast (Hex2Digit (Sector))
                      else Write (Sector:2);
      WriteFast ('=');
      if TSRadix = 16 then WriteFast (Hex2Digit (Xlate(Sector)))
                      else Write (Xlate(Sector):2);
    end;
    FVColumn := FVLMargin; FVRow := FVTMargin; FVAttribute := AtDefault;
    if DisplayNeeded then
    begin
      { We'll either display the help screen or the data depending on whether
        we "have a sector" or not. }
      if HaveSector then
      begin
        FVRow := 3; FVAttribute := AtBold;
        Center ('Press HELP key for help');
        FVRow := FVTMargin; FVAttribute := DisplayAttribute;
        for I := StartLine to StartLine + 15 do WriteFastLn (LineOfDump[I]);
      end
      else {if not HaveSector then}
      begin
        FVRow := 3;
        Center ('                       ');
        FVRow := FVTMargin; FVAttribute := AtNormal;
        WriteFastLn
    ('General instructions for sector dump facility:                          ');
        WriteFastLn
    ('* LEFT and RIGHT ARROWs decrease or increase sector number by 1''s      ');
        WriteFastLn
    ('* SHIFT LEFT/RIGHT ARROWs decrease/increase track number by 1''s        ');
        WriteFastLn
    ('* CTRL LEFT/RIGHT ARROWs decrease/increase track number by 10''s        ');
        WriteFastLn
    ('* CTRL SHIFT LEFT/RIGHT ARROWs decrease/increase track numbers by 100''s');
        WriteFastLn
    ('* After selecting track and sector, pressing DO reads & displays, e.g.:');
        FVAttribute := AtReverseBold;
        WriteFastLn
    ('20 20 20 20 20 47 46 45|20 20 20 20 44 43 42 41  0000  ABCD    EFG     ');
        FVAttribute := AtNormal;
        WriteFastLn
    ('  <---------- data in hexadecimal -------------  addr  ----in ASCII--->');
        WriteFastLn
    ('  Display lines are read from the address out; text is read normally;  ');
        WriteFastLn
    ('  Hex is read RIGHT TO LEFT (This may appear odd, but it makes for more');
        WriteFastLn
    ('  "natural" reading of multi-byte numeric values -- high order first!).');
        WriteFastLn
    ('* UP and DOWN ARROWs and NEXT SCREEN and PREV SCREEN scroll display    ');
        WriteFastLn
    ('* SELECT key toggles radix of track & sector (but dump is always hex)  ');
        WriteFastLn
    ('* The ADDTNL OPTIONS key toggles sector xlate mode (for partition data)');
        WriteFastLn
    ('* The HELP key redisplays this text                                    ');
        WriteFastLn
    ('* The MAIN SCREEN key returns to the WUTIL main menu, EXIT goes to DOS ');
      end;
      DisplayNeeded := FALSE;
    end;
    I := (RawChar and CapsLockMask);
    if I = DoKeyCode then
    begin
      FVAttribute := AtReverse;
      for j := 1 to 7 do WriteFastLn
    ('                                                                       ');
      WriteFastLn
    ('                        Reading; please wait...                        ');
      for j := 1 to 8 do WriteFastLn
    ('                                                                       ');
      if XlateMode then K := Xlate(Sector) else K := Sector;
      if ReadSector (Track, K, TempBlock) then
      begin
        HaveSector := True;
        DisplayNeeded := True;
        DisplayAttribute := AtReverseBold;
        StartLine := 0;
        for I := 0 to 31 do
        begin
          LineOfDump[I] := '';
          for J := ((I*16)+15) downto (I*16) do
          begin
            LineOfDump[I] := Concat (LineOfDump[I],
                                     Hex2Digit (TempBlock.SectorBytes[J]), ' ');
          end;
          LineOfDump[I] := Concat (LineOfDump[I], ' ', Hex4Digit(I*16), '  ');
          for J := (I*16) to ((I*16)+15) do
          begin
            LineOfDump[I] := Concat (LineOfDump[I],
                                     PrintChar(TempBlock.SectorBytes[J]));
          end;
          Delete (LineOfDump[I], 24, 1);
          Insert ('|', LineOfDump[I], 24);
        end;
      end
      else { Read failed }
      begin
        HaveSector := False;
        DisplayNeeded := False;
        Write (^G);
        for j := 1 to 7 do WriteFastLn
    ('                                                                       ');
        WriteFastLn
    ('                -- UNABLE TO READ REQUESTED SECTOR --                  ');
        for j := 1 to 8 do WriteFastLn
    ('                                                                       ');
      end;
    end
    else if (I = SelectKeyCode) then TSRadix := 26 - TSRadix
    else if (I = UpArrowKeyCode) and (HaveSector) and (StartLine > 0) then
    begin
      StartLine := StartLine - 1;
      DisplayNeeded := True;
    end
    else if (I = DownArrowKeyCode) and (HaveSector) and (StartLine < 16) then
    begin
      StartLine := StartLine + 1;
      DisplayNeeded := True;
    end
    else if (I = PrevScreenKeyCode) and (HaveSector) and (StartLine > 0) then
    begin
      StartLine := 0;
      DisplayNeeded := True;
    end
    else if (I = NextScreenKeyCode) and (HaveSector) and (StartLine < 16) then
    begin
      StartLine := 16;
      DisplayNeeded := True;
    end
    else if (I = AddtnlOptionsKeyCode) then
    begin
      XlateMode := (not XlateMode);
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = LeftArrowKeyCode) and ((Sector > 1) or (Track > 0)) then
    begin
      PrevSector (Track, Sector);
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = RightArrowKeyCode) and ((Sector < 16) or (Track < MaxTracks)) then
    begin
      NextSector (Track, Sector);
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Shift+LeftArrowKeyCode) and (Track > 0) then
    begin
      Track := Track - 1;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Shift+RightArrowKeyCode) and (Track < MaxTracks) then
    begin
      Track := Track + 1;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Ctrl+LeftArrowKeyCode) and (Track > 0) then
    begin
      Track := Track - TSRadix;
      if Track < 0 then Track := 0;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Ctrl+RightArrowKeyCode) and (Track < MaxTracks) then
    begin
      Track := Track + TSRadix;
      if Track > MaxTracks then Track := MaxTracks;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Ctrl+Shift+LeftArrowKeyCode) and (Track > 0) then
    begin
      Track := Track - TSRadix*TSRadix;
      if Track < 0 then Track := 0;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if (I = Ctrl+Shift+RightArrowKeyCode) and (Track < MaxTracks) then
    begin
      Track := Track + TSRadix*TSRadix;
      if Track > MaxTracks then Track := MaxTracks;
      if (HaveSector) and (DisplayAttribute = AtReverseBold) then
      begin
        DisplayNeeded := True;
        DisplayAttribute := AtReverse;
      end;
    end
    else if I = HelpKeyCode then
    begin
      HaveSector := False;
      DisplayNeeded := True;
    end
    else if I = MainScreenKeyCode then Exit
    else Write (^G);
  end;

end {DumpSector};

overlay procedure ParkHeadsForShipping;
var
  I :Integer;
  CylNum :String [10];
begin
  If not ReadMajorBlocks then Exit;
  DrawOutline;
  With HOMBlock.HOM do
  begin
    Str (Cylinders, CylNum);
    ManualSeek (Cylinders, StepRate);
  end;
  FVRow := 5; FVAttribute := AtBold;
  Center (Concat ('The controller has been commanded to seek to cylinder ',
                  CylNum));
  FVAttribute := AtNormal;
  Center ('This cylinder is one cylinder beyond the last valid data cylinder');
  WriteLn;
  Center ('On most hard disk drives, this will park the read/write heads');
  Center ('in a "shipping zone" to protect damage to the disk surface or');
  Center ('to your data during transportation.');
  WriteLn;
  Center ('Your drive may not work this way.  You should always be very');
  Center ('careful to pack your drive well prior to moving or shipping it.');
  WriteLn;
  FVAttribute := AtBold;
  Center ('To preserve the protection afforded by this function,');
  Center ('TURN OFF YOUR SYSTEM NOW!');
  FVAttribute := AtNormal;
  WriteLn;
  Center
  ('Further accesses to the disk will move the heads out of the shipping zone');
  Center ('(Press any key if you wish to continue anyway)');
  I := RawChar;
end {ParkHeadsForShipping};
