# ☁️ Granulares Wettercode-System v2.0

{toc:printable=true|style=disc|maxLevel=3|minLevel=1|type=list|outline=false|include=.*}

---

## 1. Übersicht

Dieses Dokument beschreibt ein granulares, herstellerübergreifendes Wettercode-System, das verschiedene Wetterdienste und Smart-Home-Systeme auf eine einheitliche Code-Basis abbildet.

| Eigenschaft | Wert |
|---|---|
| **Version** | 2.0.0 |
| **Führendes System** | WetterOnline |
| **Gemappte Systeme** | OpenWeatherMap (OWM), Loxone Wetter (Picto-Codes) |
| **Anzahl Wettercodes** | 45 |
| **Anzahl unique Symbole (Basis)** | 62 |
| **Optionale overcast Tag/Nacht-Varianten** | +52 (je 26 × `_sun` und `_moon`) |
| **Optionale Mondphasen-Varianten (max. 5 Phasen)** | +90 (18 Nachtsymbole × 5 Phasen) |

---

## 2. Systemaufbau

### 2.1 Code-Schema

Der Wettercode ist eine zusammengesetzte, eindeutige ID nach folgendem Schema:

{code:title=Wettercode-Schema|language=none}
<bewölkungsgrad>[_<niederschlagsart>][_<intensität>]
{code}

**Beispiele:**

| Wettercode | Bedeutung |
|---|---|
| `clear_day` | Sonnig (Tag) |
| `overcast` | Bedeckt, ohne Niederschlag |
| `cloudy_rain_1` | Bewölkt, leichter Regen |
| `overcast_thunderstorm_3` | Bedeckt, schweres Gewitter |

### 2.2 Bewölkungsgrade

| Code | Bedeutung | Bedeckungsgrad | Tag/Nacht-Varianten |
|---|---|---|---|
| `clear` | Wolkenlos | 0–5 % | ✅ `_sun` / `_moon` |
| `fair` | Leicht bewölkt | 5–30 % | ✅ `_sun` / `_moon` |
| `cloudy` | Bewölkt | 30–70 % | ✅ `_sun` / `_moon` |
| `overcast` | Bedeckt | 70–100 % | ⚪ `_sun` / `_moon` _(optional)_ |

### 2.3 Niederschlagsarten

| Code | Bedeutung | Kombination mit `cloudy` | Kombination mit `overcast` |
|---|---|---|---|
| `shower` | Schauer (kurz) | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `rain` | Regen (anhaltend) | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `sleet` | Schneeregen | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `snow` | Schnee | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `freezingrain` | Gefrierender Regen | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `thunderstorm` | Gewitter | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `snowthunderstorm` | Schneegewitter | ✅ Intensität 1–2 | ✅ Intensität 1–3 |
| `fog` | Nebel | ✅ (ohne Intensität) | ✅ (ohne Intensität) |
| `hail` | Hagel | ❌ | ✅ Intensität 1–3 |

### 2.4 Intensitätsstufen

| Stufe | Bedeutung | Verfügbar bei `cloudy` | Verfügbar bei `overcast` |
|---|---|---|---|
| 1 | leicht | ✅ | ✅ |
| 2 | mittel | ✅ | ✅ |
| 3 | ergiebig / stark | ❌ | ✅ |

### 2.5 Kontexte

| Kontext | Kürzel | Beschreibung | Bewölkung + Niederschlag |
|---|---|---|---|
| Aktuelles Wetter | `current` | Echtzeit-Beobachtung | Nur `overcast` + Niederschlag (WO Tabelle 3) |
| Stündliche Vorhersage | `forecast_hourly` | Prognose pro Stunde | `cloudy` + `overcast` + Niederschlag |
| Tägliche Vorhersage | `forecast_daily` | Tagesprognose | `cloudy` + `overcast` + Niederschlag |

{info:title=Hinweis}
Für aktuelles Wetter (`current`) werden Niederschlagssymbole immer ohne Sonne/Mond dargestellt (WetterOnline Tabelle 3). Die Kombination `cloudy` + Niederschlag existiert nur in Vorhersagen.
{info}

---

## 3. Symbol-Konventionen

### 3.1 Tag/Nacht-Suffixe

| Bewölkungsgrad | Tagsymbol | Nachtsymbol | Beispiel Tag | Beispiel Nacht |
|---|---|---|---|---|
| `clear` | `_sun` | `_moon` | `clear_sun` | `clear_moon` |
| `fair` | `_sun` | `_moon` | `fair_sun` | `fair_moon` |
| `cloudy` | `_sun` | `_moon` | `cloudy_rain_1_sun` | `cloudy_rain_1_moon` |
| `overcast` | `_sun` _(optional)_ | `_moon` _(optional)_ | `overcast_rain_1` oder `overcast_rain_1_sun` | `overcast_rain_1` oder `overcast_rain_1_moon` |

> **Hinweis:** Das Tag-/Nacht-Suffix bei `overcast` ist optional, da Sonne / Mond im Symbol nicht sichtbar ist. Es kann aber z.B. unterschiedlich hell sein.

### 3.2 Eindeutigkeit

Jeder Symbolname ist systemweit eindeutig. Es soll kein identisches Symbol unter verschiedenen Namen geführt werden. In jedem Set mit Wettersymbolen muss es ein Mapping der Wettercodes auf die vorhandenen Symbole geben.

---

## 4. WetterOnline Symboltabellen

WetterOnline verwendet drei Symboltabellen, die wie folgt auf das Wettercode-System abgebildet werden:

### 4.1 Tabelle 1 – Tagsymbole (mit Sonne)

_Verwendung: Vorhersagen tagsüber (`forecast_hourly`, `forecast_daily`)_

> Die Symbole mit Sonne gibt es für die Bewölkungsgrade `clear`, `fair` und `cloudy`, da im Symbol entweder eine Sonne oder ein Mond hinter Wolken zu sehen ist. Es gibt bis zu 2 Intensitäten.

| Nr | WetterOnline Beschreibung | Wettercode | Symbolname |
|---|---|---|---|
| 1 | sonnig | `clear_day` | `clear_sun` |
| 2 | heiter | `fair` | `fair_sun` |
| 3 | wolkig | `cloudy` | `cloudy_sun` |
| 4 | wolkig, leichte Schauer | `cloudy_shower_1` | `cloudy_shower_1_sun` |
| 5 | wolkig, Schauer | `cloudy_shower_2` | `cloudy_shower_2_sun` |
| 6 | wolkig, leichter Regen | `cloudy_rain_1` | `cloudy_rain_1_sun` |
| 7 | wolkig, Regen | `cloudy_rain_2` | `cloudy_rain_2_sun` |
| 8 | wolkig, leichter Schneeregen | `cloudy_sleet_1` | `cloudy_sleet_1_sun` |
| 9 | wolkig, Schneeregen | `cloudy_sleet_2` | `cloudy_sleet_2_sun` |
| 10 | wolkig, leichter Schneefall | `cloudy_snow_1` | `cloudy_snow_1_sun` |
| 11 | wolkig, Schneefall | `cloudy_snow_2` | `cloudy_snow_2_sun` |
| 12 | wolkig, leichter gefr. Regen | `cloudy_freezingrain_1` | `cloudy_freezingrain_1_sun` |
| 13 | wolkig, gefrierender Regen | `cloudy_freezingrain_2` | `cloudy_freezingrain_2_sun` |
| 14 | wolkig, leichtes Gewitter | `cloudy_thunderstorm_1` | `cloudy_thunderstorm_1_sun` |
| 15 | wolkig, Gewitter | `cloudy_thunderstorm_2` | `cloudy_thunderstorm_2_sun` |
| 16 | wolkig, leichtes Schneegewitter | `cloudy_snowthunderstorm_1` | `cloudy_snowthunderstorm_1_sun` |
| 17 | wolkig, Schneegewitter | `cloudy_snowthunderstorm_2` | `cloudy_snowthunderstorm_2_sun` |
| 18 | Nebel, teils sonnig | `cloudy_fog` | `cloudy_fog_sun` |

### 4.2 Tabelle 2 – Nachtsymbole (mit Mond)

_Verwendung: Vorhersagen nachts (`forecast_hourly`, `forecast_daily`)_

> Die Symbole mit Mond gibt es für die Bewölkungsgrade `clear`, `fair` und `cloudy`, da im Symbol entweder eine Sonne oder ein Mond hinter Wolken zu sehen ist. Es gibt bis zu 2 Intensitäten.

| Nr | WetterOnline Beschreibung | Wettercode | Symbolname |
|---|---|---|---|
| 1 | klar | `clear_night` | `clear_moon` |
| 2 | heiter | `fair` | `fair_moon` |
| 3 | wolkig | `cloudy` | `cloudy_moon` |
| 4 | wolkig, leichte Schauer | `cloudy_shower_1` | `cloudy_shower_1_moon` |
| 5 | wolkig, Schauer | `cloudy_shower_2` | `cloudy_shower_2_moon` |
| 6 | wolkig, leichter Regen | `cloudy_rain_1` | `cloudy_rain_1_moon` |
| 7 | wolkig, Regen | `cloudy_rain_2` | `cloudy_rain_2_moon` |
| 8 | wolkig, leichter Schneeregen | `cloudy_sleet_1` | `cloudy_sleet_1_moon` |
| 9 | wolkig, Schneeregen | `cloudy_sleet_2` | `cloudy_sleet_2_moon` |
| 10 | wolkig, leichter Schneefall | `cloudy_snow_1` | `cloudy_snow_1_moon` |
| 11 | wolkig, Schneefall | `cloudy_snow_2` | `cloudy_snow_2_moon` |
| 12 | wolkig, leichter gefr. Regen | `cloudy_freezingrain_1` | `cloudy_freezingrain_1_moon` |
| 13 | wolkig, gefrierender Regen | `cloudy_freezingrain_2` | `cloudy_freezingrain_2_moon` |
| 14 | wolkig, leichtes Gewitter | `cloudy_thunderstorm_1` | `cloudy_thunderstorm_1_moon` |
| 15 | wolkig, Gewitter | `cloudy_thunderstorm_2` | `cloudy_thunderstorm_2_moon` |
| 16 | wolkig, leichtes Schneegewitter | `cloudy_snowthunderstorm_1` | `cloudy_snowthunderstorm_1_moon` |
| 17 | wolkig, Schneegewitter | `cloudy_snowthunderstorm_2` | `cloudy_snowthunderstorm_2_moon` |
| 18 | Nebel, teils aufgelockert | `cloudy_fog` | `cloudy_fog_moon` |

### 4.3 Tabelle 3 – Symbole bei bedecktem Himmel (Overcast)

_Verwendung: Aktuelles Wetter (`current`) und Vorhersagen (`forecast_hourly`, `forecast_daily`)_

> Der Bewölkungsgrad 'overcast' zeigt keine Sonne / Mond an. Es gibt drei Intensitäten 1, 2 und 3. Die Symbole können für Tag und Nacht unterschiedlich sein, um z.B. eine unterschiedliche Helligkeit oder Tag / Nacht Szene darzustellen.

| Nr | WetterOnline Beschreibung | Wettercode | Symbolname (Basis) | Optionale Varianten (Tag / Nacht) | Intensität |
|---|---|---|---|---|---|
| 1 | bedeckt | `overcast` | `overcast` | `overcast_sun` / `overcast_moon` | – |
| 2 | leichte Schauer | `overcast_shower_1` | `overcast_shower_1` | `overcast_shower_1_sun` / `overcast_shower_1_moon` | 1 |
| 3 | Schauer | `overcast_shower_2` | `overcast_shower_2` | `overcast_shower_2_sun` / `overcast_shower_2_moon` | 2 |
| 4 | starke Schauer | `overcast_shower_3` | `overcast_shower_3` | `overcast_shower_3_sun` / `overcast_shower_3_moon` | 3 |
| 5 | leichter Regen | `overcast_rain_1` | `overcast_rain_1` | `overcast_rain_1_sun` / `overcast_rain_1_moon` | 1 |
| 6 | Regen | `overcast_rain_2` | `overcast_rain_2` | `overcast_rain_2_sun` / `overcast_rain_2_moon` | 2 |
| 7 | Starkregen | `overcast_rain_3` | `overcast_rain_3` | `overcast_rain_3_sun` / `overcast_rain_3_moon` | 3 |
| 8 | leichter Schneeregen | `overcast_sleet_1` | `overcast_sleet_1` | `overcast_sleet_1_sun` / `overcast_sleet_1_moon` | 1 |
| 9 | Schneeregen | `overcast_sleet_2` | `overcast_sleet_2` | `overcast_sleet_2_sun` / `overcast_sleet_2_moon` | 2 |
| 10 | starker Schneeregen | `overcast_sleet_3` | `overcast_sleet_3` | `overcast_sleet_3_sun` / `overcast_sleet_3_moon` | 3 |
| 11 | leichter Schneefall | `overcast_snow_1` | `overcast_snow_1` | `overcast_snow_1_sun` / `overcast_snow_1_moon` | 1 |
| 12 | Schneefall | `overcast_snow_2` | `overcast_snow_2` | `overcast_snow_2_sun` / `overcast_snow_2_moon` | 2 |
| 13 | starker Schneefall | `overcast_snow_3` | `overcast_snow_3` | `overcast_snow_3_sun` / `overcast_snow_3_moon` | 3 |
| 14 | leichter gefrierender Regen | `overcast_freezingrain_1` | `overcast_freezingrain_1` | `overcast_freezingrain_1_sun` / `overcast_freezingrain_1_moon` | 1 |
| 15 | gefrierender Regen | `overcast_freezingrain_2` | `overcast_freezingrain_2` | `overcast_freezingrain_2_sun` / `overcast_freezingrain_2_moon` | 2 |
| 16 | starker gefrierender Regen | `overcast_freezingrain_3` | `overcast_freezingrain_3` | `overcast_freezingrain_3_sun` / `overcast_freezingrain_3_moon` | 3 |
| 17 | leichtes Gewitter | `overcast_thunderstorm_1` | `overcast_thunderstorm_1` | `overcast_thunderstorm_1_sun` / `overcast_thunderstorm_1_moon` | 1 |
| 18 | Gewitter | `overcast_thunderstorm_2` | `overcast_thunderstorm_2` | `overcast_thunderstorm_2_sun` / `overcast_thunderstorm_2_moon` | 2 |
| 19 | schweres Gewitter | `overcast_thunderstorm_3` | `overcast_thunderstorm_3` | `overcast_thunderstorm_3_sun` / `overcast_thunderstorm_3_moon` | 3 |
| 20 | leichtes Schneegewitter | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1_sun` / `overcast_snowthunderstorm_1_moon` | 1 |
| 21 | Schneegewitter | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2_sun` / `overcast_snowthunderstorm_2_moon` | 2 |
| 22 | schweres Schneegewitter | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3_sun` / `overcast_snowthunderstorm_3_moon` | 3 |
| 23 | Nebel | `overcast_fog` | `overcast_fog` | `overcast_fog_sun` / `overcast_fog_moon` | – |
| 24 | leichter Hagel | `overcast_hail_1` | `overcast_hail_1` | `overcast_hail_1_sun` / `overcast_hail_1_moon` | 1 |
| 25 | Hagel | `overcast_hail_2` | `overcast_hail_2` | `overcast_hail_2_sun` / `overcast_hail_2_moon` | 2 |
| 26 | schwerer Hagel | `overcast_hail_3` | `overcast_hail_3` | `overcast_hail_3_sun` / `overcast_hail_3_moon` | 3 |

### 4.4 Mondphasen (Moon Phases)

_Verwendung: Nachtsymbole für Bewölkungsgrade `clear`, `fair` und `cloudy`_

> Mondphasen erlauben die Darstellung der aktuellen Mondphase im Nachtsymbol. Das Mondphasen-Suffix wird **nach** dem `_moon`-Suffix angehängt, z.B. `clear_moon_2q` oder `cloudy_rain_1_moon_4q`.

| Kürzel | Bedeutung |
|---|---|
| `0q` | Neumond |
| `1q` | Einviertel Mond (Erstes Viertel) |
| `2q` | Halbmond |
| `3q` | Dreiviertel Mond (Letztes Viertel) |
| `4q` | Vollmond |

**Regeln:**
- Mondphasen existieren **nur** für Bewölkungsgrade `clear`, `fair` und `cloudy` – **nicht** für `overcast`.
- Mondphasen gelten **nur** für Nachtsymbole (Suffix `_moon`).
- Das Mondphasen-Suffix wird nach `_moon` angehängt: z.B. `clear_moon_0q`, `fair_moon_2q`, `cloudy_rain_1_moon_4q`.
- Ein Symbol-Set MUSS eine der folgenden Varianten verwenden:
  - **5 Mondphasen**: `0q`, `1q`, `2q`, `3q`, `4q` (Neumond, Erstes Viertel, Halbmond, Letztes Viertel, Vollmond)
  - **3 Mondphasen**: `0q`, `2q`, `4q` (Neumond, Halbmond, Vollmond)
  - **1 Mondphase**: `1q`, `2q` oder `4q` (eine repräsentative Phase)
- Wenn ein Symbol-Set Mondphasen verwendet, dient das Basissymbol `_moon` (ohne Phasensuffix) als Fallback.

**Beispiele:**

| Symbolname | Bedeutung |
|---|---|
| `clear_moon_0q` | Klar, Neumond |
| `clear_moon_2q` | Klar, Halbmond |
| `clear_moon_4q` | Klar, Vollmond |
| `fair_moon_0q` | Heiter, Neumond |
| `cloudy_rain_1_moon_2q` | Bewölkt, leichter Regen, Halbmond |
| `cloudy_thunderstorm_2_moon_4q` | Bewölkt, Gewitter, Vollmond |

---

## 5. Vollständige Wettercode-Referenz

### 5.1 Reine Bewölkung (ohne Niederschlag)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 1 | `clear_day` | Sonnig | `clear_sun` | – | current, forecast | sonnig | 800 | 01d | 1 |
| 2 | `clear_night` | Klar | – | `clear_moon` | current, forecast | klar | 800 | 01n | 1 |
| 3 | `fair` | Leicht bewölkt | `fair_sun` | `fair_moon` | current, forecast | heiter | 801 | 02d, 02n | 2 |
| 4 | `cloudy` | Bewölkt | `cloudy_sun` | `cloudy_moon` | current, forecast | wolkig | 802, 803 | 03d, 03n, 04d, 04n | 3, 4 |
| 5 | `overcast` | Bedeckt | `overcast` | `overcast` | current, forecast | bedeckt | 804 | 04d, 04n | 5 |

### 5.2 Schauer (shower)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 6 | `cloudy_shower_1` | Bewölkt, leichte Schauer | `cloudy_shower_1_sun` | `cloudy_shower_1_moon` | forecast | leichte Regenschauer | 520 | 09d, 09n | 14 |
| 7 | `cloudy_shower_2` | Bewölkt, mäßige Schauer | `cloudy_shower_2_sun` | `cloudy_shower_2_moon` | forecast | Regenschauer | 521 | 09d, 09n | 14 |
| 8 | `overcast_shower_1` | Bedeckt, leichte Schauer | `overcast_shower_1` | `overcast_shower_1` | current, forecast | leichte Schauer | 520 | 09d, 09n | 14 |
| 9 | `overcast_shower_2` | Bedeckt, mäßige Schauer | `overcast_shower_2` | `overcast_shower_2` | current, forecast | Schauer | 521 | 09d, 09n | 14 |
| 10 | `overcast_shower_3` | Bedeckt, ergiebige Schauer | `overcast_shower_3` | `overcast_shower_3` | current, forecast | starke Schauer | 522, 531 | 09d, 09n | 15 |

### 5.3 Regen (rain)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 11 | `cloudy_rain_1` | Bewölkt, leichter Regen | `cloudy_rain_1_sun` | `cloudy_rain_1_moon` | forecast | leichter Regen | 500, 300, 310 | 10d, 10n | 14 |
| 12 | `cloudy_rain_2` | Bewölkt, mäßiger Regen | `cloudy_rain_2_sun` | `cloudy_rain_2_moon` | forecast | Regen | 501, 301, 311 | 10d, 10n | 14 |
| 13 | `overcast_rain_1` | Bedeckt, leichter Regen | `overcast_rain_1` | `overcast_rain_1` | current, forecast | leichter Regen | 500, 300, 310 | 10d, 10n | 14 |
| 14 | `overcast_rain_2` | Bedeckt, mäßiger Regen | `overcast_rain_2` | `overcast_rain_2` | current, forecast | Regen | 501, 301, 311 | 10d, 10n | 14 |
| 15 | `overcast_rain_3` | Bedeckt, ergiebiger Regen | `overcast_rain_3` | `overcast_rain_3` | current, forecast | Starkregen | 502, 503, 504, 302, 312, 314, 321 | 10d, 10n | 15 |

### 5.4 Schneeregen (sleet)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 16 | `cloudy_sleet_1` | Bewölkt, leichter Schneeregen | `cloudy_sleet_1_sun` | `cloudy_sleet_1_moon` | forecast | leichter Schneeregen | 611, 615 | 13d, 13n | 20 |
| 17 | `cloudy_sleet_2` | Bewölkt, mäßiger Schneeregen | `cloudy_sleet_2_sun` | `cloudy_sleet_2_moon` | forecast | Schneeregen | 612, 616 | 13d, 13n | 20 |
| 18 | `overcast_sleet_1` | Bedeckt, leichter Schneeregen | `overcast_sleet_1` | `overcast_sleet_1` | current, forecast | leichter Schneeregen | 611, 615 | 13d, 13n | 20 |
| 19 | `overcast_sleet_2` | Bedeckt, mäßiger Schneeregen | `overcast_sleet_2` | `overcast_sleet_2` | current, forecast | Schneeregen | 612, 616 | 13d, 13n | 20 |
| 20 | `overcast_sleet_3` | Bedeckt, ergiebiger Schneeregen | `overcast_sleet_3` | `overcast_sleet_3` | current, forecast | starker Schneeregen | 613 | 13d, 13n | 21 |

### 5.5 Schnee (snow)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 21 | `cloudy_snow_1` | Bewölkt, leichter Schneefall | `cloudy_snow_1_sun` | `cloudy_snow_1_moon` | forecast | leichter Schneefall | 600, 620 | 13d, 13n | 22 |
| 22 | `cloudy_snow_2` | Bewölkt, mäßiger Schneefall | `cloudy_snow_2_sun` | `cloudy_snow_2_moon` | forecast | Schneefall | 601, 621 | 13d, 13n | 22 |
| 23 | `overcast_snow_1` | Bedeckt, leichter Schneefall | `overcast_snow_1` | `overcast_snow_1` | current, forecast | leichter Schneefall | 600, 620 | 13d, 13n | 22 |
| 24 | `overcast_snow_2` | Bedeckt, mäßiger Schneefall | `overcast_snow_2` | `overcast_snow_2` | current, forecast | Schneefall | 601, 621 | 13d, 13n | 22 |
| 25 | `overcast_snow_3` | Bedeckt, ergiebiger Schneefall | `overcast_snow_3` | `overcast_snow_3` | current, forecast | starker Schneefall | 602, 622 | 13d, 13n | 23 |

### 5.6 Gefrierender Regen (freezingrain)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 26 | `cloudy_freezingrain_1` | Bewölkt, leichter gefr. Regen | `cloudy_freezingrain_1_sun` | `cloudy_freezingrain_1_moon` | forecast | leichter gefr. Regen | 511 | 13d, 13n | 19 |
| 27 | `cloudy_freezingrain_2` | Bewölkt, mäßiger gefr. Regen | `cloudy_freezingrain_2_sun` | `cloudy_freezingrain_2_moon` | forecast | gefrierender Regen | 511 | 13d, 13n | 19 |
| 28 | `overcast_freezingrain_1` | Bedeckt, leichter gefr. Regen | `overcast_freezingrain_1` | `overcast_freezingrain_1` | current, forecast | leichter gefr. Regen | 511 | 13d, 13n | 19 |
| 29 | `overcast_freezingrain_2` | Bedeckt, mäßiger gefr. Regen | `overcast_freezingrain_2` | `overcast_freezingrain_2` | current, forecast | gefrierender Regen | 511 | 13d, 13n | 19 |
| 30 | `overcast_freezingrain_3` | Bedeckt, ergiebiger gefr. Regen | `overcast_freezingrain_3` | `overcast_freezingrain_3` | current, forecast | starker gefr. Regen | 511 | 13d, 13n | 19 |

### 5.7 Gewitter (thunderstorm)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 31 | `cloudy_thunderstorm_1` | Bewölkt, leichtes Gewitter | `cloudy_thunderstorm_1_sun` | `cloudy_thunderstorm_1_moon` | forecast | leichtes Gewitter | 200, 210, 230 | 11d, 11n | 24 |
| 32 | `cloudy_thunderstorm_2` | Bewölkt, mäßiges Gewitter | `cloudy_thunderstorm_2_sun` | `cloudy_thunderstorm_2_moon` | forecast | Gewitter | 201, 211, 231 | 11d, 11n | 24 |
| 33 | `overcast_thunderstorm_1` | Bedeckt, leichtes Gewitter | `overcast_thunderstorm_1` | `overcast_thunderstorm_1` | current, forecast | leichtes Gewitter | 200, 210, 230 | 11d, 11n | 24 |
| 34 | `overcast_thunderstorm_2` | Bedeckt, mäßiges Gewitter | `overcast_thunderstorm_2` | `overcast_thunderstorm_2` | current, forecast | Gewitter | 201, 211, 231 | 11d, 11n | 24 |
| 35 | `overcast_thunderstorm_3` | Bedeckt, schweres Gewitter | `overcast_thunderstorm_3` | `overcast_thunderstorm_3` | current, forecast | schweres Gewitter | 202, 212, 221, 232 | 11d, 11n | 25 |

### 5.8 Schneegewitter (snowthunderstorm)

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 36 | `cloudy_snowthunderstorm_1` | Bewölkt, leichtes Schneegewitter | `cloudy_snowthunderstorm_1_sun` | `cloudy_snowthunderstorm_1_moon` | forecast | leichtes Schneegewitter | 200 (+Schnee) | 11d, 11n | 25 |
| 37 | `cloudy_snowthunderstorm_2` | Bewölkt, mäßiges Schneegewitter | `cloudy_snowthunderstorm_2_sun` | `cloudy_snowthunderstorm_2_moon` | forecast | Schneegewitter | 201 (+Schnee) | 11d, 11n | 25 |
| 38 | `overcast_snowthunderstorm_1` | Bedeckt, leichtes Schneegewitter | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1` | current, forecast | leichtes Schneegewitter | 200 (+Schnee) | 11d, 11n | 25 |
| 39 | `overcast_snowthunderstorm_2` | Bedeckt, mäßiges Schneegewitter | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2` | current, forecast | Schneegewitter | 201 (+Schnee) | 11d, 11n | 25 |
| 40 | `overcast_snowthunderstorm_3` | Bedeckt, schweres Schneegewitter | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3` | current, forecast | schweres Schneegewitter | 202 (+Schnee) | 11d, 11n | 25 |

### 5.9 Nebel (fog) – Sonderfall ohne Intensität

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 41 | `cloudy_fog` | Neblig, teils aufgelockert | `cloudy_fog_sun` | `cloudy_fog_moon` | current, forecast | Nebel, teils sonnig | 701, 721 | 50d, 50n | 6 |
| 42 | `overcast_fog` | Nebel | `overcast_fog` | `overcast_fog` | current, forecast | Nebel | 741 | 50d, 50n | 6 |

### 5.10 Hagel (hail) – nur overcast

|| Nr || Wettercode || Erläuterung || Symbol Tag || Symbol Nacht || Kontext || WetterOnline || OWM IDs || OWM Icons || Loxone Picto ||
| 43 | `overcast_hail_1` | Bedeckt, leichter Hagel | `overcast_hail_1` | `overcast_hail_1` | current, forecast | leichter Hagel | – | – | 16 |
| 44 | `overcast_hail_2` | Bedeckt, mäßiger Hagel | `overcast_hail_2` | `overcast_hail_2` | current, forecast | Hagel | – | – | 16 |
| 45 | `overcast_hail_3` | Bedeckt, schwerer Hagel | `overcast_hail_3` | `overcast_hail_3` | current, forecast | schwerer Hagel | – | – | 17 |

---

## 6. Kontext-Matrix

### 6.1 Aktuelles Wetter (current) – 31 Codes

|| Kategorie || Verfügbare Codes || Intensitäten ||
| Reine Bewölkung | `clear_day`, `clear_night`, `fair`, `cloudy`, `overcast` | – |
| Schauer | `overcast_shower_1`, `overcast_shower_2`, `overcast_shower_3` | 1, 2, 3 |
| Regen | `overcast_rain_1`, `overcast_rain_2`, `overcast_rain_3` | 1, 2, 3 |
| Schneeregen | `overcast_sleet_1`, `overcast_sleet_2`, `overcast_sleet_3` | 1, 2, 3 |
| Schnee | `overcast_snow_1`, `overcast_snow_2`, `overcast_snow_3` | 1, 2, 3 |
| Gefr. Regen | `overcast_freezingrain_1`, `overcast_freezingrain_2`, `overcast_freezingrain_3` | 1, 2, 3 |
| Gewitter | `overcast_thunderstorm_1`, `overcast_thunderstorm_2`, `overcast_thunderstorm_3` | 1, 2, 3 |
| Schneegewitter | `overcast_snowthunderstorm_1`, `overcast_snowthunderstorm_2`, `overcast_snowthunderstorm_3` | 1, 2, 3 |
| Nebel | `cloudy_fog`, `overcast_fog` | – |
| Hagel | `overcast_hail_1`, `overcast_hail_2`, `overcast_hail_3` | 1, 2, 3 |

### 6.2 Vorhersage (forecast) – 45 Codes

Alle 31 Codes aus `current` plus 14 zusätzliche `cloudy`-Niederschlagskombinationen:

|| Kategorie || Zusätzliche Codes (nur forecast) || Intensitäten ||
| Schauer | `cloudy_shower_1`, `cloudy_shower_2` | 1, 2 |
| Regen | `cloudy_rain_1`, `cloudy_rain_2` | 1, 2 |
| Schneeregen | `cloudy_sleet_1`, `cloudy_sleet_2` | 1, 2 |
| Schnee | `cloudy_snow_1`, `cloudy_snow_2` | 1, 2 |
| Gefr. Regen | `cloudy_freezingrain_1`, `cloudy_freezingrain_2` | 1, 2 |
| Gewitter | `cloudy_thunderstorm_1`, `cloudy_thunderstorm_2` | 1, 2 |
| Schneegewitter | `cloudy_snowthunderstorm_1`, `cloudy_snowthunderstorm_2` | 1, 2 |

---

## 7. OpenWeatherMap Mapping (Reverse)

Die folgende Tabelle zeigt, wie OWM-Condition-IDs auf Wettercodes abgebildet werden:

### 7.1 Thunderstorm (2xx)

|| OWM ID || OWM Beschreibung || Wettercode (overcast) || Wettercode (cloudy) ||
| 200 | thunderstorm with light rain | `overcast_thunderstorm_1` | `cloudy_thunderstorm_1` |
| 201 | thunderstorm with rain | `overcast_thunderstorm_2` | `cloudy_thunderstorm_2` |
| 202 | thunderstorm with heavy rain | `overcast_thunderstorm_3` | – |
| 210 | light thunderstorm | `overcast_thunderstorm_1` | `cloudy_thunderstorm_1` |
| 211 | thunderstorm | `overcast_thunderstorm_2` | `cloudy_thunderstorm_2` |
| 212 | heavy thunderstorm | `overcast_thunderstorm_3` | – |
| 221 | ragged thunderstorm | `overcast_thunderstorm_3` | – |
| 230 | thunderstorm with light drizzle | `overcast_thunderstorm_1` | `cloudy_thunderstorm_1` |
| 231 | thunderstorm with drizzle | `overcast_thunderstorm_2` | `cloudy_thunderstorm_2` |
| 232 | thunderstorm with heavy drizzle | `overcast_thunderstorm_3` | – |

### 7.2 Drizzle & Rain (3xx, 5xx)

|| OWM ID || OWM Beschreibung || Wettercode (overcast) || Wettercode (cloudy) ||
| 300 | light intensity drizzle | `overcast_rain_1` | `cloudy_rain_1` |
| 301 | drizzle | `overcast_rain_2` | `cloudy_rain_2` |
| 302 | heavy intensity drizzle | `overcast_rain_3` | – |
| 310 | light intensity drizzle rain | `overcast_rain_1` | `cloudy_rain_1` |
| 311 | drizzle rain | `overcast_rain_2` | `cloudy_rain_2` |
| 312 | heavy intensity drizzle rain | `overcast_rain_3` | – |
| 313 | shower rain and drizzle | `overcast_rain_2` | `cloudy_rain_2` |
| 314 | heavy shower rain and drizzle | `overcast_rain_3` | – |
| 321 | shower drizzle | `overcast_rain_3` | – |
| 500 | light rain | `overcast_rain_1` | `cloudy_rain_1` |
| 501 | moderate rain | `overcast_rain_2` | `cloudy_rain_2` |
| 502 | heavy intensity rain | `overcast_rain_3` | – |
| 503 | very heavy rain | `overcast_rain_3` | – |
| 504 | extreme rain | `overcast_rain_3` | – |
| 511 | freezing rain | `overcast_freezingrain_2` | `cloudy_freezingrain_2` |
| 520 | light intensity shower rain | `overcast_shower_1` | `cloudy_shower_1` |
| 521 | shower rain | `overcast_shower_2` | `cloudy_shower_2` |
| 522 | heavy intensity shower rain | `overcast_shower_3` | – |
| 531 | ragged shower rain | `overcast_shower_3` | – |

### 7.3 Snow (6xx)

|| OWM ID || OWM Beschreibung || Wettercode (overcast) || Wettercode (cloudy) ||
| 600 | light snow | `overcast_snow_1` | `cloudy_snow_1` |
| 601 | snow | `overcast_snow_2` | `cloudy_snow_2` |
| 602 | heavy snow | `overcast_snow_3` | – |
| 611 | sleet | `overcast_sleet_1` | `cloudy_sleet_1` |
| 612 | light shower sleet | `overcast_sleet_2` | `cloudy_sleet_2` |
| 613 | shower sleet | `overcast_sleet_3` | – |
| 615 | light rain and snow | `overcast_sleet_1` | `cloudy_sleet_1` |
| 616 | rain and snow | `overcast_sleet_2` | `cloudy_sleet_2` |
| 620 | light shower snow | `overcast_snow_1` | `cloudy_snow_1` |
| 621 | shower snow | `overcast_snow_2` | `cloudy_snow_2` |
| 622 | heavy shower snow | `overcast_snow_3` | – |

### 7.4 Atmosphere (7xx)

|| OWM ID || OWM Beschreibung || Wettercode ||
| 701 | mist | `cloudy_fog` |
| 711 | smoke | `overcast_fog` |
| 721 | haze | `cloudy_fog` |
| 731 | sand/dust whirls | `overcast_fog` |
| 741 | fog | `overcast_fog` |
| 751 | sand | `overcast_fog` |
| 761 | dust | `overcast_fog` |
| 762 | volcanic ash | `overcast_fog` |
| 771 | squalls | `overcast_thunderstorm_2` |
| 781 | tornado | `overcast_thunderstorm_3` |

### 7.5 Clouds (8xx)

|| OWM ID || OWM Beschreibung || Wettercode ||
| 800 | clear sky | `clear_day` / `clear_night` |
| 801 | few clouds (11–25 %) | `fair` |
| 802 | scattered clouds (25–50 %) | `cloudy` |
| 803 | broken clouds (51–84 %) | `cloudy` |
| 804 | overcast clouds (85–100 %) | `overcast` |

---

## 8. Loxone Picto-Code Mapping (Reverse)

|| Loxone Picto || Beschreibung || Wettercodes ||
| 1 | Wolkenlos | `clear_day`, `clear_night` |
| 2 | Heiter | `fair` |
| 3 | Leicht bewölkt | `cloudy` |
| 4 | Bewölkt | `cloudy` |
| 5 | Bedeckt | `overcast` |
| 6 | Nebel | `cloudy_fog`, `overcast_fog` |
| 14 | Leichter Niederschlag | `*_shower_1`, `*_shower_2`, `*_rain_1`, `*_rain_2` |
| 15 | Starker Niederschlag | `*_shower_3`, `*_rain_3` |
| 16 | Hagel | `overcast_hail_1`, `overcast_hail_2` |
| 17 | Schwerer Hagel | `overcast_hail_3` |
| 19 | Gefrierender Regen | `*_freezingrain_1`, `*_freezingrain_2`, `*_freezingrain_3` |
| 20 | Leichter Schneeregen | `*_sleet_1`, `*_sleet_2` |
| 21 | Starker Schneeregen | `overcast_sleet_3` |
| 22 | Leichter Schnee | `*_snow_1`, `*_snow_2` |
| 23 | Starker Schnee | `overcast_snow_3` |
| 24 | Gewitter | `*_thunderstorm_1`, `*_thunderstorm_2` |
| 25 | Schweres Gewitter / Schneegewitter | `overcast_thunderstorm_3`, `*_snowthunderstorm_*` |

---

## 9. Symbol-Set Integration

### 9.1 Template für Symbol-Set Mapping

Jedes Symbol-Set definiert ein JSON-Mapping, das seine Bilddateien den Symbolnamen zuordnet:

{code:title=symbol_set_mapping_template.json|language=json}
{
  "set_name": "mein_set",
  "set_version": "1.0.0",
  "format": "svg",
  "mapping": {
    "clear_sun": "mein_set/sunny.svg",
    "clear_moon": "mein_set/clear_night.svg",
    "clear_moon_0q": "mein_set/clear_night_newmoon.svg",
    "clear_moon_2q": "mein_set/clear_night_halfmoon.svg",
    "clear_moon_4q": "mein_set/clear_night_fullmoon.svg",
    "fair_sun": "mein_set/partly_cloudy_day.svg",
    "fair_moon": "mein_set/partly_cloudy_night.svg",
    "fair_moon_0q": "mein_set/partly_cloudy_night_newmoon.svg",
    "fair_moon_2q": "mein_set/partly_cloudy_night_halfmoon.svg",
    "fair_moon_4q": "mein_set/partly_cloudy_night_fullmoon.svg",
    "cloudy_sun": "mein_set/cloudy_day.svg",
    "cloudy_moon": "mein_set/cloudy_night.svg",
    "overcast": "mein_set/overcast.svg",
    "overcast_sun": "mein_set/overcast_day.svg",
    "overcast_moon": "mein_set/overcast_night.svg",
    "overcast_shower_1": "mein_set/light_shower.svg",
    "overcast_shower_2": "mein_set/shower.svg",
    "overcast_shower_3": "mein_set/heavy_shower.svg",
    "overcast_rain_1": "mein_set/light_rain.svg",
    "overcast_rain_2": "mein_set/rain.svg",
    "overcast_rain_3": "mein_set/heavy_rain.svg",
    "...": "..."
  }
}
{code}

### 9.2 Vollständige Symbolliste

|| Typ || Symbole || Anzahl ||
| Tag (`_sun`) | `clear_sun`, `fair_sun`, `cloudy_sun`, `cloudy_fog_sun`, `cloudy_shower_1_sun`, `cloudy_shower_2_sun`, `cloudy_rain_1_sun`, `cloudy_rain_2_sun`, `cloudy_sleet_1_sun`, `cloudy_sleet_2_sun`, `cloudy_snow_1_sun`, `cloudy_snow_2_sun`, `cloudy_freezingrain_1_sun`, `cloudy_freezingrain_2_sun`, `cloudy_thunderstorm_1_sun`, `cloudy_thunderstorm_2_sun`, `cloudy_snowthunderstorm_1_sun`, `cloudy_snowthunderstorm_2_sun` | 18 |
| Nacht (`_moon`) | `clear_moon`, `fair_moon`, `cloudy_moon`, `cloudy_fog_moon`, `cloudy_shower_1_moon`, `cloudy_shower_2_moon`, `cloudy_rain_1_moon`, `cloudy_rain_2_moon`, `cloudy_sleet_1_moon`, `cloudy_sleet_2_moon`, `cloudy_snow_1_moon`, `cloudy_snow_2_moon`, `cloudy_freezingrain_1_moon`, `cloudy_freezingrain_2_moon`, `cloudy_thunderstorm_1_moon`, `cloudy_thunderstorm_2_moon`, `cloudy_snowthunderstorm_1_moon`, `cloudy_snowthunderstorm_2_moon` | 18 |
| Neutral (overcast) | `overcast`, `overcast_fog`, `overcast_shower_1`, `overcast_shower_2`, `overcast_shower_3`, `overcast_rain_1`, `overcast_rain_2`, `overcast_rain_3`, `overcast_sleet_1`, `overcast_sleet_2`, `overcast_sleet_3`, `overcast_snow_1`, `overcast_snow_2`, `overcast_snow_3`, `overcast_freezingrain_1`, `overcast_freezingrain_2`, `overcast_freezingrain_3`, `overcast_thunderstorm_1`, `overcast_thunderstorm_2`, `overcast_thunderstorm_3`, `overcast_snowthunderstorm_1`, `overcast_snowthunderstorm_2`, `overcast_snowthunderstorm_3`, `overcast_hail_1`, `overcast_hail_2`, `overcast_hail_3` | 26 |
| **Gesamt (Basis)** | | **62** |
| Optionale overcast Tag-Varianten (`_sun`) | `overcast_sun`, `overcast_fog_sun`, `overcast_shower_1_sun` … `overcast_hail_3_sun` | 26 |
| Optionale overcast Nacht-Varianten (`_moon`) | `overcast_moon`, `overcast_fog_moon`, `overcast_shower_1_moon` … `overcast_hail_3_moon` | 26 |
| Optionale Mondphasen (5-Phasen-Set, 18 Nachtsymbole × 5) | `clear_moon_0q` … `cloudy_snowthunderstorm_2_moon_4q` | 90 |

---

## 10. Regelwerk (Zusammenfassung)

|| Nr || Regel || Beschreibung ||
| 1 | Code-Schema | `<cloud>[_<precip>][_<intensity>]` |
| 2 | Intensität 3 | Nur bei Bewölkungsgrad `overcast` |
| 3 | `cloudy` + Niederschlag | Nur in Vorhersagen (`forecast_hourly`, `forecast_daily`) |
| 4 | `overcast` + Niederschlag | In aktuellem Wetter (`current`) UND Vorhersagen |
| 5 | `current` + Niederschlag | Immer `overcast` (WetterOnline Tabelle 3), alle 3 Intensitäten |
| 6 | `clear_day` ≠ `clear_night` | Unterschiedliche Erläuterung: "Sonnig" vs. "Klar" |
| 7 | Tag/Nacht-Suffixe (Pflicht) | `_sun` / `_moon` bei `clear`, `fair`, `cloudy` |
| 8 | `overcast`-Symbole Tag/Nacht | Optionaler `_sun` / `_moon` Suffix für Tag/Nacht-Differenzierung |
| 9 | Eindeutigkeit | Jeder Symbolname ist systemweit eindeutig |
| 10 | Führendes System | WetterOnline; OWM und Loxone werden gemappt |
| 11 | Nebel | Kein Intensitätsgrad; `cloudy_fog` und `overcast_fog` |
| 12 | Hagel | Nur `overcast`, mit 3 Intensitäten |
| 13 | Mondphasen | Nur für `clear`, `fair`, `cloudy` Nachtsymbole (`_moon`); Suffix nach `_moon` z.B. `_moon_2q` |
| 14 | Mondphasen-Varianten | Ein Set verwendet 5 (0q–4q), 3 (0q, 2q, 4q) oder 1 Phase; `_moon` ohne Suffix dient als Fallback |
| 15 | Mondphasen bei `overcast` | Mondphasen existieren **nicht** für `overcast`-Symbole |

---

## 11. Statistik

|| Metrik || Wert ||
| Wettercodes gesamt | 45 |
| davon nutzbar für `current` | 31 |
| davon nur für `forecast` | 14 |
| WetterOnline Tabelle 1 (Tag) | 18 Symbole |
| WetterOnline Tabelle 2 (Nacht) | 18 Symbole |
| WetterOnline Tabelle 3 (Neutral) | 26 Symbole |
| Unique Symbolnamen gesamt (Basis) | 62 |
| Optionale overcast Tag/Nacht-Varianten | +52 |
| Optionale Mondphasen-Varianten (max. 5 Phasen) | +90 |
| Niederschlagsarten | 9 |
| Intensitätsstufen | 3 |
| Bewölkungsgrade | 4 |

---

## 12. Änderungshistorie

|| Version || Datum || Änderung ||
| 1.0.0 | 2026-03-07 | Initiale Erstellung des Wettercode-Systems |
| 2.0.0 | 2026-03-07 | Erweiterung: Alle `overcast`-Niederschlagscodes mit 3 Intensitäten auch für aktuelles Wetter (`current`), basierend auf WetterOnline Tabelle 3 |
