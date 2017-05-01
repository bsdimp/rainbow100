{$C-}
program Wutil; {Rainbow 100 Winchester Disk Utility}

{

                                   ********
                                    NOTICE
                                   ********

     THIS SOFTWARE IS PROVIDED AS IS AND WITHOUT PAYMENT OF CONSIDERATION.
            IT MAY BE USED ONLY WITH THE UNDERSTANDING THAT THERE
           ARE NO WARRANTIES, EXPRESSED OR IMPLIED, INCLUDING, BUT
         NOT LIMITED TO, ANY IMPLIED WARRANTIES OF MERCHANTABILITY OR
                      FITNESS FOR A PARTICULAR PURPOSE.

 ***************************************************************************
                       © COPYRIGHT 1986 Anthony G. Camas
                       © COPYRIGHT 1988 Vinzenz Esser
                              All rights reserved

  A limited license to hold and copy this source code is hereby granted,
  provided the following conditions are met:
  * THIS CODE MAY BE DISTRIBUTED ONLY IF UNMODIFIED IN ANY WAY.  ALL
    CODE (AND THIS COPYRIGHT NOTICE) MUST REMAIN EXACTLY AS YOU RECEIVED
    IT IF YOU GIVE IT TO ANYONE ELSE.  Permission to distribute modified
    versions of this software must be obtained in writing from the author.
  * UNDER NO CIRCUMSTANCES SHALL AN INDIVIDUAL DISTRIBUTING THIS SOFTWARE
    EXPECT, DEMAND, OR ACCEPT PAYMENT OF ANY KIND FOR THE SOFTWARE OR A
    "LICENSE" TO USE IT.  However, recovery of expenses for media and postage
    in connection with this software's distribution is permitted.
 ***************************************************************************

  This source code is being published because it may be of some value to
  others attempting similar projects.  The restriction regarding distributing
  versions of this software is being imposed because of the potential peril
  which could be created if bugs are introduced into the software.


  The author of WUTIL V3 can be reached at this address:

                                Vinzenz Esser
                                Waldstrasse 2E
                                D-8052 Moosburg 2
                                West-Germany

  This program performs various functions with winchester hard disks installed
  on DEC Rainbow 100, 100B, and 100+ computers.  It can:
    - Format and initialize a disk according to your parameters
    - Partition and repartition your disk in increments of 1 track (8K bytes)
    - Set up, delete, or change the auto boot partition
    - Print information about how your disk is set up and partitioned
    - Dump arbitrary sectors from the disk
    - Park the disk heads for safe shipping/transportation
    - Do all of the above to a second hard disk connected to the Rainbow via
      the Micro CHS dual winchester controller
}

{$IWUREVS.PAS}

{$IWUDATA.PAS}

{$IWUSUBL.PAS}

{$IWUSUBH.PAS}

{ **************************************************************************
                                MAJOR SECTIONS
  ************************************************************************** }

{ Initialize - Startup steps }
procedure Initialize;
begin
  EXITAllowed  := TRUE;
  SetUpExit    := False;
  OutlineDrawn := False;

  { Make sure this is a rainbow with the winchester controller installed }
  if (Port[Status2Port] AND $E0) <> $A0 then
  begin
    WriteLn (^G'Winchester controller not installed');
    Halt (1);
  end;

  { Initialize PRINT SCREEN stuff }
  FFAfterPrint := False;
  PrintFileName := '';
  if not SetPrintFile (FileSpecForPrinter) then
  begin
    WriteLn (^G'Unable to open printer (PRN) as print device!');
    Halt (1);
  end;

  { Get MS-DOS version number to find out, what (major) version of we are
    running.  If it's V3.xx, check OEM serial number field, if we're
    running V3.10 revision B.  Set BIOSSeg accordingly. }
  Registers.AH := $30;
  MsDos (Registers);
  MSDOSVersion := Registers.AL;
  BIOSSeg := $40;
  if (MSDOSVersion = 3)then
    if (Registers.AH > $0A) or
       ((Registers.AH = $0A) and (Registers.CL > $61)) then BIOSSeg := $70;

  { Look through the device driver list to locate the standard hard disk
    driver and the additional CHS driver. }
  if not (FindHDDriver) then
  begin
    WriteLn (^G'CAN''T FIND WINCHESTER SERVICE ROUTINES IN MS-DOS!');
    WriteLn ('Your version of MS-DOS is incompatible with this program');
    Halt (1);
  end;

  { Look through interrupt service routine code to set up our pointer to
    the flag set when the Hard Disk interrupts.  Try both the new-style
    vector and the old-style vector.  If both fail, this is a fatal error. }
  if not (FindISRFlag (HDVector2)) then
    if not (FindISRFlag (HDVector1)) then
    begin
      WriteLn (^G'CAN''T FIND WINCHESTER INTERRUPT SERVICE IN MS-DOS!');
      Write ('You either have a TSR program installed, ');
      Writeln ('which uses the winchester interrupt');
      Writeln ('or your version of MS-DOS is incompatible with this program.');
      Halt (1);
    end;

  { Now find other data we need for processing based on value we just
    determined.  Again, if this fails, we cannot proceed.  First we'll do it
    for the standard drive. }
  CurrentDrive := 1;
  if not FindHDData THEN
  begin
    WriteLn (^G'CAN''T FIND WINCHESTER SERVICE DATA AREAS IN MS-DOS!');
    WriteLn ('Your version of MS-DOS is incompatible with this program');
    Halt (1);
  end;

  { Now let's do the same thing for the second drive, if one is present. }
  if TwoDrives then
  begin
    CurrentDrive := 2;
    if not FindHDData THEN
    begin
      WriteLn (^G'CAN''T FIND WINCHESTER SERVICE DATA AREAS IN THE CHS DRIVER!');
      WriteLn ('Your version of the CHS driver is incompatible with this program');
      Halt (1);
    end;
  end;

  CurrentDrive := 1;
  HDStrat      := HDStrategy[CurrentDrive];
  HDInter      := HDInterrupt[CurrentDrive];

  { Get the PATH string we will use to find our overlay.  Then try to find it. }
  GetPATHString;
  FindOverlay;

  ClrScr;

end {Initialize};

{ DoPrinterMenu - Display and process printer menu }
procedure DoPrinterMenu;
var
  I, J :Integer;
  SecondLine :Str80;
  FileName :Str80;
begin
  While True do { repeat forever until we exit for MainScreen key }
  begin
    If FFAfterPrint then
      SecondLine := 'Formfeed will be printed after PRINT SCREEN output'
    else
      SecondLine := 'Formfeed will NOT be printed after PRINT SCREEN output';
    { Display printer menu and get selection from it.  Then dispatch according
      to the selection. }
    Selection := GetMenuSelection 
                  (PrinterMenu,
                   [MainScreenKeyVal],
                   Concat ('PRINT SCREEN output is being sent to ',
                           PrintFileName),
                   SecondLine, '', I);
    If I = MainScreenKeyCode then Exit;
    Case Selection of
      PMOutToPrinter:
        begin
          If not SetPrintFile (FileSpecForPrinter) then
          begin
            FVRow := 16;  Write (^G);
            Center
             ('UNABLE TO OPEN PRINTER FOR OUTPUT -- Press any key to continue');
            J := RawChar;
          end;
        end;
      PMOutToFile:
        begin
          DrawBox (8, 15, 73, 17, AtNormal);
          FVRow := 16; FVColumn := 10;
          WriteFast ('Enter file name to print on: ');
          ReadScreen (FVColumn, FVRow, (72-FVColumn),
                      ['A'..'Z', '0'..'9', ':', '\', '.', '_', '$'],
                      [MainScreenKeyVal],
                      FileName, I);
          If I = MainScreenKeyCode then Exit;
          If not SetPrintFile (FileName) then
          begin
            FVRow := 18;  FVColumn := 10;  Write (^G);
            WriteFast
             ('UNABLE TO OPEN THIS FILE FOR OUTPUT -- Press any key to continue');
            J := RawChar;
          end;
        end;
      PMToggleFF:
        FFAfterPrint := not FFAfterPrint;
      PMMainMenu:
        Exit;
    end;
  end;
end {DoPrinterMenu};

{ MenuExit - Processes "exit" request from main menu }
procedure MenuExit;
var
  I :Integer;
begin
  If EXITAllowed then NormalExit;

  { If exit not allowed, say so }

  Write (^G);
  DrawOutline;
  FVRow := 10; FVAttribute := AtBold;
  Center ('EXIT IS NOT ALLOWED NOW');
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
  Center ('Because you have modified your disk''s partitions, you cannot exit');
  Center ('this program now.  You must reboot your system to use the new');
  Center ('partitions.');
  WriteLn;
  FVAttribute := AtBold;
  Center ('To reboot and use the new partitions, press SET-UP and then CTRL/SET-UP');
  Center ('or press any other key to return to the WUTIL main menu');
  SetUpExit := True;
  I := RawChar;
end {MenuExit};

{ ** NOTE ** WUOVR.PAS included here must contain only OVERLAY procedures }
{$IWUOVR.PAS}

{ ** NOTE ** WUPART.PAS included here must contain only OVERLAY procedures }
{$IWUPART.PAS}

{ **************************************************************************
                           M A I N   P R O G R A M
  ************************************************************************** }

begin

  { Perform initializations as required. }
  Initialize;

  { Start by introducing and disclaiming (?) ourselves }
  Intro;

  while TRUE do                         { loop forever }
  begin
    { Display main menu and get selection from it.  Then dispatch according to
      the selection. }
    Selection := GetMenuSelection(MainMenu, [], '', 'MX', '', Temp);
    Case Selection of
      MMExit:
        MenuExit;
      MMPrintPart:
        PrPart;
      MMDump:
        DumpSector;
      MMPartition:
        RepartitionDisk;
      MMInitialize:
        FormatAndInitialize (MMInitialize);
      MMCopyBoot:
        FormatAndInitialize (MMCopyBoot);
      MMAutoBoot:
        SetAutoBoot;
      MMParkHeads:
        ParkHeadsForShipping;
      MMPrinterMenu:
        DoPrinterMenu;
    end;
  end;

end.
