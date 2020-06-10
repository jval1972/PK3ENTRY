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

unit pk3_main;

interface

uses
  Classes,
  pk3_utils;

function PK3_ConvertToWAD(const infiles: TStringList; const outfile: string;
  const dobck: boolean; const rename_common_names: boolean; const _progress: progress_t): boolean;

function PK3_SplitWADs(const infiles: TStringList; const outfilew, outfilez: string;
  const dobck: boolean; const _progress: progress_t): boolean;

implementation

uses
  SysUtils,
  pk3_wadwriter,
  pk3_wadreader,
  pk3_writer,
  pk3_system;

function PK3_ConvertToWAD(const infiles: TStringList; const outfile: string;
  const dobck: boolean; const rename_common_names: boolean; const _progress: progress_t): boolean;
var
  i: integer;
  wad: TWadWriter;
  ext: string;
  wadfiles, pk3files: TStringList;
  ocheck: string;
begin
  if Trim(outfile) = '' then
  begin
    Result := False;
    I_Verboseln('No output file specified');
    Exit;
  end;

  if infiles = nil then
  begin
    Result := False;
    I_Verboseln('No input files specified');
    Exit;
  end;

  if infiles.Count = 0 then
  begin
    Result := False;
    I_Verboseln('No input files specified');
    Exit;
  end;

  ocheck := UpperCase(ExpandFileName(outfile));
  for i := 0 to infiles.Count - 1 do
    if ocheck = UpperCase(ExpandFileName(infiles.Strings[i])) then
    begin
      Result := False;
      I_Verboseln('Input file can not be the save as output file "' + ExtractFileName(outfile) + '"');
      Exit;
    end;

  wadfiles := TStringList.Create;
  pk3files := TStringList.Create;
  wad := TWadWriter.Create;
  try
    if Assigned(_progress) then
      wad.onprogress := @_progress;
    for i := 0 to infiles.Count - 1 do
    begin
      ext := UpperCase(ExtractFileExt(infiles.Strings[i]));
      if (ext = '.WAD')  or (ext = '.SWD') or (ext = '.GWA') then
        wadfiles.Add(infiles.Strings[i])
      else
        pk3files.Add(infiles.Strings[i]);
    end;
    for i := 0 to wadfiles.Count - 1 do
      wad.AddWad(wadfiles.Strings[i]);
    wad.AddPK3s(pk3files, rename_common_names);
    if dobck and FileExists(outfile) then
    begin
      I_Verboseln('Making backup of ' + outfile);
      backupfile(outfile, @_progress);
    end;
    I_Verboseln('Writing WAD output to ' + outfile);
    wad.SaveToFile(outfile);
    I_Verboseln('All done!');
  finally
    wad.Free;
    wadfiles.Free;
    pk3files.Free;
  end;
  Result := True;
end;

function PK3_SplitWADs(const infiles: TStringList; const outfilew, outfilez: string;
  const dobck: boolean; const _progress: progress_t): boolean;
var
  wadi: TWadReader; // Input WAD (Reader)
  wado: TWadWriter; // Output WAD (Writer)
  pk3o: TPK3Writer; // Output PK3 (Writer)
  lumppresend: PBooleanArray; // Lumps of input WAD that we will put to the output WAD
  i, j, k, n, p: integer;
  sl: TStringList;
  sline: string;
  wentry, zentry: string;
  wentryid: integer;
begin
  if outfilew <> '' then
  begin
    wado := TWadWriter.Create;
    wado.onprogress := _progress;
  end
  else
    wado := nil;
  if outfilez <> '' then
  begin
    pk3o := TPK3Writer.Create;
    pk3o.onprogress := _progress;
  end
  else
    pk3o := nil;

  Result := (wado <> nil) or (pk3o <> nil);
  if not Result then
    Exit;
    
  sl := TStringList.Create;
  for i := 0 to infiles.Count - 1 do
  begin
    I_Verboseln('Adding WAD file ' + infiles.Strings[i]);
    wadi := TWadReader.Create;
    wadi.OpenWadFile(infiles.Strings[i]);
    n := wadi.NumEntries;

    GetMem(lumppresend, n * SizeOf(boolean));
    for j := 0 to n - 1 do
      lumppresend[j] := True;

    // First pass: find PK3ENTRY lumps and add long filename aliases to pk3/zip output
    for j := 0 to n - 1 do
    begin
      if wadi.EntryName(j) = 'PK3ENTRY' then
      begin
        lumppresend[j] := False;  // Exclude entry from output wad
        sl.Text := wadi.EntryAsString(j);
        // Parse PK3ENTRY lump
        for k := 0 to sl.Count - 1 do
        begin
          sline := sl.Strings[k];
          p := Pos('//', sline);
          if p > 0 then
            SetLength(sline, p - 1);
          sline := Trim(sline);
          splitstring(sline, wentry, zentry, '=');
          wentry := Trim(wentry);
          zentry := Trim(zentry);
          wentryid := wadi.EntryId(wentry);
          if wentryid >= 0 then
          begin
            lumppresend[wentryid] := False;  // Exclude entry from output wad
            AddDataToPK3(pk3o, zentry, wadi.EntryAsString(wentryid));
          end;
        end;
      end;
    end;

    // Second pass: Write remaing lumps to WAD
    if wado <> nil then
      for j := 0 to n - 1 do
        if lumppresend[j] then
          AddDataToWAD(wado, wadi.EntryName(j), wadi.EntryAsString(j));

    FreeMem(lumppresend, n * SizeOf(boolean));
    wadi.Free;
  end;

  // Write output WAD
  if wado <> nil then
  begin
    if dobck and FileExists(outfilew) then
    begin
      I_Verboseln('Making backup of ' + outfilew);
      backupfile(outfilew, @_progress);
    end;
    I_Verboseln('Writing WAD output to ' + outfilew);
    wado.SaveToFile(outfilew);
    wado.Free;
  end;

  // Write output PK3
  if pk3o <> nil then
  begin
    if dobck and FileExists(outfilez) then
    begin
      I_Verboseln('Making backup of ' + outfilez);
      backupfile(outfilez, @_progress);
    end;
    I_Verboseln('Writing PK3 output to ' + outfilez);
    pk3o.SaveToFile(outfilez);
    pk3o.Free;
  end;

  sl.Free;
end;

end.

