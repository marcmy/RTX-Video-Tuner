$AdapterCombo.Add_SelectionChanged({
    if ($script:Loading -or $AdapterCombo.SelectedIndex -lt 0 -or $AdapterCombo.SelectedIndex -ge $script:Adapters.Count) {
        return
    }
    $script:CurrentAdapter = $script:Adapters[$AdapterCombo.SelectedIndex]
    Load-AdapterSettings
})

$OutputCombo.Add_SelectionChanged({
    if ($script:Loading -or $OutputCombo.SelectedIndex -lt 0 -or $OutputCombo.SelectedIndex -ge $script:Outputs.Count) {
        return
    }
    $script:CurrentOutput = $script:Outputs[$OutputCombo.SelectedIndex]
    $script:Loading = $true
    try {
        Load-HdrOutputSettings
    }
    finally {
        $script:Loading = $false
    }
})

$VsrEnabledCheck.Add_Checked({ Update-VsrUiState })
$VsrEnabledCheck.Add_Unchecked({ Update-VsrUiState })
$AutoModeRadio.Add_Checked({ Update-VsrUiState })
$ManualModeRadio.Add_Checked({ Update-VsrUiState })
$HdrEnabledCheck.Add_Checked({ Update-HdrUiState })
$HdrEnabledCheck.Add_Unchecked({ Update-HdrUiState })

$GpuPrioritySlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })
$ManualQualitySlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })
$PeakSlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })
$MidSlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })
$ContrastSlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })
$SaturationSlider.Add_ValueChanged({ if (-not $script:Loading) { Sync-TextFromSliders } })

$PeakValue.Add_LostFocus({ $PeakSlider.Value = ConvertTo-UInt32Clamped -Value $PeakValue.Text -Minimum 200 -Maximum 2000 -Fallback 1000; Sync-TextFromSliders })
$MidValue.Add_LostFocus({ $MidSlider.Value = ConvertTo-UInt32Clamped -Value $MidValue.Text -Minimum 10 -Maximum 100 -Fallback 50; Sync-TextFromSliders })
$ContrastValue.Add_LostFocus({ $ContrastSlider.Value = ConvertTo-Int32Clamped -Value $ContrastValue.Text -Minimum -100 -Maximum 100 -Fallback 0; Sync-TextFromSliders })
$SaturationValue.Add_LostFocus({ $SaturationSlider.Value = ConvertTo-Int32Clamped -Value $SaturationValue.Text -Minimum -100 -Maximum 100 -Fallback 0; Sync-TextFromSliders })

$ApplyButton.Add_Click({
    try {
        Apply-CurrentSettings
    }
    catch {
        Set-Status -Text 'Could not apply changes' -Detail $_.Exception.Message -Error
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'RTX Video Tuner', 'OK', 'Error') | Out-Null
    }
})

$RefreshButton.Add_Click({
    try {
        Load-AdapterSettings
    }
    catch {
        Set-Status -Text 'Reload failed' -Detail $_.Exception.Message -Error
    }
})

$RestartDriverButton.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Windows will briefly blank or flicker the displays and may play a beep. Open video windows can lose hardware acceleration temporarily.`n`nRestart the graphics driver now?",
        'Restart graphics driver',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning
    )
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        Restart-GraphicsDriverShortcut
        Set-Status -Text 'Graphics-driver refresh requested' -Detail 'Wait a few seconds, then close and reopen the browser or video player.'
    }
    catch {
        Set-Status -Text 'Driver refresh failed' -Detail $_.Exception.Message -Error
    }
})

$ExportButton.Add_Click({
    if ($null -eq $script:CurrentAdapter) { return }
    $dialog = [System.Windows.Forms.SaveFileDialog]::new()
    $dialog.Filter = 'Registry files (*.reg)|*.reg'
    $dialog.FileName = "RTX-Video-$($script:CurrentAdapter.KeyName)-$(Get-Date -Format yyyyMMdd-HHmmss).reg"
    $dialog.Title = 'Export RTX Video registry settings'
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return
    }

    try {
        Export-ManagedRegFile -Adapter $script:CurrentAdapter -Outputs $script:Outputs -Destination $dialog.FileName
        Set-Status -Text 'Settings exported' -Detail $dialog.FileName
    }
    catch {
        Set-Status -Text 'Export failed' -Detail $_.Exception.Message -Error
    }
})

$RestoreButton.Add_Click({
    if ($null -eq $script:CurrentAdapter) { return }
    $result = [System.Windows.MessageBox]::Show(
        'Restore the RTX Video registry values captured before this app first modified the selected adapter?',
        'Restore baseline',
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question
    )
    if ($result -ne [System.Windows.MessageBoxResult]::Yes) {
        return
    }

    try {
        Restore-BaselineBackup -Adapter $script:CurrentAdapter
        Load-AdapterSettings
        Set-Status -Text 'Baseline restored' -Detail 'Use Restart graphics driver or reboot if video applications still show the previous state.'
    }
    catch {
        Set-Status -Text 'Restore failed' -Detail $_.Exception.Message -Error
        [System.Windows.MessageBox]::Show($_.Exception.Message, 'RTX Video Tuner', 'OK', 'Error') | Out-Null
    }
})

$OpenRegistryButton.Add_Click({
    if ($null -eq $script:CurrentAdapter) { return }
    try {
        $regPath = $script:CurrentAdapter.DisplayPath
        $regeditSettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Applets\Regedit'
        New-Item -Path $regeditSettingsPath -Force | Out-Null
        Set-ItemProperty -Path $regeditSettingsPath -Name LastKey -Value $regPath -Force
        Start-Process regedit.exe
    }
    catch {
        Set-Status -Text 'Could not open Registry Editor' -Detail $_.Exception.Message -Error
    }
})

$OpenHdrButton.Add_Click({
    try {
        Start-Process 'ms-settings:display'
    }
    catch {
        Set-Status -Text 'Could not open Display settings' -Detail $_.Exception.Message -Error
    }
})

$window.Add_Loaded({ Refresh-Adapters })
$null = $window.ShowDialog()
