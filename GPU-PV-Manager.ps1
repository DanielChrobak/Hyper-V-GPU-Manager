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

# Helper to find GPU by VEN/DEV IDs
function Find-GPUByVenDev {
    param([string]$InstancePath)
    if ($InstancePath -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") {
        Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object {
            $_.DeviceClass -eq "Display" -and $_.DeviceID -like "*VEN_$($matches[1])*" -and $_.DeviceID -like "*DEV_$($matches[2])*"
        } | Select-Object -First 1
    }
}
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
        $efisysNoprompt = Join-Path $workDir "efi\microsoft\boot\efisys_noprompt.bin"
        $efisys = if (Test-Path $efisysNoprompt) {
            Write-Log "Using efisys_noprompt.bin - will skip boot prompt" "SUCCESS"
            $efisysNoprompt
        } else {
            Write-Log "Using efisys.bin - ISO will show boot prompt" "INFO"
            Join-Path $workDir "efi\microsoft\boot\efisys.bin"
        }

        if (!(Test-Path $etfsboot) -or !(Test-Path $efisys)) {
            throw "Boot files not found in ISO"
        }

        Show-Spinner "Building ISO (this may take several minutes)..." 5

        # Build bootdata without inner quotes
        $bootdata = "-bootdata:2#p0,e,b$etfsboot#pEF,e,b$efisys"

        $oscdimgArgs = @(
            '-m'
            '-o'
            '-u2'
            '-udfver102'
            $bootdata
            $workDir
            $newISOPath
        )

        # Log the command for debugging
        Write-Log "Building ISO..." "INFO"

        $process = Start-Process -FilePath $oscdimg -ArgumentList $oscdimgArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput "$env:TEMP\oscdimg-out.txt" -RedirectStandardError "$env:TEMP\oscdimg-err.txt"

        if ($process.ExitCode -ne 0) {
            $errMsg = Get-Content "$env:TEMP\oscdimg-err.txt" -Raw -EA SilentlyContinue
            $outMsg = Get-Content "$env:TEMP\oscdimg-out.txt" -Raw -EA SilentlyContinue
            Write-Log "oscdimg output: $outMsg" "ERROR"
            Write-Log "oscdimg error: $errMsg" "ERROR"
            throw "oscdimg failed with exit code $($process.ExitCode)"
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
        if ($isoMount) { Dismount-DiskImage -ImagePath $SourceISO -EA SilentlyContinue | Out-Null }
        if ($workDir) {
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

function Write-Table {
    <#
    .SYNOPSIS
    Displays a formatted table with dynamic column widths

    .PARAMETER Data
    Array of objects to display

    .PARAMETER Columns
    Array of hashtables defining columns:
    @{Header="Name"; Property="PropName"; Color="PropNameColor"}
    If Color is specified, the property value will use the color from that property

    .EXAMPLE
    Write-Table -Data $vmData -Columns @(
        @{Header="#"; Property="Index"; Color="Yellow"},
        @{Header="VM Name"; Property="Name"; Color="RowColor"}
    )
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Data,

        [Parameter(Mandatory=$true)]
        [array]$Columns
    )

    if ($Data.Count -eq 0) { return }

    # Calculate dynamic column widths
    $colWidths = @()
    foreach ($col in $Columns) {
        $header = $col.Header
        $prop = $col.Property

        $maxDataWidth = ($Data | ForEach-Object {
            $val = $_.$prop
            if ($null -eq $val) { 0 } else { $val.ToString().Length }
        } | Measure-Object -Maximum).Maximum

        $width = [Math]::Max($maxDataWidth, $header.Length)
        $colWidths += $width
    }

    # Build separator line
    $separatorParts = @()
    foreach ($width in $colWidths) {
        $separatorParts += ('-' * ($width + 2))
    }
    $separator = "  +" + ($separatorParts -join '+') + "+"

    # Display header
    Write-Host $separator -ForegroundColor Cyan

    $headerParts = @()
    for ($i = 0; $i -lt $Columns.Count; $i++) {
        $headerParts += " {$i,-$($colWidths[$i])} "
    }
    $headerFormat = "  |" + ($headerParts -join '|') + "|"
    $headerValues = $Columns | ForEach-Object { $_.Header }
    Write-Host ($headerFormat -f $headerValues) -ForegroundColor Cyan

    Write-Host $separator -ForegroundColor Cyan

    # Display data rows
    foreach ($row in $Data) {
        Write-Host "  |" -ForegroundColor Cyan -NoNewline

        for ($i = 0; $i -lt $Columns.Count; $i++) {
            $col = $Columns[$i]
            $value = $row.($col.Property)
            $color = if ($col.Color -and $row.($col.Color)) { $row.($col.Color) } else { "White" }

            Write-Host " " -NoNewline
            Write-Host ("{0,-$($colWidths[$i])}" -f $value) -ForegroundColor $color -NoNewline
            Write-Host " " -NoNewline
            Write-Host "|" -ForegroundColor Cyan -NoNewline
        }
        Write-Host ""
    }

    Write-Host $separator -ForegroundColor Cyan
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

    # Calculate dynamic width based on longest item and title
    $maxItemLen = ($Items | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    $minWidth = [Math]::Max($Title.Length + 6, $maxItemLen + 10)
    $minWidth = [Math]::Max($minWidth, 60)  # Minimum 60 chars
    $boxWidth = $minWidth + 4  # Add space for borders and padding

    # Build title line with dynamic padding
    $titlePadding = $boxWidth - 4 - $Title.Length
    $titleLine = "  | $Title$(' ' * $titlePadding) |"

    # Build separator with dynamic width
    $separator = "  +$('-' * ($boxWidth - 2))+"

    # Build instruction line with dynamic padding
    $instruction = "Use UP/DOWN arrows, ENTER to select, ESC to cancel"
    $instrPadding = $boxWidth - 4 - $instruction.Length
    $instrLine = "  | $instruction$(' ' * $instrPadding) |"

    Write-Host $separator -ForegroundColor Cyan
    Write-Host $titleLine -ForegroundColor Yellow
    Write-Host $separator -ForegroundColor Cyan
    Write-Host $instrLine -ForegroundColor Gray
    Write-Host $separator -ForegroundColor Cyan
    $menuTop = [Console]::CursorTop

    foreach ($item in $Items) {
        $itemPadding = $boxWidth - 9 - $item.Length
        $itemLine = "  |     $item$(' ' * $itemPadding) |"
        Write-Host $itemLine -ForegroundColor White
    }

    Write-Host $separator -ForegroundColor Cyan
    Write-Host ""

    while ($true) {
        if ($sel -ne $last) {
            if ($last -ge 0) {
                [Console]::SetCursorPosition(0, $menuTop + $last)
                $itemPadding = $boxWidth - 9 - $Items[$last].Length
                $itemLine = "  |     $($Items[$last])$(' ' * $itemPadding) |"
                Write-Host $itemLine -ForegroundColor White
            }
            [Console]::SetCursorPosition(0, $menuTop + $sel)
            $itemPadding = $boxWidth - 9 - $Items[$sel].Length
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
    if ([string]::IsNullOrWhiteSpace($InstancePath)) { return $null }
    $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object {
        $InstancePath -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})" -and
        $_.PNPDeviceID -like "*VEN_$($matches[1])*DEV_$($matches[2])*"
    } | Select-Object -First 1
    return $gpu.Name
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
            $path = if ($gpu.Name) { $gpu.Name } else { $gpu.Id }
            $name = (Get-GPUFriendlyName $path)
            if (!$name) { $name = "GPU-$i" }
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
        $vmName = if ($name) { $name } else { $preset.Name }
        return @{ Name = $vmName; CPU = $preset.CPU; RAM = $preset.RAM; Storage = $preset.Storage; Path = $script:VHDPath; ISO = $iso }
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
    if ($r.Success) {
        return $r.Result
    } else {
        return $null
    }
}

#endregion


#region GPU Partitioning
function Set-GPUPartition {
    param([string]$VMName, [int]$Pct = 0, [string]$GPUPath = $null, [string]$GPUName = $null)

    if (!$VMName) { $vm = Select-VM -Title "GPU PARTITION VM" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) {
        Write-Log "VM not found" "ERROR"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    if (!$GPUPath) { $gpu = Select-GPU -Title "SELECT GPU FOR PARTITIONING" -ForPartition; if (!$gpu) { return $false }; $GPUPath = $gpu.Path; $GPUName = $gpu.Name }

    if ($Pct -eq 0) { Write-Host ""; $Pct = [int](Get-Input -Prompt "GPU % to allocate (1-100)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 }) }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (!$GPUName) {
        $GPUName = (Get-GPUFriendlyName $GPUPath)
        if (!$GPUName) { $GPUName = "GPU" }
    }

    Write-Box "GPU PARTITION"
    Write-Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"
    Write-Host ""

    if (!(Ensure-VMOff -VMName $VMName)) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    $result = (Invoke-Safe -Op "GPU Config" -Code {
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
    })

    if (!$result.Success) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
    }
    return $result.Success
}

function Remove-GPUPartition {
    param([string]$VMName)

    if (!$VMName) { $vm = Select-VM -Title "REMOVE GPU FROM VM" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) {
        Write-Log "VM not found" "ERROR"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }
    if (!(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)) {
        Write-Log "No GPU partition found on this VM" "WARN"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    Write-Box "REMOVE GPU PARTITION"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Host ""

    if (!(Confirm "Remove GPU partition and clean all driver files?")) { Write-Log "Cancelled" "WARN"; return $false }
    Write-Host ""
    if (!(Ensure-VMOff -VMName $VMName)) { return $false }

    # Get GPU info before removing the adapter (so we can find driver files to clean)
    $gpuAdapter = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    $gpu = if ($gpuAdapter) { Find-GPUByVenDev $gpuAdapter.InstancePath } else { $null }

    Show-Spinner "Removing GPU partition adapter..." 2
    if (!(Invoke-Safe -Op "Remove GPU Adapter" -Code {
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA Stop
        Write-Log "GPU partition adapter removed" "SUCCESS"
    }).Success) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    Show-Spinner "Resetting memory-mapped IO settings..." 1
    if (!(Invoke-Safe -Op "Reset MMIO Settings" -Code {
        Set-VM $VMName -GuestControlledCacheTypes $false -LowMemoryMappedIoSpace 0 -HighMemoryMappedIoSpace 0 -EA Stop
        Write-Log "Memory-mapped IO settings reset" "SUCCESS"
    }).Success) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) { Write-Log "No VHD found - skipping driver cleanup" "WARN"; Write-Host ""; Write-Box "GPU REMOVAL COMPLETE" "-"; Write-Log "GPU partition and MMIO settings removed" "SUCCESS"; Write-Host ""; return $true }

    $mount = $null
    try {
        Write-Host ""; Show-Spinner "Mounting VM disk to clean drivers..." 2
        $mount = Mount-VMDisk -VHDPath $vhdPath
        $hostDriverStore = "$($mount.Path)\Windows\System32\HostDriverStore"

        # Remove driver files from HostDriverStore
        $totalFilesRemoved = 0
        $totalFoldersRemoved = 0

        if (Test-Path $hostDriverStore) {
            Show-Spinner "Removing driver repository files..." 2
            if (Test-Path "$hostDriverStore\FileRepository") {
                $totalFoldersRemoved = (Get-ChildItem "$hostDriverStore\FileRepository" -Directory -EA SilentlyContinue | Measure-Object).Count
                $totalFilesRemoved = (Get-ChildItem "$hostDriverStore\FileRepository" -Recurse -File -EA SilentlyContinue | Measure-Object).Count
            }
            Remove-Item "$hostDriverStore\*" -Recurse -Force -EA SilentlyContinue
            Write-Log "Removed $totalFilesRemoved files from $totalFoldersRemoved driver folders" "SUCCESS"
        } else { Write-Log "HostDriverStore not found" "INFO" }

        # Remove individual system files if we found the GPU
        if ($gpu) {
            Write-Host ""
            Write-Log "Removing system driver files..." "INFO"
            $drivers = Get-DriverFiles -GPU $gpu

            if ($drivers -and $drivers.Files) {
                $systemFilesRemoved = 0
                foreach ($file in $drivers.Files) {
                    $filePath = "$($mount.Path)$($file.Dest)"
                    if (Test-Path $filePath) {
                        Remove-Item $filePath -Force -EA SilentlyContinue
                        if (!(Test-Path $filePath)) {
                            $systemFilesRemoved++
                            Write-Log "- $($file.Name)" "SUCCESS"
                        }
                    }
                }
                Write-Host ""
                Write-Log "Removed $systemFilesRemoved system files" "SUCCESS"
            }
        } else {
            Write-Log "Could not identify GPU - skipped system file cleanup" "WARN"
        }

        Write-Host ""; Write-Box "GPU REMOVAL COMPLETE" "-"
        Write-Log "GPU partition removed" "SUCCESS"; Write-Log "MMIO settings reset" "SUCCESS"; Write-Log "All driver files cleaned" "SUCCESS"
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
        Write-Host "  Note: Driver files (if any) remain in the VM disk" -ForegroundColor Yellow
        Write-Host ""; return $true
    } finally { if ($mount) { Show-Spinner "Unmounting VM disk..." 1; Dismount-VMDisk -Mount $mount -VHDPath $vhdPath } }
}
#endregion


#region Driver Injection
function Install-GPUDrivers {
    param([string]$VMName)

    if (!$VMName) { $vm = Select-VM -Title "SELECT VM FOR DRIVERS" -RequiredState "Any"; if (!$vm) { return $false }; $VMName = $vm.Name }

    # Check if VM has GPU partition assigned
    $gpuAdapter = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if (!$gpuAdapter) {
        Write-Box "GPU DRIVER INJECTION" "-"
        Write-Log "No GPU partition assigned to VM: $VMName" "ERROR"
        Write-Host ""
        Write-Host "  You must assign a GPU partition before installing drivers." -ForegroundColor Yellow
        Write-Host "  Use the 'GPU Partition' menu option first." -ForegroundColor Cyan
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    # Get GPU info from partition
    $gpuName = Get-GPUFriendlyName $gpuAdapter.InstancePath
    if (!$gpuName) { $gpuName = "GPU" }

    Write-Box "GPU DRIVER INJECTION"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Log "Detected GPU: $gpuName" "SUCCESS"
    Write-Host ""

    # Find matching GPU on host
    $gpu = Find-GPUByVenDev $gpuAdapter.InstancePath
    if (!$gpu) {
        Write-Log "Could not find matching GPU driver on host" "ERROR"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) {
        Write-Log "No VHD found" "ERROR"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    if (!(Ensure-VMOff -VMName $VMName)) { return $false }

    $mount = $null
    try {
        $drivers = Get-DriverFiles -GPU $gpu
        if (!$drivers) {
            Write-Host ""
            Read-Host "  Press Enter to continue"
            return $false
        }
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
            Write-Host "  The VM disk could not be mounted - install Windows first, then run driver injection." -ForegroundColor Yellow
        } else {
            Write-Log "Failed: $($_.Exception.Message)" "ERROR"
        }
        Write-Host ""
        Read-Host "  Press Enter to continue"
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

    # Collect all VM data
    $vmData = @()
    foreach ($vm in $vms) {
        $size = 0
        try {
            $vhd = Get-VHD -VMId $vm.VMId -EA SilentlyContinue
            if ($vhd) { $size = [math]::Round($vhd.Size / 1GB) }
        } catch {}
        $mem = if ($vm.MemoryAssigned -gt 0) { $vm.MemoryAssigned } else { $vm.MemoryStartup }

        $stateMap = @{Running=@{Icon="[*]"; Color="Green"}; Off=@{Icon="[ ]"; Color="Gray"}}
        $state = $stateMap[$vm.State]
        if (!$state) { $state = @{Icon="[~]"; Color="Yellow"} }
        $stateIcon = $state.Icon
        $color = $state.Color

        $gpuInfo = "None"
        $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -EA SilentlyContinue
        if ($gpuAdapter) {
            $gpuName = (Get-GPUFriendlyName $gpuAdapter.InstancePath)
            if (!$gpuName) { $gpuName = "GPU" }
            $gpuPct = try { "$([math]::Round($gpuAdapter.MaxPartitionVRAM / 1e9 * 100))%" } catch { "?" }
            $gpuInfo = "$gpuName ($gpuPct)"
        }

        $vmData += [PSCustomObject]@{
            Icon = $stateIcon
            Name = $vm.Name
            State = $vm.State
            CPU = $vm.ProcessorCount
            RAM = [math]::Round($mem / 1GB)
            Storage = $size
            GPU = $gpuInfo
            RowColor = $color
        }
    }

    # Display table using reusable Write-Table function
    Write-Table -Data $vmData -Columns @(
        @{Header=""; Property="Icon"; Color="RowColor"},
        @{Header="VM Name"; Property="Name"; Color="RowColor"},
        @{Header="State"; Property="State"; Color="RowColor"},
        @{Header="CPU"; Property="CPU"; Color="RowColor"},
        @{Header="RAM(GB)"; Property="RAM"; Color="RowColor"},
        @{Header="Storage"; Property="Storage"; Color="RowColor"},
        @{Header="GPU"; Property="GPU"; Color="RowColor"}
    )

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

    # Collect all GPU data
    $gpuData = @()
    $i = 1
    foreach ($gpu in $gpus) {
        $isOK = $gpu.Status -eq 'OK'
        $statusIcon = if ($isOK) { '[OK]' } else { '[X]' }
        $statusColor = if ($isOK) { 'Green' } else { 'Yellow' }

        # Check if GPU is partitionable
        $isPartitionable = $gpu.PNPDeviceID -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})" -and
            ($partitionableGPUs | Where-Object { $_.Name -match "VEN_$($matches[1]).*DEV_$($matches[2])" })
        $partitionStatus = if ($isPartitionable) { "Yes" } else { "No" }
        $partitionColor = if ($isPartitionable) { "Cyan" } else { "DarkGray" }

        # Get provider name
        $providerName = if ($gpu.DriverProviderName) { $gpu.DriverProviderName.Trim() }
        elseif ($gpu.AdapterCompatibility) { $gpu.AdapterCompatibility.Trim() }
        elseif ($gpu.Name -match "(NVIDIA|AMD|Intel|ATI)") { $matches[1] }
        elseif ($gpu.InfSection -match "nv|nvidia") { "NVIDIA" }
        elseif ($gpu.InfSection -match "ati|amd") { "AMD" }
        elseif ($gpu.InfSection -match "intel") { "Intel" }
        else { "Unknown" }

        $gpuData += [PSCustomObject]@{
            Index = $i
            IndexColor = "Yellow"
            StatusIcon = $statusIcon
            StatusColor = $statusColor
            Name = $gpu.Name
            NameColor = "White"
            Driver = if ($gpu.DriverVersion) { $gpu.DriverVersion.Trim() } else { "Unknown" }
            DriverColor = "White"
            Provider = $providerName
            ProviderColor = "White"
            Partitionable = $partitionStatus
            PartitionColor = $partitionColor
        }
        $i++
    }

    # Display table using reusable Write-Table function
    Write-Table -Data $gpuData -Columns @(
        @{Header="#"; Property="Index"; Color="IndexColor"},
        @{Header="Status"; Property="StatusIcon"; Color="StatusColor"},
        @{Header="GPU Name"; Property="Name"; Color="NameColor"},
        @{Header="Driver Version"; Property="Driver"; Color="DriverColor"},
        @{Header="Provider"; Property="Provider"; Color="ProviderColor"},
        @{Header="Partitionable"; Property="Partitionable"; Color="PartitionColor"}
    )

    Write-Host ""
    Read-Host "  Press Enter"
}
#endregion


#region VM Deletion
function Remove-GpuVM {
    param([string]$VMName)

    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM TO DELETE" -RequiredState "Any"
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }

    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    Write-Box "DELETE VM: $VMName"
    Write-Log "VM: $VMName" "INFO"
    Write-Log "State: $($vm.State)" "INFO"

    # Get associated files
    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    $dvdDrive = Get-VMDvdDrive $VMName -EA SilentlyContinue
    $isoPath = if ($dvdDrive) { $dvdDrive.Path } else { $null }

    # Check if ISO is in our auto-install directory
    $autoInstallISO = $null
    if ($isoPath -and (Test-Path $isoPath)) {
        $isoDir = Split-Path -Parent $isoPath
        if ($isoDir -eq $script:ISOPath) {
            $autoInstallISO = $isoPath
            Write-Log "Auto-install ISO: $autoInstallISO" "INFO"
        } else {
            Write-Log "External ISO: $isoPath (will not be deleted)" "INFO"
        }
    }

    if ($vhdPath) { Write-Log "VHD: $vhdPath" "INFO" }

    Write-Host ""
    Write-Host "  WARNING: This will permanently delete the VM!" -ForegroundColor Yellow
    Write-Host ""

    if (!(Confirm "Delete VM '$VMName'?")) {
        Write-Log "Cancelled" "WARN"
        return $false
    }

    # Ask about file deletion
    $deleteFiles = $false

    if ($vhdPath -or $autoInstallISO) {
        Write-Host ""
        if (Confirm "Also delete associated files?") {
            $deleteFiles = $true
        }
    }

    Write-Host ""

    # Stop VM if running
    if ($vm.State -ne "Off") {
        if (!(Ensure-VMOff -VMName $VMName)) {
            Write-Log "Failed to stop VM" "ERROR"
            Write-Host ""
            Read-Host "  Press Enter to continue"
            return $false
        }
    }

    # Remove GPU partition if exists
    $hasGPU = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if ($hasGPU) {
        Show-Spinner "Removing GPU partition..." 1
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue
        Write-Log "GPU partition removed" "SUCCESS"
    }

    # Remove VM
    Show-Spinner "Removing VM..." 2
    if (!(Invoke-Safe -Op "Remove VM" -Code {
        Remove-VM $VMName -Force -EA Stop
        Write-Log "VM removed successfully" "SUCCESS"
    }).Success) {
        Write-Host ""
        Read-Host "  Press Enter to continue"
        return $false
    }

    # Delete files if requested
    if ($deleteFiles) {
        Write-Host ""
        if ($vhdPath -and (Test-Path $vhdPath)) {
            Show-Spinner "Deleting VHD..." 2
            Invoke-Safe -Op "Delete VHD" -Code {
                Remove-Item $vhdPath -Force -EA Stop
                Write-Log "VHD deleted: $vhdPath" "SUCCESS"
            } | Out-Null
        }
        if ($autoInstallISO -and (Test-Path $autoInstallISO)) {
            Show-Spinner "Deleting auto-install ISO..." 1
            Invoke-Safe -Op "Delete ISO" -Code {
                Remove-Item $autoInstallISO -Force -EA Stop
                Write-Log "ISO deleted: $autoInstallISO" "SUCCESS"
            } | Out-Null
        }
    }

    Write-Host ""
    Write-Box "VM DELETED SUCCESSFULLY" "-"
    Write-Log "VM '$VMName' has been removed" "SUCCESS"
    if ($deleteFiles) {
        Write-Log "Associated files deleted" "SUCCESS"
    } else {
        if ($vhdPath) { Write-Log "VHD preserved: $vhdPath" "INFO" }
        if ($autoInstallISO) { Write-Log "ISO preserved: $autoInstallISO" "INFO" }
    }
    Write-Host ""

    return $true
}
#endregion


#region Main Menu
$menuItems = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Delete VM", "List VMs", "GPU Info", "Exit")

while ($true) {
    $choice = Select-Menu -Items $menuItems -Title "MAIN MENU"
    if ($choice -eq $null) { Write-Log "Cancelled" "INFO"; continue }
    Write-Host ""

    switch ($choice) {
        0 { New-GpuVM -Config (Get-VMConfig) | Out-Null; Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        2 { Remove-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        3 { Install-GPUDrivers | Out-Null; Read-Host "`n  Press Enter" }
        4 { Remove-GpuVM | Out-Null; Read-Host "`n  Press Enter" }
        5 { Show-VmInfo }
        6 { Show-GpuInfo }
        7 { Write-Log "Goodbye!" "INFO"; exit }
    }
}
#endregion
