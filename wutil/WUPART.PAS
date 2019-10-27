{** file wupart.pas © Copyright 1986 Anthony G. Camas, all rights reserved **}
{ RepartitionDisk - Repartitions the hard disk. }
overlay procedure RepartitionDisk;

Const
  { The following represent the standard positions in the OSN block for the
    four Rainbow operating systems.  In theory, each partition is defined
    with an index into the OSN area, and the name stored there determines
    which operating system the partition uses.  In practice, this is nearly
    unworkable, and all the operating systems search for their partitions
    by finding those which use a specific OSN index.  We will take our cue
    from that practice, and use fixed OSN index values for determining which
    operating system a partition uses.  The names we display in the editing
    phase will still come from the OSN block, but we'll use these indexes
    to determine how to initialize the partitions, to determine the maximum
    size of a partition, etc. }
  CPMIndex   = 1;
  MSDOSIndex = 2;
  CCPMIndex  = 3;
  VENIXIndex = 7;

Type
  PartitionData = Record
    Tracks   :Integer;  { Number of tracks devoted to partition }
    OS       :Integer;  { Index of operating system in OSN block }
    Descrip  :Str80;    { Description line for partition to show on screen }
  End;

Var
  DiskCapacity          :Integer; { In tracks }
  AllocDifference       :Integer; { Diff between capacity and amount actually
                                    allocated, in tracks.  + means allocation is
                                    over capacity, - means allocation is under }
  Partition             :Array [1..30] of PartitionData;
  TempDPD               :SectorBlock;
  TempPartition,
  DeletedPartition      :PartitionData;
  Trk                   :Integer;
  Sec                   :Byte;
  LastOS                :Integer;
  LastCPMUnit           :Integer;
  NumberOfPartitions    :Integer;
  Current               :Integer;
  I, J, K               :Integer;
  DisplayNeeded         :Boolean;
  DoKeyPressed          :Boolean;
  SomethingDeleted      :Boolean;
  ErrorExists           :Boolean;
  ErrorMessage          :String [45];
  MaxMSDOSSize          :Integer;

  {sub}function MinSize (OS :Integer) :Integer;
  { Return the minimum size (in tracks) allowed for an entry (partition or
    gap), given the operating system code }
  begin
    if OS = -1 then MinSize := 1
      else if OS = VENIXIndex then MinSize := 22
      else MinSize := 128;
  end {MinSize};

  {sub}function MaxSize (OS :Integer) :Integer;
  { Return the maximum size (in tracks) allowed for an entry (partition or
    gap), given the operating system code }
  begin
    if OS = -1 then MaxSize := DiskCapacity
    else if OS = MSDOSIndex then MaxSize := MaxMSDOSSize
    else if OS = VENIXIndex then MaxSize := 4096
    else MaxSize := 1024;
  end {MaxSize};

  {sub}procedure FormDescrip (Var Part :PartitionData);
  var
    Trks  :String [4];
    MB    :String [5];
    MBVal :Real;
  begin
    MBVal := Part.Tracks * 8.0 / 1024.0;
    Str (Part.Tracks:4, Trks);
    Str (MBVal:5:3, MB);
    Part.Descrip := Concat (Trks, ' (', MB, ') ');
    if Part.OS = -1 then
      Part.Descrip := Concat (Part.Descrip, '----- GAP ----- ')
    else
      Part.Descrip := Concat (Part.Descrip, OSNBlock.OSN.Entry[Part.OS]);
  end {FormDescrip};

  {sub}procedure ReadySummaryLine;
  begin
    FVRow := 22; FVColumn := 2; FVAttribute := AtNormal;
    WriteFast
('                                                                             ');
    FVRow := 22; FVColumn := 5;
  end {ReadySummaryLine};

  {sub}procedure PrintSummary;
  var
    Temp :String [10];
    Line :String [80];
  begin
    ReadySummaryLine;
    Str (DiskCapacity, Temp);
    Line := Concat ('Disk capacity is ', Temp, ' tracks (');
    Str ((DiskCapacity * 8.0 / 1024.0):5:3, Temp);
    Line := Concat (Line, Temp, 'MB).  ');
    WriteFast (Line);
    if AllocDifference = 0 then
      WriteFast ('All tracks allocated.')
    else if AllocDifference < 0 then
    begin
      Str ((-AllocDifference), Temp);
      Line := Concat (Temp, ' track');
      if AllocDifference < -1 then Line := Concat (Line, 's');
      FVAttribute := AtBold;
      WriteFast (Concat (Line, ' not allocated.'));
    end
    else
    begin
      Str (AllocDifference, Temp);
      Line := Concat (Temp, ' track');
      if AllocDifference > 1 then Line := Concat (Line, 's');
      FVAttribute := AtBlinkBold;
      WriteFast (Concat ('OVER capacity by ', Line, '!'));
    end;
  end {PrintSummary};

  {sub}procedure PaintScreen;
  begin
    DrawOutline;
    StartFastVideo (5, 5, AtDefault, 79, 23);
    FVRow := 2; FVAttribute := AtBold;
    Center ('WUTIL Partition Editor: Press HELP key for instructions');
    FVRow := 4; FVAttribute := AtNormal;
    WriteFastLn
     (' #  Tracks (MB)  Operating System   #  Tracks (MB)  Operating System');
    WriteLn;
    For I := 1 to 15 do
      WriteLn (I:2, '.                                ', (I+15):2, '.');
    PrintSummary;
  end {PaintScreen};

  {sub}procedure DisplayItem (Index :Integer; Attribute :Integer);
  begin
    If Index < 16 then
      StartFastVideo ( 9, (Index+5),  Attribute, 79, 23)
    else
      StartFastVideo (44, (Index-10), Attribute, 79, 23);
    If Index > NumberOfPartitions then
      WriteFastLn ('                             ')
    else
      WriteFastLn (Partition[Index].Descrip);
  end {DisplayItem};

begin {RepartitionDisk}
  { Read current disk information, exit (with message) if we can't }
  if not ReadMajorBlocks then Exit;

  WITH HOMBlock.HOM DO K := FirstAltTrack + NumAltTracks;
  NumberOfPartitions := 0;
  I := 1;
  while (I <= DPDBlock.DPD.EntryCount) AND (NumberOfPartitions < 30) DO
  begin
    NumberOfPartitions := NumberOfPartitions + 1;
    WITH DPDBlock.DPD.Entry[I] DO WITH Partition[NumberOfPartitions] DO
    begin
      If FirstTrack <> K then
      begin
        Tracks := FirstTrack - K;
        OS := -1;
        K := FirstTrack;
      end
      else
      begin
        Tracks := LastTrack - FirstTrack + 1;
        OS := OSNIndex;
        I := I + 1;
        K := LastTrack + 1;
      end;
    end;
    FormDescrip (Partition[NumberOfPartitions]);
  end;

  { We get out of the loop above when we either fill the partition array,
    process all the DPD partition entries, or both.  If we have not processed
    all DPD partitions yet, this means we filled our internal array, and this
    is an error (see above). }
  if I <= DPDBlock.DPD.EntryCount then
  begin
    DrawOutline;
    StartFastVideo (3, 10, AtBold, 78, 23);
    Center ('Your disk contains more than 30 partitions or unallocated gaps!');
    WriteLn;
    Center ('Sorry, but WUTIL can handle a maximum of 30 partitions+gaps');
    Center ('You cannot use the WUTIL Partition Editor');
    FVRow := 22;
    Center ('Press any key to continue');  
    I := RawChar;
    Exit;
  end;

  { There may be a gap at the end of the defined partitions.  If there is
    still room in the partition array for another entry, and if we have not
    reached the correct ending track, create one more entry for a "gap" }
  WITH HOMBlock.HOM DO
  If (NumberOfPartitions < 30) and (K < (MaintCylinder * Surfaces)) then
  begin
    NumberOfPartitions := NumberOfPartitions + 1;
    WITH Partition[NumberOfPartitions] DO
    begin
      Tracks := (MaintCylinder * Surfaces) - K;
      OS := -1;
    end;
    FormDescrip (Partition[NumberOfPartitions]);
  end;

  { Next, determine the index of the last operating system defined in the OSN
    block.  NOTE that we assume position 0 in the OSN table is not used (it
    is not by any current rainbow partitioning software, including ours). }
{******************************************************************************
    With the addition of VENIX/Rainbow this code has been commented out, since
    we know that VENIX is entry 7 in the OSN block.  We'll ignore the fact,
    that entries 4-6 are not used.
  I := 1;
  While ORD (OSNBlock.OSN.Entry[I][0]) <> 0 do I := I + 1;
  LastOS := I - 1;
*******************************************************************************}
  { Make VENIX the last OS instead }
  LastOS := VENIXIndex;

  { Determine total capacity of disk in tracks.  Then add up the sizes of all
    the partitions currently on the disk and compute the difference, if any,
    between this and the total capacity we determined. }
  WITH HOMBlock.HOM DO DiskCapacity := (MaintCylinder * Surfaces) -
                                       (FirstAltTrack + NumAltTracks);
  AllocDifference := 0;
  For I := 1 to NumberOfPartitions do AllocDifference :=
                                      AllocDifference + Partition[I].Tracks;
  AllocDifference := AllocDifference - DiskCapacity;

  { Determine the maximum size of an MS-DOS partition.  This is 8MB in versions
    of MS-DOS prior to 3.0, (almost) 32MB in versions 3.0 and after. }
  If MSDOSVersion < 3 then MaxMSDOSSize := 1024 else MaxMSDOSSize := 4095;

  { Now we can draw the screen and fill in the initial things that will always
    be there. }

  PaintScreen;

  { Indicate we will need to display the current list of partitions the first
    time into our loop, and initialize other things. }

  Current := 1;
  DisplayNeeded := True;
  DoKeyPressed := False;
  SomethingDeleted := False;

  { We are now ready to enter the main loop of the partition editor.  In it,
    we will display new data if necessary and then wait for a key to tell us
    what to do next. }

  Repeat {Until DoKeyPressed}
    { Main loop:  First, see if we should display everything.  If so, do it. }
    if DisplayNeeded then
    begin
      for I := 1 to 30 do
      begin
        if I = Current then DisplayItem (I, AtReverse)
                       else DisplayItem (I, AtNormal);
        DisplayItem (I, FVAttribute);
      end;

      DisplayNeeded := False;
    end;

    { Now wait for a character saying what the user wants us to do }
    I := (RawChar AND CapsLockMask);

    { See what character we got and dispatch accordingly }
    if (I = UpArrowKeyCode) and (Current > 1) then
    begin
      Current := Current - 1;
      DisplayNeeded := True;
    end
    else if (I = DownArrowKeyCode) and (Current < Min (NumberOfPartitions + 1,
                                                       30)) then
    begin
      Current := Current + 1;
      DisplayNeeded := True;
    end
    else if (I = Shift+UpArrowKeyCode) and (Current > 1)
        and (Current <= NumberOfPartitions) then
    begin
      TempPartition := Partition[Current-1];
      Partition[Current-1] := Partition[Current];
      Partition[Current] := TempPartition;
      Current := Current - 1;
      DisplayNeeded := True;
    end
    else if (I = Shift+DownArrowKeyCode) and (Current < NumberOfPartitions) then
    begin
      TempPartition := Partition[Current+1];
      Partition[Current+1] := Partition[Current];
      Partition[Current] := TempPartition;
      Current := Current + 1;
      DisplayNeeded := True;
    end
    else if (I = LeftArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks > MinSize(Partition[Current].OS)) then
    begin
      { Since the largest legal MS-DOS partition size for 12-bit FATS is 1024
        tracks and the smallest legal MS-DOS partition size for 16-bit FATS is
        1028 tracks, we have to make sure that no MS-DOS partition can be
        created with the size of either 1025, 1026, or 1027 tracks }
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          = 1028) then J := 4 else J := 1;
      Partition[Current].Tracks := Partition[Current].Tracks - J;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference - J;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = RightArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks < MaxSize(Partition[Current].OS)) then
    begin
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          = 1024) then J := 4 else J := 1;
      Partition[Current].Tracks := Partition[Current].Tracks + J;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference + J;
      DisplayNeeded := True;
      PrintSummary;
    end

    else if (I = Shift+LeftArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks > MinSize(Partition[Current].OS)) then
    begin
      J := Min (10, Partition[Current].Tracks-MinSize(Partition[Current].OS));
      Partition[Current].Tracks := Partition[Current].Tracks - J;
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          > 1024) and (Partition[Current].Tracks < 1028) then
      begin
        J := J + Partition[Current].Tracks - 1024;
        Partition[Current].Tracks := 1024;
      end;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference - J;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = Shift+RightArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks < MaxSize(Partition[Current].OS)) then
    begin
      J := Min (10, MaxSize(Partition[Current].OS)-Partition[Current].Tracks);
      Partition[Current].Tracks := Partition[Current].Tracks + J;
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          > 1024) and (Partition[Current].Tracks < 1028) then
      begin
        J := J - Partition[Current].Tracks + 1028;
        Partition[Current].Tracks := 1028;
      end;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference + J;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = Ctrl+LeftArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks > MinSize(Partition[Current].OS)) then
    begin
      J := Min (100, Partition[Current].Tracks-MinSize(Partition[Current].OS));
      Partition[Current].Tracks := Partition[Current].Tracks - J;
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          > 1024) and (Partition[Current].Tracks < 1028) then
      begin
        J := J + Partition[Current].Tracks - 1024;
        Partition[Current].Tracks := 1024;
      end;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference - J;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = Ctrl+RightArrowKeyCode) and (Current <= NumberOfPartitions)
        and (Partition[Current].Tracks < MaxSize(Partition[Current].OS)) then
    begin
      J := Min (100, MaxSize(Partition[Current].OS)-Partition[Current].Tracks);
      Partition[Current].Tracks := Partition[Current].Tracks + J;
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          > 1024) and (Partition[Current].Tracks < 1028) then
      begin
        J := J - Partition[Current].Tracks + 1028;
        Partition[Current].Tracks := 1028;
      end;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference + J;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = SelectKeyCode) and (Current <= NumberOfPartitions) then
    begin
      J := Partition[Current].OS + 1;
      { When cycling through the operating system choices with the SELECT
        key, we do not want to do that in the sequence of the OS indices, which
        is 'GAP  CP/M  MS-DOS  CCP/M'.  Since mostly MS-DOS partitions are
        used nowadays we want this sequence: 'GAP  MS-DOS  CP/M  CCP/M'.  To
        achieve this, we have to manipulate the OS index pointer a little bit }
      if J = 0 then J := 2
      else if J = 3 then J := 1
      else if J = 2 then J := 3
      else if J = 4 then J := 7
      else if J > LastOS then J := -1;
      Partition[Current].OS := J;
      { Check that the partition is not now too small for its new operating
        system.  If so, then increase its size to the minimum. }
      K := MinSize (J);
      If Partition[Current].Tracks < K then
      begin
        AllocDifference := AllocDifference + K - Partition[Current].Tracks;
        PrintSummary;
        Partition[Current].Tracks := K;
      end;
      { Now a similar check that the partition is not now too big for its
        new operating system.  If so, decrease its size to the maximum. }
      K := MaxSize (J);
      If Partition[Current].Tracks > K then
      begin
        AllocDifference := AllocDifference + K - Partition[Current].Tracks;
        PrintSummary;
        Partition[Current].Tracks := K;
      end;
      { And a check for MS-DOS partitions to not be 1025, 1026, or 1027 tracks
        in size }
      if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
          > 1024) and (Partition[Current].Tracks < 1028) then
      begin
        AllocDifference := AllocDifference + 1024 - Partition[Current].Tracks;
        PrintSummary;
        Partition[Current].Tracks := 1024;
      end;
      FormDescrip(Partition[Current]);
      DisplayNeeded := True;
    end
    else if (I = RemoveKeyCode) and (Current <= NumberOfPartitions) then
    begin
      SomethingDeleted := True;
      DeletedPartition := Partition[Current];
      AllocDifference := AllocDifference - DeletedPartition.Tracks;
      NumberOfPartitions := NumberOfPartitions - 1;
      for J := Current to NumberOfPartitions do
        Partition[J] := Partition[J+1];
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = InsertHereKeyCode) and (NumberOfPartitions < 30) then
    begin
      for J := NumberOfPartitions downto Current do
        Partition[J+1] := Partition[J];
      NumberOfPartitions := NumberOfPartitions + 1;
      { Form the size of the partition we will add.  Try and make it equal to
        the size of the current remaining space on the disk (if there is any).
        But in any case, it cannot be smaller than one track, nor can it be
        larger than the maximum allowed. }
      Partition[Current].Tracks := Min (MaxSize(-1),
                                        Max (1, (-AllocDifference)));
      Partition[Current].OS := -1;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference + Partition[Current].Tracks;
      DisplayNeeded := True;
      PrintSummary;
    end

    else if (I = Shift+InsertHereKeyCode) and (NumberOfPartitions < 30)
        and (SomethingDeleted) then
    begin
      for J := NumberOfPartitions downto Current do
        Partition[J+1] := Partition[J];
      NumberOfPartitions := NumberOfPartitions + 1;
      Partition[Current] := DeletedPartition;
      FormDescrip(Partition[Current]);
      AllocDifference := AllocDifference + Partition[Current].Tracks;
      DisplayNeeded := True;
      PrintSummary;
    end
    else if (I = AddtnlOptionsKeyCode) and (NumberOfPartitions > 0) then
    begin
      ReadySummaryLine;
      FVAttribute := AtNormal; WriteFast ('Press a key:  best ');
      FVAttribute := AtBold; WriteFast ('F');
      FVAttribute := AtNormal; WriteFast ('it current; ');
      FVAttribute := AtBold; WriteFast ('B');
      FVAttribute := AtNormal; WriteFast ('alance all');
      J := (RawChar AND CapsLockMask AND (NOT Shift));
      if      ((J = Ord ('F')) or (J = Ord ('f')))
          and (Current <= NumberOfPartitions) then
      begin
        AllocDifference := AllocDifference - Partition[Current].Tracks;
        Partition[Current].Tracks := Min (MaxSize(Partition[Current].OS),
                                          Max (MinSize(Partition[Current].OS),
                                               (-AllocDifference)));
        { Again, make sure our MS-DOS partition is not 1024, 1025, 1026 tracks 
          large }
        if (Partition[Current].OS = MSDOSIndex) and (Partition[Current].Tracks
            > 1024) and (Partition[Current].Tracks < 1028) then
            Partition[Current].Tracks := 1024;
        FormDescrip(Partition[Current]);
        AllocDifference := AllocDifference + Partition[Current].Tracks;
        DisplayNeeded := True;
      end
      else if (J = Ord ('B')) or (J = Ord ('b')) then
      begin
        AllocDifference := 0;
        I := DiskCapacity DIV NumberOfPartitions;
        J := DiskCapacity MOD NumberOfPartitions;
        For K := 1 to NumberOfPartitions do
        begin
          If J = 0 then Partition[K].Tracks := I else
          begin
            Partition[K].Tracks := I + 1;
            J := J - 1;
          end;
          { The above can leave us with something which is too big or too
            small for its operating system.  In a perfect world, we could
            figure out an intelligent algorithm to do something clever here
            to save the day, but unfortunately, this is not a perfect world.
            So if the result is too big or too small, we'll adjust it to
            bring it in line.  Yucky to be sure, but what else can we do? }
          If Partition[K].Tracks < MinSize(Partition[K].OS) then
          begin
            AllocDifference := AllocDifference + MinSize(Partition[K].OS)
                                               - Partition[K].Tracks;
            Partition[K].Tracks := MinSize(Partition[K].OS);
          end
          else if Partition[K].Tracks > MaxSize(Partition[K].OS) then
          begin
            AllocDifference := AllocDifference + MaxSize(Partition[K].OS)
                                               - Partition[K].Tracks;
            Partition[K].Tracks := MaxSize(Partition[K].OS);
          end;
          if (Partition[Current].OS = MSDOSIndex) and (Partition[K].Tracks
              > 1024) and (Partition[K].Tracks < 1028) then
          begin
            AllocDifference := AllocDifference + 1024 - Partition[K].Tracks;
            Partition[K].Tracks := 1024;
          end;
          FormDescrip (Partition[K]);
        end;
        DisplayNeeded := True;
      end
      else Write (^G);
      PrintSummary;
    end
    else if I = MainScreenKeyCode then Exit { Main screen aborts back to menu }

    else if I = HelpKeyCode then
    begin
      DrawOutline;
      FVAttribute := AtBold;
      Center ('WUTIL Partition Editor Instructions');
      WriteLn;
      FVAttribute := AtDefault;
      WriteFastLn
('The partition editor allows you to interactively manipulate the way');
      WriteFastLn
('your hard disk is partitioned.  After you have set up the partitions');
      WriteFastLn
('the way you want, you press the DO key to actually perform partitioning.');
      WriteLn;
      WriteFastLn
('The current partitions are always displayed.  Keys work like this:');
      WriteLn;
      WriteFastLn
('UP and DOWN arrows select a different line for editing (the "current" line).');
      WriteFastLn
('RIGHT and LEFT arrows increase or decrease the size of the current partition.');
      WriteFastLn
('SHIFT or CTRL + RIGHT and LEFT arrows do the same thing, but faster.');
      WriteFastLn
('SHIFT + UP and DOWN arrows "move" the current partition in that direction.');
      WriteFastLn
('SELECT changes the current partition''s operating system (cycles choices).');
      WriteFastLn
('INSERT HERE adds a new partition before the current partition.');
      WriteFastLn
('REMOVE deletes the current partition and saves its description.');
      WriteFastLn
('SHIFT + INSERT HERE inserts the saved partition (undeletes).');
      WriteFastLn
('ADDTNL OPTIONS, then "F" adjusts the current partition size for "best fit".');
      WriteFastLn
('ADDTNL OPTIONS, then "B" balances all partition sizes (makes same).');
      WriteFastLn
('When done, press DO to perform the partitioning, or MAIN SCREEN to abort.');
      WriteLn;
      FVAttribute := AtBold;
      WriteFastLn
('Press any key to return to partitioning editor...');
      J := RawChar;
      PaintScreen;
      DisplayNeeded := True;
    end

    else if (I = DoKeyCode) and (NumberOfPartitions > 0)
        and (AllocDifference = 0) then
    begin
      ErrorExists := False;
      DisplayItem (Current, AtNormal);

      { Initialize the DPD block we will use to describe the new partitions
        we've formed.  Start with all zeroes, and then add a few fields from
        the current DPD. }
      With TempDPD do For J := 0 to 255 do SectorArray[J] := 0;
      TempDPD.DPD.ID := DPDBlock.DPD.ID;
      TempDPD.DPD.LBN := DPDBlock.DPD.LBN;
      TempDPD.DPD.MaxEntries := DPDBlock.DPD.MaxEntries;

      { Build the beginnings of the partition data in the new DPD block.
        For now we'll just fill in the track and operating system information.
        This routine will detect if there are too many partitions (more than
        15) and exit if this happens.  This section will also check that
        each partition defined has no bad sectors within its first four
        allocated tracks.  Again, this will be treated as an error. }
      WITH HOMBlock.HOM DO K := FirstAltTrack + NumAltTracks;
      J := 1;
      While (J <= NumberOfPartitions) and (NOT ErrorExists) do
      With Partition[J] do
      begin
        If OS <> -1 then With TempDPD.DPD do
        begin
          EntryCount := EntryCount + 1;
          If EntryCount > MaxEntries then
          begin
            ErrorExists := True;
            ErrorMessage := 'MORE THAN 15 PARTITIONS DEFINED';
            Current := J;
          end
          else With Entry[EntryCount] do
          begin
            OSNIndex := OS;
            FirstTrack := K;
            LastTrack := K + Tracks - 1;
            Flag := J; { Temporarily save original index for later errors }
            For I := FirstTrack to FirstTrack + 3 do
            If SectorTable[I].Num <> 0 then
            begin
              ErrorExists := True;
              Str (J, ErrorMessage);
              ErrorMessage := Concat
                                ('BAD SECTOR IN FIRST 4 TRACKS, PARTITION #',
                                 ErrorMessage);
              Current := J; { Point to offending partition }
            end;
          end;
        end;
        K := K + Tracks;
        J := J + 1;
      end;

      { If we have not detected an error yet, the next thing to do is go
        through the partitions by operating system and fill in the things
        necessary for the operating systems.  There can be no more than
        four partitions per operating system.  For these purposes, CP/M and
        CCP/M count as one operating system, since CCP/M can access CP/M
        partitions.  We'll check all this as we go.  ** NOTE THAT THIS CODE
        RELIES ON THE FACT THE THE STANDARD OSN INDEX FOR CP/M IS LESS THAN
        THAT FOR CCP/M.  IF THIS CHANGES FOR SOME REASON (NEXT TO IMPOSSIBLE),
        THIS CODE WILL NEED MODIFICATION **}
      If NOT ErrorExists then
      begin
        J := 0;
        LastCPMUnit := 0;
        While (J < LastOS) and (Not ErrorExists) do
        begin
          J := J + 1;
          K := 0;
          For I := 1 to TempDPD.DPD.EntryCount do With TempDPD.DPD.Entry[I] do
          if (OSNIndex = J) and (Not ErrorExists) then
          begin
            K := K + 1;
            LogicalUnit := K + 4;
            If J = CPMIndex then
            begin
              LastCPMUnit := K;
              Name := 'CPM-x   ';
              Name[4] := Chr(Ord('0')+K);
            end
            else if J = CCPMIndex then
            begin
              Name := 'CCPM-x  ';
              Name[5] := Chr(Ord('0')+K);
              LogicalUnit := LogicalUnit + LastCPMUnit;
            end
            else if J = MSDOSIndex then
            begin
              Name := 'MSDOS-x ';
              Name[6] := Chr(Ord('0')+K);
            end
            else if J = VENIXIndex then
            begin
              LogicalUnit := LogicalUnit + 14;
              Case K of
                1 : Name := 'System  ';
                2 : Name := 'Temp    ';
                3 : Name := 'User    ';
                else
                begin
                  Name := 'Userx   ';
                  Name[4] := Chr(Ord('0')+K-2);
                end;
              end;
            end
            else
            begin
              Name := 'DISKnn  ';
              Name[4] := Chr(Ord('0')+(I div 10));
              Name[5] := Chr(Ord('0')+(I mod 10));
            end;
            If ((J = VENIXIndex) and (LogicalUnit > 22)) or
               ((J <> VENIXIndex) and (LogicalUnit > 8)) then
            begin
              ErrorExists := True;
              if (J = CPMIndex) or (J = CCPMIndex) then
                ErrorMessage := 'MORE THAN 4 PARTITIONS ARE CP/M OR CCP/M'
              else
                ErrorMessage := Concat ('MORE THAN 4 PARTITIONS ARE ',
                                        OSNBlock.OSN.Entry[J]);
              Current := Flag; { Point at offending entry }
            end;
            Flag := 0; { Reset flag - no longer need original index }
          end;
        end;
      end;

      { We've done everything we expect to be doing here.  If we found an
        error, print the message, wait for acknowledgement, and then return
        to the loop.  If there's no error, indicate that the DO key was pressed
        so we can leave the loop. }
      If ErrorExists then
      begin
        { "Current" now points to the "offending" line in our partitions on
          the screen.  Redisplay that line, blinking and bolded, so the user
          can see which line we're complaining about.  Then indicate that
          redisplay will be needed, so that when we re-enter the main loop,
          we'll restore normal display characteristics. }
        DisplayItem (Current, AtBlinkBold);
        DisplayNeeded := True;

        { Now print the error message on the summary line and wait for the
          user to acknowledge it; then reprint the summary line and go back
          to the main loop }
        ReadySummaryLine;
        FVAttribute := AtBold;
        Write (^G);
        WriteFast (Concat (ErrorMessage, ' -- Press any key to continue'));
        K := RawChar;
        PrintSummary;
      end
      else DoKeyPressed := True;
    end
    else Write (^G);
  Until DoKeyPressed;

  { If we get here, then we've determined that it's all right to actually
    perform the repartitioning.  We have a good portion of the partition data
    already built in the TempDPD block.  Now we have to confirm that the user
    actually wants to build the partitions, and determine which partitions
    need to be physically reformatted. }

  DrawOutline;
  DrawBox (4, 4, 77, 11, AtBlinkBold);
  FVRow := 4; FVAttribute := AtDefault;
  Write (^G^G);
  Center (' WARNING ');
  FVAttribute := AtBold;
  Center ('You are about to initiate repartitioning of your hard disk.');
  Center ('This action may result in the LOSS of all or some of your');
  Center ('data on the hard disk.  You should not attempt this operation');
  Center ('unless you do not want any of your hard disk data or you have');
  Center ('backed up whatever you wish to save.  Do not assume that any');
  Center ('data will be saved.  If you lose anything, it will be YOUR FAULT!');
  FVRow := 14;
  Center ('Press RESUME to continue');
  Center ('or Press MAIN SCREEN to cancel repartitioning');
  Repeat
    I := (RawChar and CapsLockMask);
    If I = MainScreenKeyCode then Exit
    else if I <> ResumeKeyCode then Write (^G);
  Until I = ResumeKeyCode;

  DrawBox (4, 14, 77, 18, AtBlinkBold);
  FVRow := 14; FVAttribute := AtDefault;
  Write (^G^G);
  Center (' SECOND WARNING ');
  FVAttribute := AtBold;
  Center ('If you press RESUME now, you will start repartitioning.');
  Center ('There will be no turning back.');
  Center (' Have you backed up everything you intend to save? ');
  FVRow := 21;  FVAttribute := AtBold;
  Center ('Press RESUME to begin repartitioning');
  Center ('or Press MAIN SCREEN to cancel and return to main menu');
  Repeat
    I := (RawChar and CapsLockMask);
    If I = MainScreenKeyCode then Exit
    else if I <> ResumeKeyCode then Write (^G);
  Until I = ResumeKeyCode;

  { If we get here, we have confirmed (twice) that repartitioning is desired.
    Disallow EXIT from this point forward, and then go to it! }

  EXITAllowed := False;

  { In the process of repartitioning, we might have created a "gap" somewhere
    (where there are no partitions) containing bad sectors.  Since these
    sectors will never be used, we want to see if any of them have alternate
    sectors assigned, and if they do, get rid of them (no need to waste
    alternate sectors on these. }

  For I := 0 to (HOMBlock.HOM.NumAltTracks * 16) - 1 do
  With ASTVector[I] do
  If Sector <> 0 then
  With TempDPD.DPD do
  begin
    J := 0;
    Repeat J := J + 1
    Until (J > EntryCount) or (Track <= Entry[J].LastTrack);
    { Here J is either greater than the number of partitions if the track
      specified by this AST entry is greater than the last allocated track,
      or else it points at the entry which might be the correct one.  This
      track is therefore within a gap if either J is greater than the number
      of partitions (EntryCount) or if the track is before the first track of
      the partition pointed to by J. }
    If (J > EntryCount) or (Track < Entry[J].FirstTrack) then
    begin
      Track := 0;
      Sector := 0;
    end;
  end;

  With TempDPD.DPD do
  begin
    For I := 1 to EntryCount do With Entry[I] do
    begin
      { MAIN PARTITION BUILDING CODE FOR ONE PARTITION (INDEX I). }
      { See if there's an old partition with the same (or similar enough)
        parameters to this one.  If so, we can probably leave it alone, but
        we'll give the user the option.  The idea of the code below is to
        set the value of "Flag" to "FF" (hex) if the partition must
        be initialized, or to something else if maybe it doesn't.  If we think
        the partition is similar to a partition defined previously, we'll set
        this flag value equal to the index in the old DPD block of the similar
        partition.  We will assume a partition is "similar to" a previous
        partition if they have the same starting and ending tracks and they
        are either both MS-DOS parititions or both VENIX partitions or both
        none of the two. }
      Flag := $FF; { Initially, assume must be initialized }
      For J := 1 to DPDBlock.DPD.EntryCount do
      if (FirstTrack = DPDBlock.DPD.Entry[J].FirstTrack) and
         (LastTrack  = DPDBlock.DPD.Entry[J].LastTrack) then
      begin
        if OSNIndex = MSDOSIndex then
        begin
          if OSNIndex = DPDBlock.DPD.Entry[J].OSNIndex then Flag := J;
        end
        else
        if OSNIndex = VENIXIndex then
        begin
          if OSNIndex = DPDBlock.DPD.Entry[J].OSNIndex then Flag := J;
        end
        else
        begin
          if (DPDBlock.DPD.Entry[J].OSNIndex <> MSDOSIndex) and
             (DPDBlock.DPD.Entry[J].OSNIndex <> VENIXIndex) then Flag := J;
        end;
      end;
      If Flag <> $FF then
      begin
        { If this partition is "similar to" a previous partition, but the
          name and logical unit field in the temporary DPD block are 0,
          then it's an operating system WUTIL doesn't know about (like VENIX).
          In this case we'll keep the original DPD block entries for name and
          logical unit. }
        if LogicalUnit = 0 then
        begin
          Name := DPDBlock.DPD.Entry[Flag].Name;
          LogicalUnit := DPDBlock.DPD.Entry[Flag].LogicalUnit;
        end;
        DrawOutline;
        StartFastVideo (10, 5, AtBold, 79, 23);
        Center ('-- Partition Initialization Option --');
        FVRow := 8;
        WriteFastLn ('One of your new partitions appears to be similar to a');
        WriteFastLn ('partition previously defined for this disk:');
        WriteLn;
        WriteFastLn (Concat ('New partition: ', Name, ' (drive ',
                             Chr (LogicalUnit+Ord('A')-1), ':)'));
        WriteFastLn (Concat ('Old partition: ', DPDBlock.DPD.Entry[Flag].Name,
                             ' (drive ',
                             Chr (DPDBlock.DPD.Entry[Flag].LogicalUnit+
                                  Ord('A')-1),
                             ':)'));
        WriteLn;
        FVAttribute := AtNormal;
        WriteFastLn ('You can re-initialize this partition if you wish.');
        WriteFastLn ('Or, you can leave the partition with the data it had');
        WriteFastLn ('before repartitioning.');
        WriteLn;
        FVAttribute := AtBold;
        WriteFastLn
          ('Press RESUME to LEAVE THE PARTITION AS IS (don''t re-initialize)');
        WriteFastLn
          ('Press ADDTNL OPTIONS to re-initialize the partition anyway');
        FVAttribute := AtBlinkBold;
        WriteFastLn
          ('BE SURE TO PRESS THE RIGHT KEY!  You will not get another chance.');
        Repeat
          K := (RawChar and CapsLockMask);
          If (K <> ResumeKeyCode) and (K <> AddtnlOptionsKeyCode) then
            Write (^G);
        Until (K = ResumeKeyCode) or (K = AddtnlOptionsKeyCode);
        If K = ResumeKeyCode then
          Flag := $F0  { Correct flag value for "initialized" partition }
        else
          Flag := $FF; { Value for "non-existent" -- will cause init }
      end;
      { Now we have the flag set to indicate whether or not we should
        initialize this partition.  If it is $F0 (hex), then the partition
        is already initialized.  If it is anything else, we'll initialize it. }
      If Flag <> $F0 then
      begin
        DrawOutline;
        FVRow := 12; FVAttribute := AtBlink;
        Center (Concat ('Initializing partition ', Name, ' ...please wait'));
        If OSNIndex = MSDOSIndex then
        begin
          FormatMSDOSPartition (FirstTrack, LastTrack, Name);
          If OSNIndex = MSDOSIndex then FATSectors := NumFATSectors;
        end
        else if OSNIndex <> VENIXIndex then
        begin
          FormatCPMPartition (FirstTrack, LastTrack, Name);
          NumPASBlocks := 1;
        end;
        Flag := $F0; { Indicate the partition is now initialized }
      end;
    end;
  end;

  { Finally, update the DPD and AST blocks with the correct information, as
    modified.  }
  DrawOutline;
  FVRow := 12; FVAttribute := AtBlink;
  Center ('Updating partitioning and alternate sector information on hard disk');
  { Write AST blocks first }
  WriteASTBlocks;
  { Finally, write the new DPD block }
  With HOMBlock.HOM.DPDLocation do
    WriteMajorBlock (Track, Sector, TempDPD);

  { The last thing we need to check is to see if the auto boot partition makes
    sense in the context of what we have changed.  If it doesn't, then we'll
    remove auto-boot and update the HOM block. }
  With HOMBlock.HOM do If (BootTrack <> 0) and (AutoBoot <> $FF) then
  With TempDPD.DPD do
  Begin
    I := 0;
    Repeat I := I + 1
    Until (I > EntryCount) or
          ((Entry[I].FirstTrack = BootTrack) and
           (Entry[I].LogicalUnit = AutoBoot));
    If I > EntryCount {we didn't find a matching partition} then
    begin
      BootTrack := 0;  AutoBoot := $FF;
      WriteMajorBlock (0, 2, HOMBlock);
    end;
  end;

  { We've finished.  Tell the guy. }

  DrawOutline;
  FVRow := 10; FVAttribute := AtBold;
  Center ('Re-partitioning has been completed');
  WriteLn;
  if TwoDrives and (CurrentDrive = 2) then
  begin
    CurrentDrive := 1;
    if ReadMajorBlocks then
    begin
      With HOMBlock.HOM do ManualSeek(0,StepRate);
      CurrentDrive :=2;
    end;
  end;
  FVAttribute := AtDefault;
  Center ('Now that you have modified the way your disk is partitioned, you');
  Center ('will not be able to exit this program.');
  WriteLn;
  FVAttribute := AtBold;
  Center ('To reboot and use the new partitions, press SET-UP and then CTRL/SET-UP');
  Center ('or press any other key to return to the WUTIL main menu');
  SetUpExit := True;
  I := RawChar;
end {RepartitionDisk};

