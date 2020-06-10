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

unit pk3_utils;

interface

uses
  Classes;

type
  progress_t = procedure (const pct: double);

function fshortname(const FileName: string): string;

procedure splitstring(const inp: string; var out1, out2: string; const splitter: string = ' ');

function IntToStr8(const x: integer): string;

function CopyFile(const sname, dname: string; const p: progress_t = nil): boolean;

procedure backupfile(const fn: string; const p: progress_t = nil);

function ReverseString(const s: string): string;

function RemoveCharFromString(const s: string; const ch: char): string;

function findfiles(const mask: string): TStringList;

type
  TBooleanArray = array[0..$FFFF] of boolean;
  PBooleanArray = ^TBooleanArray;

implementation

uses
  SysUtils;

function fshortname(const FileName: string): string;
var
  i: integer;
begin
  Result := '';
  for i := Length(FileName) downto 1 do
  begin
    if FileName[i] in ['\', '/'] then
      break;
    Result := FileName[i] + Result;
  end;
end;

procedure splitstring(const inp: string; var out1, out2: string; const splitter: string = ' ');
var
  p: integer;
begin
  p := Pos(splitter, inp);
  if p = 0 then
  begin
    out1 := inp;
    out2 := '';
  end
  else
  begin
    out1 := Trim(Copy(inp, 1, p - 1));
    out2 := Trim(Copy(inp, p + 1, Length(inp) - p));
  end;
end;

function IntToStr8(const x: integer): string;
begin
  Result := IntToStr(x);
  while Length(Result) < 8 do
    Result := '0' + Result;
end;

function CopyFile(const sname, dname: string; const p: progress_t = nil): boolean;
var
  FromF, ToF: file;
  NumRead, NumWritten: Integer;
  Buf: array[1..8192] of Char;
  adir: string;
  totsize: integer;
  totwritten: integer;
begin
  Result := False;

  if (Trim(sname) = '') or (Trim(dname) = '') then
    Exit;

  if FileExists(sname) then
  begin
    {$I-}
    if assigned(p) then
      p(0.0);
    AssignFile(FromF, sname);
    Reset(FromF, 1);
    totsize := FileSize(FromF);
    adir := Trim(ExtractFilePath(dname));
    if adir <> '' then
      if not DirectoryExists(adir) then
        ForceDirectories(adir);
    AssignFile(ToF, dname);
    Rewrite(ToF, 1);
    totwritten := 0;
    if assigned(p) then
      p(0.0);
    repeat
      BlockRead(FromF, Buf, SizeOf(Buf), NumRead);
      BlockWrite(ToF, Buf, NumRead, NumWritten);
      totwritten := totwritten + NumWritten;
      if assigned(p) then
        p(totwritten / totsize);
    until (NumRead = 0) or (NumWritten <> NumRead);
    CloseFile(FromF);
    CloseFile(ToF);
    {$I+}
    Result := IOResult = 0;
    if assigned(p) then
      p(1.0);
  end;
end;

procedure backupfile(const fn: string; const p: progress_t = nil);
var
  fbck: string;
  fname: string;
begin
  fname := Trim(fn);

  if fname = '' then
    Exit;

  if not FileExists(fname) then
    Exit;

  fbck := fname + '_bak';
  CopyFile(fname, fbck, p);
end;

function ReverseString(const s: string): string;
var
  i: integer;
begin
  Result := '';
  for i := Length(s) downto 1 do
    Result := Result + s[i];
end;

function RemoveCharFromString(const s: string; const ch: char): string;
var
  i: integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    if s[i] <> ch then
      Result := Result + s[i];
end;

function findfiles(const mask: string): TStringList;
var
  sr: TSearchRec;
begin
  Result := TStringList.Create;
  if FindFirst(mask, faAnyFile, sr) = 0 then
  begin
    Result.Add(sr.Name);
    while FindNext(sr) = 0 do
      Result.Add(sr.Name);
    FindClose(sr);
  end;
end;

end.

