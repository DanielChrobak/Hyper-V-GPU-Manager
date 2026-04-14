#region Auto Install ISO
$script:AutoXMLTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>__UI_LANGUAGE__</UILanguage>
            </SetupUILanguage>
            <InputLocale>__INPUT_LOCALE__</InputLocale>
            <SystemLocale>__SYSTEM_LOCALE__</SystemLocale>
            <UILanguage>__UI_LANGUAGE__</UILanguage>
            <UserLocale>__USER_LOCALE__</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>User</FullName>
                <Organization>Organization</Organization>
                <ProductKey>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
            </UserData>
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <CreatePartitions>
                        <CreatePartition wcm:action="add">
                            <Order>1</Order>
                            <Type>Primary</Type>
                            <Size>100</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                            <Order>2</Order>
                            <Type>EFI</Type>
                            <Size>100</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                            <Order>3</Order>
                            <Type>MSR</Type>
                            <Size>128</Size>
                        </CreatePartition>
                        <CreatePartition wcm:action="add">
                            <Order>4</Order>
                            <Extend>true</Extend>
                            <Type>Primary</Type>
                        </CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add">
                            <Order>1</Order>
                            <PartitionID>1</PartitionID>
                            <Label>WINRE</Label>
                            <Format>NTFS</Format>
                            <TypeID>DE94BBA4-06D1-4D40-A16A-BFD50179D6AC</TypeID>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>2</Order>
                            <PartitionID>2</PartitionID>
                            <Label>System</Label>
                            <Format>FAT32</Format>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>3</Order>
                            <PartitionID>3</PartitionID>
                        </ModifyPartition>
                        <ModifyPartition wcm:action="add">
                            <Order>4</Order>
                            <PartitionID>4</PartitionID>
                            <Label>Windows</Label>
                            <Format>NTFS</Format>
                        </ModifyPartition>
                    </ModifyPartitions>
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    __IMAGE_SELECTION__
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>4</PartitionID>
                    </InstallTo>
                    <InstallToAvailablePartition>false</InstallToAvailablePartition>
                </OSImage>
            </ImageInstall>
        </component>
    </settings>
    <settings pass="specialize">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <ComputerName>*</ComputerName>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>__INPUT_LOCALE__</InputLocale>
            <SystemLocale>__SYSTEM_LOCALE__</SystemLocale>
            <UILanguage>__UI_LANGUAGE__</UILanguage>
            <UserLocale>__USER_LOCALE__</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <TimeZone>UTC</TimeZone>
            __LOCAL_ACCOUNT_SETUP__
        </component>
    </settings>
</unattend>
'@

function XmlEsc($Value) {
    if ($null -eq $Value) { return "" }
    return [System.Security.SecurityElement]::Escape([string]$Value)
}

function GetHostLocaleSettings {
    $fallback = "en-US"
    $inputLocale = $fallback; $systemLocale = $fallback; $uiLanguage = $fallback; $userLocale = $fallback

    try { $systemLocale = (Get-WinSystemLocale).Name } catch {}
    try { $userLocale = (Get-Culture).Name } catch {}
    try {
        $uiOverride = Get-WinUILanguageOverride
        if (![string]::IsNullOrWhiteSpace($uiOverride)) { $uiLanguage = $uiOverride }
    } catch {}
    if ([string]::IsNullOrWhiteSpace($uiLanguage) -or $uiLanguage -eq $fallback) {
        try { $uiLanguage = (Get-UICulture).Name } catch {}
    }

    try {
        $langList = Get-WinUserLanguageList
        if ($langList -and $langList.Count -gt 0) {
            $primary = $langList | Select-Object -First 1
            if ($primary.InputMethodTips -and $primary.InputMethodTips.Count -gt 0 -and ![string]::IsNullOrWhiteSpace($primary.InputMethodTips[0])) {
                $inputLocale = $primary.InputMethodTips[0]
            } elseif (![string]::IsNullOrWhiteSpace($primary.LanguageTag)) {
                $inputLocale = $primary.LanguageTag
            }
        }
    } catch {}

    if ([string]::IsNullOrWhiteSpace($systemLocale)) { $systemLocale = $fallback }
    if ([string]::IsNullOrWhiteSpace($userLocale)) { $userLocale = $systemLocale }
    if ([string]::IsNullOrWhiteSpace($uiLanguage)) { $uiLanguage = $systemLocale }
    if ([string]::IsNullOrWhiteSpace($inputLocale)) { $inputLocale = $userLocale }

    return [PSCustomObject]@{
        InputLocale  = $inputLocale
        SystemLocale = $systemLocale
        UILanguage   = $uiLanguage
        UserLocale   = $userLocale
    }
}

function GetWindowsSetupImagePath($MediaRoot) {
    if ([string]::IsNullOrWhiteSpace($MediaRoot)) { return $null }
    $candidates = @(
        (Join-Path $MediaRoot "sources\install.wim"),
        (Join-Path $MediaRoot "sources\install.esd")
    )
    return ($candidates | Where-Object { Test-Path $_ } | Select-Object -First 1)
}

function GetWindowsInstallImageOptions($IsoPath) {
    if ([string]::IsNullOrWhiteSpace($IsoPath) -or !(Test-Path $IsoPath)) { return @() }

    $mount = $null
    try {
        Spin "Scanning ISO installation options..." 1
        $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru -EA Stop
        $drv = ($mount | Get-Volume).DriveLetter
        if (!$drv) { throw "Could not get ISO drive letter" }

        $imagePath = GetWindowsSetupImagePath "${drv}:"
        if (!$imagePath) {
            Log "No install.wim/install.esd found on ISO; edition auto-selection unavailable." "WARN"
            return @()
        }

        if (!(Get-Command Get-WindowsImage -EA SilentlyContinue)) {
            Log "Get-WindowsImage cmdlet is unavailable; edition auto-selection unavailable." "WARN"
            return @()
        }

        $images = @(Get-WindowsImage -ImagePath $imagePath -EA Stop)
        if (!$images) { return @() }

        return @($images | ForEach-Object {
            [PSCustomObject]@{
                Index       = [int]$_.ImageIndex
                Name        = "$($_.ImageName)"
                Description = "$($_.ImageDescription)"
                Version     = if ($_.Version) { "$($_.Version)" } else { "" }
            }
        } | Sort-Object Index)
    } catch {
        Log "Failed to enumerate Windows installation options: $_" "WARN"
        return @()
    } finally {
        if ($mount) { Dismount-DiskImage -ImagePath $IsoPath -EA SilentlyContinue | Out-Null }
    }
}

function PromptWindowsInstallImageSelection($ImageOptions) {
    if (!$ImageOptions -or $ImageOptions.Count -eq 0) { return $null }

    Write-Host ""
    Box "WINDOWS INSTALLATION OPTIONS" "-"
    foreach ($opt in $ImageOptions) {
        $descText = if (![string]::IsNullOrWhiteSpace($opt.Description) -and $opt.Description -ne $opt.Name) { " | $($opt.Description)" } else { "" }
        $verText = if (![string]::IsNullOrWhiteSpace($opt.Version)) { " | Version: $($opt.Version)" } else { "" }
        Write-Host ("  [{0}] {1}{2}{3}" -f $opt.Index.ToString().PadLeft(2, '0'), $opt.Name, $verText, $descText) -ForegroundColor Gray
    }
    Write-Host ""

    while ($true) {
        $raw = (Read-Host "  Installation index (press Enter to select manually during setup)").Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Log "No installation index selected; setup edition selection will remain manual." "INFO"
            return $null
        }

        $idx = 0
        if ([int]::TryParse($raw, [ref]$idx)) {
            $choice = $ImageOptions | Where-Object { $_.Index -eq $idx } | Select-Object -First 1
            if ($choice) {
                Log ("Selected installation index {0}: {1}" -f $choice.Index, $choice.Name) "SUCCESS"
                return [PSCustomObject]@{ Index = [int]$choice.Index; Name = "$($choice.Name)" }
            }
        }

        Log "Invalid selection. Enter a listed index number or press Enter to skip." "WARN"
    }
}

function BuildImageSelectionXml($ImageSelection) {
    if (!$ImageSelection) { return "" }

    $index = 0
    if (![int]::TryParse("$($ImageSelection.Index)", [ref]$index) -or $index -le 0) { return "" }

    return @"
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>$index</Value>
                        </MetaData>
                    </InstallFrom>
"@
}

function BuildLocalAccountXml($LocalAccount) {
    if (!$LocalAccount) { return "" }

    $username = ""
    if ($LocalAccount.PSObject.Properties.Name -contains "Username") {
        $username = "$($LocalAccount.Username)"
    }
    $username = $username.Trim()
    if ([string]::IsNullOrWhiteSpace($username)) { $username = "User" }

    $password = ""
    if ($LocalAccount.PSObject.Properties.Name -contains "Password") {
        $password = "$($LocalAccount.Password)"
    }

    $escUser = XmlEsc $username
    $escPass = XmlEsc $password

    return @"
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>$escUser</Name>
                        <DisplayName>$escUser</DisplayName>
                        <Group>Administrators</Group>
                        <Password>
                            <Value>$escPass</Value>
                            <PlainText>true</PlainText>
                        </Password>
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
            <AutoLogon>
                <Password>
                    <Value>$escPass</Value>
                    <PlainText>true</PlainText>
                </Password>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>$escUser</Username>
            </AutoLogon>
            <RegisteredOwner>$escUser</RegisteredOwner>
"@
}

function BuildAutoUnattendXml($LocaleSettings, $ImageSelection=$null, $LocalAccount=$null) {
    if (!$LocaleSettings) {
        $LocaleSettings = [PSCustomObject]@{
            InputLocale  = "en-US"
            SystemLocale = "en-US"
            UILanguage   = "en-US"
            UserLocale   = "en-US"
        }
    }

    $xml = $script:AutoXMLTemplate
    $xml = $xml.Replace("__IMAGE_SELECTION__", (BuildImageSelectionXml $ImageSelection))
    $xml = $xml.Replace("__INPUT_LOCALE__", (XmlEsc $LocaleSettings.InputLocale))
    $xml = $xml.Replace("__SYSTEM_LOCALE__", (XmlEsc $LocaleSettings.SystemLocale))
    $xml = $xml.Replace("__UI_LANGUAGE__", (XmlEsc $LocaleSettings.UILanguage))
    $xml = $xml.Replace("__USER_LOCALE__", (XmlEsc $LocaleSettings.UserLocale))
    $xml = $xml.Replace("__LOCAL_ACCOUNT_SETUP__", (BuildLocalAccountXml $LocalAccount))
    return $xml
}

function NewAutoISO($Src, $VM, $ImageSelection=$null, $LocalAccount=$null) {
    Box "AUTOMATED INSTALLATION SETUP" "-"; Log "Creating automated installation ISO..." "INFO"; Write-Host ""
    $mount = $null; $work = $null
    try {
        EnsureDir $script:Paths.ISO
        $new = Join-Path $script:Paths.ISO "$VM-AutoInstall.iso"
        Spin "Mounting source ISO..." 1
        $mount = Mount-DiskImage -ImagePath $Src -PassThru -EA Stop
        $drv = ($mount | Get-Volume).DriveLetter
        if (!$drv) { throw "Could not get ISO drive letter" }
        Log "ISO mounted at ${drv}:" "SUCCESS"
        $work = Join-Path $env:TEMP "HyperV-ISO-$VM-$(Get-Random)"
        EnsureDir $work; Log "Working directory: $work" "INFO"; Write-Host ""
        Log "Copying ISO contents (this may take a few minutes)..." "INFO"
        Spin "Copying files..." 3
        Copy-Item "${drv}:\*" $work -Recurse -Force -EA Stop
        Get-ChildItem $work -Recurse | ForEach-Object { $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) }
        Log "ISO contents copied successfully" "SUCCESS"; Write-Host ""
        Spin "Creating autounattend.xml..." 1
        $locale = GetHostLocaleSettings
        Log ("Using host locale settings: UI={0}, System={1}, User={2}, Keyboard={3}" -f $locale.UILanguage, $locale.SystemLocale, $locale.UserLocale, $locale.InputLocale) "INFO"
        if ($ImageSelection -and $ImageSelection.Index) {
            Log ("Using selected installation image index: {0}" -f $ImageSelection.Index) "INFO"
        }
        if ($LocalAccount) {
            $accountName = if ([string]::IsNullOrWhiteSpace("$($LocalAccount.Username)")) { "User" } else { "$($LocalAccount.Username)".Trim() }
            Log ("Using unattended local account: {0}" -f $accountName) "INFO"
        }
        BuildAutoUnattendXml $locale $ImageSelection $LocalAccount | Out-File "$work\autounattend.xml" -Encoding UTF8 -Force
        Log "autounattend.xml created" "SUCCESS"
        Spin "Dismounting source ISO..." 1
        Dismount-DiskImage -ImagePath $Src -EA SilentlyContinue | Out-Null; $mount = $null
        Write-Host ""; Log "Building new ISO with automated installation..." "INFO"
        $osc = @("C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
                 "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
                 "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
        if (!$osc) {
            Log "oscdimg.exe not found - Windows ADK required" "WARN"; Write-Host ""
            Write-Host "  Windows ADK is required to create ISO files." -ForegroundColor Yellow
            Write-Host "  Download: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Yellow
            Write-Host "  Alternatively, manually copy autounattend.xml to installation media." -ForegroundColor Cyan; Write-Host ""
            $desktop = Join-Path ([Environment]::GetFolderPath("Desktop")) "autounattend.xml"
            Copy-Item "$work\autounattend.xml" $desktop -Force
            Log "autounattend.xml saved to Desktop" "SUCCESS"
            return $null
        }
        $etfs = "$work\boot\etfsboot.com"
        $efi = if (Test-Path "$work\efi\microsoft\boot\efisys_noprompt.bin") { Log "Using efisys_noprompt.bin" "SUCCESS"; "$work\efi\microsoft\boot\efisys_noprompt.bin" }
               else { Log "Using efisys.bin" "INFO"; "$work\efi\microsoft\boot\efisys.bin" }
        if (!(Test-Path $etfs) -or !(Test-Path $efi)) { throw "Boot files not found in ISO" }
        Spin "Building ISO (this may take several minutes)..." 5
        $proc = Start-Process $osc @('-m','-o','-u2','-udfver102',"-bootdata:2#p0,e,b$etfs#pEF,e,b$efi",$work,$new) -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\osc-out.txt" -RedirectStandardError "$env:TEMP\osc-err.txt"
        if ($proc.ExitCode -ne 0) { throw "oscdimg failed with exit code $($proc.ExitCode)" }
        if (!(Test-Path $new)) { throw "ISO file was not created" }
        Write-Host ""; Box "AUTOMATED ISO CREATED" "-"
        Log "ISO Path: $new" "SUCCESS"; Log "Size: $([math]::Round((Get-Item $new).Length / 1GB, 2)) GB" "SUCCESS"
        return $new
    } catch { Log "Failed to create automated ISO: $_" "ERROR"; Write-Host ""; return $null }
    finally {
        if ($mount) { Dismount-DiskImage -ImagePath $Src -EA SilentlyContinue | Out-Null }
        if ($work) { Spin "Cleaning up temporary files..." 2; Remove-Item $work -Recurse -Force -EA SilentlyContinue }
    }
}
#endregion
