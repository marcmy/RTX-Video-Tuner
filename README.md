# RTX Video Tuner

[![Validate](https://github.com/marcmy/RTX-Video-Tuner/actions/workflows/validate.yml/badge.svg)](https://github.com/marcmy/RTX-Video-Tuner/actions/workflows/validate.yml)

A lightweight, portable Windows GUI for NVIDIA RTX Video settings that are otherwise only fully exposed by the NVIDIA App. The NVIDIA App is not required.

## Requirements

- Windows 10 or Windows 11
- An NVIDIA RTX GPU and compatible NVIDIA display driver
- PowerShell 7 or Windows PowerShell 5.1

## Run

Download or clone the repository, then double-click **Launch-RTX-Video-Tuner.cmd**. Windows will request administrator permission because NVIDIA stores these settings under `HKEY_LOCAL_MACHINE`.

The launcher prefers PowerShell 7 (`pwsh.exe`) and falls back to Windows PowerShell 5.1.

## Controls

- RTX Video Super Resolution on/off
- Auto or manual VSR quality
- Auto-mode GPU priority: Low, Balanced, High
- Manual quality levels 1–4
- RTX Video HDR on/off
- Per-output peak brightness and middle grey
- Per-output contrast and saturation
- Shared VSR/HDR on-video status indicator
- NVIDIA adapter and output auto-detection
- Export only the managed values to a `.reg` file
- Automatic baseline backup and one-click restore
- Graphics-driver refresh button
- Dark-themed native controls, including readable enabled and disabled dropdowns

## Registry mappings

| UI setting | NVIDIA registry value |
|---|---|
| VSR off | `_User_Global_VAL_SuperResolution = 0` |
| VSR manual quality | `_User_Global_VAL_SuperResolution = 1..4` |
| VSR auto | `_User_Global_VAL_SuperResolution = 5` |
| Auto GPU priority | `_User_Global_VAL_SuperResolution_Auto = 0..2` |
| RTX Video HDR off/on | `_User_Global_VAL_TrueHDR = 0/5` |
| Status indicator off/on | `_User_Global_VAL_RTXVideoFlags = 0/0x101` |
| Peak brightness | `_User_SUBx_DFPy_VAL_TrueHDR_P` |
| Middle grey | `_User_SUBx_DFPy_VAL_TrueHDR_M` |
| Saturation | `_User_SUBx_DFPy_VAL_TrueHDR_S`, stored as UI value + 100 |
| Contrast | `_User_SUBx_DFPy_VAL_TrueHDR_C`, stored as UI value + 100 |

The matching `_XEN_` values are written as `0x80000001`, which marks the corresponding driver setting as explicitly configured.

## Notes

These are NVIDIA driver registry settings, not a documented public API. The GUI intentionally touches only the known RTX Video values and leaves NVIDIA's binary Super Resolution data untouched.

Registry changes can be cached by the running display driver and video application. After applying:

1. Close and reopen the browser or player.
2. Use **Restart graphics driver** if the old values remain active.
3. Reboot Windows if the driver still does not reload them.

RTX Video HDR also requires Windows HDR to be enabled on an HDR10-compatible display.
