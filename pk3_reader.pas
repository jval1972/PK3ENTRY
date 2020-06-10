//------------------------------------------------------------------------------
//
//  PK3Entry
//  PK3Entry is a tool to encapsulate multiple PK3 files inside a WAD file
//  The output WAD file contains long filename aliases (PK3ENTRY lump)
//  Copyright (C) 2019 by Jim Valavanis
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 2
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
//  02111-1307, USA.
//
//------------------------------------------------------------------------------
//  E-Mail: jimmyvalavanis@yahoo.gr
//  Site  : https://sourceforge.net/projects/pk3entry/
//------------------------------------------------------------------------------

unit pk3_reader;

interface

uses
  Classes,
  pk3_zip;

const
  Pakid: integer = $4B434150;   // 'PACK' In Hex!
  WAD2id: integer = $32444157;  // 'WAD2' in Hex!
  WAD3id: integer = $33444157;  // 'WAD3' in Hex!

type
  FPakHead = packed record // A PAK Directory Entry
    Name: packed array[1..56] of char;
    Offs: integer;
    Fsize: integer;
  end;

  TFPakHeadArray = packed array[0..$FFFF] of FPakHead;
  PFPakHeadArray = ^TFPakHeadArray;

  FWadHead = packed record // A WAD2/WAD3 Directory Entry
    Offs: integer;
    disksize: integer;
    size: integer;  // uncompressed
    _type: char;
    compression: char;
    pad1, pad2: char;
    name: packed array[1..16] of char; // must be null terminated
  end;

  TFWadHeadArray = packed array[0..$FFFF] of FWadHead;
  PFWadHeadArray = ^TFWadHeadArray;

type
  TCompressorCache = class(TObject)
  private
    fZip: TZipFile;
    fID: integer;
    fPosition: integer;
    fSize: integer;
    data: pointer;
  public
    constructor Create(aZip: TZipFile; aID: integer); virtual;
    destructor Destroy; override;
    function Read(var Buf; Sz: Integer): integer;
    function Seek(pos: integer): boolean;
    property Position: integer read fPosition;
    property Size: integer read fSize;
  end;

  TPK3Entry = record // A Directory Entry Memory Image
    Pak: string[255];
    Name: string[255];
    ShortName: string[32];
    Offset, Size: Integer;
    Hash: integer;
    ZIP: TZipFile;
  end;
  PPK3Entry = ^TPK3Entry;

  TPK3Entries = array[0..$FFFF] of TPK3Entry;
  PPK3Entries = ^TPK3Entries;

  TPK3File = record
    Entry: Integer;
    F: file;
    Z: TCompressorCache;
  end;
  PPK3File = ^TPK3File;

  TPK3Reader = class
  private
    Entries: PPK3Entries;
    NumEntries: Integer;
    MaxEntries: Integer;
    PAKS: TStringList;
    procedure Grow;
    procedure AddEntry(var H: FPakHead; Pakn: string); overload;
    procedure AddEntry(var HD: FWADhead; Pakn: string); overload;
    procedure AddEntry(ZIPFILE: TZipFile; const ZIPFileName, EntryName: string; const index: integer); overload;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure GetEntries(var s: TStringList);
    function POpenFileName(var F: TPK3File; Name: string): boolean;
    function POpenFileNameIdx(var F: TPK3File; Name: string; const idx: integer): boolean;
    function PClosefile(var F: TPK3File): boolean;
    function PBlockRead(var F: TPK3File; var Buf; Sz: Integer): integer;
    function PSeek(var F: TPK3File; Pos: Integer): boolean;
    function PFilePos(var F: TPK3File): Integer;
    function PFileSize(var F: TPK3File): Integer;
    function PAddFile(const FileName: string): boolean;
  end;

type
  TPakStream = class(TStream)
  private
    entry: TPK3File;
    manager: TPK3Reader;
    FIOResult: integer;
  public
    constructor Create(const FileName: string);
    destructor Destroy; override;
    function Read(var Buffer; Count: integer): integer; override;
    function Write(const Buffer; Count: integer): integer; override;
    function Seek(Offset: integer; Origin: Word): integer; override;
    function Size: integer;
    function Position: integer;
  end;

procedure PAK_InitFileSystem;
procedure PAK_ShutDown;
function PAK_AddFile(const FileName: string): boolean;

implementation

uses
  pk3_utils,
  pk3_system,
  SysUtils;

{******** TCompressorCache ********}
constructor TCompressorCache.Create(aZip: TZipFile; aID: integer);
begin
  Inherited Create;
  fZip := aZip;
  fID := aID;
  fZip.GetZipFileData(fID, data, fSize);
  fPosition := 0;
end;

destructor TCompressorCache.Destroy;
begin
  FreeMem(data, fSize);
  Inherited Destroy;
end;

function TCompressorCache.Read(var Buf; Sz: Integer): integer;
begin
  if fPosition + Sz > Size then
    Result := Size - fPosition
  else
    Result := Sz;

  Move(pointer(integer(data) + fPosition)^, buf, Result);
  fPosition := fPosition + Result;
end;

function TCompressorCache.Seek(pos: integer): boolean;
begin
  if (pos < 0) or (pos > Size) then
    Result := False
  else
  begin
    fPosition := pos;
    Result := True;
  end;
end;

function MkHash(const s: string): integer;
var
  i: integer;
begin
  Result := 0;
  for i := 1 to length(s) do
  begin
    Result := ((Result shl 7) or (Result shr 25)) + Ord(s[i]);
  end;
end;

{********* TPackDir *********}
constructor TPK3Reader.Create;
begin
  PAKS := TStringList.Create;

  Entries := nil;
  NumEntries := 0;
  MaxEntries := 0;
end;

procedure TPK3Reader.Grow;
var
  newentries: integer;
begin
  Inc(NumEntries);
  if NumEntries > MaxEntries then
  begin
    newentries := MaxEntries + 512;
    ReallocMem(Entries, newentries * SizeOf(TPK3Entry));
    MaxEntries := newentries;
  end;
end;

// Add a ZIP file entry (ZIP/PK3/PK4)
procedure TPK3Reader.AddEntry(ZIPFILE: TZipFile; const ZIPFileName, EntryName: string; const index: integer);
var
  e: PPK3Entry;
begin
  Grow;
  e := @Entries[NumEntries - 1];
  e.Pak := ZIPFileName;
  e.Name := UpperCase(EntryName);
  e.ShortName := fshortname(e.Name);
  e.Hash := MkHash(e.ShortName);
  e.Offset := index; // offset -> index to ZIP file
  e.Size := 0;
  e.ZIP := ZIPFILE;
end;

// Add an entry from Quake PAK file
procedure TPK3Reader.AddEntry(var H: FPakHead; Pakn: string); // Add A Pak Entry to Memory List
var
  S: string;
  I: Integer;
  e: PPK3Entry;
begin
  Grow;

  S := '';
  for I := 1 to 56 do
    if H.Name[I] <> #0 then
      S := S + H.Name[I]
    else
      break;

  S := UpperCase(S);
  e := @Entries[NumEntries - 1];
  e.Pak := Pakn;
  e.Name := S;
  e.ShortName := fshortname(e.Name);
  e.Hash := MkHash(e.ShortName);
  e.Offset := H.Offs;
  e.Size := H.Fsize;
  e.ZIP := nil;
end;

// Add an entry from a WAD file (new WAD version)
procedure TPK3Reader.AddEntry(var HD: FWADhead; Pakn: string);
var
  S: string;
  I: Integer;
  e: PPK3Entry;
begin
  Grow;

  S := '';
  for I := 1 to 16 do
    if HD.Name[I] <> #0 then
      S := S + UpCase(HD.Name[I])
    else
      break;

  e := @Entries[NumEntries - 1];
  e.Pak := Pakn;
  e.Name := S;
  e.ShortName := fshortname(e.Name);
  e.Hash := MkHash(e.ShortName);
  e.Offset := HD.Offs;
  e.Size := HD.size;
  e.ZIP := nil;
end;

function TPK3Reader.PAddFile(const FileName: string): boolean; // Add A Pak file
var
  Nr: Integer;
  N, Id, Ofs:Integer;
  F: file;
  P: Pointer;
  I: Integer;
  z: TZipFile;
  pkid: integer;
  Fn: string;
begin
  Result := False;
  Fn := UpperCase(Trim(FileName));
  if PAKS.IndexOf(Fn) > -1  then
    Exit;
  if Fn = '' then
    Exit;

  pkid := PAKS.Add(Fn);
  PAKS.Objects[pkid] := nil;

  {$I-}
  assign(F, Fn);
  FileMode := 0;
  reset(F, 1);
  {$I+}
  if IOResult <> 0 then
    Exit;

  Blockread(F, Id, 4, N);
  if N <> 4 then
  begin
    close(F);
    Exit;
  end;
  if (Id <> Pakid) and (Id <> WAD2Id) and (Id <> WAD3Id) and (id <> ZIPFILESIGNATURE) then
  begin
    Result := False;
    close(F);
    Exit;
  end;

  if Id = Pakid then // PAK file
  begin
    BlockRead(F, Ofs, 4, N);
    if N <> 4 then
    begin
      close(F);
      Exit;
    end;
    BlockRead(F, Nr, 4, N);
    if N <> 4 then
    begin
      close(F);
      Exit;
    end;
    Nr := Nr div SizeOf(FPakHead);
    Seek(F, Ofs);
    GetMem(P, Nr * SizeOf(FPakHead));
    Blockread(F, P^, Nr * SizeOf(FPakHead), N);
    for i := 0 to N div SizeOf(FPakHead) - 1 do
      AddEntry(PFPakHeadArray(P)[i], Fn);
    FreeMem(P, Nr * SizeOf(FPakHead));
  end
  else if id = ZIPFILESIGNATURE then // zip, pk3, pk4 file
  begin
    z := TZipFile.Create(Fn);
    PAKS.Objects[pkid] := z;
    for i := 0 to z.FileCount - 1 do
      AddEntry(z, Fn, z.Files[i], i);
  end
  else // WAD2 or WAD3
  begin
    BlockRead(F, Nr, 4, N);
    if N <> 4 then
    begin
      close(F);
      Exit;
    end;
    BlockRead(F, Ofs, 4, N);
    if N <> 4 then
    begin
      close(F);
      Exit;
    end;
    seek(F, Ofs);
    GetMem(P, Nr * SizeOf(FWadHead));
    Blockread(F, P^, Nr * SizeOf(FWadHead), N);
    for i := 0 to N div SizeOf(FWadHead) - 1 do
      AddEntry(PFWadHeadArray(P)[i], Fn);
    FreeMem(P, Nr * SizeOf(FWadHead));
  end;
  close(F);
  Result := True;
end;

procedure TPK3Reader.GetEntries(var s: TStringList);
var i: integer;
begin
  if s = nil then
    s := TStringList.Create;
  for I := 0  to NumEntries - 1 do
    s.Add(Entries[I].Name);
end;

// Opens a file
function TPK3Reader.POpenFileName(var F: TPK3File; Name: string): boolean;
var
  I: Integer;
  hcode: integer;
  pe: PPK3Entry;
begin
  Result := False;
  F.Z := nil;

  {$I-}
  assign(F.F, Name);
  FileMode := 0;
  reset(F.F, 1);
  {$I+}
  if IOResult = 0 then
  begin
    F.Entry := -1;
    Result := True;
    Exit;
  end; // Disk file Overrides Pak file

  Name := UpperCase(Name);
  hcode := MkHash(fshortname(Name));
  for I := NumEntries - 1 downto 0 do // From last entry to zero, last file has priority
  begin
    pe := @Entries[i];
    if hcode = pe.Hash then   // Fast compare the hash values
      if pe.Name = Name then  // Slow compare strings
      begin // Found In Pak
        if pe.ZIP <> nil then // It's a zip (pk3/pk4) file
          F.Z := TCompressorCache.Create(pe.ZIP, pe.Offset)
        else
        begin // Standard Quake1/2 pak file
          {$I-}
          assign(F.F, string(pe.Pak));
          FileMode := 0;
          Reset(F.F, 1);
          {$I+}
          if IOResult <> 0 then
            Exit;
          Seek(F.F, pe.Offset);
        end;
        F.Entry := I;
        Result := True;
        Exit;
      end;
    end;
end;

function TPK3Reader.POpenFileNameIdx(var F: TPK3File; Name: string; const idx: integer): boolean;
var
  I: Integer;
  hcode: integer;
  pe: PPK3Entry;
begin
  Result := False;
  F.Z := nil;

  {$I-}
  assign(F.F, Name);
  FileMode := 0;
  reset(F.F, 1);
  {$I+}
  if IOResult = 0 then
  begin
    F.Entry := -1;
    Result := True;
    Exit;
  end; // Disk file Overrides Pak file

  Name := UpperCase(Name);
  hcode := MkHash(fshortname(Name));
  i := idx;
  if (i >= 0) and (i < NumEntries) then
  begin
    pe := @Entries[i];
    if hcode = pe.Hash then   // Fast compare the hash values
      if pe.Name = Name then  // Slow compare strings
      begin // Found In Pak
        if pe.ZIP <> nil then // It's a zip (pk3/pk4) file
          F.Z := TCompressorCache.Create(pe.ZIP, pe.Offset)
        else
        begin // Standard Quake1/2 pak file
          {$I-}
          assign(F.F, string(pe.Pak));
          FileMode := 0;
          Reset(F.F, 1);
          {$I+}
          if IOResult <> 0 then
            Exit;
          Seek(F.F, pe.Offset);
        end;
        F.Entry := I;
        Result := True;
        Exit;
      end;
    end;

  if not Result then
    I_Error(Format('TPK3Reader.POpenFileNameIdx(): Name %s does not match index %d', [Name, idx]));
end;

function TPK3Reader.PClosefile(var F: TPK3File): boolean;
begin
  if F.Z <> nil then
  begin
    F.Z.Free;
    F.Z := nil;
    Result := True;
  end
  else
  begin
    {$I-}
    Close(F.F);
    {$I+}
    Result := IOResult = 0;
  end;
end;

function TPK3Reader.PBlockRead(var F: TPK3File; var Buf; Sz: Integer): integer;
begin
  if F.Z <> nil then
    Result := F.Z.Read(Buf, Sz)
  else
  begin
    {$I-}
    Blockread(F.F, Buf, Sz, Result);
    {$I+}
  end;
end;

function TPK3Reader.PSeek(var F: TPK3File; Pos: Integer): boolean;
begin
  if F.Z <> nil then
    Result := F.Z.Seek(pos)
  else
  begin
  {$I-}
    if F.Entry = -1 then
      Seek(F.F, Pos)
    else
      Seek(F.F, Entries[F.Entry].Offset + Pos);
    {$I+}
    Result := IOResult = 0;
  end;
end;

function TPK3Reader.PFilePos(var F: TPK3File): Integer;
begin
  if F.Z <> nil then
    Result := F.Z.Position
  else
  begin
    Result := FilePos(F.F);
    if F.Entry <> -1 then
      Result := Result - Entries[F.Entry].Offset;
  end;
end;

function TPK3Reader.PFileSize(var F: TPK3File): Integer;
begin
  if F.Z <> nil then
    Result := F.Z.Size
  else if F.Entry <> -1 then
    Result := Entries[F.Entry].Size
  else
  begin
  {$I-}
    Result := Filesize(F.F);
  {$I+}
    if IOResult <> 0 then
      Result := 0;
  end;
end;

destructor TPK3Reader.Destroy;
var
  i: integer;
begin
  FreeMem(Entries, MaxEntries * Sizeof(TPK3Entry));

  for i := 0 to PAKS.Count - 1 do
    if PAKS.Objects[i] <> nil then
      PAKS.Objects[i].Free;

  PAKS.Free;
end;

// Global Pak Loader Object
var
  pakmanager: TPK3Reader;

//
// TPakStream
constructor TPakStream.Create(const FileName: string);
var
  ok: boolean;
begin
  Inherited Create;

  manager := pakmanager;
  if manager = nil then
  begin
    FIOResult := 1;
    Exit;
  end;
  ok := manager.POpenFileName(entry, FileName);
  if not ok then
    FIOResult := 1
  else
    FIOResult := 0;
end;

destructor TPakStream.Destroy;
begin
  manager.PClosefile(entry);
  Inherited;
end;

function TPakStream.Read(var Buffer; Count: integer): integer;
begin
  Result := manager.PBlockRead(entry, Buffer, Count);
  if IOResult <> 0 then
    inc(FIOResult);
end;

function TPakStream.Write(const Buffer; Count: integer): integer;
begin
  I_Error('TPakStream::Write(): Pak managment is read-only'#13#10);
  inc(FIOResult);
  Result := 0;
end;

function TPakStream.Seek(Offset: integer; Origin: Word): integer;
var
  p: integer;
begin
  if Origin = soFromBeginning then
    p := Offset
  else if Origin = soFromCurrent then
    p := manager.PFilePos(entry) + Offset
  else {sFromEnd}
    p := manager.PFileSize(entry) - Offset;

  if not manager.PSeek(entry, p) then
    inc(FIOResult);
  Result := p;
end;

function TPakStream.Size: integer;
begin
  Result := manager.PFileSize(entry)
end;

function TPakStream.Position: integer;
begin
  Result := manager.PFilePos(entry);
end;

//
// W_InitPakFileSystem
//
procedure PAK_InitFileSystem;
begin
  pakmanager := TPK3Reader.Create;
end;

procedure PAK_ShutDown;
begin
  pakmanager.Free;
  pakmanager := nil;
end;

function PAK_AddFile(const FileName: string): boolean;
begin
  Result := pakmanager.PAddFile(FileName);
end;

end.


