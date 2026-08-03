# RTX Video Tuner
# Lightweight NVIDIA RTX Video settings GUI for Windows 10/11.
# Version 0.1.1
# Requires administrator rights because NVIDIA stores these values under HKLM.

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-RelaunchedSelf {
    param([switch] $Elevated)

    $hostPath = (Get-Process -Id $PID).Path
    $scriptPath = $PSCommandPath
    $arguments = @(
        '-NoProfile'
        '-Sta'
        '-ExecutionPolicy', 'Bypass'
        '-File', ('"{0}"' -f $scriptPath)
    )

    $startParameters = @{
        FilePath     = $hostPath
        ArgumentList = $arguments
    }
    if ($Elevated) {
        $startParameters.Verb = 'RunAs'
    }

    Start-Process @startParameters | Out-Null
}

$needsElevation = -not (Test-IsAdministrator)
$needsSta = [Threading.Thread]::CurrentThread.ApartmentState -ne [Threading.ApartmentState]::STA
if ($needsElevation -or $needsSta) {
    try {
        Start-RelaunchedSelf -Elevated:$needsElevation
    }
    catch {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            "RTX Video Tuner needs an elevated STA PowerShell process.`n`n$($_.Exception.Message)",
            'RTX Video Tuner',
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error
        ) | Out-Null
    }
    exit
}

Add-Type -AssemblyName PresentationCore, PresentationFramework, WindowsBase, System.Xaml
Add-Type -AssemblyName System.Windows.Forms

$script:DisplayClassPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
$script:XenEnabled = [uint32]2147483649
$script:IndicatorMask = [uint32]0x00000101
$script:Loading = $false
$script:Adapters = @()
$script:Outputs = @()
$script:CurrentAdapter = $null
$script:CurrentOutput = $null
$script:AppDataPath = Join-Path $env:LOCALAPPDATA 'RTXVideoTuner'
$script:BaselinePath = $null

New-Item -ItemType Directory -Path $script:AppDataPath -Force | Out-Null

$modulePath = Join-Path $PSScriptRoot 'src'
. (Join-Path $modulePath 'Registry.ps1')
. (Join-Path $modulePath 'Window.ps1')
. (Join-Path $modulePath 'Events.ps1')
