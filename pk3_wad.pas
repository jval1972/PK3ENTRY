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

unit pk3_wad;

interface

const
  PWAD = integer(Ord('P') or
                (Ord('W') shl 8) or
                (Ord('A') shl 16) or
                (Ord('D') shl 24));

  IWAD = integer(Ord('P') or
                (Ord('W') shl 8) or
                (Ord('A') shl 16) or
                (Ord('D') shl 24));

type
  header_t = packed record
    identification: integer;
    numlumps: integer;
    infotableofs: integer;
  end;
  header_p = ^header_t;

  char8_t = packed array[0..7] of char;

  lump_t = packed record
    filepos: integer;
    size: integer;
    name: char8_t;
  end;
  lump_p = ^lump_t;
  lumparray_t = array[0..$FFF] of lump_t;
  lumparray_p = ^lumparray_t;

function string_to_char8(const s: string): char8_t;

function char8_to_string(const l: char8_t): string;

implementation

uses
  SysUtils;

function string_to_char8(const s: string): char8_t;
var
  i: integer;
  uS: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  uS := UpperCase(s);
  for i := 1 to Length(uS) do
  begin
    Result[i - 1] := uS[i];
    if i = 8 then
      Exit;
  end;
end;

function char8_to_string(const l: char8_t): string;
var
  i: integer;
begin
  Result := '';
  for i := 0 to 7 do
  begin
    if l[i] = #0 then
      Exit;
    Result := Result + UpperCase(l[i]);
  end;
end;

end.
 