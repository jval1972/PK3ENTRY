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

program pk3entry;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  Classes,
  pk3_main in 'pk3_main.pas',
  pk3_utils in 'pk3_utils.pas',
  pk3_zip in 'pk3_zip.pas',
  pk3_reader in 'pk3_reader.pas',
  pk3_writer in 'pk3_writer.pas',
  pk3_wadwriter in 'pk3_wadwriter.pas',
  pk3_system in 'pk3_system.pas',
  pk3_version in 'pk3_version.pas',
  pk3_data in 'pk3_data.pas',
  pk3_argv in 'pk3_argv.pas',
  pk3_wad in 'pk3_wad.pas',
  pk3_wadreader in 'pk3_wadreader.pas';

var
  forcewait: boolean = False;

procedure Usage;
begin
  I_Println('This is a tool that:');
  I_Println(' -Inserts PK3 files inside a WAD file');
  I_Println('  The output WAD file contains long filename aliases (PK3ENTRY lump)');
  I_Println(' -Split WAD files that contain PK3ENTRY lump(s) to PK3 and WAD');
  I_Println('');
  I_Println('USAGE');
  I_Println(' -To insert PK3 files inside a WAD file');
  I_Println('  ' + APPNAME + ' -i infile1 [infile2....] -ow outfile [-r]');
  I_Println('     [-i]      : specify input PK3/WAD files');
  I_Println('     [-ow]     : specify output WAD file');
  I_Println('     [-r]      : rename common lumps (ACTORDEF, VOXELDEF, ...)');
  I_Println('');
  I_Println(' -Split WAD files that contain contain PK3ENTRY lump(s)');
  I_Println('  ' + APPNAME + ' -s infile [-oz outfile] [-ow outfile]');
  I_Println('     [-s]      : specify input WAD files to split');
  I_Println('     [-oz]     : specify output PK3/ZIP file');
  I_Println('     [-ow]     : specify output WAD file with the remaining lumps');
  I_Println('');
  I_Println('ADDITIONAL PARAMETERS:');
  I_Println('     [-help]   : show this help screen');
  I_Println('     [-wait]   : wait for key when done');
  I_Println('     [-nowait] : does not wait for key when done');
  I_Println('     [-quiet]  : does not show screen information');
  I_Println('     [-nobck]  : does not create backup file');

  forcewait := True;
  Sleep(100);
end;

procedure PressAnyKeyToContinue;
var
  k: byte;
begin
  while True do
    for k := 0 to 255 do
    begin
      GetAsyncKeyState(k);
      if GetAsyncKeyState(k) <> 0 then
        Exit;
    end;
end;

procedure _progress(const pct: double);
begin
  if pct >= 0.999999999 then
    I_Verbose(#13)
  else
    I_Verbose(#13 + IntToStr(Round(pct * 100)) + '%');
end;

procedure ExpandMaskedFiles(const lst: TStringList);
var
  lst2: TStringList;
  i, j: integer;
  sline: string;
  lmask: TStringList;

  function lst_index(const src: string): integer;
  var
    x: integer;
    check: string;
  begin
    check := UpperCase(ExpandFileName(Trim(src)));
    for x := 0 to lst.Count - 1 do
      if check = UpperCase(ExpandFileName(Trim(lst.Strings[x]))) then
      begin
        Result := x;
        Exit;
      end;
    Result := -1;
  end;

begin
  lst2 := TStringList.Create;
  lst2.Text := lst.Text;
  lst.Clear;

  for i := 0 to lst2.Count - 1 do
  begin
    sline := lst2.Strings[i];
    if (Pos('*', sline) > 0) or (Pos('?', sline) > 0) then
    begin
      lmask := findfiles(sline);
      for j := 0 to lmask.Count - 1 do
        if lst_index(lmask.Strings[j]) < 0 then
          lst.Add(lmask.Strings[j]);
      lmask.Free;
    end
    else
    begin
      if lst_index(sline) < 0 then
        lst.Add(sline);
    end;
  end;
  lst2.Free;
end;

procedure PK3EntryMain;
var
  infiles: TStringList;
  infile, outfilew, outfilez: string;
  pini, pins, poutw, poutz: integer;
  rename_common_names: boolean;
begin
  quiet := (CheckParam('-q') > 0) or (CheckParam('-quiet') > 0);
  I_Verboseln(APPNAME + ' version ' + APPVERSION + ', ' + APPCOPYRIGHT);

  if (ParamCount < 1) or
     (CheckParam('-h') > 0) or (CheckParam('-help') > 0) or
     (CheckParam('/?') > 0) or (CheckParam('/h') > 0)  then
  begin
    Usage;
    Exit;
  end;

  pini := ParamNotLast(CheckParams('-i', '-input'));
  pins := ParamNotLast(CheckParams('-s', '-split'));
  poutw := ParamNotLast(CheckParams('-ow', '-outputw'));
  poutz := ParamNotLast(CheckParams('-oz', '-outputz'));
  rename_common_names := CheckParam('-r') > 0;

  // no input
  if (pini < 0) and (pins < 0) then
  begin
    Usage;
    Exit;
  end;

  // no output
  if (poutw < 0) and (poutz < 0) then
  begin
    Usage;
    Exit;
  end;

  // erronous input
  if (pini > 0) and (pins > 0) then
  begin
    Usage;
    Exit;
  end;

  // erronous input
  if (poutw > 0) and (poutz > 0) and (pini > 0) then
  begin
    Usage;
    Exit;
  end;

  // erronous input - output compination
  if (pini > 0) and (poutz > 0) then
  begin
    Usage;
    Exit;
  end;

  // Rename common files only at WAD output mode
  if rename_common_names and (poutz > 0) then
  begin
    Usage;
    Exit;
  end;

  infiles := TStringList.Create;

  if pini > 0 then  // Insert PK3 files inside a WAD file
  begin
    while pini < ParamCount do
    begin
      inc(pini);
      infile := ParamStr(pini);
      if Pos('-', infile) <> 1 then
        infiles.Add(infile)
      else
        Break;
    end;
    ExpandMaskedFiles(infiles);

    if infiles.Count = 0 then
    begin
      infiles.Free;
      Usage;
      Exit;
    end;

    outfilew := ParamStr(poutw + 1);

    if not PK3_ConvertToWAD(infiles, outfilew, CheckParam('-nobck') < 0, rename_common_names, _progress) then
    begin
      infiles.Free;
      Usage;
      Exit;
    end;
  end;

  if pins > 0 then  // Split a WAD file
  begin
    while pins < ParamCount do
    begin
      inc(pins);
      infile := ParamStr(pins);
      if Pos('-', infile) <> 1 then
        infiles.Add(infile)
      else
        Break;
    end;
    ExpandMaskedFiles(infiles);
    
    if infiles.Count = 0 then
    begin
      infiles.Free;
      Usage;
      Exit;
    end;

    if poutw > 0 then
      outfilew := ParamStr(poutw + 1);
    if poutz > 0 then
      outfilez := ParamStr(poutz + 1);

    if not PK3_SplitWADs(infiles, outfilew, outfilez, CheckParam('-nobck') < 0, _progress) then
    begin
      infiles.Free;
      Usage;
      Exit;
    end;
  end;

  infiles.Free;
end;

begin
  PK3EntryMain;
  if (forcewait or (CheckParam('-wait') > 0)) and not (CheckParam('-nowait') > 0) then
  begin
    I_Verbose(#13#10'Press any key to exit...');
    PressAnyKeyToContinue;
  end;
end.

