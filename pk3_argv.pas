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

unit pk3_argv;

interface

function CheckParam(const param: string): integer;

function CheckParams(const param1, param2: string): integer;

function ParamNotLast(const paramid: integer): integer;

implementation

uses
  SysUtils;

function CheckParam(const param: string): integer;
var
  i: integer;
begin
  for i := 1 to ParamCount do
    if UpperCase(ParamStr(i)) = UpperCase(param) then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function CheckParams(const param1, param2: string): integer;
var
  Result1, Result2: integer;
begin
  Result1 := CheckParam(param1);
  Result2 := CheckParam(param2);
  if (Result1 < 0) and (Result2 < 0) then
  begin
    Result := -1;
    Exit;
  end;

  if (Result1 > 0) and (Result2 > 0) then
  begin
    Result := -1;
    Exit;
  end;

  if Result1 > 0 then
    Result := Result1
  else
    Result := Result2;
end;

function ParamNotLast(const paramid: integer): integer;
begin
  if paramid >= ParamCount then
    Result := -1
  else
    Result := paramid;
end;

end.
