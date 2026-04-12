#region Auto Install ISO
$script:AutoXML = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
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
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <TimeZone>UTC</TimeZone>
        </component>
    </settings>
</unattend>
'@

function NewAutoISO($Src, $VM) {
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
        $script:AutoXML | Out-File "$work\autounattend.xml" -Encoding UTF8 -Force
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
