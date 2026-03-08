# ☁️ Granular Weather Code System v2.0

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Structure](#2-system-structure)
   - 2.1 [Code Schema](#21-code-schema)
   - 2.2 [Cloud Cover Levels](#22-cloud-cover-levels)
   - 2.3 [Precipitation Types](#23-precipitation-types)
   - 2.4 [Intensity Levels](#24-intensity-levels)
   - 2.5 [Contexts](#25-contexts)
3. [Symbol Conventions](#3-symbol-conventions)
   - 3.1 [Day/Night Suffixes](#31-daynight-suffixes)
   - 3.2 [Uniqueness](#32-uniqueness)
4. [WetterOnline Symbol Tables](#4-wetteronline-symbol-tables)
   - 4.1 [Table 1 – Day Symbols (with Sun)](#41-table-1--day-symbols-with-sun)
   - 4.2 [Table 2 – Night Symbols (with Moon)](#42-table-2--night-symbols-with-moon)
   - 4.3 [Table 3 – Overcast Sky Symbols](#43-table-3--overcast-sky-symbols)
   - 4.4 [Moon Phases](#44-moon-phases)
5. [Complete Weather Code Reference](#5-complete-weather-code-reference)
6. [Context Matrix](#6-context-matrix)
7. [OpenWeatherMap Mapping (Reverse)](#7-openweathermap-mapping-reverse)
8. [Loxone Picto-Code Mapping (Reverse)](#8-loxone-picto-code-mapping-reverse)
9. [Symbol Set Integration](#9-symbol-set-integration)
10. [Rules Summary](#10-rules-summary)
11. [Statistics](#11-statistics)
12. [Changelog](#12-changelog)

---

## 1. Overview

This document describes a granular, vendor-independent weather code system that maps various weather services and smart-home systems to a unified code base.

| Property | Value |
|---|---|
| **Version** | 2.0.0 |
| **Leading System** | WetterOnline |
| **Mapped Systems** | OpenWeatherMap (OWM), Loxone Weather (Picto-Codes) |
| **Number of Weather Codes** | 45 |
| **Unique Symbol Names (Base)** | 62 |
| **Optional overcast day/night variants** | +52 (26 × `_sun` and `_moon` each) |
| **Optional moon phase variants (max. 5 phases)** | +90 (18 night symbols × 5 phases) |

---

## 2. System Structure

### 2.1 Code Schema

The weather code is a compound, unique ID following this schema:

```
<cloud_cover>[_<precipitation_type>][_<intensity>]
```

**Examples:**

| Weather Code | Meaning |
|---|---|
| `clear_day` | Sunny (day) |
| `overcast` | Overcast, no precipitation |
| `cloudy_rain_1` | Cloudy, light rain |
| `overcast_thunderstorm_3` | Overcast, severe thunderstorm |

### 2.2 Cloud Cover Levels

| Code | Meaning | Cover Percentage | Day/Night Variants |
|---|---|---|---|
| `clear` | Clear | 0–5 % | ✅ `_sun` / `_moon` |
| `fair` | Partly cloudy | 5–30 % | ✅ `_sun` / `_moon` |
| `cloudy` | Cloudy | 30–70 % | ✅ `_sun` / `_moon` |
| `overcast` | Overcast | 70–100 % | ⚪ `_sun` / `_moon` _(optional)_ |

### 2.3 Precipitation Types

| Code | Meaning | Combo with `cloudy` | Combo with `overcast` |
|---|---|---|---|
| `shower` | Shower (brief) | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `rain` | Rain (continuous) | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `sleet` | Sleet | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `snow` | Snow | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `freezingrain` | Freezing rain | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `thunderstorm` | Thunderstorm | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `snowthunderstorm` | Snow thunderstorm | ✅ Intensity 1–2 | ✅ Intensity 1–3 |
| `fog` | Fog | ✅ (no intensity) | ✅ (no intensity) |
| `hail` | Hail | ❌ | ✅ Intensity 1–3 |

### 2.4 Intensity Levels

| Level | Meaning | Available with `cloudy` | Available with `overcast` |
|---|---|---|---|
| 1 | light | ✅ | ✅ |
| 2 | moderate | ✅ | ✅ |
| 3 | heavy / severe | ❌ | ✅ |

### 2.5 Contexts

| Context | Key | Description | Cloud Cover + Precipitation |
|---|---|---|---|
| Current weather | `current` | Real-time observation | Only `overcast` + precipitation (WetterOnline Table 3) |
| Hourly forecast | `forecast_hourly` | Hourly forecast | `cloudy` + `overcast` + precipitation |
| Daily forecast | `forecast_daily` | Daily forecast | `cloudy` + `overcast` + precipitation |

> **Note:** For current weather (`current`), precipitation symbols are always shown without sun/moon (WetterOnline Table 3). The combination `cloudy` + precipitation exists only in forecasts.

---

## 3. Symbol Conventions

### 3.1 Day/Night Suffixes

| Cloud Cover | Day Symbol | Night Symbol | Day Example | Night Example |
|---|---|---|---|---|
| `clear` | `_sun` | `_moon` | `clear_sun` | `clear_moon` |
| `fair` | `_sun` | `_moon` | `fair_sun` | `fair_moon` |
| `cloudy` | `_sun` | `_moon` | `cloudy_rain_1_sun` | `cloudy_rain_1_moon` |
| `overcast` | `_sun` _(optional)_ | `_moon` _(optional)_ | `overcast_rain_1` or `overcast_rain_1_sun` | `overcast_rain_1` or `overcast_rain_1_moon` |

> **Note:** The day/night suffix for `overcast` is optional, as the sun/moon is not visible in the symbol. However, it can be used to represent different brightness levels or a day/night scene.

### 3.2 Uniqueness

Every symbol name is globally unique within the system. No identical symbol should be listed under different names. Every symbol set must include a mapping of weather codes to the available symbols.

---

## 4. WetterOnline Symbol Tables

WetterOnline uses three symbol tables, mapped to the weather code system as follows:

### 4.1 Table 1 – Day Symbols (with Sun)

_Usage: Daytime forecasts (`forecast_hourly`, `forecast_daily`)_

> Sun symbols exist for cloud cover levels `clear`, `fair`, and `cloudy`, as the symbol shows either a sun or moon behind clouds. Up to 2 intensity levels are available.

| Nr | WetterOnline Description | Weather Code | Symbol Name |
|---|---|---|---|
| 1 | sunny | `clear_day` | `clear_sun` |
| 2 | fair | `fair` | `fair_sun` |
| 3 | cloudy | `cloudy` | `cloudy_sun` |
| 4 | cloudy, light showers | `cloudy_shower_1` | `cloudy_shower_1_sun` |
| 5 | cloudy, showers | `cloudy_shower_2` | `cloudy_shower_2_sun` |
| 6 | cloudy, light rain | `cloudy_rain_1` | `cloudy_rain_1_sun` |
| 7 | cloudy, rain | `cloudy_rain_2` | `cloudy_rain_2_sun` |
| 8 | cloudy, light sleet | `cloudy_sleet_1` | `cloudy_sleet_1_sun` |
| 9 | cloudy, sleet | `cloudy_sleet_2` | `cloudy_sleet_2_sun` |
| 10 | cloudy, light snowfall | `cloudy_snow_1` | `cloudy_snow_1_sun` |
| 11 | cloudy, snowfall | `cloudy_snow_2` | `cloudy_snow_2_sun` |
| 12 | cloudy, light freezing rain | `cloudy_freezingrain_1` | `cloudy_freezingrain_1_sun` |
| 13 | cloudy, freezing rain | `cloudy_freezingrain_2` | `cloudy_freezingrain_2_sun` |
| 14 | cloudy, light thunderstorm | `cloudy_thunderstorm_1` | `cloudy_thunderstorm_1_sun` |
| 15 | cloudy, thunderstorm | `cloudy_thunderstorm_2` | `cloudy_thunderstorm_2_sun` |
| 16 | cloudy, light snow thunderstorm | `cloudy_snowthunderstorm_1` | `cloudy_snowthunderstorm_1_sun` |
| 17 | cloudy, snow thunderstorm | `cloudy_snowthunderstorm_2` | `cloudy_snowthunderstorm_2_sun` |
| 18 | fog, partly sunny | `cloudy_fog` | `cloudy_fog_sun` |

### 4.2 Table 2 – Night Symbols (with Moon)

_Usage: Nighttime forecasts (`forecast_hourly`, `forecast_daily`)_

> Moon symbols exist for cloud cover levels `clear`, `fair`, and `cloudy`, as the symbol shows either a sun or moon behind clouds. Up to 2 intensity levels are available.

| Nr | WetterOnline Description | Weather Code | Symbol Name |
|---|---|---|---|
| 1 | clear | `clear_night` | `clear_moon` |
| 2 | fair | `fair` | `fair_moon` |
| 3 | cloudy | `cloudy` | `cloudy_moon` |
| 4 | cloudy, light showers | `cloudy_shower_1` | `cloudy_shower_1_moon` |
| 5 | cloudy, showers | `cloudy_shower_2` | `cloudy_shower_2_moon` |
| 6 | cloudy, light rain | `cloudy_rain_1` | `cloudy_rain_1_moon` |
| 7 | cloudy, rain | `cloudy_rain_2` | `cloudy_rain_2_moon` |
| 8 | cloudy, light sleet | `cloudy_sleet_1` | `cloudy_sleet_1_moon` |
| 9 | cloudy, sleet | `cloudy_sleet_2` | `cloudy_sleet_2_moon` |
| 10 | cloudy, light snowfall | `cloudy_snow_1` | `cloudy_snow_1_moon` |
| 11 | cloudy, snowfall | `cloudy_snow_2` | `cloudy_snow_2_moon` |
| 12 | cloudy, light freezing rain | `cloudy_freezingrain_1` | `cloudy_freezingrain_1_moon` |
| 13 | cloudy, freezing rain | `cloudy_freezingrain_2` | `cloudy_freezingrain_2_moon` |
| 14 | cloudy, light thunderstorm | `cloudy_thunderstorm_1` | `cloudy_thunderstorm_1_moon` |
| 15 | cloudy, thunderstorm | `cloudy_thunderstorm_2` | `cloudy_thunderstorm_2_moon` |
| 16 | cloudy, light snow thunderstorm | `cloudy_snowthunderstorm_1` | `cloudy_snowthunderstorm_1_moon` |
| 17 | cloudy, snow thunderstorm | `cloudy_snowthunderstorm_2` | `cloudy_snowthunderstorm_2_moon` |
| 18 | fog, partly clear | `cloudy_fog` | `cloudy_fog_moon` |

### 4.3 Table 3 – Overcast Sky Symbols

_Usage: Current weather (`current`) and forecasts (`forecast_hourly`, `forecast_daily`)_

> The `overcast` cloud cover level shows no sun/moon. There are three intensity levels 1, 2, and 3. Symbols may differ for day and night to represent different brightness levels or a day/night scene.

| Nr | WetterOnline Description | Weather Code | Base Symbol Name | Optional Variants (Day / Night) | Intensity |
|---|---|---|---|---|---|
| 1 | overcast | `overcast` | `overcast` | `overcast_sun` / `overcast_moon` | – |
| 2 | light showers | `overcast_shower_1` | `overcast_shower_1` | `overcast_shower_1_sun` / `overcast_shower_1_moon` | 1 |
| 3 | showers | `overcast_shower_2` | `overcast_shower_2` | `overcast_shower_2_sun` / `overcast_shower_2_moon` | 2 |
| 4 | heavy showers | `overcast_shower_3` | `overcast_shower_3` | `overcast_shower_3_sun` / `overcast_shower_3_moon` | 3 |
| 5 | light rain | `overcast_rain_1` | `overcast_rain_1` | `overcast_rain_1_sun` / `overcast_rain_1_moon` | 1 |
| 6 | rain | `overcast_rain_2` | `overcast_rain_2` | `overcast_rain_2_sun` / `overcast_rain_2_moon` | 2 |
| 7 | heavy rain | `overcast_rain_3` | `overcast_rain_3` | `overcast_rain_3_sun` / `overcast_rain_3_moon` | 3 |
| 8 | light sleet | `overcast_sleet_1` | `overcast_sleet_1` | `overcast_sleet_1_sun` / `overcast_sleet_1_moon` | 1 |
| 9 | sleet | `overcast_sleet_2` | `overcast_sleet_2` | `overcast_sleet_2_sun` / `overcast_sleet_2_moon` | 2 |
| 10 | heavy sleet | `overcast_sleet_3` | `overcast_sleet_3` | `overcast_sleet_3_sun` / `overcast_sleet_3_moon` | 3 |
| 11 | light snowfall | `overcast_snow_1` | `overcast_snow_1` | `overcast_snow_1_sun` / `overcast_snow_1_moon` | 1 |
| 12 | snowfall | `overcast_snow_2` | `overcast_snow_2` | `overcast_snow_2_sun` / `overcast_snow_2_moon` | 2 |
| 13 | heavy snowfall | `overcast_snow_3` | `overcast_snow_3` | `overcast_snow_3_sun` / `overcast_snow_3_moon` | 3 |
| 14 | light freezing rain | `overcast_freezingrain_1` | `overcast_freezingrain_1` | `overcast_freezingrain_1_sun` / `overcast_freezingrain_1_moon` | 1 |
| 15 | freezing rain | `overcast_freezingrain_2` | `overcast_freezingrain_2` | `overcast_freezingrain_2_sun` / `overcast_freezingrain_2_moon` | 2 |
| 16 | heavy freezing rain | `overcast_freezingrain_3` | `overcast_freezingrain_3` | `overcast_freezingrain_3_sun` / `overcast_freezingrain_3_moon` | 3 |
| 17 | light thunderstorm | `overcast_thunderstorm_1` | `overcast_thunderstorm_1` | `overcast_thunderstorm_1_sun` / `overcast_thunderstorm_1_moon` | 1 |
| 18 | thunderstorm | `overcast_thunderstorm_2` | `overcast_thunderstorm_2` | `overcast_thunderstorm_2_sun` / `overcast_thunderstorm_2_moon` | 2 |
| 19 | severe thunderstorm | `overcast_thunderstorm_3` | `overcast_thunderstorm_3` | `overcast_thunderstorm_3_sun` / `overcast_thunderstorm_3_moon` | 3 |
| 20 | light snow thunderstorm | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1_sun` / `overcast_snowthunderstorm_1_moon` | 1 |
| 21 | snow thunderstorm | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2_sun` / `overcast_snowthunderstorm_2_moon` | 2 |
| 22 | severe snow thunderstorm | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3_sun` / `overcast_snowthunderstorm_3_moon` | 3 |
| 23 | fog | `overcast_fog` | `overcast_fog` | `overcast_fog_sun` / `overcast_fog_moon` | – |
| 24 | light hail | `overcast_hail_1` | `overcast_hail_1` | `overcast_hail_1_sun` / `overcast_hail_1_moon` | 1 |
| 25 | hail | `overcast_hail_2` | `overcast_hail_2` | `overcast_hail_2_sun` / `overcast_hail_2_moon` | 2 |
| 26 | heavy hail | `overcast_hail_3` | `overcast_hail_3` | `overcast_hail_3_sun` / `overcast_hail_3_moon` | 3 |

### 4.4 Moon Phases

_Usage: Night symbols for cloud cover levels `clear`, `fair`, and `cloudy`_

> Moon phases allow the display of the current moon phase in the night symbol. The moon phase suffix is appended **after** the `_moon` suffix, e.g. `clear_moon_2q` or `cloudy_rain_1_moon_4q`.

| Suffix | Meaning |
|---|---|
| `0q` | New Moon |
| `1q` | First Quarter |
| `2q` | Half Moon |
| `3q` | Three-Quarter Moon (Last Quarter) |
| `4q` | Full Moon |

**Rules:**
- Moon phases exist **only** for cloud cover levels `clear`, `fair`, and `cloudy` — **not** for `overcast`.
- Moon phases apply **only** to night symbols (suffix `_moon`).
- The moon phase suffix is appended after `_moon`: e.g. `clear_moon_0q`, `fair_moon_2q`, `cloudy_rain_1_moon_4q`.
- A symbol set MUST use one of the following variants:
  - **5 moon phases**: `0q`, `1q`, `2q`, `3q`, `4q` (new moon, first quarter, half moon, last quarter, full moon)
  - **3 moon phases**: `0q`, `2q`, `4q` (new moon, half moon, full moon)
  - **1 moon phase**: `1q`, `2q`, or `4q` only (one representative phase)
- If a symbol set uses moon phases, the base `_moon` symbol (without phase suffix) serves as fallback.

**Examples:**

| Symbol Name | Meaning |
|---|---|
| `clear_moon_0q` | Clear, new moon |
| `clear_moon_2q` | Clear, half moon |
| `clear_moon_4q` | Clear, full moon |
| `fair_moon_0q` | Fair, new moon |
| `cloudy_rain_1_moon_2q` | Cloudy, light rain, half moon |
| `cloudy_thunderstorm_2_moon_4q` | Cloudy, thunderstorm, full moon |

---

## 5. Complete Weather Code Reference

### 5.1 Cloud Cover Only (no precipitation)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `clear_day` | Sunny | `clear_sun` | – | current, forecast | sunny | 800 | 01d | 1 |
| 2 | `clear_night` | Clear | – | `clear_moon` | current, forecast | clear | 800 | 01n | 1 |
| 3 | `fair` | Partly cloudy | `fair_sun` | `fair_moon` | current, forecast | fair | 801 | 02d, 02n | 2 |
| 4 | `cloudy` | Cloudy | `cloudy_sun` | `cloudy_moon` | current, forecast | cloudy | 802, 803 | 03d, 03n, 04d, 04n | 3, 4 |
| 5 | `overcast` | Overcast | `overcast` | `overcast` | current, forecast | overcast | 804 | 04d, 04n | 5 |

### 5.2 Showers (shower)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 6 | `cloudy_shower_1` | Cloudy, light showers | `cloudy_shower_1_sun` | `cloudy_shower_1_moon` | forecast | light rain showers | 520 | 09d, 09n | 14 |
| 7 | `cloudy_shower_2` | Cloudy, moderate showers | `cloudy_shower_2_sun` | `cloudy_shower_2_moon` | forecast | rain showers | 521 | 09d, 09n | 14 |
| 8 | `overcast_shower_1` | Overcast, light showers | `overcast_shower_1` | `overcast_shower_1` | current, forecast | light showers | 520 | 09d, 09n | 14 |
| 9 | `overcast_shower_2` | Overcast, moderate showers | `overcast_shower_2` | `overcast_shower_2` | current, forecast | showers | 521 | 09d, 09n | 14 |
| 10 | `overcast_shower_3` | Overcast, heavy showers | `overcast_shower_3` | `overcast_shower_3` | current, forecast | heavy showers | 522, 531 | 09d, 09n | 15 |

### 5.3 Rain (rain)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 11 | `cloudy_rain_1` | Cloudy, light rain | `cloudy_rain_1_sun` | `cloudy_rain_1_moon` | forecast | light rain | 500, 300, 310 | 10d, 10n | 14 |
| 12 | `cloudy_rain_2` | Cloudy, moderate rain | `cloudy_rain_2_sun` | `cloudy_rain_2_moon` | forecast | rain | 501, 301, 311 | 10d, 10n | 14 |
| 13 | `overcast_rain_1` | Overcast, light rain | `overcast_rain_1` | `overcast_rain_1` | current, forecast | light rain | 500, 300, 310 | 10d, 10n | 14 |
| 14 | `overcast_rain_2` | Overcast, moderate rain | `overcast_rain_2` | `overcast_rain_2` | current, forecast | rain | 501, 301, 311 | 10d, 10n | 14 |
| 15 | `overcast_rain_3` | Overcast, heavy rain | `overcast_rain_3` | `overcast_rain_3` | current, forecast | heavy rain | 502, 503, 504, 302, 312, 314, 321 | 10d, 10n | 15 |

### 5.4 Sleet (sleet)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 16 | `cloudy_sleet_1` | Cloudy, light sleet | `cloudy_sleet_1_sun` | `cloudy_sleet_1_moon` | forecast | light sleet | 611, 615 | 13d, 13n | 20 |
| 17 | `cloudy_sleet_2` | Cloudy, moderate sleet | `cloudy_sleet_2_sun` | `cloudy_sleet_2_moon` | forecast | sleet | 612, 616 | 13d, 13n | 20 |
| 18 | `overcast_sleet_1` | Overcast, light sleet | `overcast_sleet_1` | `overcast_sleet_1` | current, forecast | light sleet | 611, 615 | 13d, 13n | 20 |
| 19 | `overcast_sleet_2` | Overcast, moderate sleet | `overcast_sleet_2` | `overcast_sleet_2` | current, forecast | sleet | 612, 616 | 13d, 13n | 20 |
| 20 | `overcast_sleet_3` | Overcast, heavy sleet | `overcast_sleet_3` | `overcast_sleet_3` | current, forecast | heavy sleet | 613 | 13d, 13n | 21 |

### 5.5 Snow (snow)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 21 | `cloudy_snow_1` | Cloudy, light snowfall | `cloudy_snow_1_sun` | `cloudy_snow_1_moon` | forecast | light snow | 600, 620 | 13d, 13n | 22 |
| 22 | `cloudy_snow_2` | Cloudy, moderate snowfall | `cloudy_snow_2_sun` | `cloudy_snow_2_moon` | forecast | snowfall | 601, 621 | 13d, 13n | 22 |
| 23 | `overcast_snow_1` | Overcast, light snowfall | `overcast_snow_1` | `overcast_snow_1` | current, forecast | light snow | 600, 620 | 13d, 13n | 22 |
| 24 | `overcast_snow_2` | Overcast, moderate snowfall | `overcast_snow_2` | `overcast_snow_2` | current, forecast | snowfall | 601, 621 | 13d, 13n | 22 |
| 25 | `overcast_snow_3` | Overcast, heavy snowfall | `overcast_snow_3` | `overcast_snow_3` | current, forecast | heavy snow | 602, 622 | 13d, 13n | 23 |

### 5.6 Freezing Rain (freezingrain)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 26 | `cloudy_freezingrain_1` | Cloudy, light freezing rain | `cloudy_freezingrain_1_sun` | `cloudy_freezingrain_1_moon` | forecast | light freezing rain | 511 | 13d, 13n | 19 |
| 27 | `cloudy_freezingrain_2` | Cloudy, moderate freezing rain | `cloudy_freezingrain_2_sun` | `cloudy_freezingrain_2_moon` | forecast | freezing rain | 511 | 13d, 13n | 19 |
| 28 | `overcast_freezingrain_1` | Overcast, light freezing rain | `overcast_freezingrain_1` | `overcast_freezingrain_1` | current, forecast | light freezing rain | 511 | 13d, 13n | 19 |
| 29 | `overcast_freezingrain_2` | Overcast, moderate freezing rain | `overcast_freezingrain_2` | `overcast_freezingrain_2` | current, forecast | freezing rain | 511 | 13d, 13n | 19 |
| 30 | `overcast_freezingrain_3` | Overcast, heavy freezing rain | `overcast_freezingrain_3` | `overcast_freezingrain_3` | current, forecast | heavy freezing rain | 511 | 13d, 13n | 19 |

### 5.7 Thunderstorm (thunderstorm)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 31 | `cloudy_thunderstorm_1` | Cloudy, light thunderstorm | `cloudy_thunderstorm_1_sun` | `cloudy_thunderstorm_1_moon` | forecast | light thunderstorm | 200, 210, 230 | 11d, 11n | 24 |
| 32 | `cloudy_thunderstorm_2` | Cloudy, moderate thunderstorm | `cloudy_thunderstorm_2_sun` | `cloudy_thunderstorm_2_moon` | forecast | thunderstorm | 201, 211, 231 | 11d, 11n | 24 |
| 33 | `overcast_thunderstorm_1` | Overcast, light thunderstorm | `overcast_thunderstorm_1` | `overcast_thunderstorm_1` | current, forecast | light thunderstorm | 200, 210, 230 | 11d, 11n | 24 |
| 34 | `overcast_thunderstorm_2` | Overcast, moderate thunderstorm | `overcast_thunderstorm_2` | `overcast_thunderstorm_2` | current, forecast | thunderstorm | 201, 211, 231 | 11d, 11n | 24 |
| 35 | `overcast_thunderstorm_3` | Overcast, severe thunderstorm | `overcast_thunderstorm_3` | `overcast_thunderstorm_3` | current, forecast | severe thunderstorm | 202, 212, 221, 232 | 11d, 11n | 25 |

### 5.8 Snow Thunderstorm (snowthunderstorm)

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 36 | `cloudy_snowthunderstorm_1` | Cloudy, light snow thunderstorm | `cloudy_snowthunderstorm_1_sun` | `cloudy_snowthunderstorm_1_moon` | forecast | light snow thunderstorm | 200 (+snow) | 11d, 11n | 25 |
| 37 | `cloudy_snowthunderstorm_2` | Cloudy, moderate snow thunderstorm | `cloudy_snowthunderstorm_2_sun` | `cloudy_snowthunderstorm_2_moon` | forecast | snow thunderstorm | 201 (+snow) | 11d, 11n | 25 |
| 38 | `overcast_snowthunderstorm_1` | Overcast, light snow thunderstorm | `overcast_snowthunderstorm_1` | `overcast_snowthunderstorm_1` | current, forecast | light snow thunderstorm | 200 (+snow) | 11d, 11n | 25 |
| 39 | `overcast_snowthunderstorm_2` | Overcast, moderate snow thunderstorm | `overcast_snowthunderstorm_2` | `overcast_snowthunderstorm_2` | current, forecast | snow thunderstorm | 201 (+snow) | 11d, 11n | 25 |
| 40 | `overcast_snowthunderstorm_3` | Overcast, severe snow thunderstorm | `overcast_snowthunderstorm_3` | `overcast_snowthunderstorm_3` | current, forecast | severe snow thunderstorm | 202 (+snow) | 11d, 11n | 25 |

### 5.9 Fog (fog) – Special Case without Intensity

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 41 | `cloudy_fog` | Foggy, partly clear | `cloudy_fog_sun` | `cloudy_fog_moon` | current, forecast | fog, partly sunny | 701, 721 | 50d, 50n | 6 |
| 42 | `overcast_fog` | Fog | `overcast_fog` | `overcast_fog` | current, forecast | fog | 741 | 50d, 50n | 6 |

### 5.10 Hail (hail) – overcast only

| Nr | Weather Code | Description | Day Symbol | Night Symbol | Context | WetterOnline | OWM IDs | OWM Icons | Loxone Picto |
|---|---|---|---|---|---|---|---|---|---|
| 43 | `overcast_hail_1` | Overcast, light hail | `overcast_hail_1` | `overcast_hail_1` | current, forecast | light hail | – | – | 16 |
| 44 | `overcast_hail_2` | Overcast, moderate hail | `overcast_hail_2` | `overcast_hail_2` | current, forecast | hail | – | – | 16 |
| 45 | `overcast_hail_3` | Overcast, heavy hail | `overcast_hail_3` | `overcast_hail_3` | current, forecast | heavy hail | – | – | 17 |

---

## 6. Context Matrix

### 6.1 Current Weather (current) – 31 Codes

| Category | Available Codes | Intensities |
|---|---|---|
| Cloud Cover Only | `clear_day`, `clear_night`, `fair`, `cloudy`, `overcast` | – |
| Showers | `overcast_shower_1`, `overcast_shower_2`, `overcast_shower_3` | 1, 2, 3 |
| Rain | `overcast_rain_1`, `overcast_rain_2`, `overcast_rain_3` | 1, 2, 3 |
| Sleet | `overcast_sleet_1`, `overcast_sleet_2`, `overcast_sleet_3` | 1, 2, 3 |
| Snow | `overcast_snow_1`, `overcast_snow_2`, `overcast_snow_3` | 1, 2, 3 |
| Freezing Rain | `overcast_freezingrain_1`, `overcast_freezingrain_2`, `overcast_freezingrain_3` | 1, 2, 3 |
| Thunderstorm | `overcast_thunderstorm_1`, `overcast_thunderstorm_2`, `overcast_thunderstorm_3` | 1, 2, 3 |
| Snow Thunderstorm | `overcast_snowthunderstorm_1`, `overcast_snowthunderstorm_2`, `overcast_snowthunderstorm_3` | 1, 2, 3 |
| Fog | `cloudy_fog`, `overcast_fog` | – |
| Hail | `overcast_hail_1`, `overcast_hail_2`, `overcast_hail_3` | 1, 2, 3 |

### 6.2 Forecast (forecast) – 45 Codes

All 31 codes from `current` plus 14 additional `cloudy` precipitation combinations:

| Category | Additional Codes (forecast only) | Intensities |
|---|---|---|
| Showers | `cloudy_shower_1`, `cloudy_shower_2` | 1, 2 |
| Rain | `cloudy_rain_1`, `cloudy_rain_2` | 1, 2 |
| Sleet | `cloudy_sleet_1`, `cloudy_sleet_2` | 1, 2 |
| Snow | `cloudy_snow_1`, `cloudy_snow_2` | 1, 2 |
| Freezing Rain | `cloudy_freezingrain_1`, `cloudy_freezingrain_2` | 1, 2 |
| Thunderstorm | `cloudy_thunderstorm_1`, `cloudy_thunderstorm_2` | 1, 2 |
| Snow Thunderstorm | `cloudy_snowthunderstorm_1`, `cloudy_snowthunderstorm_2` | 1, 2 |

---

## 7. OpenWeatherMap Mapping (Reverse)

The following table shows how OWM condition IDs map to weather codes:

### 7.1 Thunderstorm (2xx)

| OWM ID | OWM Description | Weather Code (overcast) | Weather Code (cloudy) |
|---|---|---|---|
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

| OWM ID | OWM Description | Weather Code (overcast) | Weather Code (cloudy) |
|---|---|---|---|
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

| OWM ID | OWM Description | Weather Code (overcast) | Weather Code (cloudy) |
|---|---|---|---|
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

| OWM ID | OWM Description | Weather Code |
|---|---|---|
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

| OWM ID | OWM Description | Weather Code |
|---|---|---|
| 800 | clear sky | `clear_day` / `clear_night` |
| 801 | few clouds (11–25 %) | `fair` |
| 802 | scattered clouds (25–50 %) | `cloudy` |
| 803 | broken clouds (51–84 %) | `cloudy` |
| 804 | overcast clouds (85–100 %) | `overcast` |

---

## 8. Loxone Picto-Code Mapping (Reverse)

| Loxone Picto | Description | Weather Codes |
|---|---|---|
| 1 | Clear | `clear_day`, `clear_night` |
| 2 | Fair | `fair` |
| 3 | Slightly cloudy | `cloudy` |
| 4 | Cloudy | `cloudy` |
| 5 | Overcast | `overcast` |
| 6 | Fog | `cloudy_fog`, `overcast_fog` |
| 14 | Light precipitation | `*_shower_1`, `*_shower_2`, `*_rain_1`, `*_rain_2` |
| 15 | Heavy precipitation | `*_shower_3`, `*_rain_3` |
| 16 | Hail | `overcast_hail_1`, `overcast_hail_2` |
| 17 | Heavy hail | `overcast_hail_3` |
| 19 | Freezing rain | `*_freezingrain_1`, `*_freezingrain_2`, `*_freezingrain_3` |
| 20 | Light sleet | `*_sleet_1`, `*_sleet_2` |
| 21 | Heavy sleet | `overcast_sleet_3` |
| 22 | Light snow | `*_snow_1`, `*_snow_2` |
| 23 | Heavy snow | `overcast_snow_3` |
| 24 | Thunderstorm | `*_thunderstorm_1`, `*_thunderstorm_2` |
| 25 | Severe thunderstorm / snow thunderstorm | `overcast_thunderstorm_3`, `*_snowthunderstorm_*` |

---

## 9. Symbol Set Integration

### 9.1 Symbol Set Mapping Template

Each symbol set defines a JSON mapping that assigns its image files to symbol names:

```json
{
  "set_name": "my_set",
  "set_version": "1.0.0",
  "format": "svg",
  "mapping": {
    "clear_sun": "my_set/sunny.svg",
    "clear_moon": "my_set/clear_night.svg",
    "clear_moon_0q": "my_set/clear_night_newmoon.svg",
    "clear_moon_2q": "my_set/clear_night_halfmoon.svg",
    "clear_moon_4q": "my_set/clear_night_fullmoon.svg",
    "fair_sun": "my_set/partly_cloudy_day.svg",
    "fair_moon": "my_set/partly_cloudy_night.svg",
    "fair_moon_0q": "my_set/partly_cloudy_night_newmoon.svg",
    "fair_moon_2q": "my_set/partly_cloudy_night_halfmoon.svg",
    "fair_moon_4q": "my_set/partly_cloudy_night_fullmoon.svg",
    "cloudy_sun": "my_set/cloudy_day.svg",
    "cloudy_moon": "my_set/cloudy_night.svg",
    "overcast": "my_set/overcast.svg",
    "overcast_sun": "my_set/overcast_day.svg",
    "overcast_moon": "my_set/overcast_night.svg",
    "overcast_shower_1": "my_set/light_shower.svg",
    "overcast_shower_2": "my_set/shower.svg",
    "overcast_shower_3": "my_set/heavy_shower.svg",
    "overcast_rain_1": "my_set/light_rain.svg",
    "overcast_rain_2": "my_set/rain.svg",
    "overcast_rain_3": "my_set/heavy_rain.svg",
    "...": "..."
  }
}
```

### 9.2 Complete Symbol List

| Type | Symbols | Count |
|---|---|---|
| Day (`_sun`) | `clear_sun`, `fair_sun`, `cloudy_sun`, `cloudy_fog_sun`, `cloudy_shower_1_sun`, `cloudy_shower_2_sun`, `cloudy_rain_1_sun`, `cloudy_rain_2_sun`, `cloudy_sleet_1_sun`, `cloudy_sleet_2_sun`, `cloudy_snow_1_sun`, `cloudy_snow_2_sun`, `cloudy_freezingrain_1_sun`, `cloudy_freezingrain_2_sun`, `cloudy_thunderstorm_1_sun`, `cloudy_thunderstorm_2_sun`, `cloudy_snowthunderstorm_1_sun`, `cloudy_snowthunderstorm_2_sun` | 18 |
| Night (`_moon`) | `clear_moon`, `fair_moon`, `cloudy_moon`, `cloudy_fog_moon`, `cloudy_shower_1_moon`, `cloudy_shower_2_moon`, `cloudy_rain_1_moon`, `cloudy_rain_2_moon`, `cloudy_sleet_1_moon`, `cloudy_sleet_2_moon`, `cloudy_snow_1_moon`, `cloudy_snow_2_moon`, `cloudy_freezingrain_1_moon`, `cloudy_freezingrain_2_moon`, `cloudy_thunderstorm_1_moon`, `cloudy_thunderstorm_2_moon`, `cloudy_snowthunderstorm_1_moon`, `cloudy_snowthunderstorm_2_moon` | 18 |
| Neutral (overcast) | `overcast`, `overcast_fog`, `overcast_shower_1`, `overcast_shower_2`, `overcast_shower_3`, `overcast_rain_1`, `overcast_rain_2`, `overcast_rain_3`, `overcast_sleet_1`, `overcast_sleet_2`, `overcast_sleet_3`, `overcast_snow_1`, `overcast_snow_2`, `overcast_snow_3`, `overcast_freezingrain_1`, `overcast_freezingrain_2`, `overcast_freezingrain_3`, `overcast_thunderstorm_1`, `overcast_thunderstorm_2`, `overcast_thunderstorm_3`, `overcast_snowthunderstorm_1`, `overcast_snowthunderstorm_2`, `overcast_snowthunderstorm_3`, `overcast_hail_1`, `overcast_hail_2`, `overcast_hail_3` | 26 |
| **Total (Base)** | | **62** |
| Optional overcast day variants (`_sun`) | `overcast_sun`, `overcast_fog_sun`, `overcast_shower_1_sun` … `overcast_hail_3_sun` | 26 |
| Optional overcast night variants (`_moon`) | `overcast_moon`, `overcast_fog_moon`, `overcast_shower_1_moon` … `overcast_hail_3_moon` | 26 |
| Optional moon phases (5-phase set, 18 night symbols × 5) | `clear_moon_0q` … `cloudy_snowthunderstorm_2_moon_4q` | 90 |

---

## 10. Rules Summary

| Nr | Rule | Description |
|---|---|---|
| 1 | Code schema | `<cloud>[_<precip>][_<intensity>]` |
| 2 | Intensity 3 | Only for cloud cover level `overcast` |
| 3 | `cloudy` + precipitation | Only in forecasts (`forecast_hourly`, `forecast_daily`) |
| 4 | `overcast` + precipitation | In current weather (`current`) AND forecasts |
| 5 | `current` + precipitation | Always `overcast` (WetterOnline Table 3), all 3 intensities |
| 6 | `clear_day` ≠ `clear_night` | Different description: "Sunny" vs. "Clear" |
| 7 | Day/night suffixes (mandatory) | `_sun` / `_moon` for `clear`, `fair`, `cloudy` |
| 8 | `overcast` day/night symbols | Optional `_sun` / `_moon` suffix for day/night differentiation |
| 9 | Uniqueness | Every symbol name is globally unique |
| 10 | Leading system | WetterOnline; OWM and Loxone are mapped |
| 11 | Fog | No intensity level; `cloudy_fog` and `overcast_fog` |
| 12 | Hail | Only `overcast`, with 3 intensity levels |
| 13 | Moon phases | Only for `clear`, `fair`, `cloudy` night symbols (`_moon`); suffix appended after `_moon` e.g. `_moon_2q` |
| 14 | Moon phase variants | A set uses 5 (0q–4q), 3 (0q, 2q, 4q) or 1 phase; `_moon` without suffix serves as fallback |
| 15 | Moon phases for `overcast` | Moon phases do **not** exist for `overcast` symbols |

---

## 11. Statistics

| Metric | Value |
|---|---|
| Weather codes total | 45 |
| Usable for `current` | 31 |
| Only for `forecast` | 14 |
| WetterOnline Table 1 (Day) | 18 symbols |
| WetterOnline Table 2 (Night) | 18 symbols |
| WetterOnline Table 3 (Neutral) | 26 symbols |
| Unique symbol names (base) | 62 |
| Optional overcast day/night variants | +52 |
| Optional moon phase variants (max. 5 phases) | +90 |
| Precipitation types | 9 |
| Intensity levels | 3 |
| Cloud cover levels | 4 |

---

## 12. Changelog

| Version | Date | Change |
|---|---|---|
| 1.0.0 | 2026-03-07 | Initial creation of the weather code system |
| 2.0.0 | 2026-03-07 | Extension: All `overcast` precipitation codes with 3 intensities also for current weather (`current`), based on WetterOnline Table 3 |
