function Get-NvidiaAdapters {
    if (-not (Test-Path $script:DisplayClassPath)) {
        return @()
    }

    $results = foreach ($key in Get-ChildItem -Path $script:DisplayClassPath -ErrorAction SilentlyContinue) {
        if ($key.PSChildName -notmatch '^\d{4}$') {
            continue
        }

        $properties = Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction SilentlyContinue
        if ($null -eq $properties) {
            continue
        }

        $driverDesc = [string]$properties.DriverDesc
        $provider = [string]$properties.ProviderName
        if ($driverDesc -notmatch 'NVIDIA' -and $provider -notmatch 'NVIDIA') {
            continue
        }

        [pscustomobject]@{
            Name          = if ($driverDesc) { $driverDesc } else { 'NVIDIA display adapter' }
            KeyName       = $key.PSChildName
            RegistryPath  = $key.PSPath
            DisplayPath   = $key.Name
            DriverVersion = [string]$properties.DriverVersion
        }
    }

    return @($results | Sort-Object KeyName)
}

function Get-RegistryProperty {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [object] $Default = $null
    )

    try {
        $value = Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop
        return $value
    }
    catch {
        return $Default
    }
}

function Test-RegistryProperty {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )

    try {
        Get-ItemPropertyValue -LiteralPath $Path -Name $Name -ErrorAction Stop | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function ConvertTo-DwordBits {
    param([Parameter(Mandatory)] [object] $Value)

    # Registry DWORDs are unsigned bit patterns, while the PowerShell registry
    # provider can return values above 0x7FFFFFFF as signed Int32 numbers.
    $signed64 = [int64]$Value
    return [uint32]($signed64 -band [int64]4294967295)
}

function Set-DwordValue {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [uint32] $Value
    )

    # Pass the same 32-bit pattern as a signed Int32 for compatibility with
    # both Windows PowerShell 5.1 and PowerShell 7's registry providers.
    $signedValue = [BitConverter]::ToInt32([BitConverter]::GetBytes($Value), 0)
    New-ItemProperty -LiteralPath $Path -Name $Name -PropertyType DWord -Value $signedValue -Force | Out-Null
}

function Get-NvidiaOutputs {
    param([Parameter(Mandatory)] [string] $Path)

    $properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
    $outputMap = @{}

    foreach ($property in $properties.PSObject.Properties) {
        if ($property.Name -match '^_User_SUB(?<Sub>\d+)_DFP(?<Dfp>\d+)_') {
            $id = "SUB$($Matches.Sub)_DFP$($Matches.Dfp)"
            if (-not $outputMap.ContainsKey($id)) {
                $outputMap[$id] = [ordered]@{
                    Id            = $id
                    Sub           = [int]$Matches.Sub
                    Dfp           = [int]$Matches.Dfp
                    HasHdrTuning  = $false
                    PropertyCount = 0
                }
            }
            $outputMap[$id].PropertyCount++
            if ($property.Name -match '_VAL_TrueHDR_[PMSC]$') {
                $outputMap[$id].HasHdrTuning = $true
            }
        }
    }

    $results = foreach ($entry in $outputMap.Values) {
        [pscustomobject]@{
            Id            = $entry.Id
            Sub           = $entry.Sub
            Dfp           = $entry.Dfp
            HasHdrTuning  = $entry.HasHdrTuning
            PropertyCount = $entry.PropertyCount
            Label         = if ($entry.HasHdrTuning) {
                "HDR output DFP$($entry.Dfp) (configured)"
            }
            else {
                "NVIDIA output DFP$($entry.Dfp)"
            }
        }
    }

    return @($results | Sort-Object @{ Expression = 'HasHdrTuning'; Descending = $true }, Dfp)
}

function Get-HdrValueName {
    param(
        [Parameter(Mandatory)] $Output,
        [Parameter(Mandatory)] [ValidateSet('P', 'M', 'S', 'C')] [string] $Suffix,
        [switch] $Xen
    )

    $kind = if ($Xen) { 'XEN' } else { 'VAL' }
    return "_User_SUB$($Output.Sub)_DFP$($Output.Dfp)_${kind}_TrueHDR_$Suffix"
}

function Get-ManagedValueNames {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [object[]] $Outputs = @()
    )

    $names = [System.Collections.Generic.List[string]]::new()
    foreach ($name in @(
        '_User_Global_VAL_SuperResolution',
        '_User_Global_XEN_SuperResolution',
        '_User_Global_VAL_SuperResolution_Auto',
        '_User_Global_XEN_SuperResolution_Auto',
        '_User_Global_VAL_TrueHDR',
        '_User_Global_XEN_TrueHDR',
        '_User_Global_VAL_RTXVideoFlags',
        '_User_Global_XEN_RTXVideoFlags'
    )) {
        $names.Add($name)
    }

    foreach ($output in $Outputs) {
        foreach ($suffix in 'P', 'M', 'S', 'C') {
            $names.Add((Get-HdrValueName -Output $output -Suffix $suffix))
            $names.Add((Get-HdrValueName -Output $output -Suffix $suffix -Xen))
        }
    }

    return @($names | Select-Object -Unique)
}

function Save-BaselineBackup {
    param(
        [Parameter(Mandatory)] $Adapter,
        [Parameter(Mandatory)] [object[]] $Outputs
    )

    $baseline = Join-Path $script:AppDataPath "baseline-$($Adapter.KeyName).json"
    $script:BaselinePath = $baseline
    if (Test-Path $baseline) {
        return
    }

    $values = foreach ($name in Get-ManagedValueNames -Path $Adapter.RegistryPath -Outputs $Outputs) {
        $exists = Test-RegistryProperty -Path $Adapter.RegistryPath -Name $name
        [pscustomobject]@{
            Name   = $name
            Exists = $exists
            Value  = if ($exists) { ConvertTo-DwordBits (Get-RegistryProperty -Path $Adapter.RegistryPath -Name $name -Default 0) } else { 0 }
        }
    }

    [pscustomobject]@{
        Version       = 1
        CreatedUtc    = [DateTime]::UtcNow.ToString('o')
        AdapterName   = $Adapter.Name
        AdapterKey    = $Adapter.KeyName
        RegistryPath  = $Adapter.RegistryPath
        DriverVersion = $Adapter.DriverVersion
        Values        = @($values)
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $baseline -Encoding utf8
}

function Restore-BaselineBackup {
    param([Parameter(Mandatory)] $Adapter)

    $baseline = Join-Path $script:AppDataPath "baseline-$($Adapter.KeyName).json"
    if (-not (Test-Path $baseline)) {
        throw 'No automatic baseline backup exists for this adapter yet.'
    }

    $backup = Get-Content -LiteralPath $baseline -Raw | ConvertFrom-Json
    foreach ($value in $backup.Values) {
        if ($value.Exists) {
            Set-DwordValue -Path $Adapter.RegistryPath -Name ([string]$value.Name) -Value ([uint32]$value.Value)
        }
        elseif (Test-RegistryProperty -Path $Adapter.RegistryPath -Name ([string]$value.Name)) {
            Remove-ItemProperty -LiteralPath $Adapter.RegistryPath -Name ([string]$value.Name) -Force
        }
    }
}

function Export-ManagedRegFile {
    param(
        [Parameter(Mandatory)] $Adapter,
        [Parameter(Mandatory)] [object[]] $Outputs,
        [Parameter(Mandatory)] [string] $Destination
    )

    $registryHeaderPath = $Adapter.DisplayPath -replace '^HKEY_LOCAL_MACHINE', 'HKEY_LOCAL_MACHINE'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('Windows Registry Editor Version 5.00')
    $lines.Add('')
    $lines.Add("[$registryHeaderPath]")

    foreach ($name in Get-ManagedValueNames -Path $Adapter.RegistryPath -Outputs $Outputs) {
        if (-not (Test-RegistryProperty -Path $Adapter.RegistryPath -Name $name)) {
            continue
        }
        $value = ConvertTo-DwordBits (Get-RegistryProperty -Path $Adapter.RegistryPath -Name $name -Default 0)
        $lines.Add(('"{0}"=dword:{1:x8}' -f $name, $value))
    }

    [IO.File]::WriteAllLines($Destination, $lines, [Text.Encoding]::Unicode)
}

function Restart-GraphicsDriverShortcut {
    if (-not ('NativeKeyboard' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class NativeKeyboard
{
    [DllImport("user32.dll", SetLastError = true)]
    private static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    private const uint KEYEVENTF_KEYUP = 0x0002;

    public static void RestartGraphicsDriver()
    {
        byte VK_LWIN = 0x5B;
        byte VK_CONTROL = 0x11;
        byte VK_SHIFT = 0x10;
        byte VK_B = 0x42;

        keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        keybd_event(VK_SHIFT, 0, 0, UIntPtr.Zero);
        keybd_event(VK_B, 0, 0, UIntPtr.Zero);

        keybd_event(VK_B, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_SHIFT, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
'@
    }

    [NativeKeyboard]::RestartGraphicsDriver()
}

function ConvertTo-UInt32Clamped {
    param(
        [object] $Value,
        [uint32] $Minimum,
        [uint32] $Maximum,
        [uint32] $Fallback
    )

    $parsed = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$parsed)) {
        return $Fallback
    }
    return [uint32][Math]::Min([long]$Maximum, [Math]::Max([long]$Minimum, $parsed))
}

function ConvertTo-Int32Clamped {
    param(
        [object] $Value,
        [int] $Minimum,
        [int] $Maximum,
        [int] $Fallback
    )

    $parsed = 0
    if (-not [int]::TryParse([string]$Value, [ref]$parsed)) {
        return $Fallback
    }
    return [Math]::Min($Maximum, [Math]::Max($Minimum, $parsed))
}
