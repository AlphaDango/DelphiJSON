unit uDangoJSON;

interface

uses
  Classes, SysUtils, DateUtils,
  IdGlobalProtocols,
  uDangoStringBuilder;

type
  TJSONValueType = (jvtString, jvtNumber, jvtBoolean, jvtNull, jvtObject, jvtArray, jvtDateTime);

  TJSONObject = class;
  TJSONArray  = class;

  TJSONValue = class
  private
    procedure ResetValues;
  public
    ValueType : TJSONValueType;
    AsString  : string;
    AsNumber  : Extended;
    AsBoolean : Boolean;
    AsObject  : TJSONObject;
    AsArray   : TJSONArray;
    AsDateTime: TDateTime;

    constructor CreateString(const S: string);
    constructor CreateNumber(const N: Extended);
    constructor CreateBoolean(const B: Boolean);
    constructor CreateNull;
    constructor CreateObject(Obj: TJSONObject);
    constructor CreateArray(Arr: TJSONArray);
    constructor CreateDateTime(const DT: TDateTime);
    destructor Destroy; override;

    function ToString: string; reintroduce; virtual;
  end;

  TJSONObject = class
  private
    FKeys: TStringList;
    function GetCount: Integer;
    function GetKey(Index: Integer): string;
    function GetValueByIndex(Index: Integer): TJSONValue;

  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Add(const Key: string; Value: TJSONValue); overload;
    function  Add(const Key: string; Value: string): TJSONObject; overload;
    function  Add(const Key: string; Value: Extended): TJSONObject; overload;
    function  Add(const Key: string; Value: Boolean): TJSONObject; overload;
    function  Add(const Key: string; Value: TJSONObject): TJSONObject; overload;
    function  Add(const Key: string; Value: TJSONArray): TJSONObject; overload;
    procedure SetValue(const Key: string; Value: TJSONValue); // Überschreibt und freed ggf. alten Wert
    function  GetValue(const Key: string): TJSONValue; // Kann nil ausgeben
    function  Contains(const Key: string): Boolean;

    property  Count: Integer read GetCount;
    property  Keys[Index: Integer]: string read GetKey;
    property  Values[Index: Integer]: TJSONValue read GetValueByIndex;

    function ToString: string; reintroduce; virtual;

    class function ParseJSON(const S: string): TJSONObject; overload;
    class function ParseJSON(const S: TStream): TJSONObject; overload;
  end;

  TJSONArray = class
  private
    FItems: TList;
    function GetCount: Integer;
    function GetItem(Index: Integer): TJSONValue;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure Add(Value: TJSONValue);
    property  Count: Integer read GetCount;
    property  Items[Index: Integer]: TJSONValue read GetItem;

    function ToString: string; reintroduce; virtual;
  end;

  function ParseJSON(const S: string): TJSONValue;
  function JSONStreamToString(JSONStream: TStream): string;

implementation

// --- ISO8601 Hilfsfunktionen ---
function DateTimeToISO8601(const DT: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss.zzz', DT);
end;

function TryISO8601ToDateTime(const S: string; out DT: TDateTime): Boolean;
begin
  try
    DT := GMTToLocalDateTime(S);
    Result := (DT-1 <> -1);
  except
    Result := False;
  end;
end;

// ===== Helpers für JSON-Zahlen mit '.' als Dezimaltrennzeichen =====

function FloatToJSON(const N: Extended): string;
var
  I: Integer;
begin
  Result := FloatToStr(N);
  
  if SysUtils.DecimalSeparator <> '.' then
    for I := 1 to Length(Result) do
      if Result[I] = ',' then begin
        Result[I] := '.';
        Break;
      end;
end;


function StrToJSONFloat(const S: string): Extended;
var
  LocalStr: string;
  I: Integer;
begin
  LocalStr := S;
  if SysUtils.DecimalSeparator  <> '.' then
    for I := 0 to Length(LocalStr) do
      if LocalStr[I] = '.' then begin
        LocalStr[I] := SysUtils.DecimalSeparator;
        Break;
      end;

  Result := StrToFloat(LocalStr);
end;


// ===== String Escaping / Unescaping =====

function EscapeJSONString(const Input: string): string;
var
  InputIndex, InputLength, OutputLength: Integer;
  CurrentChar: Char;
  TempBuffer: string;
  HexStr: string;
begin
  InputLength := Length(Input);

  // Einen Puffer erstellen, welcher maximal 6x so groß ist,
  // weil z.B. ein Zeichen wie #0 zu '\u0000' wird (= 6 Zeichen).
  SetLength(TempBuffer, InputLength * 6);
  OutputLength := 0;

  for InputIndex := 1 to InputLength do
  begin
    CurrentChar := Input[InputIndex];

    case CurrentChar of
      '"':
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := '"';
        end;
      '\':
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
        end;
      #8:
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := 'b';
        end;
      #9:
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := 't';
        end;
      #10:
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := 'n';
        end;
      #12:
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := 'f';
        end;
      #13:
        begin
          Inc(OutputLength); TempBuffer[OutputLength] := '\';
          Inc(OutputLength); TempBuffer[OutputLength] := 'r';
        end;
    else
      // Steuerzeichen unterhalb ASCII 32 -> Unicode-Escape
      if Ord(CurrentChar) < $20 then
      begin
        // Füge z.B. \u0001 hinzu
        Inc(OutputLength, 6);
        Move(PChar('\u00')[0], TempBuffer[OutputLength - 5], 4);

        // Wandelt z.B. 13 ? '0D'
        HexStr := IntToHex(Ord(CurrentChar), 2);

        TempBuffer[OutputLength - 2] := HexStr[1];
        TempBuffer[OutputLength - 1] := HexStr[2];
      end
      else
      begin
        // Normales Zeichen -> direkt übernehmen
        Inc(OutputLength);
        TempBuffer[OutputLength] := CurrentChar;
      end;
    end;
  end;

  // Gib nur den tatsächlich genutzten Teil des Puffers als Resultat zurück
  SetLength(Result, OutputLength);
  Move(TempBuffer[1], Result[1], OutputLength * SizeOf(Char));
end;



function HexDigitToInt(H: Char): Integer;
begin
  case H of
    '0'..'9': Result := Ord(H) - Ord('0');
    'A'..'F': Result := 10 + (Ord(H) - Ord('A'));
    'a'..'f': Result := 10 + (Ord(H) - Ord('a'));
  else
    Result := -1;
  end;
end;

function ParseHex4(const S: string; var P: Integer; out Code: Word): Boolean;
var
  i, v, n: Integer;
begin
  Result := False;
  n := 0;
  for i := 0 to 3 do
  begin
    if P > Length(S) then Exit;
    v := HexDigitToInt(S[P]);
    Inc(P);
    if v < 0 then Exit;
    n := (n shl 4) or v;
  end;
  Code := Word(n);
  Result := True;
end;

function AppendUnicodeEscapeToAnsi(const S: string; var P: Integer; var OutStr: string): Boolean;
var
  Code: Word;
  Ch: Char;
begin
  Result := False;
  if not ParseHex4(S, P, Code) then Exit;
  if Code <= 255 then
    Ch := Char(Code)
  else
    Ch := '?';
  OutStr := OutStr + Ch;
  Result := True;
end;

// ===== Parser (rekursiv Absteigend) =====

procedure SkipWhitespace(const S: string; var P: Integer);
begin
  while (P <= Length(S)) and (S[P] in [' ', #9, #13, #10]) do
    Inc(P);
end;

procedure ExpectChar(const S: string; var P: Integer; Ch: Char);
begin
  SkipWhitespace(S, P);
  if (P > Length(S)) or (S[P] <> Ch) then
    raise Exception.CreateFmt('Erwartetes Zeichen "%s" fehlt an Position %d', [Ch, P]);
  Inc(P);
end;

function ParseJSONString(const S: string; var P: Integer): string; forward;
function ParseValue     (const S: string; var P: Integer): TJSONValue; forward;
function ParseObject    (const S: string; var P: Integer): TJSONValue; forward;
function ParseArray     (const S: string; var P: Integer): TJSONValue; forward;

function ParseJSONString(const S: string; var P: Integer): string;
var
  C: Char;
begin
  Result := '';
  SkipWhitespace(S, P);
  if (P > Length(S)) or (S[P] <> '"') then
    raise Exception.CreateFmt('String erwartet an Position %d', [P]);
  Inc(P); // überspringe die öffnende "
  while P <= Length(S) do
  begin
    C := S[P];
    Inc(P);
    if C = '"' then
      Exit; // Ende String
    if C = '\' then
    begin
      if P > Length(S) then
        raise Exception.Create('Ungültiger Escape am Stringende');
      C := S[P];
      Inc(P);
      case C of
        '"':  Result := Result + '"';
        '\':  Result := Result + '\';
        '/':  Result := Result + '/';
        'b':  Result := Result + #8;
        'f':  Result := Result + #12;
        'n':  Result := Result + #10;
        'r':  Result := Result + #13;
        't':  Result := Result + #9;
        'u':  begin
                if not AppendUnicodeEscapeToAnsi(S, P, Result) then
                  raise Exception.CreateFmt('Ungültige \u-Sequenz an Position %d', [P]);
              end;
      else
        raise Exception.CreateFmt('Unbekannter Escape "\%s" an Position %d', [C, P-1]);
      end;
    end
    else
      Result := Result + C;
  end;
  raise Exception.Create('Unerwartetes Ende im Stringliteral');
end;

function ParseNumberString(const S: string; var P: Integer): string;
var
  Start: Integer;
begin
  SkipWhitespace(S, P);
  Start := P;

  if (P <= Length(S)) and (S[P] = '-') then Inc(P);
  if (P <= Length(S)) and (S[P] = '0') then
    Inc(P)
  else
  begin
    if (P > Length(S)) or not (S[P] in ['0'..'9']) then
      raise Exception.CreateFmt('Ziffer erwartet an Position %d', [P]);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;

  if (P <= Length(S)) and (S[P] = '.') then
  begin
    Inc(P);
    if (P > Length(S)) or not (S[P] in ['0'..'9']) then
      raise Exception.CreateFmt('Ziffer nach "." erwartet an Position %d', [P]);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;

  if (P <= Length(S)) and (S[P] in ['e', 'E']) then
  begin
    Inc(P);
    if (P <= Length(S)) and (S[P] in ['+', '-']) then Inc(P);
    if (P > Length(S)) or not (S[P] in ['0'..'9']) then
      raise Exception.CreateFmt('Ziffer im Exponent erwartet an Position %d', [P]);
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  end;

  Result := Copy(S, Start, P - Start);
end;

function ParseValue(const S: string; var P: Integer): TJSONValue;
var
  L: Integer;
  Lit: string;
  DT: TDateTime;
begin
  SkipWhitespace(S, P);
  if P > Length(S) then
    raise Exception.Create('Unerwartetes Ende der JSON-Daten');

  case S[P] of
    '{': Result := ParseObject(S, P);
    '[': Result := ParseArray(S, P);
    '"':
      begin
        Lit := ParseJSONString(S, P);
        // Nur als Datum interpretieren, wenn das Format eindeutig ist
        if (Length(Lit) >= 10) and (Pos('T', Lit) > 0) and TryISO8601ToDateTime(Lit, DT) then
          Result := TJSONValue.CreateDateTime(DT)
        else
          Result := TJSONValue.CreateString(Lit);
      end;
    't','f':
      begin
        if Copy(S, P, 4) = 'true' then
        begin
          Inc(P, 4);
          Result := TJSONValue.CreateBoolean(True);
        end
        else if Copy(S, P, 5) = 'false' then
        begin
          Inc(P, 5);
          Result := TJSONValue.CreateBoolean(False);
        end
        else
          raise Exception.CreateFmt('Ungültiges Literal an Position %d', [P]);
      end;
    'n':
      begin
        if Copy(S, P, 4) = 'null' then
        begin
          Inc(P, 4);
          Result := TJSONValue.CreateNull;
        end
        else
          raise Exception.CreateFmt('Ungültiges Literal an Position %d', [P]);
      end;
    '-', '0'..'9':
      begin
        Lit := ParseNumberString(S, P);
        Result := TJSONValue.CreateNumber(StrToJSONFloat(Lit));
      end;
  else
    L := P;
    raise Exception.CreateFmt('Ungültiges Zeichen "%s" an Position %d', [S[P], L]);
  end;
end;

function ParseObject(const S: string; var P: Integer): TJSONValue;
var
  Obj: TJSONObject;
  Key: string;
  Val: TJSONValue;
  First: Boolean;
begin
  ExpectChar(S, P, '{');
  Obj := TJSONObject.Create;
  try
    SkipWhitespace(S, P);
    First := True;
    if (P <= Length(S)) and (S[P] = '}') then
    begin
      Inc(P);
      Result := TJSONValue.CreateObject(Obj);
      Exit;
    end;

    while True do
    begin
      if not First then
      begin
        ExpectChar(S, P, ',');
      end;
      SkipWhitespace(S, P);
      Key := ParseJSONString(S, P);
      ExpectChar(S, P, ':');
      Val := ParseValue(S, P);
      Obj.Add(Key, Val);
      SkipWhitespace(S, P);
      if (P <= Length(S)) and (S[P] = '}') then
      begin
        Inc(P);
        Break;
      end;
      First := False;
    end;

    Result := TJSONValue.CreateObject(Obj);
  except
    Obj.Free;
    raise;
  end;
end;

function ParseArray(const S: string; var P: Integer): TJSONValue;
var
  Arr: TJSONArray;
  Val: TJSONValue;
  First: Boolean;
begin
  ExpectChar(S, P, '[');
  Arr := TJSONArray.Create;
  try
    SkipWhitespace(S, P);
    First := True;
    if (P <= Length(S)) and (S[P] = ']') then
    begin
      Inc(P);
      Result := TJSONValue.CreateArray(Arr);
      Exit;
    end;

    while True do
    begin
      if not First then
        ExpectChar(S, P, ',');
      Val := ParseValue(S, P);
      Arr.Add(Val);
      SkipWhitespace(S, P);
      if (P <= Length(S)) and (S[P] = ']') then
      begin
        Inc(P);
        Break;
      end;
      First := False;
    end;

    Result := TJSONValue.CreateArray(Arr);
  except
    Arr.Free;
    raise;
  end;
end;

// ===== Öffentliche Parser-API =====

function ParseJSON(const S: string): TJSONValue;
var
  P: Integer;
begin
  P := 1;
  Result := ParseValue(S, P);
  SkipWhitespace(S, P);
  if P <= Length(S) then
  begin
    Result.Free;
    raise Exception.CreateFmt('Unerwartete Zeichen ab Position %d', [P]);
  end;
end;

// ===== Implementierung TJSONValue =====

constructor TJSONValue.CreateDateTime(const DT: TDateTime);
begin
  inherited Create;
  ValueType   := jvtDateTime;
  ResetValues;
  AsDateTime  := DT;
  AsNumber    := DT;
  AsString    := DateTimeToStr(DT);
  AsBoolean   := DT > 0;
end;

constructor TJSONValue.CreateString(const S: string);
begin
  inherited Create;
  ValueType   := jvtString;
  ResetValues;
  AsString    := S;
  AsNumber    := StrToFloatDef(S,0);
  AsDateTime  := AsNumber;
  AsBoolean   := AsNumber > 0;
end;

constructor TJSONValue.CreateNumber(const N: Extended);
begin
  inherited Create;
  ValueType   := jvtNumber;
  ResetValues;
  AsNumber    := N;
  AsString    := FloatToStr(N);
  AsBoolean   := N > 0;
  AsDateTime  := N;
end;

constructor TJSONValue.CreateBoolean(const B: Boolean);
begin
  inherited Create;
  ValueType   := jvtBoolean;
  ResetValues;
  AsBoolean   := B;
  AsNumber    := Ord(B);
  if B then
    AsString := 'true'
  else
    AsString := 'false';
end;

constructor TJSONValue.CreateNull;
begin
  inherited Create;
  ValueType   := jvtNull;
  ResetValues;
  AsString    := 'null';
end;

constructor TJSONValue.CreateObject(Obj: TJSONObject);
begin
  inherited Create;
  ValueType := jvtObject;
  ResetValues;
  AsObject  := Obj;
  AsBoolean := Obj <> nil;
end;

constructor TJSONValue.CreateArray(Arr: TJSONArray);
begin
  inherited Create;
  ResetValues;
  ValueType := jvtArray;
  AsArray   := Arr;
  if (Arr <> nil) then
    AsBoolean := (Arr.Count > 0)
  else
    AsBoolean := False;
end;

procedure TJSONValue.ResetValues;
begin
  AsString   := '';
  AsNumber   := 0;
  AsBoolean  := False;
  AsDateTime := 0;
  AsObject   := nil;
  AsArray    := nil;
end;

destructor TJSONValue.Destroy;
begin
  case ValueType of
    jvtObject: AsObject.Free;
    jvtArray : AsArray.Free;
  end;
  inherited;
end;

function TJSONValue.ToString: string;
begin
  case ValueType of
    jvtString : Result := '"' + EscapeJSONString(AsString) + '"';
    jvtNumber : Result := FloatToJSON(AsNumber);
    jvtBoolean: if AsBoolean then Result := 'true' else Result := 'false';
    jvtNull   : Result := 'null';
    jvtObject : Result := AsObject.ToString;
    jvtArray  : Result := AsArray.ToString;
    jvtDateTime: Result := '"' + DateTimeToISO8601(AsDateTime) + '"'; // 
  else
    Result := 'null';
  end;
end;

// ===== Implementierung TJSONObject =====

constructor TJSONObject.Create;
begin
  inherited Create;
  FKeys := TStringList.Create;
  FKeys.Sorted := False;
  FKeys.Duplicates := dupIgnore;
end;

destructor TJSONObject.Destroy;
var
  i: Integer;
begin
  for i := 0 to FKeys.Count - 1 do
    TObject(FKeys.Objects[i]).Free;
  FKeys.Free;
  inherited;
end;

procedure TJSONObject.Clear;
var
  i: Integer;
begin
  for i := 0 to FKeys.Count - 1 do
    TObject(FKeys.Objects[i]).Free;
  FKeys.Clear;
end;

function TJSONObject.GetCount: Integer;
begin
  Result := FKeys.Count;
end;

function TJSONObject.GetKey(Index: Integer): string;
begin
  Result := FKeys[Index];
end;

function TJSONObject.GetValueByIndex(Index: Integer): TJSONValue;
begin
  Result := TJSONValue(FKeys.Objects[Index]);
end;

procedure TJSONObject.Add(const Key: string; Value: TJSONValue);
begin
  SetValue(Key, Value);
end;

function TJSONObject.Add(const Key: string; Value: string): TJSONObject;
begin
  Add(Key, TJSONValue.CreateString(Value));
  Result := Self;
end;

function TJSONObject.Add(const Key: string; Value: Extended): TJSONObject;
begin
  Add(Key, TJSONValue.CreateNumber(Value));
  Result := Self;
end;

function TJSONObject.Add(const Key: string; Value: Boolean): TJSONObject;
begin
  Add(Key, TJSONValue.CreateBoolean(Value));
  Result := Self;
end;

function TJSONObject.Add(const Key: string; Value: TJSONObject): TJSONObject;
begin
  Add(Key, TJSONValue.CreateObject(Value));
  Result := Self;
end;

function TJSONObject.Add(const Key: string; Value: TJSONArray): TJSONObject;
begin
  Add(Key, TJSONValue.CreateArray(Value));
  Result := Self;
end;

procedure TJSONObject.SetValue(const Key: string; Value: TJSONValue);
var
  idx: Integer;
begin
  idx := FKeys.IndexOf(Key);
  if idx >= 0 then
  begin
    TObject(FKeys.Objects[idx]).Free;
    FKeys.Objects[idx] := Value;
  end
  else
    FKeys.AddObject(Key, Value);
end;

function TJSONObject.GetValue(const Key: string): TJSONValue;
var
  idx: Integer;
begin
  idx := FKeys.IndexOf(Key);
  if idx >= 0 then
    Result := TJSONValue(FKeys.Objects[idx])
  else
    Result := nil;
end;

function TJSONObject.Contains(const Key: string): Boolean;
begin
  Result := FKeys.IndexOf(Key) >= 0;
end;

function TJSONObject.ToString: string;
var
  i: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('{');
    for i := 0 to FKeys.Count - 1 do
    begin
      SB.Append('"');
      SB.Append(EscapeJSONString(FKeys[i]));
      SB.Append('":');
      SB.Append(TJSONValue(FKeys.Objects[i]).ToString);
      if i < FKeys.Count - 1 then
        SB.Append(',');
    end;
    SB.Append('}');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;


class function TJSONObject.ParseJSON(const S: string): TJSONObject;
begin
  Result := uDangoJSON.ParseJSON(S).AsObject;
end;

class function TJSONObject.ParseJSON(const S: TStream): TJSONObject;
var
  JSONString: string;
begin
  JSONString := uDangoJSON.JSONStreamToString(S);
  Result := ParseJSON(JSONString);
end;

// ===== Implementierung TJSONArray =====

constructor TJSONArray.Create;
begin
  inherited Create;
  FItems := TList.Create;
end;

destructor TJSONArray.Destroy;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    TJSONValue(FItems[i]).Free;
  FItems.Free;
  inherited;
end;

procedure TJSONArray.Clear;
var
  i: Integer;
begin
  for i := 0 to FItems.Count - 1 do
    TJSONValue(FItems[i]).Free;
  FItems.Clear;
end;

procedure TJSONArray.Add(Value: TJSONValue);
begin
  FItems.Add(Value);
end;

function TJSONArray.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TJSONArray.GetItem(Index: Integer): TJSONValue;
begin
  Result := TJSONValue(FItems[Index]);
end;

function TJSONArray.ToString: string;
var
  i: Integer;
  SB: TStringBuilder;
begin
  SB := TStringBuilder.Create;
  try
    SB.Append('[');
    for i := 0 to FItems.Count - 1 do
    begin
      SB.Append(TJSONValue(FItems[i]).ToString);
      if i < FItems.Count - 1 then
        SB.Append(',');
    end;
    SB.Append(']');
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

// ===== Stream-Helfer =====

function JSONStreamToString(JSONStream: TStream): string;
var
  SS: TStringStream;
  S: string;
begin
  JSONStream.Position := 0;
  SS := TStringStream.Create('');
  try
    SS.CopyFrom(JSONStream, JSONStream.Size);
    S := SS.DataString;
    Result := S;
  finally
    SS.Free;
  end;
end;

end.