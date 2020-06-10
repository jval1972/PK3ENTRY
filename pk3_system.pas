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

unit pk3_system;

interface

type
  outproc_t = procedure(const msg: string);

var
  outproc: outproc_t;
  quiet: boolean = False;

procedure I_Error(const msg: string);

procedure I_Print(const msg: string);

procedure I_Println(const msg: string);

procedure I_Verbose(const msg: string);

procedure I_Verboseln(const msg: string);

implementation

procedure I_Error(const msg: string);
begin
  I_println(msg);
  Halt(1);
end;

procedure I_Print(const msg: string);
begin
  if Assigned(outproc) then
    outproc(msg)
  else if IsConsole then
    write(msg);
end;

procedure I_Println(const msg: string);
begin
  if Assigned(outproc) then
    outproc(msg + #13#10)
  else if IsConsole then
    writeln(msg);
end;

procedure I_Verbose(const msg: string);
begin
  if not quiet then
    I_Print(msg);
end;

procedure I_Verboseln(const msg: string);
begin
  if not quiet then
    I_Println(msg);
end;

end.
