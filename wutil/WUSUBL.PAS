{** file wusubl.pas © Copyright 1986 Anthony G. Camas, all rights reserved **}
{ **************************************************************************
              UTILITY PROCEDURES AND FUNCTIONS (TERMINAL OUTPUT)
  ************************************************************************** }

{ PrintChar - Return printable character version of passed byte.
  A byte value is passed.  This function returns the CHAR equivalent of that
  value if it is printable.  If it is not printable, an "equivalent" printable
  character is returned.  This is sometimes the character code for a "special"
  character printable only by the direct screen I/O routines; thus this
  function should only be called when in Fast Video mode (see code appearing
  later in this module). }
function PrintChar (Number: Byte) :Char;
var
  Result :Char;
begin
  Number := (Number AND $7F);
  if (Number < Ord (' ')) or (Number = $7F) then
  begin
    if Number = 0 then Number := HollowBoxChar  { Box outline for null }
    else if Number = 8 then Number := BSChar    { "«" for backspace }
    else if Number = 9 then Number := HTChar    { Displayable "HT" }
    else if Number = 10 then Number := LFChar   { Displayable "LF" }
    else if Number = 12 then Number := FFChar   { Displayable "FF" }
    else if Number = 13 then Number := CRChar   { Displayable "CR" }
    else Number := InvertedQuesChar;            { "¿" for all others }
  end;
  PrintChar := Chr(Number);
end {PrintChar};

{ HexDigit - Return hexadecimal character corresponding to input value (0-15) }
function HexDigit (Number: Byte) :Char;
const
  CharZero = $30;
  CharA = $41;
begin
  if (Number > 9) then HexDigit := Chr(CharA-10+Number)
                  else HexDigit := Chr(CharZero+Number);
end {HexDigit};

{ Hex2Digit - Return two hex characters corresponding to an 8-bit value }
function Hex2Digit (Number:Byte) :Str2;
begin
  Number := (Number AND $FF);
  Hex2Digit := Concat (HexDigit (Number DIV $10),
                       HexDigit (Number MOD $10));
end {Hex2Digit};

{ Hex4Digit - Return four hex characters corresponding to a 16-bit value }
function Hex4Digit (Number:Integer) :Str4;
begin
  Hex4Digit := Concat (Hex2Digit(Hi(Number)), Hex2Digit(Lo(Number)));
end {Hex4Digit};

{ WriteHex - Display an 8-bit value as two hex digits }
procedure WriteHex (Number:Byte);
begin
  Number := (Number AND $FF);
  Write (HexDigit(Number DIV $10),
         HexDigit(Number MOD $10));
end {WriteHex};

{ WriteHex4 - Display a 16-bit value as four hex digits }
procedure WriteHex4 (Number:Integer);
begin
  WriteHex (Hi(Number));  WriteHex (Lo(Number));
end {WriteHex4};

{ WriteTSL - Display track, sector, and length information in standard format }
procedure WriteTSL (Var TSL:DiskAddrLength);
begin
  Write ('Track ');
  WriteHex4 (TSL.Track);
  Write ('H Sector ');
  WriteHex (TSL.Sector);
  Write ('H (');
  WriteHex4 (TSL.Length);
  Write ('H sectors)');
end {WriteTSL};

{ SetPrintFile - Set print screen output file.
  This routine is passed the name of a file to which future printer output
  should be sent.  It attempts to open that file as PrintFile.  If the open
  succeeds, this function returns TRUE and puts the name of the file
  opened in the global variable PrintFileName.  If it fails, the function
  returns FALSE and leaves PrintFileName as is. }
function SetPrintFile (Name :Str60) :Boolean;
begin
{$I-}
  { Close old print file, if there was one }
  If Length(PrintFileName) > 0 then Close (PrintFile);
  Assign (PrintFile, Name);
  Rewrite (PrintFile);
  If IOResult = 0 then
  begin
    If Name = FileSpecForPrinter then PrintFileName := 'Printer'
                                 else PrintFileName := Name;
    SetPrintFile := True;
  end
  else SetPrintFile := False;
{$I+}
end {SetPrintFile};

{ PrintTheScreen - Prints contents of screen to specified device/file. }
procedure PrintTheScreen;
const
  ScreenMemSeg = $EE00;
  EightBitsValue = 4;
var
  CCB :Record
    Func, ReturnCode, Char, CharStat,
    DeviceNumber, ModemControl, StopBits, DataBits, Parity,
    RcvBaud, XmtBaud, XONChar, XOFFChar, RcvXONXOFF, XmtXONXOFF,
    X0B, X0C, X0D, X0E, X0F, X10 :Byte;
  End;
  I :Integer;
  Ch :Byte;
  Count :Integer;
  DECPrinter :Boolean;
  EmptyLine :Boolean;

begin
  { We will now try to determine if we are dealing with a DEC printer or
    some other printer.  We'll do this by looking at the programming of the
    printer device.  If it is set to an "eight bit" mode, we'll assume it's
    a DEC printer and that it can receive special characters.  If it's not,
    we'll send it only "regular" characters.  Note, by the way, that we
    won't bother with this check unless printer output is going to the printer.
    If it's going to a file, we'll always assume we're not a dec printer. }
  If PrintFileName <> FileSpecForPrinter then DECPrinter := False
  else
  begin
    Registers.AX := $4402; { IOCTL function to read printer configuration }
    Registers.BX := $04;   { Printer port }
    Registers.DS := Seg (CCB);
    Registers.DX := Ofs (CCB);
    CCB.Func := 3;
    CCB.DeviceNumber := 2;
    MsDos (Registers);
    DECPrinter := (CCB.DataBits = EightBitsValue);
  end;

  { We have to read what's in screen memory for a total of 26/29 lines,
    depending on the Rainbow's 50/60Hz setting.  On 50Hz the first five lines
    and on 60Hz the first two lines will always be blank.  They will cause a
    jump around the global data used by the video controller.  We have to stop
    after the 24 lines are printed, because otherwise we'll end up printing 
    endless stuff. }
  I := 0;
  Count := 0;
  EmptyLine := True;

  { Now we skip over the blank lines.  In a blank line the first byte is the
    terminator $FF.  So, all we do is skip over all lines that have the ter-
    minator in the first byte. }
  Repeat {Until EmptyLine = False}
    begin
      Ch := Mem[ScreenMemSeg:I];
      If Ch <> $FF then EmptyLine := False
      else
        begin
          I := I + 1;
          I := MemW[ScreenMemSeg:I];
        end;
    end;
  Until EmptyLine = False;

  Repeat {Until Count = 24}
    Ch := Mem[ScreenMemSeg:I];
    I := I + 1;
    If Ch = $FF then
    begin
      I := MemW[ScreenMemSeg:I];
      Count := Count + 1;
      WriteLn (PrintFile);
    end
    else
    begin
      { Printers don't have the same character set as we do for the screen.
        We will make some translations, therefore, to make sure this character
        can be printed. }
      If (Ch = ULCornerChar) or (Ch = URCornerChar)
      or (Ch = LLCornerChar) or (Ch = LRCornerChar) then Ch := Ord ('+')
      else if Ch = VLineChar then Ch := Ord ('|')
      else if Ch = HLineChar then Ch := Ord ('-')
      else if (DECPrinter)
          and (   (Ch < $20)
               or ((Ch > $7E) and (Ch < $A1))) then Ch := $B7 { Centered dot }
      else if (NOT DECPrinter)
          and (   (Ch < $20)
               or (Ch > $7E)) then Ch := Ord ('.');
      Write (PrintFile, Char(Ch));
    end;
  Until Count = 24;
  if FFAfterPrint then Write (PrintFile, ^L);
  WriteLn (PrintFile);
  Flush (PrintFile);
end {PrintTheScreen};

{ CursorOff and CursorOn - Disable/enable display of cursor }
procedure CursorOff;
begin
  Registers.DI := $08;
  Intr ($18, Registers);
end {CursorOff};

procedure CursorOn;
begin
  Registers.DI := $0A;
  Intr ($18, Registers);
end {CursorOn};

{ FastVideoOut - Writes one character to "current" position using fast video.
  This procedure becomes the TURBO "ConOut" procedure when StartFastVideo
  is called until EndFastVideo is called subsequently.  It is passed a
  character to write, and it writes it at the current position using firmware
  fast video routines.  The attribute value in FVAttribute is used for the
  attribute, unless it is $FF, in which case the "current" attribute it used.
  Carriage return, line feed, and backspace are handled properly by adjusting
  the row and column values; all other characters are taken literally and
  printed. }
procedure FastVideoOut (Ch: Char);
begin
  IF Ch = #13 THEN         { Return }
    FVColumn := FVLMargin
  ELSE IF Ch = #10 THEN    { Line Feed }
  begin
    FVRow := FVRow + 1;
    IF FVRow > FVBmargin THEN FVRow := FVTMargin; { Wrap -- too hard to scroll }
  end
  ELSE IF Ch = #8 THEN     { Backspace }
  begin
    IF FVColumn > FVLMargin THEN FVColumn := FVColumn - 1;
  end
  ELSE IF Ch = #7 THEN     { Bell }
  begin
    Registers.DI := $1E;
    Intr ($18, Registers);
  end
  ELSE                     { All others (printable) }
  begin
    IF FVColumn > FVRmargin THEN
    begin
      FVColumn := FVLMargin;
      FVRow := FVRow + 1;
      IF FVRow > FVBMargin THEN FVRow := FVTMargin;
    end;
    FVChar := Ch;
    WITH Registers DO
    begin
      DI := $14; { Send data to screen function }
      IF FVAttribute = AtDefault THEN
        AX := 2  { Just Characters }
      ELSE
        AX := 0; { Characters AND Attributes }
      BL := Byte(FVRow); BH := Byte(FVColumn);
      CX := 1;
      DX := Ofs (FVAttribute);
      SI := Ofs (FVChar);
      BP := DSeg;
    end;
    Intr ($18, Registers);
    FVColumn := FVColumn + 1;
  end;
end {FastVideoOut};

{ WriteFast - Writes a string to the current position (very) fast.
  This procedure writes the contents of a string to the screen at the current
  fast video position "very" fast.  If you are writing just strings (with no
  data which needs to be formatted), you should use this instead of Write,
  because this routine will write the whole string at once, whereas Write
  writes the line one character at a time through FastVideoOut.  After the
  string is written, the current position is incremented to point to the
  posotion following the string just written (as if Write had been used).
  THIS ROUTINE DOES NOT CHECK FOR MARGIN WRAPPING.  ANYTHING YOU WRITE WITH
  IT MUST FIT ON THE SCREEN OR YOU MAY CRASH YOUR MACHINE. }
procedure WriteFast (Text :Str80);
var
  AttribBuff :Array [1..80] of Byte;
  I :Integer;
begin
  If FVAttribute <> AtDefault then FillChar (AttribBuff[1], Length(Text),
                                             FVAttribute);
  WITH Registers DO
  begin
    DI := $14; { Send data to screen function }
    IF FVAttribute = AtDefault THEN
      AX := 2  { Just Characters }
    ELSE
      AX := 0; { Characters AND Attributes }
    BL := Byte(FVRow); BH := Byte(FVColumn);
    CX := Length(Text);
    DX := Ofs (AttribBuff);
    SI := Ofs (Text[1]);
    BP := SSeg;
  end;
  Intr ($18, Registers);
  FVColumn := FVColumn + Length(Text);

end {WriteFast};

{ WriteFastLn - Writes a string to the current position (very) fast + New Line.
  This procedure writes the contents of a string to the screen at the current
  fast video position "very" fast and then advances the current position to
  the left margin of the next line (as if WriteLn) had been used.  SEE COMMENTS
  FOR WriteFast ROUTINE FOR IMPORTANT ADDITIONAL INFORMATION. }
procedure WriteFastLn (Text :Str80);
begin
  WriteFast (Text);
  FVColumn := FVLMargin;
  FVRow := FVRow + 1;
  if FVRow > FVBmargin then FVRow := FVTmargin;
end {WriteFastLn};


{ StartFastVideo - Sets up to do fast video output starting at given position.
  An initial row, column, and attribute value are passed.  Then this routine
  adjusts so that Turbo Pascal sends all output through the FastVideoOut
  routing.  Also, right and bottom margin values are passed, which are used
  in wrapping the display.  The left and top margin values are set to the
  initial column and row values (these are assumed to be the upper left corner
  of the area being used for text).  The cursor is also hidden while fast
  video mode is turned on.
  If this routine is called when fast video is already enabled, everything
  functions as described above, except that the cursor is not turned off
  "again". }
procedure StartFastVideo (InitialColumn, InitialRow, InitialAttribute,
                          RightMargin, BottomMargin :Byte);
begin
  FVRow := InitialRow;
  FVColumn := InitialColumn;
  FVAttribute := InitialAttribute;
  FVLMargin := InitialColumn;
  FVTMargin := InitialRow;
  FVRMargin := RightMargin;
  FVBMargin := BottomMargin;
  IF ConOutPtr <> Ofs(FastVideoOut) THEN
  begin
    SaveConOutPtr := ConOutPtr;
    ConOutPtr := Ofs(FastVideoOut);
    CursorOff;
  end;
end {StartFastVideo};

{ EndFastVideo - Turns off fast video mode so normal output resumes.
  Disables fast video mode and restores turbo output to its normal mode.
  If fast video mode is already off, nothing happens. }
procedure EndFastVideo;
begin
  IF ConOutPtr = Ofs(FastVideoOut) THEN
  begin
    ConOutPtr := SaveConOutPtr;
    CursorOn;
  end;
end {EndFastVideo};

{ NormalExit - Reset and exit back to MS-DOS. }
procedure NormalExit;
const
  BIOSSeg = $40;

begin
  EndFastVideo;
  ClrScr;
  LowVideo;
  If Length (PrintFileName) > 0 then Close (PrintFile);
  If LongChain = TRUE then MemW[BIOSSeg:PatchLocation] := $478A;
  Halt (0);
end {NormalExit};

{ RawChar - Returns 16-bit value of character in "Raw Key buffer".
  This procedure waits until a character has been typed on the keyboard
  and returns that character's 16-bit "raw key" code.
  It also processes the EXIT and PRINT SCREEN keys.  }
function RawChar :Integer;
begin
  repeat
    Registers.DI := $06;
    Intr ($18, Registers);
    IF Registers.CL = $01 THEN
    repeat
      Registers.DI := $02;
      Intr ($18, Registers);
    until Registers.CL = $00;
    { Intercept PrintScreen key and do a print screen; then pretend nothing
      was typed so loop will continue. }
    if  (Registers.CL = $FF)
    and ((Registers.AX and CapsLockMask) = PrintScreenKeyCode) then
    begin
      PrintTheScreen;
      Registers.CL := $00;
    end;
  until Registers.CL = $FF;
  if (EXITAllowed) and ((Registers.AX and CapsLockMask) = ExitKeyCode) then
    NormalExit;
  RawChar := Registers.AX;
end {RawChar};

{ WaitForResume - Waits until the RESUME key is pressed. }
procedure WaitForResume;
var
  I :Integer;
begin
  repeat
    I := (RawChar AND CapsLockMask);
    IF I <> ResumeKeyCode THEN Write (^G);
  until I = ResumeKeyCode;
end {WaitForResume};

{ DrawBox - Display a box on the screen using direct screen I/O.
  This procedure draws a box on the screen when given the upper left and
  lower right coordinates and the "attribute" value to use for the characters
  displayed.  The interior of the box contains spaces, but with the same
  attribute as the outside of the box.  Thus, fast video output to the
  interior of the box will have the same attributes as the box edges if
  not changed when written.
  This routine does not check that the values given are in range.  If they
  are not, results are unpredictable. }
procedure DrawBox (ULColumn, ULRow, LRColumn, LRRow :Integer;
                   Attribute :Byte);
const
  Blank = $20;
var
  I, Height, Width :Integer;
  CharBuff, AttribBuff :Array [1..80] OF Byte;
begin
  { Compute height and width of box.  If either value is less than or equal
    to one, something is wrong...get out and don't draw anything }
  Width := (LRColumn - ULColumn) + 1;
  Height := (LRRow - ULRow) + 1;
  IF (Width < 2) OR (Height < 2) THEN Exit;
  { Turn off cursor while we do this }
  CursorOff;
  { Fill Character Buffer with horizontal line chars and attribute buffer
    with specified value }
  FillChar (CharBuff[ULColumn], Width, HLineChar);
  FillChar (AttribBuff[ULColumn], Width, Attribute);
  { Form top line by changing first and last characters in buffer to upper
    corners }
  CharBuff[ULColumn] := ULCornerChar;
  CharBuff[LRColumn] := URCornerChar;
  { Write top line }
  WITH Registers DO
  begin
    DI := $14; { Send data to screen function }
    AX := 0;   { Characters AND Attributes }
    BL := Byte(ULRow); BH := Byte(ULColumn);
    CX := Width;
    DX := Ofs (AttribBuff[ULColumn]);
    SI := Ofs (CharBuff[ULColumn]);
    BP := Seg (CharBuff[ULColumn]);
  end;
  Intr ($18, Registers);

  { Form bottom line by changing first and last characters in buffer to lower
    corners }
  CharBuff[ULColumn] := LLCornerChar;
  CharBuff[LRColumn] := LRCornerChar;
  { Write bottom line }
  WITH Registers DO
  begin
    DI := $14; { Send data to screen function }
    AX := 0;   { Characters AND Attributes }
    BL := Byte(LRRow); BH := Byte(ULColumn);
    CX := Width;
    DX := Ofs (AttribBuff[ULColumn]);
    SI := Ofs (CharBuff[ULColumn]);
    BP := Seg (CharBuff[ULColumn]);
  end;
  Intr ($18, Registers);

  { If the height of the box is 2, we're done.  Else, set up intermediate
    lines containing vertical lines on each side and spaces in between }
  IF Height > 2 THEN
  begin
    FillChar (CharBuff[ULColumn], Width, Blank);
    CharBuff[ULColumn] := VLineChar;
    CharBuff[LRColumn] := VLineChar;

    { Now display each line containing box sides }
    FOR I := (ULRow + 1) TO (LRRow - 1) DO
    begin
      WITH Registers DO
      begin
        DI := $14; { Send data to screen function }
        AX := 0;   { Characters AND Attributes }
        BL := Byte(I); BH := Byte(ULColumn);
        CX := Width;
        DX := Ofs (AttribBuff[ULColumn]);
        SI := Ofs (CharBuff[ULColumn]);
        BP := Seg (CharBuff[ULColumn]);
      end;
      Intr ($18, Registers);
    end;
  end;

  { Re-enable cursor }
  CursorOn;

  { All done.  Return now. }
end {DrawBox};

{ Center - Display in center of current line using fast video stuff. }
procedure Center (Msg :Str80);
begin
  FVColumn := ((80 - Length(Msg)) div 2) + 1;
  WriteFastLn (Msg);
end {Center};

{ DrawOutline - Display a box around the screen borders with program name. 
  This procedure displays a box around the perimeter of the screen and
  centers the program name in the top line of the box.  This procedure is
  used to "clear" most screens before they are displayed.  Fast video I/O
  is also set up to start at row 3, column 3, with bottom and top margins
  at 23 and 79, respectively.  These can be changed after the procedure is
  called if so desired.  Note that if the outer box has already been drawn,
  it is not drawn again. }
procedure DrawOutline;
var
  I :Integer;
begin
  If not OutlineDrawn then
  begin
    DrawBox (1, 1, 80, 24, AtNormal);
    FVRow := 1;
    Center (Concat (' ', HeaderString, ' '));
    OutlineDrawn := True;
  end
  else
  begin
    StartFastVideo (2, 2, AtNormal, 79, 23);
    For I := 1 to 22 do WriteFastLn
('                                                                              ');
  end;
  if TwoDrives then
  begin
    FVRow := 24; FVAttribute := AtBold;
    Center (Concat(' Physical Drive ',Chr($30+CurrentDrive),' selected '));
    if SetUpExit = True then
    begin
      FVRow := 1; FVAttribute := ATBlinkBold;
      Center (' Select main menu item 9 BEFORE pressing SETUP/CTRL-SETUP !!! ');
    end;
  end;
  StartFastVideo (3, 3, AtNormal, 79, 23);
end {DrawOutline};

{ ReadScreen - Use fast video and raw character calls to read a string.
  This procedure is passed a row and column, a maximum input length, a list
  of allowed (printable) characters in the input, and a list of allowed
  function keys.  It then reads data from the screen, handling the delete key
  appropriately.  The result is returned in the string area passed, and the
  "terminator" key value is also returned.  The terminator key is 0 for
  Return, Keypad Enter, or DO, or the actual raw key value for allowed
  function keys. }
procedure ReadScreen (Column, Row :Byte; MaxLength :Integer;
                      LegalChars :CharsAllowed;
                      Functions :KeysAllowed;
                      Var Result :Str80;
                      Var Terminator :Integer);
var
  Attributes :Array [0..79] of Byte;
  Text :Array [0..79] of Byte;
  Position :Integer;
  I, J :Integer;
  UpshiftMode :Boolean;

  {sub}procedure PrintIt;
  begin
    WITH Registers DO
    begin
      DI := $14; { Send data to screen function }
      AX := 0;   { Characters and Attributes }
      BL := Byte(Row); BH := Byte(Column);
      CX := MaxLength+1;
      DX := Ofs (Attributes);
      SI := Ofs (Text);
      BP := SSeg;
    end;
    Intr ($18, Registers);
  end {PrintIt};

begin
  { Some special magic:  If the allowed characters shows that alphabetic
    upper case characters (or "A", anyway) are allowed but that lower case
    are not, we will upshift any lower case things to upper case.  Determine
    if this will be the case, and flag it if so. }
  UpshiftMode := (('A' in LegalChars) and (Not ('a' in LegalChars)));
  { Start with spaces everywhere }
  FillChar (Text, MaxLength+1, Ord (' '));
  FillChar (Attributes, MaxLength+1, AtNormal);
  { Start with no characters }
  Position := 0;
  While True do { do forever until we exit }
  begin
    { Put cursor character at current cursor position and make it blink }
    Text[Position] := HollowBoxChar;
    Attributes[Position] := AtBlink;
    { Display current string at given position }
    PrintIt;
    Text[Position] := Ord (' ');
    Attributes[Position] := AtNormal;
    { Get character and remove caps lock indicator.  Then remove shift and ctrl
      bits unless key is a function key.  And upshift lower case alphabetics
      if we're dealing with one and that mode is on.  }
    I := (RawChar and CapsLockMask);
    If ((I and $100) = 0) then
    begin
      I := Lo (I);
      If (UpshiftMode) then if ((I >= Ord ('a')) and (I <= Ord ('z'))) then
        I := (I and not $20);
    end;
    { DO, ENTER, and RETURN are all changed to value zero }
    IF (I = ReturnKeyCode) or (I = DoKeyCode) or (I = KeypadEnterKeyCode) then
      I := 0;
    { Now process characters received.  If printable character, add it to
      what we have unless we've filled our alloted space.  If delete key,
      back up one position unless we're already at the beginning.  If anything
      else, see if it's a legitimate terminator and finish up if it is.
      Otherwise, beep and ignore the character. }
    If ((I = $7F) or (I = $08)) and (Position > 0) then
    begin
      Text[Position] := Ord(' ');
      Position := Position - 1;
    end
    else If ((I >= $20) and (I < $7F)) and (Char(I) in LegalChars)
        and (Position < MaxLength) then
    begin
      Text[Position] := I;
      Position := Position + 1;
    end
    else If (I = 0) or ((I >= $100) and ((I-$100) in Functions)) then
    begin
      PrintIt; { Redisplay without hollow box "cursor" }
      For J := 0 To Position-1 do Result[J+1] := Char(Text[J]);
      Result[0] := Char(Position);
      Terminator := I;
      Exit;
    end
    else Write (^G);
  end;
end {ReadScreen};

{ **************************************************************************
                OTHER LOW-LEVEL UTILITY FUNCTIONS & PROCEDURES
  ************************************************************************** }

{ Max - Returns maximum of two integers
  Min - Returns minimum of two integers }
function Min (a, b:Integer) :integer;
begin
  if a < b then Min := a else Min := b;
end {Min};
function Max (a, b:Integer) :integer;
begin
  if a < b then Max := b else Max := a;
end {Max};

{ Checksum - Return checksum of a sector block.
  This function computes the checksum of a block by adding all 256 words
  contained in the block (including the checksum word).  To check that the
  checksum of a block just read is correct, see that this routine returns
  zero for the block.  To compute the checksum for a block to be written,
  set the checksum word to zero, call this function, and then set the
  checksum word to the two's complement (negative) of the value returned.
  For example, when you set the checksum to zero and call this routine it
  returns 183.  You should replace the checksum word with -183; this will
  yield a (proper) checksum of zero for the block being written. }
function Checksum (Var block :SectorBlock): Integer;
var
  I,
  Sum :Integer; {Running checksum total}
begin
  Sum := 0;
  WITH block DO For I := 0 TO 255 DO Sum := Sum + SectorArray[I];
  Checksum := Sum;
end {Checksum};

{ ComputeBATBlocks - Compute number of BAT sectors needed for disk capacity.
  This function is passed the number of tracks on a disk.  It returns the
  number of sectors required for the BAT area (250 tracks fit in one BAT
  block). }
function ComputeBATBlocks (Capacity :Integer) :Integer;
var
  I, J :Integer;
begin
  I := Capacity div 250;
  J := Capacity mod 250;
  If J > 0 then I := I + 1;
  ComputeBATBlocks := I;
end {ComputeBATBlocks};

{ ComputeASTBlocks - Compute # of AST sectors needed to map alternate sectors.
  This function is passed the number of sectors allocated to the alternate
  sector area.  It returns the number of sectors required for the AST area
  (100 alternate sectors fit in one AST block). }
function ComputeASTBlocks (AltSectors :Integer) :Integer;
var
  I, J :Integer;
begin
  I := AltSectors div 100;
  J := AltSectors mod 100;
  If J > 0 then I := I + 1;
  ComputeASTBlocks := I;
end {ComputeASTBlocks};

{ Xlate - Translate O/S logical sector number to physical sector number.
  Under operating systems (CP/M and MS-DOS) disk sectors are "skewed" in
  order to improve access time.  When this procedure is called with a
  sector number (1-16), it takes that sector number as a sector number
  used by the operating system and translates it to the correct physical
  sector.  In practice, these sector translations occur for all blocks
  except "boot" blocks and blocks on the disk which are not operating
  system related (the HOM block, DPD block, etc.) }
function Xlate (InSector :Byte) :Byte;
const
  XlateTable :Array [1..16] of Byte = ( 1,  8, 15,  6, 13,  4, 11,  2,
                                        9, 16,  7, 14,  5, 12,  3, 10);
begin
  Xlate := XlateTable[InSector];
end {Xlate};

{ NextSector - Increments passed track & sector to point to next sector }
procedure NextSector (Var Track :Integer; Var Sector :Byte);
begin
  Sector := Sector + 1;
  If Sector > 16 then
  begin
    Track := Track + 1;
    Sector := 1;
  end;
end {NextSector};

{ PrevSector - Decrements passed track & sector to point to previous sector }
procedure PrevSector (Var Track :Integer; Var Sector :Byte);
begin
  Sector := Sector - 1;
  If Sector < 1 then
  begin
    Track := Track - 1;
    Sector := 16;
  end;
end {PrevSector};

{ **************************************************************************
                    WINCHESTER I/O FUNCTIONS & PROCEDURES
  ************************************************************************** }

{ DoHDFunction - Perform the specified winchester control function.
  This procedure performs the specified function (read, write, write/verify,
  format, etc.) on the specified track and sector of the winchester disk.
  The buffer is either the place the data comes from or goes to, depending
  on the function; its segment and offset are passed separately.  The routine
  returns a status value (nonzero if error) and an error type (providing
  additional error information if status <> 0). }
procedure DoHDFunction (FuncNum :Integer; RTrack :Integer; RSector :Byte;
                        BSeg: Integer; BOffset :Integer;
                        VAR RStatus :Byte; VAR RErrorType :Byte);
begin
  { Initialize block for to DOS }
  WITH WinchesterBlock DO
  begin
    Func := FuncNum;         { Requested function }
    DriveCode := $FF;        { Physical unit, not logical drive }
    Count := 1;              { Number of sectors to read = 1 }
    BuffOfs := BOffset;      { Pointer to buffer... }
    BuffSeg := BSeg;
    Sector := RSector;
    Surface := (RTrack MOD HOMBlock.HOM.Surfaces) OR $40;
    Track := (RTrack DIV HOMBlock.HOM.Surfaces);
    Status := $FF;  ErrorType := $FF;
  end;
  { Now set up request block that will be sent to BIOS }
  With DriverRequest do
  begin
    HeaderLength := 13;
    UnitCode     := 5;
    CommandCode  := 3; { IOCTL function }
    Status       := 0;
    MediaDescrip := $FF;
    TransferAddr := Ptr (Seg (WinchesterBlock), Ofs (WinchesterBlock));
    Count        := 0;   { Not used for IOCTL }
    Start        := 0;   { Not used for IOCTL }
  end;
  { Now use assembly code to call BIOS.  First the stragety entry point, then
    the interrupt entry point }
  inline (
        $8C/$DB/              { MOV BX,DS }
        $8E/$C3/              { MOV ES,BX }
        $BB/DriverRequest/    { MOV BX,OFFSET DriverRequest }
        $FF/$1E/HDStrat/      { CALL DWORD PTR HDStrategy }
        $FF/$1E/HDInter       { CALL DWORD PTR HDInterrupt }
  );
  { Return resulting status to caller }
  With WinchesterBlock DO
  begin
    RStatus := Status;
    RErrorType := ErrorType;
  end;
end {DoHDFunction};

{ ReadSector - Read the specified track/sector into the specified buffer.
  This function returns TRUE if the read succeeds, FALSE if it fails }
function ReadSector (RTrack :Integer; RSector :Byte; Var Buffer :SectorBlock)
                    :Boolean;
Var
  Status, ErrorType :Byte;
begin
  { Perform read of specified track and sector }
  DoHDFunction (READFunc,
                RTrack, RSector,
                Seg(Buffer), Ofs(Buffer),
                Status, ErrorType);

  ReadSector := (Status = 0); { Return TRUE if resulting status is zero }
end {ReadSector};

{ WriteSector - Write the specified track/sector from the specified buffer.
  This function returns TRUE if the write succeeds, FALSE if it fails.  A
  Write with Verify function is used to assure that the data was written
  correctly. }
function WriteSector (WTrack :Integer; WSector :Byte; Var Buffer :SectorBlock)
                     :Boolean;
Var
  Status, ErrorType :Byte;
begin
{ WriteLn (Lst, 'Write track ', WTrack, ' sector ', WSector);
  WriteSector := True; Exit; }
  { Perform Write of specified track and sector }
  DoHDFunction (WRITEVERIFYFunc,
                WTrack, WSector,
                Seg(Buffer), Ofs(Buffer),
                Status, ErrorType);

  WriteSector := (Status = 0); { Return TRUE if resulting status is zero }
end {WriteSector};

{ FormatTrack - Format the specified track.
  This function returns TRUE if the format succeeds, FALSE if it fails. }
function FormatTrack (WTrack :Integer) :Boolean;
Var
  Status, ErrorType :Byte;
begin
  { Perform Write of specified track and sector }
  DoHDFunction (FORMATFunc,
                WTrack, 1,
                Seg(FormatData), Ofs(FormatData),
                Status, ErrorType);

  FormatTrack := (Status = 0); { Return TRUE if resulting status is zero }
end {FormatTrack};

{ WriteNoError - Write the specified track/sector, abort if error.
  This procedure works just like function WriteSector, above, but it prints
  a warning message if the write fails.  It does not return a status value. }
procedure WriteNoError (WTrack :Integer; WSector :Byte;
                        Var Buffer :SectorBlock);
var
  I :Integer;
begin
  If Not WriteSector (WTrack, WSector, Buffer) then With Buffer do
  begin
    DrawOutline;
    StartFastVideo (3, 5, AtBlinkBold, 78, 23);
    Center ('ERROR WRITING DATA TO HARD DISK!');
    Write (^G^G^G);
    FVAttribute := AtBold;
    Center (Concat ('Track: ', Hex4Digit (WTrack), 'H  Sector: ',
                    Hex2Digit (WSector), 'H  Block type: ',
                    PrintChar (SectorBytes[0]), PrintChar (SectorBytes[1]),
                    PrintChar (SectorBytes[2])));
    If WTrack in [0..1] then
      Center (Concat ('(Duplicate data in track ', Chr(Ord('0')+WTrack+2),
                      ' may still permit use of the disk)'))
    else if WTrack in [2..3] then
      Center (Concat ('(Duplicate data in track ', Chr(Ord('0')+Wtrack-2),
                      ' may still permit use of the disk)'))
    else
      WriteLn;
    WriteLn;
    FVAttribute := AtNormal;
    Center ('WUTIL was unable to write the specified track and sector to your');
    Center ('hard disk.  Generally, this indicates a serious error and your');
    Center ('disk will not be usable.  In some cases, the disk may still be');
    Center ('usable because primary data stored in tracks 0 and 1 is');
    Center ('duplicated in tracks 2 and 3.  A message to that effect is');
    Center ('printed above if your disk is still salvageable.');
    WriteLn;
    Center ('Whether this disk appears usable or not after you reboot, you');
    Center ('you should reformat and initialize the disk at your earliest');
    Center ('convenience so that the disk may continue to be used without');
    Center ('difficulty.');
    FVRow := 22;  FVAttribute := AtBold;
    Center ('Press any key to continue');  
    I := RawChar;
  end;
end {WriteNoError};

{ WriteMajorBlock - Write the specified "major block" from the specified buffer.
  This procedure performs several functions.  First, it computes a proper
  checksum for the block contained in "Buffer", which is assumed to be one
  of the major blocks (HOM, OSN, DPD, BAT, AST) contained in the first tracks
  on the disk.  Then it writes the block, first to the specified "WTrack" and
  "WSector", and then to the same sector in track "WTrack+2", which is the
  location of the backup copy of the sector on the disk.  Writes are performed
  using procedure WriteNoError, which will print a warning message if there
  is a problem with the write.  Note that the writing of the additional "backup"
  copy only occurs if the requested track number is 0 or 1.  Otherwise, the
  block is assumed to reside in an unusual location and is only written at
  its primary location. }
procedure WriteMajorBlock (WTrack :Integer; WSector :Byte;
                           Var Buffer :SectorBlock);
begin
  { The checksum is always in the same position.  We'll use the definition
    for the HOM block, but it doesn't really matter which one we use. }
  Buffer.HOM.Checksum := 0;
  Buffer.HOM.Checksum := -(Checksum(Buffer));
  { The result of the operation above is that the sum of the integer data in
    the whole block, including the Checksum word, will be zero. }
  WriteNoError (WTrack, WSector, Buffer);
  If WTrack < 2 then WriteNoError (WTrack+2, WSector, Buffer);
end {WriteMajorBlock};

{ ReadHOMBlock - Read the specified track/sector, verify as valid HOM block.
  If block cannot be read or does not appear to be a HOM block, returns
  value FALSE; returns TRUE if all looks OK }
function ReadHOMBlock (Track :Integer; Sector :Byte; Var Buffer :SectorBlock)
                      :Boolean;
begin
  if not ReadSector (Track, Sector, Buffer) then
  begin
    ReadHOMBlock := FALSE;
    Exit;
  end;
  { Set return value to TRUE if checksum is OK and block ID says it's a HOM
    block.  FALSE otherwise. }
  ReadHOMBlock := ((Checksum(Buffer) = 0) AND (Buffer.HOM.ID = 'HOM'));
end {ReadHOMBlock};

{ ReadDPDBlock - Read the specified track/sector, verify as valid DPD block.
  If block cannot be read or does not appear to be a DPD block, returns
  value FALSE; returns TRUE if all looks OK }
function ReadDPDBlock (Track :Integer; Sector :Byte; Var Buffer :SectorBlock)
                      :Boolean;
begin
  if not ReadSector (Track, Sector, Buffer) then
  begin
    ReadDPDBlock := FALSE;
    Exit;
  end;
  { Set return value to TRUE if checksum is OK and block ID says it's a DPD
    block.  FALSE otherwise. }
  ReadDPDBlock := ((Checksum(Buffer) = 0) AND (Buffer.DPD.ID = 'DPD'));
end {ReadDPDBlock};

{ ReadOSNBlock - Read the specified track/sector, verify as valid OSN block.
  If block cannot be read or does not appear to be a OSN block, returns
  value FALSE; returns TRUE if all looks OK }
function ReadOSNBlock (Track :Integer; Sector :Byte; Var Buffer :SectorBlock)
                      :Boolean;
begin
  if not ReadSector (Track, Sector, Buffer) then
  begin
    ReadOSNBlock := FALSE;
    Exit;
  end;
  { Set return value to TRUE if checksum is OK and block ID says it's a OSN
    block.  FALSE otherwise. }
  ReadOSNBlock := ((Checksum(Buffer) = 0) AND (Buffer.OSN.ID = 'OSN'));
end {ReadOSNBlock};

{ ReadBATBlock - Read the specified track/sector, verify as valid BAT block.
  If block cannot be read or does not appear to be a BAT block, returns
  value FALSE; returns TRUE if all looks OK.  Unlike the other block-reading
  routines here, this routine is also passed a logical block number which is
  expected.  If the block which is read is not the logical BAT block we
  expected to see, we'll also return an error.  }
function ReadBATBlock (Track :Integer; Sector :Byte; LogicalBlock :Byte;
                       Var Buffer :SectorBlock) :Boolean;
begin
  if not ReadSector (Track, Sector, Buffer) then
  begin
    ReadBATBlock := FALSE;
    Exit;
  end;
  { Set return value to TRUE if checksum is OK and block ID says it's a BAT
    block and it's the expected logical block.  FALSE otherwise. }
  ReadBATBlock := ((Checksum(Buffer) = 0) AND (Buffer.BAT.ID = 'BAT')
                   AND (Buffer.BAT.LBN = LogicalBlock));
end {ReadBATBlock};

{ ReadASTBlock - Read the specified track/sector, verify as valid AST block.
  If block cannot be read or does not appear to be a AST block, returns
  value FALSE; returns TRUE if all looks OK.  Unlike the other block-reading
  routines here, this routine is also passed a logical block number which is
  expected.  If the block which is read is not the logical AST block we
  expected to see, we'll also return an error.  }
function ReadASTBlock (Track :Integer; Sector :Byte; LogicalBlock :Byte;
                       Var Buffer :SectorBlock) :Boolean;
begin
  if not ReadSector (Track, Sector, Buffer) then
  begin
    ReadASTBlock := FALSE;
    Exit;
  end;
  { Set return value to TRUE if checksum is OK and block ID says it's a AST
    block and it's the expected logical block.  FALSE otherwise. }
  ReadASTBlock := ((Checksum(Buffer) = 0) AND (Buffer.AST.ID = 'AST')
                   AND (Buffer.AST.LBN = LogicalBlock));
end {ReadASTBlock};

{ SectorIsBad - Returns TRUE if specified track/sector is marked as bad }
Function SectorIsBad (Track :Integer; Sector :Byte) :Boolean;
begin
  { Note: The first check we do (num <> 0) would seem to be superfluous, but
    it allows us to skip the (very slow) "IN" test if none of the sectors
    in the given track are bad, which will be the case most of the time. }
  If SectorTable[Track].Num = 0 then
  begin
    SectorIsBad := False;
    Exit;
  end;
  SectorIsBad := (Pred(Sector) IN SectorTable[Track].Bits);
end;

{ MarkSectorGood - Marks the given sector as good in the sector table }
Procedure MarkSectorGood (Track :Integer; Sector :Byte);
begin
  With SectorTable[Track] do Bits := Bits - [Pred(Sector)];
end;

{ MarkSectorBad - Marks the given sector as bad in the sector table }
Procedure MarkSectorBad (Track :Integer; Sector :Byte);
begin
  With SectorTable[Track] do Bits := Bits + [Pred(Sector)];
end;
