# uDangoJSON

Ein leichter, eigenständiger **JSON Parser und Generator** für Delphi/Object Pascal.  
Entwickelt primär für **ältere Delphi-Versionen**, die noch keine eingebaute `System.JSON`-Unit haben.  

---

## ✨ Features

- Unterstützte JSON-Datentypen:
  - String
  - Number (Extended)
  - Boolean
  - Null
  - Object (`TJSONObject`)
  - Array (`TJSONArray`)
  - DateTime (`TDateTime`, ISO8601)

- Vollständiger Parser (rekursiv absteigend)
- Eigene Implementierung für Escaping/Unescaping von JSON-Strings
- Konvertierung zwischen `TDateTime` und ISO8601
- Direkte `ToString`-Methoden für alle Typen → Ausgabe als gültiges JSON
- Kompatibel auch mit alten Delphi-Versionen (Delphi 7+)
- Benötigt akteull **Indy 10** (`IdGlobalProtocols`) für Datum/Zeit-Konvertierungen

---

## 📖 Klassenübersicht

### 🔹 TJSONValue
Repräsentiert einen einzelnen JSON-Wert (String, Number, Boolean, Null, Object, Array, DateTime).

**Wichtige Eigenschaften**
- `ValueType: TJSONValueType` → Datentyp des Werts
- `AsString: string`
- `AsNumber: Extended`
- `AsBoolean: Boolean`
- `AsObject: TJSONObject`
- `AsArray: TJSONArray`
- `AsDateTime: TDateTime`

**Methoden**
- `function ToString: string`  
  Serialisiert den Wert in gültiges JSON.

---

### 🔹 TJSONObject
Repräsentiert ein JSON-Objekt mit Key/Value-Paaren.

**Methoden**
- `function Add(Key: string; Value: string/Extended/Boolean/TJSONObject/TJSONArray): TJSONObject`  
  Wert hinzufügen (überladen für verschiedene Typen).  
  Rückgabewert = Self (Für Method Chaining).

- `function GetValue(Key: string): TJSONValue`  
  Zugriff auf den JSON-Wert eines Keys.

- `function GetValueOf(Key: string): string`  
  Direkter Zugriff auf den String-Wert.

- `function Contains(Key: string): Boolean`  
  Prüft, ob ein Key existiert.

- `function ToString: string`  
  Serialisiert das gesamte Objekt.

- `class function ParseJSON(const S: string): TJSONObject`  
  Parst einen JSON-String in ein `TJSONObject`.

- `class function ParseJSONFromStream(const Stream: TStream): TJSONObject`  
  Parst JSON direkt aus einem Stream.

---

### 🔹 TJSONArray
Repräsentiert ein JSON-Array.

**Eigenschaften**
- `Count: Integer` → Anzahl der Elemente
- `Items[Index: Integer]: TJSONValue` → Zugriff per Index

**Methoden**
- `procedure Add(Value: TJSONValue)`  
  Fügt ein Element hinzu.

- `function ToString: string`  
  Serialisiert das Array.

---

### 🔹 Parser-Helferfunktionen
- `function DateTimeToISO8601(const DT: TDateTime): string`  
  Wandelt Delphi `TDateTime` in ISO8601-String.

- `function TryISO8601ToDateTime(const S: string; out DT: TDateTime): Boolean`  
  Versucht, einen ISO8601-String in `TDateTime` zu wandeln.

- `function EscapeJSONString(const Input: string): string`  
  Escaped Sonderzeichen für gültiges JSON.

- `function UnescapeJSONString(const Input: string): string`  
  Wandelt escaped Strings zurück.

---

## 👨‍💻 Anwedung

### JSON parsen aus einem String

```pascal
var
  JSON: TJSONObject;
begin
  JSON := TJSONObject.ParseJSON('{"name":"Dango"}');
  try
    ShowMessage(JSON.GetValueOf('name'));   // "Dango"
  finally
    JSON.Free;
  end;
end;
```

### JSON parsen aus Stream (Indy PostStream als Beispiel)

```pascal
var
  JSON: TJSONObject;
begin
  ARequestInfo.PostStream.Position := 0;
  JSON := TJSONObject.ParseJSON(ARequestInfo.PostStream);
  try
    if JSON.Contains('user') then
      ShowMessage('User: ' + JSON.GetValueOf('user'));
  finally
    JSON.Free;
  end;
end;
```

### JSON erstellen (Method Chaining)

```pascal
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.Add('user', 'Dango')
       .Add('age', 42)
       .Add('isProgrammer', True);

    ShowMessage(Obj.ToString);
    // {"user":"Dango","age":42,"isProgrammer":true}
  finally
    Obj.Free;
  end;
end;
```

### Arrays verwenden

```pascal
var
  Arr: TJSONArray;
  Root: TJSONObject;
begin
  Arr := TJSONArray.Create;
  Arr.Add(TJSONValue.CreateString('Apfel'));
  Arr.Add(TJSONValue.CreateString('Birne'));
  Arr.Add(TJSONValue.CreateNumber(123));

  Root := TJSONObject.Create;
  Root.Add('fruits', Arr);

  ShowMessage(Root.ToString);
  // {"fruits":["Apfel","Birne",123]}
end;
```

### Verschachtelte Objekte

```pascal
var
  Address, User: TJSONObject;
begin
  Address := TJSONObject.Create;
  Address.Add('street', 'Musterstraße 1')
         .Add('city', 'Bremen');

  User := TJSONObject.Create;
  User.Add('name', 'Dango')
      .Add('address', Address);

  ShowMessage(User.ToString);
  // {"name":"Dango","address":{"street":"Musterstraße 1","city":"Bremen"}}
end;
```
 
---

## 🛠️ Geplante Features

Die `uDangoJSON`-Unit ist funktional, aber es gibt noch Ideen für zukünftige Erweiterungen:

- **Weitere Datentypen**  
  Unterstützung für `Int64`, `Currency` und `Base64-kodierte Binärdaten`.

- **Unabhängigkeit von Indy**  
  `GMTToLocalDateTime` durch eigene Implementierung ersetzen, um die Unit komplett ohne externe Abhängigkeiten nutzbar zu machen.

- **Pretty Print / Formatierung**  
  Möglichkeit, JSON-Ausgabe mit Einrückungen und Zeilenumbrüchen zu erzeugen, um sie besser lesbar zu machen.

- **Erweiterte Fehlerdiagnose beim Parsen**  
  Detailliertere Fehlermeldungen mit Zeilen- und Spaltenangabe.

---

## ⚠️ Lizenz

Dieses Projekt hat keine offene Lizenz.
Für jede Verwendung oder Weitergabe bitte vorher anfragen.
