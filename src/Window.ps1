[xml]$xaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'MainWindow.xaml') -Raw

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$controlNames = @(
    'AdapterCombo', 'VsrEnabledCheck', 'VsrSettingsPanel', 'AutoModeRadio', 'ManualModeRadio',
    'AutoPriorityPanel', 'GpuPrioritySlider', 'GpuPriorityValue', 'ManualQualityPanel',
    'ManualQualitySlider', 'ManualQualityValue', 'HdrEnabledCheck', 'OutputCombo',
    'HdrSettingsPanel', 'PeakSlider', 'PeakValue', 'MidSlider', 'MidValue',
    'ContrastSlider', 'ContrastValue', 'SaturationSlider', 'SaturationValue',
    'IndicatorCheck', 'ExportButton', 'RestoreButton', 'OpenRegistryButton', 'OpenHdrButton',
    'RegistryPathText', 'StatusText', 'StatusDetailText', 'RefreshButton', 'RestartDriverButton',
    'ApplyButton'
)

foreach ($name in $controlNames) {
    Set-Variable -Name $name -Value $window.FindName($name) -Scope Script
}

function Set-Status {
    param(
        [Parameter(Mandatory)] [string] $Text,
        [string] $Detail = '',
        [switch] $Error
    )

    $StatusText.Text = $Text
    $StatusText.Foreground = if ($Error) { '#FFFF7B72' } else { '#FFF4F6F8' }
    if ($Detail) {
        $StatusDetailText.Text = $Detail
    }
}

function Update-VsrUiState {
    $enabled = [bool]$VsrEnabledCheck.IsChecked
    $VsrSettingsPanel.IsEnabled = $enabled
    $AutoPriorityPanel.Visibility = if ($AutoModeRadio.IsChecked) { 'Visible' } else { 'Collapsed' }
    $ManualQualityPanel.Visibility = if ($ManualModeRadio.IsChecked) { 'Visible' } else { 'Collapsed' }
}

function Update-HdrUiState {
    $hasOutput = $null -ne $script:CurrentOutput
    $HdrSettingsPanel.IsEnabled = [bool]$HdrEnabledCheck.IsChecked -and $hasOutput
    $OutputCombo.IsEnabled = $script:Outputs.Count -gt 0
}

function Sync-TextFromSliders {
    $PeakValue.Text = [string][int][Math]::Round($PeakSlider.Value)
    $MidValue.Text = [string][int][Math]::Round($MidSlider.Value)
    $ContrastValue.Text = [string][int][Math]::Round($ContrastSlider.Value)
    $SaturationValue.Text = [string][int][Math]::Round($SaturationSlider.Value)

    $priorityLabels = @('Low', 'Balanced', 'High')
    $priorityIndex = [Math]::Min(2, [Math]::Max(0, [int][Math]::Round($GpuPrioritySlider.Value)))
    $GpuPriorityValue.Text = $priorityLabels[$priorityIndex]
    $ManualQualityValue.Text = [string][int][Math]::Round($ManualQualitySlider.Value)
}

function Load-HdrOutputSettings {
    if ($null -eq $script:CurrentAdapter -or $null -eq $script:CurrentOutput) {
        $HdrSettingsPanel.IsEnabled = $false
        return
    }

    $path = $script:CurrentAdapter.RegistryPath
    $output = $script:CurrentOutput

    $peak = [int](Get-RegistryProperty -Path $path -Name (Get-HdrValueName -Output $output -Suffix P) -Default 1000)
    $mid = [int](Get-RegistryProperty -Path $path -Name (Get-HdrValueName -Output $output -Suffix M) -Default 50)
    $saturationRaw = [int](Get-RegistryProperty -Path $path -Name (Get-HdrValueName -Output $output -Suffix S) -Default 100)
    $contrastRaw = [int](Get-RegistryProperty -Path $path -Name (Get-HdrValueName -Output $output -Suffix C) -Default 100)

    $PeakSlider.Value = [Math]::Min($PeakSlider.Maximum, [Math]::Max($PeakSlider.Minimum, $peak))
    $MidSlider.Value = [Math]::Min($MidSlider.Maximum, [Math]::Max($MidSlider.Minimum, $mid))
    $SaturationSlider.Value = [Math]::Min(100, [Math]::Max(-100, $saturationRaw - 100))
    $ContrastSlider.Value = [Math]::Min(100, [Math]::Max(-100, $contrastRaw - 100))
    Sync-TextFromSliders
    Update-HdrUiState
}

function Load-AdapterSettings {
    if ($null -eq $script:CurrentAdapter) {
        return
    }

    $script:Loading = $true
    try {
        $path = $script:CurrentAdapter.RegistryPath
        $RegistryPathText.Text = $script:CurrentAdapter.DisplayPath

        $vsr = ConvertTo-DwordBits (Get-RegistryProperty -Path $path -Name '_User_Global_VAL_SuperResolution' -Default 0)
        $VsrEnabledCheck.IsChecked = ($vsr -ne 0)
        if ($vsr -eq 5) {
            $AutoModeRadio.IsChecked = $true
            $ManualQualityRadioValue = 4
        }
        else {
            $ManualModeRadio.IsChecked = $true
            $ManualQualityRadioValue = if ($vsr -ge 1 -and $vsr -le 4) { [int]$vsr } else { 4 }
        }

        $ManualQualitySlider.Value = $ManualQualityRadioValue
        $autoPriority = [int](Get-RegistryProperty -Path $path -Name '_User_Global_VAL_SuperResolution_Auto' -Default 2)
        $GpuPrioritySlider.Value = [Math]::Min(2, [Math]::Max(0, $autoPriority))

        $hdr = ConvertTo-DwordBits (Get-RegistryProperty -Path $path -Name '_User_Global_VAL_TrueHDR' -Default 0)
        $HdrEnabledCheck.IsChecked = ($hdr -ne 0)

        $flags = ConvertTo-DwordBits (Get-RegistryProperty -Path $path -Name '_User_Global_VAL_RTXVideoFlags' -Default 0)
        $IndicatorCheck.IsChecked = (($flags -band $script:IndicatorMask) -ne 0)

        $script:Outputs = @(Get-NvidiaOutputs -Path $path)
        $OutputCombo.ItemsSource = $script:Outputs
        if ($script:Outputs.Count -gt 0) {
            $OutputCombo.SelectedIndex = 0
            $script:CurrentOutput = $script:Outputs[0]
        }
        else {
            $script:CurrentOutput = $null
            $OutputCombo.ItemsSource = @([pscustomobject]@{ Label = 'No NVIDIA display output values found' })
            $OutputCombo.SelectedIndex = 0
        }

        Update-VsrUiState
        Sync-TextFromSliders
        Load-HdrOutputSettings
        Save-BaselineBackup -Adapter $script:CurrentAdapter -Outputs $script:Outputs

        Set-Status -Text 'Settings loaded' -Detail "$($script:CurrentAdapter.Name), driver $($script:CurrentAdapter.DriverVersion)."
    }
    finally {
        $script:Loading = $false
    }
}

function Refresh-Adapters {
    $script:Loading = $true
    try {
        $script:Adapters = @(Get-NvidiaAdapters | ForEach-Object {
            $_ | Add-Member -NotePropertyName DisplayLabel -NotePropertyValue ("{0}  [{1}]" -f $_.Name, $_.KeyName) -PassThru
        })
        $AdapterCombo.ItemsSource = $script:Adapters

        if ($script:Adapters.Count -eq 0) {
            $script:CurrentAdapter = $null
            $ApplyButton.IsEnabled = $false
            $RestartDriverButton.IsEnabled = $false
            Set-Status -Text 'No NVIDIA adapter found' -Detail 'No active NVIDIA display-adapter registry key was detected.' -Error
            return
        }

        $AdapterCombo.SelectedIndex = 0
        $script:CurrentAdapter = $script:Adapters[0]
        $ApplyButton.IsEnabled = $true
        $RestartDriverButton.IsEnabled = $true
    }
    finally {
        $script:Loading = $false
    }

    Load-AdapterSettings
}

function Apply-CurrentSettings {
    if ($null -eq $script:CurrentAdapter) {
        throw 'No NVIDIA adapter is selected.'
    }

    $adapter = $script:CurrentAdapter
    $path = $adapter.RegistryPath
    Save-BaselineBackup -Adapter $adapter -Outputs $script:Outputs

    $vsrValue = [uint32]0
    if ($VsrEnabledCheck.IsChecked) {
        if ($AutoModeRadio.IsChecked) {
            $vsrValue = 5
        }
        else {
            $vsrValue = [uint32][int][Math]::Round($ManualQualitySlider.Value)
        }
    }

    Set-DwordValue -Path $path -Name '_User_Global_VAL_SuperResolution' -Value $vsrValue
    Set-DwordValue -Path $path -Name '_User_Global_XEN_SuperResolution' -Value $script:XenEnabled
    Set-DwordValue -Path $path -Name '_User_Global_VAL_SuperResolution_Auto' -Value ([uint32][int][Math]::Round($GpuPrioritySlider.Value))
    Set-DwordValue -Path $path -Name '_User_Global_XEN_SuperResolution_Auto' -Value $script:XenEnabled

    Set-DwordValue -Path $path -Name '_User_Global_VAL_TrueHDR' -Value ([uint32]$(if ($HdrEnabledCheck.IsChecked) { 5 } else { 0 }))
    Set-DwordValue -Path $path -Name '_User_Global_XEN_TrueHDR' -Value $script:XenEnabled

    Set-DwordValue -Path $path -Name '_User_Global_VAL_RTXVideoFlags' -Value ([uint32]$(if ($IndicatorCheck.IsChecked) { $script:IndicatorMask } else { 0 }))
    Set-DwordValue -Path $path -Name '_User_Global_XEN_RTXVideoFlags' -Value $script:XenEnabled

    if ($null -ne $script:CurrentOutput) {
        $peak = ConvertTo-UInt32Clamped -Value $PeakValue.Text -Minimum 200 -Maximum 2000 -Fallback ([uint32][int]$PeakSlider.Value)
        $mid = ConvertTo-UInt32Clamped -Value $MidValue.Text -Minimum 10 -Maximum 100 -Fallback ([uint32][int]$MidSlider.Value)
        $contrast = ConvertTo-Int32Clamped -Value $ContrastValue.Text -Minimum -100 -Maximum 100 -Fallback ([int]$ContrastSlider.Value)
        $saturation = ConvertTo-Int32Clamped -Value $SaturationValue.Text -Minimum -100 -Maximum 100 -Fallback ([int]$SaturationSlider.Value)

        foreach ($item in @(
            @{ Suffix = 'P'; Value = [uint32]$peak },
            @{ Suffix = 'M'; Value = [uint32]$mid },
            @{ Suffix = 'C'; Value = [uint32]($contrast + 100) },
            @{ Suffix = 'S'; Value = [uint32]($saturation + 100) }
        )) {
            Set-DwordValue -Path $path -Name (Get-HdrValueName -Output $script:CurrentOutput -Suffix $item.Suffix) -Value $item.Value
            Set-DwordValue -Path $path -Name (Get-HdrValueName -Output $script:CurrentOutput -Suffix $item.Suffix -Xen) -Value $script:XenEnabled
        }
    }

    Set-Status -Text 'Changes written' -Detail 'Close and reopen the video app. If the driver keeps the old values cached, use Restart graphics driver or reboot Windows.'
}
