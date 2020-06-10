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

unit pk3_wadwriter;

interface

uses
  Classes,
  pk3_utils;

type
  TWadWriter = class(TObject)
  private
    lumps: TStringList;
    fonprogress: progress_t;
  protected
    procedure Progress(const pct: double);
  public
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Clear; virtual;
    procedure AddFile(const lumpname: string; const fname: string);
    procedure AddData(const lumpname: string; const data: pointer; const size: integer);
    procedure AddString(const lumpname: string; const data: string);
    procedure AddWad(const fname: string);
    procedure AddPK3(const fname: string; const rename_common_names: boolean);
    procedure AddPK3s(const lpk: TStrings; const rename_common_names: boolean);
    procedure AddSeparator(const lumpname: string);
    procedure SaveToStream(const strm: TStream);
    procedure SaveToFile(const fname: string);
    property onprogress: progress_t read fonprogress write fonprogress;
  end;

function AddDataToWAD(const wad: TWADWriter; const lumpname, data: string): boolean;

implementation

uses
  SysUtils,
  pk3_system,
  pk3_version,
  pk3_reader,
  pk3_data,
  pk3_wad;

constructor TWadWriter.Create;
begin
  lumps := TStringList.Create;
  fonprogress := nil;
  Inherited;
end;

destructor TWadWriter.Destroy;
var
  i: integer;
begin
  for i := 0 to lumps.Count - 1 do
    if lumps.Objects[i] <> nil then
      lumps.Objects[i].Free;
  lumps.Free;
  Inherited;
end;

procedure TWadWriter.Clear;
var
  i: integer;
begin
  for i := 0 to lumps.Count - 1 do
    if lumps.Objects[i] <> nil then
      lumps.Objects[i].Free;
  lumps.Clear;
end;

procedure TWadWriter.Progress(const pct: double);
begin
  if Assigned(fonprogress) then
    fonprogress(pct);
end;

procedure TWadWriter.AddFile(const lumpname: string; const fname: string);
var
  m: TMemoryStream;
  fs: TFileStream;
begin
  m := TMemoryStream.Create;
  fs := TFileStream.Create(fname, fmOpenRead);
  try
    m.CopyFrom(fs, fs.Size);
    lumps.AddObject(UpperCase(lumpname), m);
  finally
    fs.Free;
  end;
end;

procedure TWadWriter.AddData(const lumpname: string; const data: pointer; const size: integer);
var
  m: TMemoryStream;
begin
  m := TMemoryStream.Create;
  m.Write(data^, size);
  lumps.AddObject(UpperCase(lumpname), m);
end;

procedure TWadWriter.AddString(const lumpname: string; const data: string);
var
  m: TMemoryStream;
  i: integer;
begin
  m := TMemoryStream.Create;
  for i := 1 to Length(data) do
    m.Write(data[i], SizeOf(char));
  lumps.AddObject(UpperCase(lumpname), m);
end;

procedure TWadWriter.AddWad(const fname: string);
var
  fs: TFileStream;
  h: header_t;
  la: lumparray_p;
  i: integer;
  buf: pointer;
  bufsize: integer;
  totsize, cursize: integer;
begin
  if fname = '' then
    Exit;
  I_Verboseln('Adding WAD file ' + fname);
  fs := TFileStream.Create(fname, fmOpenRead);
  try
    fs.Read(h, SizeOf(h));
    GetMem(la, h.numlumps * SizeOf(lump_t));
    fs.Position := h.infotableofs;
    fs.Read(la^, h.numlumps * SizeOf(lump_t));
    buf := nil;
    bufsize := 0;
    Progress(0.0);
    totsize := 0;
    for i := 0 to h.numlumps - 1 do
      totsize := totsize + la[i].size;
    cursize := 0;
    for i := 0 to h.numlumps - 1 do
    begin
      if i mod 10 = 0 then
        if totsize > 0 then
          Progress(cursize / totsize);
      if la[i].size = 0 then
        AddSeparator(char8_to_string(la[i].name))
      else
      begin
        cursize := cursize + la[i].size;
        if bufsize < la[i].size then
        begin
          bufsize := la[i].size;
          ReallocMem(buf, bufsize);
        end;
        fs.Position := la[i].filepos;
        fs.Read(buf^, la[i].size);
        AddData(char8_to_string(la[i].name), buf, la[i].size);
      end;
    end;
    Progress(1.0);
  finally
    fs.Free;
  end;
end;

procedure TWadWriter.AddPK3(const fname: string; const rename_common_names: boolean);
var
  lst: TStringList;
begin
  lst := TStringList.Create;
  try
    lst.Add(fname);
    AddPK3s(lst, rename_common_names);
  finally
    lst.Free;
  end;
end;

procedure data_to_list(const lst: TStringList; const A: Array of Byte; const size: integer);
var
  x: integer;
  s: string;
begin
  SetLength(s, size);
  for x := 0 to size - 1 do
    s[x + 1] := Chr(A[x]);
  lst.Text := s;
end;

procedure TWadWriter.AddPK3s(const lpk: TStrings; const rename_common_names: boolean);
var
  pk3: TPK3Reader;
  ff: TPK3File;
  i: integer;
  entries: TStringList;
  buf: pointer;
  bufsize: integer;
  size: integer;
  new_lumps: TStringList;
  common_lumps: TStringList;
  multiple_names: TStringList;
  pk3entry_data: TStringList;
  global_idx: integer;

  function _multiple_check(const s: string): string;
  var
    x: integer;
    check: string;
  begin
    if rename_common_names then
    begin
      Result := '';
      Exit;
    end;
    check := UpperCase(ExtractFileName(s));
    for x := 0 to multiple_names.Count - 1 do
      if (check = multiple_names.Strings[x]) or (check = multiple_names.Strings[x] + '.TXT') then
      begin
        Result := multiple_names.Strings[x];
        Exit;
      end;
    Result := '';
  end;

  function _global_idx: integer;
  begin
    Result := global_idx;
    inc(global_idx);
  end;

  function valid_name(const name: string): boolean;
  var
    uname: string;
  begin
    uname := UpperCase(name);
    if new_lumps.IndexOf(uname) < 0 then
      if lumps.IndexOf(uname) < 0 then
        if common_lumps.IndexOf(uname) < 0 then
          if multiple_names.IndexOf(uname) < 0 then
          begin
            Result := True;
            Exit;
          end;
    Result := False;
  end;

  function find_valid_entry(const name: string): string;
  var
    x: integer;
    stest: string;
    idx: integer;
  begin
    Result := _multiple_check(name);
    if Result <> '' then
      Exit;

    Result := '';
    for x := 1 to Length(name) do
    begin
      if name[x] = '.' then
        Result := Result + '_'
      else if not (name[x] in [' ', '\', '/', '=']) then
        Result := Result + name[x];
    end;

    if Length(Result) > 8 then
    begin
      Result := ExtractFileName(name);
        for x := 1 to Length(Result) do
          if Result[x] in [' ', '\', '/', '.', '='] then
            Result[x] := '_';

      if Length(Result) > 8 then
      begin
        stest := RemoveCharFromString(Result, '_');
        if Length(stest) > 0 then
          if Length(stest) <= 8 then
            Result := stest;
      end;
      if Length(Result) > 8 then
        SetLength(Result, 8);
    end
    else if Result = '' then  // ?
    begin
      Result := find_valid_entry(IntToStr8(_global_idx));
      Exit;
    end;

    Result := UpperCase(Result);
    if valid_name(Result) then
      Exit;

    while Length(Result) < 8 do
      Result := Result + '0';

    if global_idx >= 99999999 then
      global_idx := 0;

    repeat
      idx := _global_idx;
      stest := ReverseString(IntToStr(idx));
      for x := 8 downto 9 - Length(stest) do
        Result[x] := stest[9 - x];
    until valid_name(Result) or (global_idx = 99999999);

    if global_idx = 99999999 then
    begin
      global_idx := 0;
      randomize;
      repeat
        Result := S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1] +
                  S_RNDSEQ[random(Length(S_RNDSEQ)) + 1];
      until valid_name(Result);
    end;
  end;

  function _add_pk3_entry(const name: string): string;
  begin
    Result := find_valid_entry(name);
    if multiple_names.IndexOf(Result) < 0 then
    begin
      new_lumps.Add(Result);
      pk3entry_data.Add(Result + '=' + name);
    end;
  end;

begin
  pk3 := TPK3Reader.Create;
  try
    for i := 0 to lpk.Count - 1 do
    begin
      I_Verboseln('Adding PK3 file ' + lpk.Strings[i]);
      pk3.PAddFile(lpk.Strings[i]);
    end;
    entries := TStringList.Create;
    pk3entry_data := TStringList.Create;
    pk3entry_data.Add('// Created with ' + APPNAME + ' version ' + APPVERSION);
    new_lumps := TStringList.Create;
    common_lumps := TStringList.Create;
    multiple_names := TStringList.Create;
    multiple_names.Text := S_MULTIPLE_NAME;
    try
      pk3.GetEntries(entries);
      data_to_list(common_lumps, S_COMMON_LUMPS, SizeOf(S_COMMON_LUMPS));
      buf := nil;
      bufsize := 0;
      global_idx := 0;
      Progress(0.0);
      for i := 0 to entries.Count - 1 do
      begin
        if i mod 10 = 0 then
          Progress(i / entries.Count);
        if pk3.POpenFileNameIdx(ff, entries.Strings[i], i) then
        begin
          size := pk3.PFileSize(ff);
          if size > 0 then
          begin
            if bufsize < size then
            begin
              bufsize := size;
              ReallocMem(buf, size);
            end;
            pk3.PBlockRead(ff, buf^, size);
            AddData(_add_pk3_entry(entries.Strings[i]), buf, size);
          end;
          pk3.PClosefile(ff);
        end;
      end;
      AddString('PK3ENTRY', pk3entry_data.Text);
      Progress(1.0);
    finally
      entries.Free;
      pk3entry_data.Free;
      new_lumps.Free;
      common_lumps.Free;
      multiple_names.Free;
    end;
  finally
    pk3.Free;
  end;
end;

procedure TWadWriter.AddSeparator(const lumpname: string);
begin
  lumps.Add(UpperCase(lumpname));
end;

procedure TWadWriter.SaveToStream(const strm: TStream);
var
  h: header_t;
  la: lumparray_p;
  i: integer;
  p, ssize: integer;
  m: TMemoryStream;
  totsize, cursize: integer;
begin
  p := strm.Position;
  h.identification := PWAD;
  h.numlumps := lumps.Count;
  h.infotableofs := p + SizeOf(header_t);
  strm.Write(h, SizeOf(h));
  p := strm.Position;
  GetMem(la, lumps.Count * SizeOf(lump_t));
  strm.Write(la^, lumps.Count * SizeOf(lump_t));

  Progress(0.0);
  totsize := 0;
  for i := 0 to lumps.Count - 1 do
    if lumps.Objects[i] <> nil then
      totsize := totsize + (lumps.Objects[i] as TStream).Size;
  cursize := 0;
  for i := 0 to lumps.Count - 1 do
  begin
    if i mod 10 = 0 then
      if totsize > 0 then
        Progress(cursize / totsize);
    la[i].filepos := strm.Position;
    m := lumps.Objects[i] as TMemoryStream;
    if m <> nil then
    begin
      la[i].size := m.Size;
      cursize := cursize + la[i].size;
      m.Position := 0;
      strm.CopyFrom(m, la[i].size);
    end
    else
      la[i].size := 0;
    la[i].name := string_to_char8(lumps.Strings[i]);
  end;
  ssize := strm.Position;
  strm.Position := p;
  strm.Write(la^, lumps.Count * SizeOf(lump_t));
  FreeMem(la, lumps.Count * SizeOf(lump_t));
  strm.Position := ssize;
  Progress(1.0);
end;

procedure TWadWriter.SaveToFile(const fname: string);
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(fname, fmCreate);
  try
    SaveToStream(fs);
  finally
    fs.Free;
  end;
end;

function AddDataToWAD(const wad: TWADWriter; const lumpname, data: string): boolean;
begin
  if wad <> nil then
  begin
    wad.AddString(lumpname, data);
    Result := True;
  end
  else
    Result := False;
end;

end.

