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

unit pk3_wadreader;

interface

uses
  Classes,
  pk3_utils,
  pk3_wad;

type
  TWadReader = class(TObject)
  private
    h: header_t;
    la: lumparray_p;
    fs: TFileStream;
    fonprogress: progress_t;
  protected
    procedure Progress(const pct: double);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear; virtual;
    procedure OpenWadFile(const aname: string);
    function EntryAsString(const id: integer): string; overload;
    function EntryAsString(const aname: string): string; overload;
    function EntryName(const id: integer): string;
    function EntryId(const aname: string): integer;
    function NumEntries: integer;
  end;

implementation

uses
  SysUtils,
  pk3_system;

constructor TWadReader.Create;
begin
  h.identification := 0;
  h.numlumps := 0;
  h.infotableofs := 0;
  la := nil;
  fs := nil;
  fonprogress := nil;
  Inherited;
end;

destructor TWadReader.Destroy;
begin
  Clear;
  Inherited;
end;

procedure TWadReader.Clear;
begin
  if h.numlumps > 0 then
  begin
    FreeMem(la, h.numlumps * SizeOf(lump_t));
    h.identification := 0;
    h.numlumps := 0;
    h.infotableofs := 0;
    la := nil;
  end
  else
  begin
    h.identification := 0;
    h.infotableofs := 0;
  end;
  if fs <> nil then
  begin
    fs.Free;
    fs := nil;
  end;
end;

procedure TWadReader.Progress(const pct: double);
begin
  if Assigned(fonprogress) then
    fonprogress(pct);
end;

procedure TWadReader.OpenWadFile(const aname: string);
begin
  if aname = '' then
    Exit;
  I_Verboseln('Opening WAD file ' + aname);
  Clear;
  fs := TFileStream.Create(aname, fmOpenRead);

  fs.Read(h, SizeOf(header_t));
  if (h.numlumps > 0) and (h.infotableofs < fs.Size) and ((h.identification = IWAD) or (h.identification = PWAD)) then
  begin
    fs.Seek(h.infotableofs, soFromBeginning);
    GetMem(la, h.numlumps * SizeOf(lump_t));
    fs.Read(la^, h.numlumps * SizeOf(lump_t));
  end
  else
    I_Verboseln('Invalid WAD file ' + aname);
end;

function TWadReader.EntryAsString(const id: integer): string;
begin
  if (fs <> nil) and (id >= 0) and (id < h.numlumps) then
  begin
    SetLength(Result, la[id].size);
    fs.Position := la[id].filepos;
    fs.Read((@Result[1])^, la[id].size);
  end
  else
    Result := '';
end;

function TWadReader.EntryAsString(const aname: string): string;
var
  id: integer;
begin
  id := EntryId(aname);
  if id >= 0 then
    Result := EntryAsString(id)
  else
    Result := '';
end;

function TWadReader.EntryName(const id: integer): string;
begin
  if (id >= 0) and (id < h.numlumps) then
    Result := char8_to_string(la[id].name)
  else
    Result := '';
end;

function TWadReader.EntryId(const aname: string): integer;
var
  i: integer;
  uname: string;
begin
  uname := UpperCase(aname);
  for i := h.numlumps - 1 downto 0 do
    if char8_to_string(la[i].name) = uname then
    begin
      Result := i;
      Exit;
    end;
  Result := -1;
end;

function TWadReader.NumEntries: integer;
begin
  Result := h.numlumps;
end;

end.
