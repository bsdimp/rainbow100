{** file wudata.pas © Copyright 1986 Anthony G. Camas, all rights reserved **}
{ **************************************************************************
                                  CONSTANTS
  ************************************************************************** }

CONST
  { Functions for winchester extended DOS function }
  READFunc          = 0;
  WRITEFunc         = 1;
  WRITEVERIFYFunc   = 2;
  FORMATFunc        = 3;

  { Winchester hardware I/O ports }
  DataPort          = $60;      { I/O: Data }
  ErrorPort         = $61;      { I  : Error register }
  PrecompPort       = $61;      {   O: Precompensation setting }
  SectorCountPort   = $62;      { I/O: Sector count }
  SectorNumberPort  = $63;      { I/O: Sector number }
  CylinderLowPort   = $64;      { I/O: Cylinder number low order }
  CylinderHighPort  = $65;      { I/O: Cylinder number high order }
  SDHPort           = $66;      { I/O: "SDH" (size/drive/head) byte }
  StatusPort        = $67;      { I  : Status register }
  CommandPort       = $67;      {   O: Command port }
  Status2Port       = $68;      { I  : Secondary status register }
  Command2Port      = $68;      {   O: Secondary command port }
  DriveStatusPort   = $69;      { I  : Drive status register }

  HDVector1         = $45;      { Interrupt in v2.01 and on all 100A's }
  HDVector2         = $A5;      { Interrupt for 100B/100+ in v2.05 and up }

  CHSAttrib         = $4000;    { Attribute of CHSDriver }

  { Key codes returned for certain keys in raw key mode.  For function keys,
    two values are shown.  The first value is the actual function key value
    including the "this is a function key" bit.  The second excludes the
    extra bit in order to produce a set element for "KeysAllowed" sets.  }
  BackspaceKeyCode     = $08;
  ReturnKeyCode        = $0D;
  Digit0KeyCode        = $30;
  Digit9KeyCode        = $39;
  HelpKeyCode          = $100;       HelpKeyVal           =  $00;
  DoKeyCode            = $101;       DoKeyVal             =  $01;
  PrintScreenKeyCode   = $103;       PrintScreenKeyVal    =  $03;
  ResumeKeyCode        = $109;       ResumeKeyVal         =  $09;
  MainScreenKeyCode    = $10D;       MainScreenKeyVal     =  $0D;
  ExitKeyCode          = $10F;       ExitKeyVal           =  $0F;
  AddtnlOptionsKeyCode = $111;       AddtnlOptionsKeyVal  =  $11;
  FindKeyCode          = $11B;       FindKeyVal           =  $1B;
  InsertHereKeyCode    = $11D;       InsertHereKeyVal     =  $1D;
  RemoveKeyCode        = $11F;       RemoveKeyVal         =  $1F;
  SelectKeyCode        = $121;       SelectKeyVal         =  $21;
  PrevScreenKeyCode    = $123;       PrevScreenKeyVal     =  $23;
  NextScreenKeyCode    = $125;       NextScreenKeyVal     =  $25;
  UpArrowKeyCode       = $127;       UpArrowKeyVal        =  $27;
  DownArrowKeyCode     = $129;       DownArrowKeyVal      =  $29;
  LeftArrowKeyCode     = $12D;       LeftArrowKeyVal      =  $2D;
  RightArrowKeyCode    = $12B;       RightArrowKeyVal     =  $2B;
  Keypad0KeyCode       = $12F;       Keypad0KeyVal        =  $2F;
  Keypad9KeyCode       = $14A;       Keypad9KeyVal        =  $4A;
  KeypadEnterKeyCode   = $156;       KeypadEnterKeyVal    =  $56;
  Shift                = $200; { Shift key adds this value }
  Ctrl                 = $400; { CTRL key adds this value }
  CapsLockMask         = $7FF; { AND this with values to remove caps lock effect }

  { Rainbow internal character values (display memory) }
  HollowBoxChar    = $80;
  BSChar           = $AB;
  HTChar           = $03;
  LFChar           = $06;
  FFChar           = $04;
  CRChar           = $05;
  InvertedQuesChar = $BF;
  ULCornerChar     = $0D;
  URCornerChar     = $0C;
  LLCornerChar     = $0E;
  LRCornerChar     = $0B;
  HLineChar        = $12;
  VLineChar        = $19;

  { Rainbow screen memory attribute values }
  AtNormal         = 14;
  AtBold           = 12;
  AtBlink          = 10;
  AtBlinkBold      =  8;
  AtUnderline      =  6;
  AtUnderlineBold  =  4;
  AtReverse        = 15;
  AtReverseBold    = 13;
  AtDefault        = $FF; {***WARNING*** works internally only}

  { Other (misc.) constants }

  { This is the file spec used to access the printer.  It is used whenever
    the "set print screen output to printer" option is chosen. }
  FileSpecForPrinter = '\DEV\PRN';

  { This is the highest track number WUTIL can handle (determines size
    of internal bad sector table, etc.).  Note that this is higher already
    than the Rainbow's hardware can access. }
  TrackLimit = 14999;

{ **************************************************************************
                               TYPE DEFINITIONS
  ************************************************************************** }

TYPE

  Str2         = String [2];
  Str4         = String [4];
  Str8         = String [8];
  Str35        = String [35];
  Str60        = String [60];
  Str80        = String [80];
  Str255       = String [255];

  KeyAllowed   = 0..$FF;
  KeysAllowed  = Set of KeyAllowed;

  CharAllowed  = ' '..'~';
  CharsAllowed = Set of CharAllowed;

  Sectors      = 0..15;
  SectorsInTrack = Set of Sectors;

  BadSectorData = Record
    Case Integer of
     1: (Num :Integer);
     2: (Bits:SectorsInTrack);
  end;

  { Functions which may be selected from menus }
  MenuFunction = (
    MenuNull,
    { Main Menu functions }
    MMExit,
    MMDump,
    MMPartition,
    MMInitialize,
    MMCopyBoot,
    MMAutoBoot,
    MMPrintPart,
    MMPrinterMenu,
    MMParkHeads,
    { Formatting Menu functions }
    FMDoubleVerify,
    FMSingleVerify,
    FMNoVerify,
    FMInitializeOnly,
    { Printer Menu functions }
    PMMainMenu,
    PMOutToPrinter,
    PMOutToFile,
    PMToggleFF );

  { The structure shown below is used to display menus and drive the menu
    selection process.  A maximum of nine items is allowed in a menu.  NOTE
    THAT ALL ITEMS UNDER "NAME" SHOULD BE OF THE SAME LENGTH FOR ANY GIVEN
    MENU, PADDED WITH SPACES ON THE RIGHT IF NECESSARY! }
  Menu = record
    MenuHeader          : Str60;        { Header line describing menu }
    NumberOfSelections  : Byte;         { Number of valid selections this menu }
    Selection           : Array[1..9] OF Record
      Name              :   Str60;      { Textual description of selection }
      Value             :   MenuFunction; { Value returned for this selection }
    end;
  end;

  RegisterList = record
    case Integer of
    1: (AX,BX,CX,DX,BP,SI,DI,DS,ES,Flags: Integer);
    2: (AL,AH,BL,BH,CL,CH,DL,DH         : Byte);
  end;

  DiskAddr = record
    Track: Integer;
    Sector: Byte;
  end;

  DiskAddrLength = record
    Track: Integer;
    Sector: Byte;
    Length: Integer;
  end;

  WinchesterRecord = Record
    Func :Byte;
    DriveCode :Byte;
    Sector :Byte;
    Surface :Byte;
    Track :Integer;
    Count :Integer;
    BuffOfs :Integer;
    BuffSeg :Integer;
    Status :Byte;
    ErrorType :Byte;
  end;

  FormatArray = Array [0..31] of Byte;

  DPDEntry = record
    Flag:             Byte;
    LogicalUnit:      Byte;
    Name:             Array [0..7] of Char;
    OccurNum:         Byte;
    OSNIndex:         Byte;
    FirstTrack:       Integer;
    LastTrack:        Integer;
    NumPASBlocks:     Byte;
    CCPMSizeCode:     Byte;
    MSDOSCluster:     Byte;
    FATSectors:       Byte;
    MustBeZero2:      Array [20..31] of Byte;
  end;

  { This very large type definition defines all the different types of sectors
    we can read from and write to disk.  It is defined with a bunch of variant
    records, each with their own type, because they all must be able to be
    referenced as an array of words for checksum calculation using the same
    procedure. }

  SectorBlock = record
  CASE Integer of
  1:  (SectorArray:          Array [0..255] of Integer);
  2:  (SectorBytes:          Array [0..511] of Byte);
  3:  (HOM: RECORD           { *** HOME BLOCK *** }
         ID:                 Array [0..2] of Char;
         PartFlag:           Byte;
         Checksum:           Integer;
         VolumeID:           Array [0..7] of Char;
         SystemID:           Array [0..1] of Integer;
         BATLocation,
         DPDLocation,
         OSNLocation,
         BOOTLocation,
         ASTLocation:        DiskAddrLength;
         FirstAltTrack:      Integer;
         NumAltTracks:       Byte;
         AutoBoot:           Byte;
         BootTrack:          Integer;
         MustBeZero1:        Array [0..14] of Byte;
         { Physical disk parameters: }
         Cylinders:          Integer;
         SectorsPerTrack:    Byte;
         SectorSize:         Integer;
         Surfaces:           Byte;
         MaintCylinder:      Integer;
         MfgCylinder:        Integer;
         PreCompValue:       Integer;
         StepRate:           Byte;
         TypeCode:           Byte;
         { End physical parameters }
         ThisBlockNumber:    Byte;
         MustBeZero2:        Array [0..191] of Integer;
       end);
  4:  (OSN: RECORD           { *** Operating system name block *** }
         ID:                 Array [0..2] of Char;
         LBN:                Byte;
         Checksum:           Integer;
         MaxEntries:         Integer;
         MustBeZero1:        Array [0..3] of Integer;
         Entry:              Array [0..30] of Array [0..15] of Char;
       end);
  5:  (DPD: RECORD           { *** DISK PARTITION DATA BLOCK *** }
         ID:                 Array [0..2] of Char;
         LBN:                Byte;
         Checksum:           Integer;
         MaxEntries:         Integer;
         EntryCount:         Integer;
         MustBeZero1:        Array [0..10] of Integer;
         Entry:              Array [1..15] of DPDEntry;
       end);
  6:  (BAT: RECORD           { *** BAD ADDRESS TABLE DATA *** }
         ID:                 Array [0..2] of Char;
         LBN:                Byte;
         Checksum:           Integer;
         FirstSector:        DiskAddr;
         LastSector:         DiskAddr;
         Entry:              Array [0..249] of BadSectorData;
       end);
  7:  (AST: RECORD           { *** ALTERNATE SECTOR TABLE DATA *** }
         ID:                 Array [0..2] of Char;
         LBN:                Byte;
         Checksum:           Integer;
         MaxEntries:         Integer;
         EntryCount:         Integer;
         MustBeZero1:        Integer;
         Entry:              Array [0..99] of record
           BadSectorAddress: DiskAddr;
           GoodTrackOffset:  Byte;
           GoodSector:       Byte;
         end;
       end);
  end;

{ **************************************************************************
              TYPED CONSTANTS (MENUS AND OTHER STANDARD BLOCKS)
  ************************************************************************** }

CONST

  FormatData :FormatArray =
    ( 0,  1, 0,  2, 0,  3, 0,  4, 0,  5, 0,  6, 0,  7, 0,  8,
      0,  9, 0, 10, 0, 11, 0, 12, 0, 13, 0, 14, 0, 15, 0, 16);

  { ** REMINDER ** all menu "name" items should be the same length (space
    padded) within a given menu }
  MainMenu: Menu =
   (MenuHeader:         'WUTIL Main Menu';
    NumberOfSelections: 9;
    Selection:         ((Name:  'Display current hard disk information     ';
                         Value: MMPrintPart),
                        (Name:  'Dump contents of any disk sector on screen';
                         Value: MMDump),
                        (Name:  'Format and Initialize hard disk           ';
                         Value: MMInitialize),
                        (Name:  'Re-partition the hard disk                ';
                         Value: MMPartition),
                        (Name:  'Change auto-boot partition                ';
                         Value: MMAutoBoot),
                        (Name:  'Copy new boot loaders onto hard disk      ';
                         Value: MMCopyBoot),
                        (Name:  'Park hard disk heads for shipping         ';
                         Value: MMParkHeads),
                        (Name:  'PRINT SCREEN Configuration Menu           ';
                         Value: MMPrinterMenu),
                        (Name:  'EXIT from WUTIL and return to MS-DOS      ';
                         Value: MMExit)));

  PrinterMenu: Menu =
   (MenuHeader:         'PRINT SCREEN Configuration Menu';
    NumberOfSelections: 4;
    Selection:         ((Name:  'Send PRINT SCREEN output to printer';
                         Value: PMOutToPrinter),
                        (Name:  'Send PRINT SCREEN output to file   ';
                         Value: PMOutToFile),
                        (Name:  'Toggle formfeed after print option ';
                         Value: PMToggleFF),
                        (Name:  'Return to Main Menu                ';
                         Value: PMMainMenu),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull)));

  FormatMenu: Menu =
   (MenuHeader:         'Format/Initialize Options Menu';
    NumberOfSelections: 4;
    Selection:         ((Name:  'Format with Double Verify and Initialize';
                         Value: FMDoubleVerify),
                        (Name:  'Format with Single Verify and Initialize';
                         Value: FMSingleVerify),
                        (Name:  'Format Without Verify and Initialize    ';
                         Value: FMNoVerify),
                        (Name:  'Re-Initialize Only (already formatted)  ';
                         Value: FMInitializeOnly),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull),
                        (Name:  '';
                         Value: MenuNull)));

{ **************************************************************************
                               GLOBAL VARIABLES
  ************************************************************************** }

VAR
  Registers     :RegisterList;
  HOMBlock,
  DPDBlock,
  OSNBlock,
  TempBlock     :SectorBlock;
  Selection     :MenuFunction;
  EXITAllowed   :Boolean;
  OutlineDrawn  :Boolean;
  LongChain     :Boolean;
  TwoDrives     :Boolean;
  SetUpExit     :Boolean;
  Temp          :Integer;
  MSDOSVersion  :Integer;
  CurrentDrive  :Integer;
  NumFATSectors :Byte;
  BIOSSeg       :Integer;

  PrintFile     :Text;
  PrintFileName :Str60;
  FFAfterPrint  :Boolean;

  PATHString    :String [255];

  WinchesterBlock :WinchesterRecord;
  DriverRequest :Record
    HeaderLength :Byte;
    UnitCode     :Byte;
    CommandCode  :Byte;
    Status       :Integer;
    Reserved     :Array [0..7] of Byte;
    MediaDescrip :Byte;
    TransferAddr :^WinchesterRecord;
    Count        :Integer;
    Start        :Integer;
  end;

  { Table of bad/good sector information for entire disk.  Index into this
    array is a track number; then individual bits can be accessed using set
    operators.  The sector number (minus one) is used as a member of the
    set. }
  SectorTable   :Array [0..TrackLimit] of BadSectorData;

  { Internal table of alternate sector information (matching that which is
    stored in AST blocks on the disk.  This is stored so that it can be
    accessed two ways.  The first is as an array indexed by the alternate
    sector's relative track number and sector number (two indices).  The
    second is as a one-dimensional array.  The first method is used when
    we want to specifically worry about specific alternate track and sector
    numbers.  The second is used for quick access to the entire structure.  }

  ASTData       :Array [0..49, 1..16] of DiskAddr                   ;
  ASTVector     :Array [0..799]       of DiskAddr   absolute ASTData;

  { Values used for fast video output }
  FVRow, FVColumn, FVAttribute :Byte;   { Current row/column/attribute }
  FVChar        :Char;                  { Buffers character to be written }
  FVLMargin     :Byte;                  { Left margin }
  FVRMargin     :Byte;                  { Right margin }
  FVTMargin     :Byte;                  { Top margin }
  FVBMargin     :Byte;                  { Bottom margin }
  SaveConOutPtr :Integer;               { "Normal" value of ConOutPtr sav/rst }

  { Pointers to areas in Rainbow Hard Disk Service }
  ISRFlag     :Array[1..2] of ^Byte;    { Ptr to flag set by hard disk ISRs }
  HDMAXTRK    :Array[1..2] of ^Integer; { Ptr to max track value in HD service }
  HDSTEPR     :Array[1..2] of ^Byte;    { Ptr to step rate value in HD service }
  HDPRECOMP   :Array[1..2] of ^Integer; { Ptr to precomp value in HD service }
  HDStrategy  :Array[1..2] of ^Byte; { Ptr to "strategy" routine in HD driver }
  HDInterrupt :Array[1..2] of ^Byte; { Ptr to "interrupt" routine in HD driver }
  HDStrat     :^Byte;       { Pointer to "strategy" routine in HD driver }
  HDInter     :^Byte;       { Pointer to "interrupt" routine in HD driver }
  PatchLocation :Integer; { Pointer to location in HD driver for patch }
