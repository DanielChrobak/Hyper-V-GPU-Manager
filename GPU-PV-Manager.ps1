if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

#region Global Settings
$script:Colors = @{INFO='Cyan'; SUCCESS='Green'; WARN='Yellow'; ERROR='Red'; HEADER='Magenta'}
$script:Icons = @{INFO='>'; SUCCESS='+'; WARN='!'; ERROR='X'; HEADER='~'}
$script:Spinner = @('|', '/', '-', '\')
$script:VHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
$script:MountBasePath = "C:\ProgramData\HyperV-Mounts"
$script:ISOPath = "C:\ProgramData\HyperV-ISOs"
$script:GPURegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
#endregion


#region Automated Installation
function New-AutoUnattendXML {
    param([string]$OutputPath)

    $xml = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>User</FullName>
                <Organization>Organization</Organization>
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
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
            <ComputerName>*</ComputerName>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
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

    $xml | Out-File -FilePath $OutputPath -Encoding UTF8 -Force
}

function New-AutoInstallISO {
    param([string]$SourceISO, [string]$VMName)

    Write-Box "AUTOMATED INSTALLATION SETUP" "-"
    Write-Log "Creating automated installation ISO..." "INFO"
    Write-Host ""

    $isoMount = $null
    $workDir = $null
    $newISOPath = $null

    try {
        # Create ISO storage directory
        New-Dir $script:ISOPath
        $newISOPath = Join-Path $script:ISOPath "$VMName-AutoInstall.iso"

        # Mount source ISO
        Show-Spinner "Mounting source ISO..." 1
        $isoMount = Mount-DiskImage -ImagePath $SourceISO -PassThru -EA Stop
        $isoDrive = ($isoMount | Get-Volume).DriveLetter
        if (!$isoDrive) { throw "Could not get ISO drive letter" }
        $isoRoot = "${isoDrive}:"
        Write-Log "ISO mounted at $isoRoot" "SUCCESS"

        # Create working directory
        $workDir = Join-Path $env:TEMP "HyperV-ISO-$VMName-$(Get-Random)"
        New-Dir $workDir
        Write-Log "Working directory: $workDir" "INFO"

        # Copy ISO contents
        Write-Host ""
        Write-Log "Copying ISO contents (this may take a few minutes)..." "INFO"
        Show-Spinner "Copying files..." 3
        Copy-Item -Path "$isoRoot\*" -Destination $workDir -Recurse -Force -EA Stop

        # Remove read-only attributes
        Get-ChildItem $workDir -Recurse | ForEach-Object { $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly) }
        Write-Log "ISO contents copied successfully" "SUCCESS"

        # Create autounattend.xml
        Write-Host ""
        Show-Spinner "Creating autounattend.xml..." 1
        $autoUnattendPath = Join-Path $workDir "autounattend.xml"
        New-AutoUnattendXML -OutputPath $autoUnattendPath
        Write-Log "autounattend.xml created" "SUCCESS"

        # Dismount source ISO
        Show-Spinner "Dismounting source ISO..." 1
        Dismount-DiskImage -ImagePath $SourceISO -EA SilentlyContinue | Out-Null
        $isoMount = $null

        # Create new ISO using oscdimg
        Write-Host ""
        Write-Log "Building new ISO with automated installation..." "INFO"

        # Find oscdimg.exe
        $oscdimgPaths = @(
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe",
            "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\x86\Oscdimg\oscdimg.exe",
            "C:\Program Files\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        )

        $oscdimg = $oscdimgPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (!$oscdimg) {
            Write-Log "oscdimg.exe not found - Windows ADK required" "WARN"
            Write-Host ""
            Write-Host "  Windows Assessment and Deployment Kit (ADK) is required to create ISO files." -ForegroundColor Yellow
            Write-Host "  Download from: https://learn.microsoft.com/en-us/windows-hardware/get-started/adk-install" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  Alternatively, manually copy autounattend.xml to your installation media." -ForegroundColor Cyan
            Write-Host "  Location: $autoUnattendPath" -ForegroundColor Cyan
            Write-Host ""

            # Clean up but keep autounattend.xml
            if (Test-Path $autoUnattendPath) {
                $desktopPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "autounattend.xml"
                Copy-Item $autoUnattendPath $desktopPath -Force
                Write-Log "autounattend.xml saved to Desktop" "SUCCESS"
            }

            return $null
        }

        # Get boot sector files
        $etfsboot = Join-Path $workDir "boot\etfsboot.com"
        $efisys = Join-Path $workDir "efi\microsoft\boot\efisys.bin"

        if (!(Test-Path $etfsboot) -or !(Test-Path $efisys)) {
            throw "Boot files not found in ISO"
        }

        Show-Spinner "Building ISO (this may take several minutes)..." 5

        $oscdimgArgs = @(
            '-m',
            '-o',
            '-u2',
            '-udfver102',
            "-bootdata:2#p0,e,b`"$etfsboot`"#pEF,e,b`"$efisys`"",
            "`"$workDir`"",
            "`"$newISOPath`""
        )

        $process = Start-Process -FilePath $oscdimg -ArgumentList $oscdimgArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\oscdimg-out.txt" -RedirectStandardError "$env:TEMP\oscdimg-err.txt"

        if ($process.ExitCode -ne 0) {
            $errMsg = Get-Content "$env:TEMP\oscdimg-err.txt" -Raw -EA SilentlyContinue
            throw "oscdimg failed with exit code $($process.ExitCode): $errMsg"
        }

        if (!(Test-Path $newISOPath)) {
            throw "ISO file was not created"
        }

        Write-Host ""
        Write-Box "AUTOMATED ISO CREATED" "-"
        Write-Log "ISO Path: $newISOPath" "SUCCESS"
        Write-Log "Size: $([math]::Round((Get-Item $newISOPath).Length / 1GB, 2)) GB" "SUCCESS"

        return $newISOPath

    } catch {
        Write-Log "Failed to create automated ISO: $_" "ERROR"
        Write-Host ""
        return $null
    } finally {
        # Cleanup
        if ($isoMount) { Dismount-DiskImage -ImagePath $SourceISO -EA SilentlyContinue | Out-Null }
        if ($workDir -and (Test-Path $workDir)) {
            Show-Spinner "Cleaning up temporary files..." 2
            Remove-Item $workDir -Recurse -Force -EA SilentlyContinue
        }
    }
}
#endregion


#region Core UI & Logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $($script:Icons[$Level]) $Message" -ForegroundColor $script:Colors[$Level]
}

function Write-Box {
    param([string]$Text, [string]$Style = "=", [int]$Width = 80)
    $w = [Math]::Min(140, [Math]::Max($Width, [Math]::Max(40, $Text.Length + 6)))
    $t = if ($Text.Length -gt ($w - 6)) { $Text.Substring(0, $w - 9) + "..." } else { $Text }

    if ($Style -eq "=") {
        Write-Host ""
        Write-Host "  +$('=' * ($w - 4))+" -ForegroundColor Cyan
        Write-Host "  | " -ForegroundColor Cyan -NoNewline
        Write-Host "$($t.PadRight($w - 6))" -ForegroundColor Yellow -NoNewline
        Write-Host " |" -ForegroundColor Cyan
        Write-Host "  +$('=' * ($w - 4))+" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "  +$('-' * ($w - 4))+" -ForegroundColor Cyan
        Write-Host "  | " -ForegroundColor Cyan -NoNewline
        Write-Host "$($t.PadRight($w - 6))" -ForegroundColor White -NoNewline
        Write-Host " |" -ForegroundColor Cyan
        Write-Host "  +$('-' * ($w - 4))+" -ForegroundColor Cyan
    }
}

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================================================+" -ForegroundColor Cyan
    Write-Host "  |                                                                            |" -ForegroundColor Cyan
    Write-Host "  |                       GPU VIRTUALIZATION MANAGER                           |" -ForegroundColor Cyan
    Write-Host "  |                                                                            |" -ForegroundColor Cyan
    Write-Host "  |                Partition and manage GPUs for Hyper-V VMs                   |" -ForegroundColor Gray
    Write-Host "  |                                                                            |" -ForegroundColor Cyan
    Write-Host "  +============================================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Show-Spinner {
    param([string]$Message, [int]$Duration = 2, [scriptblock]$Condition = $null, [int]$TimeoutSeconds = 60, [string]$SuccessMessage = $null)
    if ($Condition) {
        for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
            if (& $Condition) {
                Write-Host "`r  + $(if ($SuccessMessage) { $SuccessMessage } else { $Message })             " -ForegroundColor Green
                return $true
            }
            Write-Host "`r  $($script:Spinner[$i % 4]) $Message ($i sec)" -ForegroundColor Cyan -NoNewline
            Start-Sleep -Milliseconds 500
        }
        Write-Host "`r  X $Message - Timeout" -ForegroundColor Red
        return $false
    }
    1..$Duration | ForEach-Object { Write-Host "`r  $($script:Spinner[$_ % 4]) $Message" -ForegroundColor Cyan -NoNewline; Start-Sleep -Milliseconds 150 }
    Write-Host "`r  + $Message" -ForegroundColor Green
}

function Invoke-Safe {
    param([scriptblock]$Code, [string]$Op, [string]$OkMsg = $null, [scriptblock]$OnFail = $null)
    try {
        $result = & $Code
        if ($OkMsg) { Write-Log $OkMsg "SUCCESS" }
        return @{Success=$true; Result=$result}
    } catch {
        Write-Log "$Op failed: $_" "ERROR"
        if ($OnFail) { & $OnFail }
        return @{Success=$false; Error=$_}
    }
}

function New-Dir { param([string]$Path); if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force -EA SilentlyContinue | Out-Null } }
#endregion


#region Menu System
function Select-Menu {
    param([string[]]$Items, [string]$Title = "MENU")
    $sel = 0; $last = -1
    Show-Banner

    # Build title line with proper padding
    $titlePadding = 72 - $Title.Length
    $titleLine = "  | $Title$(' ' * $titlePadding) |"

    Write-Host "  +--------------------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host $titleLine -ForegroundColor Yellow
    Write-Host "  +--------------------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  | Use UP/DOWN arrows, ENTER to select, ESC to cancel                       |" -ForegroundColor Gray
    Write-Host "  +--------------------------------------------------------------------------+" -ForegroundColor Cyan
    $menuTop = [Console]::CursorTop

    foreach ($item in $Items) {
        $itemPadding = 68 - $item.Length
        $itemLine = "  |     $item$(' ' * $itemPadding) |"
        Write-Host $itemLine -ForegroundColor White
    }

    Write-Host "  +--------------------------------------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""

    while ($true) {
        if ($sel -ne $last) {
            if ($last -ge 0) {
                [Console]::SetCursorPosition(0, $menuTop + $last)
                $itemPadding = 68 - $Items[$last].Length
                $itemLine = "  |     $($Items[$last])$(' ' * $itemPadding) |"
                Write-Host $itemLine -ForegroundColor White
            }
            [Console]::SetCursorPosition(0, $menuTop + $sel)
            $itemPadding = 68 - $Items[$sel].Length
            $selectedLine = "  | >>  $($Items[$sel])$(' ' * $itemPadding) |"
            Write-Host $selectedLine -ForegroundColor Green
            $last = $sel
        }
        switch ([Console]::ReadKey($true).Key) {
            "UpArrow" { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            "DownArrow" { $sel = ($sel + 1) % $Items.Count }
            "Enter" { [Console]::SetCursorPosition(0, $menuTop + $Items.Count + 2); return $sel }
            "Escape" { [Console]::SetCursorPosition(0, $menuTop + $Items.Count + 2); return $null }
        }
    }
}

function Get-Input {
    param([string]$Prompt, [scriptblock]$Validator = {$true}, [string]$Default = $null)
    do {
        $in = Read-Host "  $Prompt"
        if ([string]::IsNullOrWhiteSpace($in) -and $Default) { return $Default }
        if (& $Validator $in) { return $in }
        Write-Log "Invalid input" "WARN"
    } while ($true)
}

function Confirm { param([string]$Msg); return (Read-Host "  $Msg (Y/N)") -match "^[Yy]$" }
#endregion


#region VM Management
function Select-VM {
    param([string]$Title = "SELECT VM", [string]$RequiredState = "Any")
    Write-Box $Title
    $vms = @(Get-VM | Where-Object {
        $RequiredState -eq "Any" -or $_.State -eq $RequiredState
    })

    if (!$vms) {
        $stateMsg = if ($RequiredState -eq "Any") { "" } else { "$RequiredState " }
        Write-Log "No ${stateMsg}VMs found" "ERROR"
        Write-Host ""
        return $null
    }

    $items = @($vms | ForEach-Object {
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $gpuAdapter = Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue
        $gpuPct = if ($gpuAdapter) { "$([math]::Round($gpuAdapter.MaxPartitionVRAM / 1e9 * 100))%" } else { "None" }

        $stateIcon = switch ($_.State) {
            "Running" { "[*]" }
            "Off" { "[ ]" }
            default { "[~]" }
        }

        $stateColor = switch ($_.State) {
            "Running" { "[Running]" }
            "Off" { "[Stopped]" }
            default { "[$($_.State)]" }
        }

        "$stateIcon $($_.Name.PadRight(20)) $stateColor CPU:$($_.ProcessorCount) RAM:$([math]::Round($mem / 1GB))GB GPU:$gpuPct"
    }) + "< Cancel >"

    $sel = Select-Menu -Items $items -Title $Title
    if ($sel -eq $null -or $sel -eq ($items.Count - 1)) { return $null }
    return $vms[$sel]
}

function Stop-VMSafelySafe {
    param([string]$VMName)
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }

    Write-Log "VM is running - attempting graceful shutdown..." "WARN"

    return (Invoke-Safe -Op "Stop VM" -Code {
        Stop-VM $VMName -Force -EA Stop
        if (Show-Spinner -Message "Shutting down VM" -Condition { (Get-VM $VMName).State -eq "Off" } -TimeoutSeconds 60 -SuccessMessage "VM shut down") {
            Start-Sleep 2; return $true
        }
        Stop-VM $VMName -TurnOff -Force -EA Stop
        Start-Sleep 3
        return $true
    }).Success
}

function Ensure-VMOff {
    param([string]$VMName)
    $v = Get-VM $VMName -EA SilentlyContinue
    if (!$v) { Write-Log "VM not found: $VMName" "ERROR"; return $false }
    return ($v.State -eq "Off") -or (Stop-VMSafelySafe -VMName $VMName)
}
#endregion


#region VHD Operations
function New-SecureDir {
    param([string]$Path)
    if (Test-Path $Path) { return }
    New-Item $Path -ItemType Directory -Force -EA Stop | Out-Null
    $acl = Get-Acl -Path $Path
    $acl.SetAccessRuleProtection($true, $false)
    @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators") | ForEach-Object {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($_, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    Set-Acl -Path $Path -AclObject $acl
}

function Mount-VMDisk {
    param([string]$VHDPath)
    New-SecureDir -Path $script:MountBasePath
    $mountPoint = Join-Path $script:MountBasePath "VMMount_$(Get-Random)"
    $disk = $null; $part = $null

    try {
        New-SecureDir -Path $mountPoint
        Show-Spinner "Mounting virtual disk..." 2
        $disk = Mount-VHD $VHDPath -NoDriveLetter -PassThru -EA Stop
        Start-Sleep 2
        Update-Disk $disk.DiskNumber -EA SilentlyContinue

        $part = Get-Partition -DiskNumber $disk.DiskNumber -EA Stop | Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        if (!$part) { throw "No valid partition found" }

        Show-Spinner "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mountPoint
        if (!(Test-Path "$mountPoint\Windows")) { throw "Windows folder not found - is Windows installed?" }

        return @{Disk=$disk; Partition=$part; Path=$mountPoint; VHDPath=$VHDPath}
    } catch {
        if ($part -and $disk) { Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mountPoint -EA SilentlyContinue }
        if ($disk) { Dismount-VHD $VHDPath -EA SilentlyContinue }
        if (Test-Path $mountPoint) { Remove-Item $mountPoint -Recurse -Force -EA SilentlyContinue }
        throw
    }
}

function Dismount-VMDisk {
    param($Mount, [string]$VHDPath)
    if ($Mount) {
        if ($Mount.Disk -and $Mount.Partition -and $Mount.Path) { Remove-PartitionAccessPath -DiskNumber $Mount.Disk.DiskNumber -PartitionNumber $Mount.Partition.PartitionNumber -AccessPath $Mount.Path -EA SilentlyContinue }
        if ($Mount.VHDPath) { Dismount-VHD $Mount.VHDPath -EA SilentlyContinue }
        if ($Mount.Path -and (Test-Path $Mount.Path)) { Remove-Item $Mount.Path -Recurse -Force -EA SilentlyContinue }
    }
    if ($VHDPath) { Dismount-VHD $VHDPath -EA SilentlyContinue }
}
#endregion


#region GPU Functions
function Get-GPUFriendlyName {
    param([string]$InstancePath)
    if ([string]::IsNullOrWhiteSpace($InstancePath) -or $InstancePath -notmatch "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") { return $null }
    $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.PNPDeviceID -like "*VEN_$($matches[1])*" -and $_.PNPDeviceID -like "*DEV_$($matches[2])*" } | Select-Object -First 1
    if ($gpu) { return $gpu.Name } else { return $null }
}

function Select-GPU {
    param([string]$Title = "SELECT GPU", [switch]$ForPartition)
    Write-Box $Title

    if ($ForPartition) {
        $gpus = @(Get-VMHostPartitionableGpu -EA SilentlyContinue)
        if (!$gpus) { Write-Log "No partitionable GPUs found" "ERROR"; Write-Host ""; return $null }

        $list = @()
        $i = 0
        foreach ($gpu in $gpus) {
            $path = if ([string]::IsNullOrWhiteSpace($gpu.Name)) { $gpu.Id } else { $gpu.Name }
            $name = Get-GPUFriendlyName -InstancePath $path
            if (-not $name) { $name = "GPU-$i" }
            $list += [PSCustomObject]@{Index=$i; Path=$path; Name=$name}
            Write-Host "  [$($i + 1)] $name" -ForegroundColor Green
            $i++
        }
    } else {
        $gpus = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
        if (!$gpus) { Write-Log "No GPUs found" "ERROR"; return $null }

        $i = 1
        foreach ($gpu in $gpus) {
            Write-Host "  [$i] $($gpu.DeviceName)" -ForegroundColor Green
            Write-Host "      Provider: $($gpu.DriverProviderName) | Version: $($gpu.DriverVersion)" -ForegroundColor DarkGray
            $i++
        }
        $list = $gpus
    }

    Write-Host ""
    while ($true) {
        $sel = Read-Host "  Enter GPU # (1-$($list.Count))"
        if ([int]::TryParse($sel, [ref]$null) -and [int]$sel -ge 1 -and [int]$sel -le $list.Count) {
            $picked = $list[[int]$sel - 1]
            if ($ForPartition) { Write-Log "Selected: $($picked.Name)" "SUCCESS"; Write-Host "" }
            return $picked
        }
        Write-Log "Enter 1-$($list.Count)" "WARN"
    }
}

function Get-DriverFiles {
    param([Object]$GPU)
    Write-Box "ANALYZING GPU DRIVERS" "-"
    Write-Log "GPU: $($GPU.DeviceName)" "INFO"
    Write-Log "Provider: $($GPU.DriverProviderName) | Version: $($GPU.DriverVersion)" "INFO"
    Write-Host ""

    Show-Spinner "Finding INF file..." 1
    $inf = Get-ChildItem $script:GPURegPath -EA SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        if ($props.MatchingDeviceId -and ($GPU.DeviceID -like "*$($props.MatchingDeviceId)*" -or $props.MatchingDeviceId -like "*$($GPU.DeviceID)*")) { $props.InfPath }
    } | Select-Object -First 1

    if (!$inf) { Write-Log "GPU not found in registry" "ERROR"; return $null }
    $infPath = "C:\Windows\INF\$inf"
    if (!(Test-Path $infPath)) { Write-Log "INF file missing: $infPath" "ERROR"; return $null }
    Write-Log "Found: $inf" "SUCCESS"

    Show-Spinner "Parsing driver files..." 1
    $content = Get-Content $infPath -Raw
    $refs = @('\.sys','\.dll','\.exe','\.cat','\.inf','\.bin','\.vp','\.cpa') | ForEach-Object { [regex]::Matches($content, "[\w\-\.]+$_", 2) | ForEach-Object { $_.Value } } | Sort-Object -Unique
    Write-Log "Found $($refs.Count) file references" "SUCCESS"
    Write-Host ""

    Show-Spinner "Locating files on disk..." 2
    $searchPaths = @(
        @{Path="C:\Windows\System32\DriverStore\FileRepository"; Type="Store"; Recurse=$true},
        @{Path="C:\Windows\System32"; Type="Sys"; Recurse=$false},
        @{Path="C:\Windows\SysWow64"; Type="Wow"; Recurse=$false}
    )

    $files = @(); $folders = @()
    foreach ($ref in $refs) {
        foreach ($sp in $searchPaths) {
            $found = Get-ChildItem -Path $sp.Path -Filter $ref -Recurse:$sp.Recurse -EA SilentlyContinue | Select-Object -First 1
            if ($found) {
                if ($sp.Type -eq "Store") { if ($found.DirectoryName -notin $folders) { $folders += $found.DirectoryName } }
                else { $files += [PSCustomObject]@{Name=$ref; Source=$found.FullName; Dest=$found.FullName.Replace("C:","")} }
                break
            }
        }
    }

    Write-Log "Located $($files.Count) files + $($folders.Count) folders" "SUCCESS"
    Write-Host ""
    return @{Files=$files; Folders=$folders}
}

function Copy-Logged {
    param([string]$Src, [string]$Dst, [string]$Name, [switch]$Recurse)
    New-Dir (Split-Path -Parent $Dst)
    return (Invoke-Safe -Op "Copy $Name" -Code {
        Copy-Item -Path $Src -Destination $Dst -Force -Recurse:$Recurse -EA Stop
        Write-Log "+ $Name" "SUCCESS"
        return $true
    } -OnFail { Write-Log "! $Name skipped" "WARN" }).Success
}
#endregion


#region VM Creation
$script:VMPresets = @(
    @{Label="Gaming | 8CPU, 16GB, 256GB"; Name="Gaming-VM"; CPU=8; RAM=16; Storage=256},
    @{Label="Development | 4CPU, 8GB, 128GB"; Name="Dev-VM"; CPU=4; RAM=8; Storage=128},
    @{Label="ML Training | 12CPU, 32GB, 512GB"; Name="ML-VM"; CPU=12; RAM=32; Storage=512}
)

function Get-VMConfig {
    $items = @($script:VMPresets | ForEach-Object { $_.Label }) + "Custom"
    $choice = Select-Menu -Items $items -Title "VM CONFIG"
    if ($choice -eq $null) { return $null }

    if ($choice -lt 3) {
        $preset = $script:VMPresets[$choice]
        Write-Host ""
        $name = Read-Host "  Name (default: $($preset.Name))"
        $iso = Read-Host "  ISO path (press Enter to skip)"
        Write-Host ""
        return @{ Name = if ($name) { $name } else { $preset.Name }; CPU = $preset.CPU; RAM = $preset.RAM; Storage = $preset.Storage; Path = $script:VHDPath; ISO = $iso }
    }

    Write-Box "CUSTOM CONFIG" "-"
    return @{
        Name = Get-Input -Prompt "VM Name" -Validator { ![string]::IsNullOrWhiteSpace($_) }
        CPU = [int](Get-Input -Prompt "CPU Cores" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        RAM = [int](Get-Input -Prompt "RAM (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Storage = [int](Get-Input -Prompt "Storage (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Path = $script:VHDPath
        ISO = Read-Host "  ISO path (press Enter to skip)"
    }
}

function New-GpuVM {
    param($Config)
    if (!$Config) { Write-Log "Cancelled" "WARN"; return $null }

    # Check if user wants automated installation
    $isoToUse = $null
    if ($Config.ISO -and (Test-Path $Config.ISO)) {
        Write-Host ""
        if (Confirm "Enable automated Windows installation? (Skips most setup screens)") {
            $isoToUse = New-AutoInstallISO -SourceISO $Config.ISO -VMName $Config.Name
            if ($isoToUse) {
                Write-Log "Will use automated installation ISO" "SUCCESS"
                Write-Host ""
            } else {
                Write-Log "Falling back to original ISO" "WARN"
                $isoToUse = $Config.ISO
                Write-Host ""
            }
        } else {
            $isoToUse = $Config.ISO
        }
    }

    Write-Box "CREATING VM"
    Write-Log "VM: $($Config.Name) | CPU: $($Config.CPU) | RAM: $($Config.RAM)GB | Storage: $($Config.Storage)GB" "INFO"
    Write-Host ""

    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"
    if (Get-VM $Config.Name -EA SilentlyContinue) { Write-Log "VM already exists" "ERROR"; return $null }
    if ((Test-Path $vhdPath) -and !(Confirm "VHDX exists. Overwrite?")) { Write-Log "Cancelled" "WARN"; return $null }
    if (Test-Path $vhdPath) { Remove-Item $vhdPath -Force }

    $r = Invoke-Safe -Op "VM Creation" -Code {
        Show-Spinner "Creating VM..." 2
        New-Dir $Config.Path
        New-VM -Name $Config.Name -MemoryStartupBytes ([int64]$Config.RAM * 1GB) -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes ([int64]$Config.Storage * 1GB) | Out-Null

        Show-Spinner "Configuring..." 1
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -AutomaticCheckpointsEnabled $false

        Show-Spinner "Finalizing..." 1
        if ((Get-VM $Config.Name).State -ne "Off") { Stop-VMSafely $Config.Name -Force -EA SilentlyContinue; while ((Get-VM $Config.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 } }

        Set-VMFirmware $Config.Name -EnableSecureBoot On
        Set-VMKeyProtector $Config.Name -NewLocalKeyProtector
        Enable-VMTPM $Config.Name

        if ($isoToUse -and (Test-Path $isoToUse)) {
            Add-VMDvdDrive $Config.Name -Path $isoToUse
            $dvd = Get-VMDvdDrive $Config.Name; $hdd = Get-VMHardDiskDrive $Config.Name
            if ($dvd -and $hdd) { Set-VMFirmware $Config.Name -BootOrder $dvd, $hdd }
            Write-Log "ISO attached" "SUCCESS"
        }

        Write-Host ""
        Write-Box "VM CREATED: $($Config.Name)" "-"
        Write-Log "CPU: $($Config.CPU) | RAM: $($Config.RAM)GB | Storage: $($Config.Storage)GB" "SUCCESS"
        Write-Host ""
        return $Config.Name
    }
    if ($r.Success) { return $r.Result } else { return $null }
}

#endregion


#region GPU Partitioning
function Set-GPUPartition {
    param([string]$VMName, [int]$Pct = 0, [string]$GPUPath = $null, [string]$GPUName = $null)

    if (!$VMName) { $vm = Select-VM -Title "GPU PARTITION VM" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Write-Log "VM not found" "ERROR"; return $false }

    if (!$GPUPath) { $gpu = Select-GPU -Title "SELECT GPU FOR PARTITIONING" -ForPartition; if (!$gpu) { return $false }; $GPUPath = $gpu.Path; $GPUName = $gpu.Name }

    if ($Pct -eq 0) { Write-Host ""; $Pct = [int](Get-Input -Prompt "GPU % to allocate (1-100)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 }) }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (-not $GPUName) { $name = Get-GPUFriendlyName $GPUPath; $GPUName = if ($name) { $name } else { "GPU" } }

    Write-Box "GPU PARTITION"
    Write-Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"
    Write-Host ""

    if (!(Ensure-VMOff -VMName $VMName)) { return $false }

    return (Invoke-Safe -Op "GPU Config" -Code {
        Show-Spinner "Configuring GPU partition..." 2
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue
        Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $GPUPath

        $max = [int](($Pct / 100) * 1e9)
        $opt = $max - 1
        Set-VMGpuPartitionAdapter $VMName `
            -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt `
            -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt `
            -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt `
            -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB

        Write-Host ""; Write-Box "GPU ALLOCATED: $Pct%" "-"; Write-Host ""
        return $true
    }).Success
}

function Remove-GPUPartition {
    param([string]$VMName)

    if (!$VMName) { $vm = Select-VM -Title "REMOVE GPU FROM VM" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Write-Log "VM not found" "ERROR"; return $false }
    if (!(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)) { Write-Log "No GPU partition found on this VM" "WARN"; Write-Host ""; return $false }

    Write-Box "REMOVE GPU PARTITION"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Host ""

    if (!(Confirm "Remove GPU partition and clean driver files?")) { Write-Log "Cancelled" "WARN"; return $false }
    Write-Host ""
    if (!(Ensure-VMOff -VMName $VMName)) { return $false }

    if (!(Invoke-Safe -Op "Remove GPU Adapter" -Code { Show-Spinner "Removing GPU partition adapter..." 2; Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA Stop; Write-Log "GPU partition adapter removed" "SUCCESS"; return $true }).Success) { Write-Host ""; return $false }
    if (!(Invoke-Safe -Op "Reset MMIO Settings" -Code { Show-Spinner "Resetting memory-mapped IO settings..." 1; Set-VM $VMName -GuestControlledCacheTypes $false -LowMemoryMappedIoSpace 0 -HighMemoryMappedIoSpace 0 -EA Stop; Write-Log "Memory-mapped IO settings reset" "SUCCESS"; return $true }).Success) { Write-Host ""; return $false }

    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) { Write-Log "No VHD found - skipping driver cleanup" "WARN"; Write-Host ""; Write-Box "GPU REMOVAL COMPLETE" "-"; Write-Log "GPU partition and MMIO settings removed" "SUCCESS"; Write-Host ""; return $true }

    $mount = $null
    try {
        Write-Host ""; Show-Spinner "Mounting VM disk to clean drivers..." 2
        $mount = Mount-VMDisk -VHDPath $vhdPath
        $hostDriverStore = "$($mount.Path)\Windows\System32\HostDriverStore"

        if (Test-Path $hostDriverStore) {
            Show-Spinner "Removing driver files..." 2
            $fc = 0; $dc = 0
            if (Test-Path "$hostDriverStore\FileRepository") {
                $dc = (Get-ChildItem "$hostDriverStore\FileRepository" -Directory -EA SilentlyContinue | Measure-Object).Count
                $fc = (Get-ChildItem "$hostDriverStore\FileRepository" -Recurse -File -EA SilentlyContinue | Measure-Object).Count
            }
            Remove-Item "$hostDriverStore\*" -Recurse -Force -EA SilentlyContinue
            Write-Log "Removed $fc files from $dc driver folders" "SUCCESS"
        } else { Write-Log "HostDriverStore not found - no drivers to clean" "INFO" }

        Write-Host ""; Write-Box "GPU REMOVAL COMPLETE" "-"
        Write-Log "GPU partition removed" "SUCCESS"; Write-Log "MMIO settings reset" "SUCCESS"; Write-Log "Driver files cleaned" "SUCCESS"
        Write-Host ""; return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Write-Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - Windows may not be installed yet.`n" -ForegroundColor Yellow
        } else {
            Write-Log "Driver cleanup failed: $($_.Exception.Message)" "WARN"
        }
        Write-Host ""; Write-Box "GPU REMOVAL PARTIAL" "-"
        Write-Log "GPU partition and MMIO settings removed successfully" "SUCCESS"
        Write-Log "Driver cleanup skipped - could not access VM disk" "WARN"
        Write-Host ""; return $true
    } finally { if ($mount) { Show-Spinner "Unmounting VM disk..." 1; Dismount-VMDisk -Mount $mount -VHDPath $vhdPath } }
}
#endregion


#region Driver Injection
function Install-GPUDrivers {
    param([string]$VMName)

    if (!$VMName) { $vm = Select-VM -Title "SELECT VM FOR DRIVERS" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }
    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) { Write-Log "No VHD found" "ERROR"; return $false }

    Write-Box "GPU DRIVER INJECTION"
    Write-Log "Target: $VMName" "INFO"
    Write-Host ""

    if (!(Ensure-VMOff -VMName $VMName)) { return $false }

    $mount = $null
    try {
        $gpu = Select-GPU -Title "SELECT GPU FOR DRIVERS"; if (!$gpu) { return $false }
        Write-Host ""

        $drivers = Get-DriverFiles -GPU $gpu; if (!$drivers) { return $false }
        $mount = Mount-VMDisk -VHDPath $vhdPath
        Show-Spinner "Preparing destination..." 1
        $hostDriverStore = "$($mount.Path)\Windows\System32\HostDriverStore\FileRepository"
        New-Dir $hostDriverStore

        Write-Log "Copying $($drivers.Folders.Count) driver folders..." "INFO"
        Write-Host ""
        foreach ($folder in $drivers.Folders) {
            $name = Split-Path -Leaf $folder
            $dest = Join-Path $hostDriverStore $name
            if (Copy-Logged -Src $folder -Dst $dest -Name $name -Recurse) {
                Write-Host "      ($((Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object).Count) files)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Log "Copying $($drivers.Files.Count) system files..." "INFO"
        foreach ($file in $drivers.Files) {
            Copy-Logged -Src $file.Source -Dst "$($mount.Path)$($file.Dest)" -Name $file.Name | Out-Null
        }

        Write-Host ""
        Write-Box "DRIVER INJECTION COMPLETE" "-"
        Write-Log "Injected $($drivers.Files.Count) files + $($drivers.Folders.Count) folders" "SUCCESS"
        Write-Host ""
        return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Write-Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - install Windows first, then run driver injection.`n" -ForegroundColor Yellow
        } else {
            Write-Log "Failed: $($_.Exception.Message)" "ERROR"
        }
        return $false
    } finally { if ($mount) { Show-Spinner "Unmounting VM disk..." 1; Dismount-VMDisk -Mount $mount -VHDPath $vhdPath } }
}
#endregion


#region Info Display
function Show-VmInfo {
    Write-Box "VM OVERVIEW"
    Write-Log "Gathering VM information..." "INFO"
    Write-Host ""

    $vms = Get-VM
    if (!$vms) { Write-Log "No VMs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }

    $line = "+{0}+{1}+{2}+{3}+{4}+{5}+{6}+" -f ('-'*3),('-'*26),('-'*12),('-'*7),('-'*9),('-'*11),('-'*32)
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ("  | {0,-1} | {1,-24} | {2,-10} | {3,-5} | {4,-7} | {5,-9} | {6,-30} |" -f "", "VM Name", "State", "CPU", "RAM(GB)", "Storage", "GPU") -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor Cyan

    foreach ($vm in $vms) {
        $size = 0
        try {
            $vhd = Get-VHD -VMId $vm.VMId -EA SilentlyContinue
            if ($vhd) { $size = [math]::Round($vhd.Size / 1GB) }
        } catch {}
        $mem = if ($vm.MemoryAssigned -gt 0) { $vm.MemoryAssigned } else { $vm.MemoryStartup }

        $stateIcon = switch ($vm.State) {
            "Running" { "[*]" }
            "Off" { "[ ]" }
            default { "[~]" }
        }

        $color = switch ($vm.State) {
            "Running" { "Green" }
            "Off" { "Gray" }
            default { "Yellow" }
        }

        $gpuInfo = "None"
        $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -EA SilentlyContinue
        if ($gpuAdapter) {
            $name = Get-GPUFriendlyName -InstancePath $gpuAdapter.InstancePath
            $gpuName = if ($name) { $name } else { "GPU" }
            $gpuPct = try { "$([math]::Round($gpuAdapter.MaxPartitionVRAM / 1e9 * 100))%" } catch { "?" }
            $gpuInfo = "$gpuName ($gpuPct)"
            if ($gpuInfo.Length -gt 30) { $gpuInfo = $gpuInfo.Substring(0, 27) + "..." }
        }

        $vmName = $vm.Name
        if ($vmName.Length -gt 24) { $vmName = $vmName.Substring(0, 21) + "..." }

        Write-Host ("  | {0,-1} | {1,-24} | {2,-10} | {3,-5} | {4,-7} | {5,-9} | {6,-30} |" -f $stateIcon, $vmName, $vm.State, $vm.ProcessorCount, [math]::Round($mem / 1GB), $size, $gpuInfo) -ForegroundColor $color
    }
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Press Enter"
}

function Show-GpuInfo {
    Write-Box "GPU INFORMATION"
    Write-Log "Detecting GPUs..." "INFO"
    Write-Host ""

    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if (!$gpus) { Write-Log "No GPUs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }

    $partitionableGPUs = @(Get-VMHostPartitionableGpu -EA SilentlyContinue)

    $i = 1
    foreach ($gpu in $gpus) {
        $statusIcon = if ($gpu.Status -eq 'OK') { '[OK]' } else { '[X]' }
        $statusColor = if ($gpu.Status -eq 'OK') { 'Green' } else { 'Yellow' }

        # Extract VEN and DEV IDs from PNPDeviceID to match against partitionable GPUs
        $isPartitionable = $false
        if ($gpu.PNPDeviceID -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") {
            $venID = $matches[1]
            $devID = $matches[2]
            $isPartitionable = $partitionableGPUs | Where-Object {
                $_.Name -match "VEN_$venID.*DEV_$devID"
            }
        }
        $partitionStatus = if ($isPartitionable) { "[Partitionable]" } else { "[Not Partitionable]" }
        $partitionColor = if ($isPartitionable) { "Cyan" } else { "DarkGray" }

        Write-Host "  [$i] " -ForegroundColor Yellow -NoNewline
        Write-Host "$statusIcon " -ForegroundColor $statusColor -NoNewline
        Write-Host "$($gpu.Name)" -ForegroundColor Green
        Write-Host "      Driver: $($gpu.DriverVersion) | Provider: $($gpu.DriverProviderName)" -ForegroundColor Gray
        Write-Host "      Status: $($gpu.Status) " -ForegroundColor $statusColor -NoNewline
        Write-Host "$partitionStatus" -ForegroundColor $partitionColor
        Write-Host ""
        $i++
    }
    Read-Host "  Press Enter"
}
#endregion


#region Main Menu
$menuItems = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "List VMs", "GPU Info", "Exit")

while ($true) {
    $choice = Select-Menu -Items $menuItems -Title "MAIN MENU"
    if ($choice -eq $null) { Write-Log "Cancelled" "INFO"; continue }
    Write-Host ""

    switch ($choice) {
        0 { New-GpuVM -Config (Get-VMConfig) | Out-Null; Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        2 { Remove-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        3 { Install-GPUDrivers | Out-Null; Read-Host "`n  Press Enter" }
        4 { Show-VmInfo }
        5 { Show-GpuInfo }
        6 { Write-Log "Goodbye!" "INFO"; exit }
    }
}
#endregion
