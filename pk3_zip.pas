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

unit pk3_zip;

interface

uses
  Classes;

const
  ZIPFILESIGNATURE = $04034b50;
  ZIPARCIEVESIGNATURE = $08064b50;

type
  TZipFileHeader = packed record
    Signature: integer; // $04034b50
    Version: word;
    BitFlag: word;
    CompressionMethod: word;
    DosDate: integer;
    crc32: integer;
    CompressedSize: integer;
    UnCompressedSize: integer;
    FileNameLen: word;
    ExtraFieldLen: word;
  end;

// This descriptor exists only if bit 3 of the general
// purpose bit flag is set (see below).
  TZipFileDescriptor = record
    crc32: integer;
    CompressedSize: integer;
    UnCompressedSize: integer;
  end;

  TZipArchieveExtraDataRecord = record
    Signature: integer; // $08064b50
    ExtraFieldLen: integer;
  end;

  TZipFile = class
  private
    fFileName: string;
    fFiles: TStringList;
    f: TFileStream;
  protected
    function GetFile(Index: Integer): string; virtual;
    procedure Load; virtual;
    procedure Clear; virtual;
    procedure SetFileName(const Value: string); virtual;
    function GetFileCount: integer;
  public
    constructor Create(const aFileName: string); virtual;
    destructor Destroy; override;
    function GetZipFileData(const Index: integer; var p: pointer;
      var size: integer): boolean; overload; virtual;
    function GetZipFileData(const Name: string; var p: pointer;
      var size: integer): boolean; overload; virtual;
    property FileName: string read fFileName write SetFileName;
    property Files[Index: Integer]: string read GetFile;
    property FileCount: integer read GetFileCount;
  end;

type
  TZAlloc = function (opaque: Pointer; items, size: Integer): Pointer;
  TZFree  = procedure (opaque, block: Pointer);

  TZStreamRec = packed record
    next_in  : PChar;     // next input byte
    avail_in : Longint;   // number of bytes available at next_in
    total_in : Longint;   // total nb of input bytes read so far

    next_out : PChar;     // next output byte should be put here
    avail_out: Longint;   // remaining free space at next_out
    total_out: Longint;   // total nb of bytes output so far

    msg      : PChar;     // last error message, NULL if no error
    state    : Pointer;   // not visible by applications

    zalloc   : TZAlloc;   // used to allocate the internal state
    zfree    : TZFree;    // used to free the internal state
    opaque   : Pointer;   // private data object passed to zalloc and zfree

    data_type: Integer;   // best guess about the data type: ascii or binary
    adler    : Longint;   // adler32 value of the uncompressed data
    reserved : Longint;   // reserved for future use
  end;

function inflate(var strm: TZStreamRec; flush: Integer): Integer;

function inflateInit2_(var strm: TZStreamRec; windowBits: Integer;
  version: PChar; recsize: Integer): Integer;

function deflateInit_(var strm: TZStreamRec; level: Integer; version: PChar;
  recsize: Integer): Integer;

function deflate(var strm: TZStreamRec; flush: Integer): Integer;

function deflateEnd(var strm: TZStreamRec): Integer;

function inflateInit_(var strm: TZStreamRec; version: PChar;
  recsize: Integer): Integer;

function inflateEnd(var strm: TZStreamRec): Integer;

const
  ZLIB_VERSION = '1.2.8';


implementation

uses
  SysUtils,
  pk3_system;

{$L obj\z128_deflate}
{$L obj\z128_inflate}
{$L obj\z128_inftrees}
{$L obj\z128_infback}
{$L obj\z128_inffast}
{$L obj\z128_trees}
{$L obj\z128_compress}
{$L obj\z128_adler32}
{$L obj\z128_crc32}

const
  {** flush constants *******************************************************}
  Z_NO_FLUSH      = 0;
  Z_PARTIAL_FLUSH = 1;
  Z_SYNC_FLUSH    = 2;
  Z_FULL_FLUSH    = 3;
  Z_FINISH        = 4;
  Z_BLOCK         = 5;

const
  z_errmsg: Array [0..9] of String = (
    'Need dictionary',      // Z_NEED_DICT      (2)
    'Stream end',           // Z_STREAM_END     (1)
    'OK',                   // Z_OK             (0)
    'File error',           // Z_ERRNO          (-1)
    'Stream error',         // Z_STREAM_ERROR   (-2)
    'Data error',           // Z_DATA_ERROR     (-3)
    'Insufficient memory',  // Z_MEM_ERROR      (-4)
    'Buffer error',         // Z_BUF_ERROR      (-5)
    'Incompatible version', // Z_VERSION_ERROR  (-6)
    ''
  );

function zcalloc(opaque: Pointer; items, size: Integer): Pointer;
begin
  GetMem(Result, items * size);
end;

procedure zcfree(opaque, block: Pointer);
begin
  FreeMem(block);
end;

procedure memcpy(dest, source: Pointer; count: Integer); cdecl;
begin
  Move(source^, dest^, count);
end;

{** c function implementations **********************************************}

function memset(p: Pointer; b: Byte; count: Integer): pointer; cdecl;
begin
  FillChar(p^, count, b);
  Result := p;
end;

function inflate(var strm: TZStreamRec; flush: Integer): Integer; external;

function inflateInit2_(var strm: TZStreamRec; windowBits: Integer;
  version: PChar; recsize: Integer): Integer; external;

function deflateInit_(var strm: TZStreamRec; level: Integer; version: PChar;
  recsize: Integer): Integer; external;

function deflate(var strm: TZStreamRec; flush: Integer): Integer; external;

function deflateEnd(var strm: TZStreamRec): Integer; external;

function inflateInit_(var strm: TZStreamRec; version: PChar;
  recsize: Integer): Integer; external;

function inflateEnd(var strm: TZStreamRec): Integer; external;

function InflateInit2(var stream: TZStreamRec; windowBits: Integer): Integer;
begin
  Result := inflateInit2_(stream, windowBits, ZLIB_VERSION, SizeOf(TZStreamRec));
end;

procedure ZDecompress2(const inBuffer: Pointer; const inSize: Integer;
  const outSize: Integer; out outBuffer: Pointer);
var
  zstream: TZStreamRec;

  procedure CheckErr(err: integer);
  begin
    if err < 0 then
      I_Error(Format('ZDecompress2(): Zip file error(%d)', [err]));
  end;

begin
  FillChar(zstream, SizeOf(TZStreamRec), 0);

  GetMem(outBuffer, outSize);

  CheckErr(InflateInit2(zstream, -15));

  zstream.next_in := inBuffer;
  zstream.avail_in := inSize;
  zstream.next_out := outBuffer;
  zstream.avail_out := outSize;

  CheckErr(inflate(zstream, Z_SYNC_FLUSH));

  inflateEnd(zstream);
end;

//------------------------------------------------------------------------------
type
  TZipFileEntryInfo = class
  private
    fSize: integer;
    fCompressedSize: integer;
    fPosition: integer;
    fCompressed: boolean;
  public
    constructor Create(const aSize, aCompressedSize, aPosition: integer;
      aCompressed: boolean); virtual;
    property Size: integer read fSize;
    property CompressedSize: integer read fCompressedSize;
    property Position: integer read fPosition;
    property Compressed: boolean read fCompressed;
  end;

constructor TZipFileEntryInfo.Create(const aSize, aCompressedSize, aPosition: integer;
      aCompressed: boolean);
begin
  fSize := aSize;
  fCompressedSize := aCompressedSize;
  fPosition := aPosition;
  fCompressed := aCompressed;
end;

//------------------------------------------------------------------------------
constructor TZipFile.Create(const aFileName: string);
begin
  Inherited Create;
  fFiles := TStringList.Create;
  fFileName := aFileName;
  Load;
end;

destructor TZipFile.Destroy;
begin
  Clear;
  fFiles.Free;
  Inherited Destroy;
end;

function TZipFile.GetZipFileData(const Index: integer; var p: pointer;
  var size: integer): boolean;
var
  tmp: pointer;
  zinf: TZipFileEntryInfo;
  csize: integer;
begin
  if (Index >= 0) and (Index < fFiles.Count) then
  begin
    zinf := (fFiles.Objects[Index] as TZipFileEntryInfo);
    if zinf.Compressed then
    begin
      size := zinf.Size;
      csize := zinf.CompressedSize;
      GetMem(tmp, csize);
      try
        f.Seek(zinf.Position, soFromBeginning);
        f.Read(tmp^, csize);
        ZDecompress2(tmp, csize, size, p);
      finally
        FreeMem(tmp, csize);
      end;
      Result := True;
    end
    else
    begin
      size := zinf.Size;
      GetMem(p, size);
      f.Seek(zinf.Position, soFromBeginning);
      f.Read(p^, size);
      Result := True;
    end;
  end
  else
    Result := False;
end;

function TZipFile.GetZipFileData(const Name: string; var p: pointer;
  var size: integer): boolean;
var
  Name2: string;
  i: integer;
begin
  Name2 := UpperCase(Name);
  for i := 1 to Length(Name) do
    if Name2[i] = '/' then
      Name2[i] := '\';
  Result := GetZipFileData(fFiles.IndexOf(Name2), p, size);
end;

function TZipFile.GetFile(Index: Integer): string;
begin
  Result := fFiles[Index];
end;

procedure TZipFile.Load;
var
  h: TZipFileHeader;
  str: string;
  i: integer;
begin
  Clear;
  if fFileName <> '' then
  begin
    f := TFileStream.Create(fFileName, fmOpenRead or fmShareDenyWrite);
    while True do
    begin
      f.Read(h, SizeOf(h));
      if h.Signature = ZIPFILESIGNATURE then
      begin
        SetLength(str, h.FileNameLen);
        if h.FileNameLen > 0 then
        begin
          f.Read((@str[1])^, h.FileNameLen);
          str := UpperCase(str);
          for i := 1 to h.FileNameLen do
            if str[i] = '/' then
              str[i] := '\';
          fFiles.Objects[fFiles.Add(str)] :=
            TZipFileEntryInfo.Create(h.UnCompressedSize, h.CompressedSize,
              f.Position + h.ExtraFieldLen, h.CompressionMethod > 0);
          if (h.BitFlag and $4) <> 0 then
            f.Seek(h.ExtraFieldLen + h.CompressedSize + SizeOf(TZipFileDescriptor), soFromCurrent)
          else
            f.Seek(h.ExtraFieldLen + h.CompressedSize, soFromCurrent);
        end;
      end
      else
        Break;
    end;
  end;
end;

procedure TZipFile.Clear;
var
  i: integer;
begin
  for i := 0 to fFiles.Count - 1 do
    fFiles.Objects[i].Free;
  fFiles.Clear;
  f.Free;
end;

procedure TZipFile.SetFileName(const Value: string);
begin
  if fFileName <> Value then
  begin
    fFileName := Value;
    Load;
  end;
end;

function TZipFile.GetFileCount: integer;
begin
  Result := fFiles.Count;
end;

{$ifndef WIN64}
procedure _llmod;
asm
  jmp System.@_llmod;
end;
{$endif}

end.

