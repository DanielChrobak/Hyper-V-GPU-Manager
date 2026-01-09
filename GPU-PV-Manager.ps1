if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

#region Config & Helpers
$script:Paths = @{VHD="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"; Mount="C:\ProgramData\HyperV-Mounts"; ISO="C:\ProgramData\HyperV-ISOs"}
$script:GPUReg = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$script:Presets = @(
    @{L="Gaming | 8CPU, 16GB, 256GB"; N="Gaming-VM"; C=8; R=16; S=256},
    @{L="Development | 4CPU, 8GB, 128GB"; N="Dev-VM"; C=4; R=8; S=128},
    @{L="ML Training | 12CPU, 32GB, 512GB"; N="ML-VM"; C=12; R=32; S=512}
)

function Log($M, $L="INFO") {
    $c = @{INFO="Cyan"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; HEADER="Magenta"}
    $i = @{INFO=">"; SUCCESS="+"; WARN="!"; ERROR="X"; HEADER="~"}
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $($i[$L]) $M" -ForegroundColor $c[$L]
}

function Box($T, $S="=", $W=80) {
    $w = [Math]::Min(140, [Math]::Max($W, [Math]::Max(40, $T.Length + 6)))
    $t = if ($T.Length -gt ($w - 6)) { $T.Substring(0, $w - 9) + "..." } else { $T }
    $b = if ($S -eq "=") { "=" } else { "-" }
    $c = if ($S -eq "=") { "Yellow" } else { "White" }
    Write-Host "`n  +$($b * ($w - 4))+`n  | $($t.PadRight($w - 6)) |`n  +$($b * ($w - 4))+" -ForegroundColor Cyan
    if ($S -eq "=") { Write-Host "" }
}

function Spin($M, $D=2, $Cond=$null, $Timeout=60, $SuccessMsg=$null) {
    $s = '|','/','-','\'
    if ($Cond) {
        for ($i = 0; $i -lt $Timeout; $i++) {
            if (& $Cond) { Write-Host "`r  + $(if ($SuccessMsg) { $SuccessMsg } else { $M })             " -ForegroundColor Green; return $true }
            Write-Host "`r  $($s[$i % 4]) $M ($i sec)" -ForegroundColor Cyan -NoNewline
            Start-Sleep -Milliseconds 500
        }
        Write-Host "`r  X $M - Timeout" -ForegroundColor Red; return $false
    }
    1..$D | ForEach-Object { Write-Host "`r  $($s[$_ % 4]) $M" -ForegroundColor Cyan -NoNewline; Start-Sleep -Milliseconds 150 }
    Write-Host "`r  + $M" -ForegroundColor Green
}

function Try-Op($Code, $Op, $Ok=$null, $OnFail=$null) {
    try { $r = & $Code; if ($Ok) { Log $Ok "SUCCESS" }; return @{OK=$true; R=$r} }
    catch { Log "$Op failed: $_" "ERROR"; if ($OnFail) { & $OnFail }; return @{OK=$false; E=$_} }
}

function EnsureDir($P) { if (!(Test-Path $P)) { New-Item $P -ItemType Directory -Force -EA SilentlyContinue | Out-Null } }

function Confirm($M) { (Read-Host "  $M (Y/N)") -match "^[Yy]$" }

function Pause { Read-Host "`n  Press Enter to continue" }

function Input($P, $V={$true}, $D=$null) {
    do { $i = Read-Host "  $P"
        if (!$i -and $D) { return $D }
        if (& $V $i) { return $i }
        Log "Invalid input" "WARN"
    } while ($true)
}

function Table($Data, $Cols) {
    if (!$Data) { return }
    $widths = $Cols | ForEach-Object { $p = $_.P; [Math]::Max($_.H.Length, ($Data | ForEach-Object { "$($_.$p)".Length } | Measure-Object -Max).Maximum) }
    $sep = "  +" + (($widths | ForEach-Object { '-' * ($_ + 2) }) -join '+') + "+"
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ("  |" + (($Cols | ForEach-Object -Begin {$j=0} { " $($_.H.PadRight($widths[$j++])) " }) -join '|') + "|") -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan
    foreach ($r in $Data) {
        Write-Host "  |" -ForegroundColor Cyan -NoNewline
        for ($j = 0; $j -lt $Cols.Count; $j++) {
            $v = "$($r.($Cols[$j].P))"; $c = if ($Cols[$j].C -and $r.($Cols[$j].C)) { $r.($Cols[$j].C) } else { "White" }
            Write-Host " $($v.PadRight($widths[$j])) " -ForegroundColor $c -NoNewline
            Write-Host "|" -ForegroundColor Cyan -NoNewline
        }
        Write-Host ""
    }
    Write-Host $sep -ForegroundColor Cyan
}

function Menu($Items, $Title="MENU") {
    Clear-Host
    Write-Host "`n  +============================================================================+`n  |                       GPU VIRTUALIZATION MANAGER                           |`n  |                Partition and manage GPUs for Hyper-V VMs                   |`n  +============================================================================+`n" -ForegroundColor Cyan
    $w = [Math]::Max(60, ($Items | ForEach-Object { $_.Length } | Measure-Object -Max).Maximum + 10)
    $sep = "  +$('-' * ($w - 2))+"
    Write-Host "$sep`n  | $Title$(' ' * ($w - 4 - $Title.Length)) |`n$sep`n  | Use UP/DOWN, ENTER to select, ESC to cancel$(' ' * ($w - 49)) |`n$sep" -ForegroundColor Cyan
    $top = [Console]::CursorTop
    $Items | ForEach-Object { Write-Host "  |     $_$(' ' * ($w - 9 - $_.Length)) |" -ForegroundColor White }
    Write-Host "$sep`n"
    $sel = 0; $last = -1
    while ($true) {
        if ($sel -ne $last) {
            if ($last -ge 0) { [Console]::SetCursorPosition(0, $top + $last); Write-Host "  |     $($Items[$last])$(' ' * ($w - 9 - $Items[$last].Length)) |" -ForegroundColor White }
            [Console]::SetCursorPosition(0, $top + $sel); Write-Host "  | >>  $($Items[$sel])$(' ' * ($w - 9 - $Items[$sel].Length)) |" -ForegroundColor Green
            $last = $sel
        }
        switch ([Console]::ReadKey($true).Key) {
            "UpArrow" { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            "DownArrow" { $sel = ($sel + 1) % $Items.Count }
            "Enter" { [Console]::SetCursorPosition(0, $top + $Items.Count + 2); return $sel }
            "Escape" { [Console]::SetCursorPosition(0, $top + $Items.Count + 2); return $null }
        }
    }
}
#endregion

#region GPU Helpers
function GetPartitionableGPUs {
    # Try Windows 11 cmdlet first, fall back to Windows 10 cmdlet
    $gpus = $null
    try { $gpus = @(Get-VMHostPartitionableGpu -EA Stop) } catch {}
    if (!$gpus) { try { $gpus = @(Get-VMPartitionableGpu -EA Stop) } catch {} }
    return $gpus
}

function GPUName($Path) {
    if (!$Path -or $Path -notmatch "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") { return $null }
    (Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.PNPDeviceID -like "*VEN_$($matches[1])*DEV_$($matches[2])*" } | Select-Object -First 1).Name
}

function FindGPU($Path) {
    if ($Path -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") {
        Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" -and $_.DeviceID -like "*VEN_$($matches[1])*DEV_$($matches[2])*" } | Select-Object -First 1
    }
}

function SelectGPU($Title="SELECT GPU", [switch]$Partition) {
    Box $Title
    if ($Partition) {
        $gpus = GetPartitionableGPUs
        if (!$gpus) { Log "No partitionable GPUs found" "ERROR"; Write-Host ""; return $null }
        $list = @(); $i = 0
        foreach ($g in $gpus) {
            $p = if ($g.Name) { $g.Name } else { $g.Id }
            $n = (GPUName $p); if (!$n) { $n = "GPU-$i" }
            $list += [PSCustomObject]@{I=$i; P=$p; N=$n}
            Write-Host "  [$($i + 1)] $n" -ForegroundColor Green; $i++
        }
    } else {
        $gpus = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
        if (!$gpus) { Log "No GPUs found" "ERROR"; return $null }
        $i = 1; foreach ($g in $gpus) { Write-Host "  [$i] $($g.DeviceName)" -ForegroundColor Green; Write-Host "      Provider: $($g.DriverProviderName) | Version: $($g.DriverVersion)" -ForegroundColor DarkGray; $i++ }
        $list = $gpus
    }
    Write-Host ""
    while ($true) {
        $s = Read-Host "  Enter GPU # (1-$($list.Count))"
        if ([int]::TryParse($s, [ref]$null) -and [int]$s -ge 1 -and [int]$s -le $list.Count) {
            $pick = $list[[int]$s - 1]
            if ($Partition) { Log "Selected: $($pick.N)" "SUCCESS"; Write-Host "" }
            return $pick
        }
        Log "Enter 1-$($list.Count)" "WARN"
    }
}

function GetDrivers($GPU) {
    Box "ANALYZING GPU DRIVERS" "-"
    Log "GPU: $($GPU.DeviceName)" "INFO"
    Log "Provider: $($GPU.DriverProviderName) | Version: $($GPU.DriverVersion)" "INFO"; Write-Host ""
    Spin "Finding INF file..." 1
    $inf = Get-ChildItem $script:GPUReg -EA SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        if ($p.MatchingDeviceId -and ($GPU.DeviceID -like "*$($p.MatchingDeviceId)*" -or $p.MatchingDeviceId -like "*$($GPU.DeviceID)*")) { $p.InfPath }
    } | Select-Object -First 1
    if (!$inf) { Log "GPU not found in registry" "ERROR"; return $null }
    $infPath = "C:\Windows\INF\$inf"
    if (!(Test-Path $infPath)) { Log "INF file missing: $infPath" "ERROR"; return $null }
    Log "Found: $inf" "SUCCESS"
    Spin "Parsing driver files..." 1
    $content = Get-Content $infPath -Raw
    $refs = @('\.sys','\.dll','\.exe','\.cat','\.inf','\.bin','\.vp','\.cpa') | ForEach-Object { [regex]::Matches($content, "[\w\-\.]+$_", 2) | ForEach-Object { $_.Value } } | Sort-Object -Unique
    Log "Found $($refs.Count) file references" "SUCCESS"; Write-Host ""
    Spin "Locating files on disk..." 2
    $search = @(@{P="C:\Windows\System32\DriverStore\FileRepository"; T="Store"; R=$true}, @{P="C:\Windows\System32"; T="Sys"; R=$false}, @{P="C:\Windows\SysWow64"; T="Wow"; R=$false})
    $files = @(); $folders = @()
    foreach ($r in $refs) {
        foreach ($sp in $search) {
            $f = Get-ChildItem -Path $sp.P -Filter $r -Recurse:$sp.R -EA SilentlyContinue | Select-Object -First 1
            if ($f) {
                if ($sp.T -eq "Store") { if ($f.DirectoryName -notin $folders) { $folders += $f.DirectoryName } }
                else { $files += [PSCustomObject]@{N=$r; S=$f.FullName; D=$f.FullName.Replace("C:","")} }
                break
            }
        }
    }
    Log "Located $($files.Count) files + $($folders.Count) folders" "SUCCESS"; Write-Host ""
    return @{Files=$files; Folders=$folders}
}
#endregion

#region VHD Operations
function SecureDir($P) {
    if (Test-Path $P) { return }
    New-Item $P -ItemType Directory -Force -EA Stop | Out-Null
    $acl = Get-Acl $P
    $acl.SetAccessRuleProtection($true, $false)
    @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators") | ForEach-Object {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($_, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    Set-Acl $P $acl
}

function MountVHD($VHD) {
    SecureDir $script:Paths.Mount
    $mp = Join-Path $script:Paths.Mount "VMMount_$(Get-Random)"
    $disk = $null; $part = $null
    try {
        SecureDir $mp; Spin "Mounting virtual disk..." 2
        $disk = Mount-VHD $VHD -NoDriveLetter -PassThru -EA Stop
        Start-Sleep 2; Update-Disk $disk.DiskNumber -EA SilentlyContinue
        $part = Get-Partition -DiskNumber $disk.DiskNumber -EA Stop | Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        if (!$part) { throw "No valid partition found" }
        Spin "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mp
        if (!(Test-Path "$mp\Windows")) { throw "Windows folder not found - is Windows installed?" }
        return @{Disk=$disk; Part=$part; Path=$mp; VHD=$VHD}
    } catch {
        if ($part -and $disk) { Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mp -EA SilentlyContinue }
        if ($disk) { Dismount-VHD $VHD -EA SilentlyContinue }
        if (Test-Path $mp) { Remove-Item $mp -Recurse -Force -EA SilentlyContinue }
        throw
    }
}

function UnmountVHD($M, $VHD) {
    if ($M) {
        if ($M.Disk -and $M.Part -and $M.Path) { Remove-PartitionAccessPath -DiskNumber $M.Disk.DiskNumber -PartitionNumber $M.Part.PartitionNumber -AccessPath $M.Path -EA SilentlyContinue }
        if ($M.VHD) { Dismount-VHD $M.VHD -EA SilentlyContinue }
        if ($M.Path -and (Test-Path $M.Path)) { Remove-Item $M.Path -Recurse -Force -EA SilentlyContinue }
    }
    if ($VHD) { Dismount-VHD $VHD -EA SilentlyContinue }
}
#endregion

#region VM Helpers
function SelectVM($Title="SELECT VM", $State="Any") {
    Box $Title
    $vms = @(Get-VM | Where-Object { $State -eq "Any" -or $_.State -eq $State })
    if (!$vms) { Log "No $(if ($State -ne 'Any') { "$State " })VMs found" "ERROR"; Write-Host ""; return $null }
    $items = @($vms | ForEach-Object {
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $ga = Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue
        $gp = if ($ga) { "$([math]::Round($ga.MaxPartitionVRAM / 1e9 * 100))%" } else { "None" }
        $si = switch ($_.State) { "Running" { "[*]" } "Off" { "[ ]" } default { "[~]" } }
        $sc = switch ($_.State) { "Running" { "[Running]" } "Off" { "[Stopped]" } default { "[$($_.State)]" } }
        "$si $($_.Name.PadRight(20)) $sc CPU:$($_.ProcessorCount) RAM:$([math]::Round($mem / 1GB))GB GPU:$gp"
    }) + "< Cancel >"
    $sel = Menu -Items $items -Title $Title
    if ($sel -eq $null -or $sel -eq ($items.Count - 1)) { return $null }
    return $vms[$sel]
}

function StopVM($Name) {
    $vm = Get-VM $Name -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }
    Log "VM is running - attempting graceful shutdown..." "WARN"
    return (Try-Op {
        Stop-VM $Name -Force -EA Stop
        if (Spin "Shutting down VM" -Cond { (Get-VM $Name).State -eq "Off" } -Timeout 60 -SuccessMsg "VM shut down") { Start-Sleep 2; return $true }
        Stop-VM $Name -TurnOff -Force -EA Stop; Start-Sleep 3; return $true
    } "Stop VM").OK
}

function EnsureOff($Name) {
    $v = Get-VM $Name -EA SilentlyContinue
    if (!$v) { Log "VM not found: $Name" "ERROR"; return $false }
    return ($v.State -eq "Off") -or (StopVM $Name)
}
#endregion

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

#region Main Functions
function NewVM {
    $items = @($script:Presets | ForEach-Object { $_.L }) + "Custom"
    $ch = Menu -Items $items -Title "VM CONFIG"
    if ($ch -eq $null) { return $null }
    if ($ch -lt 3) {
        $p = $script:Presets[$ch]; Write-Host ""
        $name = Read-Host "  Name (default: $($p.N))"; $iso = Read-Host "  ISO path (press Enter to skip)"; Write-Host ""
        $cfg = @{Name=if ($name) { $name } else { $p.N }; CPU=$p.C; RAM=$p.R; Storage=$p.S; Path=$script:Paths.VHD; ISO=$iso}
    } else {
        Box "CUSTOM CONFIG" "-"
        $cfg = @{
            Name = Input "VM Name" { ![string]::IsNullOrWhiteSpace($_) }
            CPU = [int](Input "CPU Cores" { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
            RAM = [int](Input "RAM (GB)" { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
            Storage = [int](Input "Storage (GB)" { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
            Path = $script:Paths.VHD; ISO = Read-Host "  ISO path (press Enter to skip)"
        }
    }
    $iso = $null
    if ($cfg.ISO -and (Test-Path $cfg.ISO)) {
        Write-Host ""
        if (Confirm "Enable automated Windows installation? (Skips most setup screens)") {
            $iso = NewAutoISO $cfg.ISO $cfg.Name
            if ($iso) { Log "Will use automated installation ISO" "SUCCESS"; Write-Host "" }
            else { Log "Falling back to original ISO" "WARN"; $iso = $cfg.ISO; Write-Host "" }
        } else { $iso = $cfg.ISO }
    }
    Box "CREATING VM"; Log "VM: $($cfg.Name) | CPU: $($cfg.CPU) | RAM: $($cfg.RAM)GB | Storage: $($cfg.Storage)GB" "INFO"; Write-Host ""
    $vhd = Join-Path $cfg.Path "$($cfg.Name).vhdx"
    if (Get-VM $cfg.Name -EA SilentlyContinue) { Log "VM already exists" "ERROR"; return $null }
    if ((Test-Path $vhd) -and !(Confirm "VHDX exists. Overwrite?")) { Log "Cancelled" "WARN"; return $null }
    if (Test-Path $vhd) { Remove-Item $vhd -Force }
    $r = Try-Op {
        Spin "Creating VM..." 2; EnsureDir $cfg.Path
        New-VM -Name $cfg.Name -MemoryStartupBytes ([int64]$cfg.RAM * 1GB) -Generation 2 -NewVHDPath $vhd -NewVHDSizeBytes ([int64]$cfg.Storage * 1GB) | Out-Null
        Spin "Configuring..." 1
        Set-VMProcessor $cfg.Name -Count $cfg.CPU
        Set-VMMemory $cfg.Name -DynamicMemoryEnabled $false
        Set-VM $cfg.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -AutomaticCheckpointsEnabled $false
        Spin "Finalizing..." 1
        if ((Get-VM $cfg.Name).State -ne "Off") { Stop-VM $cfg.Name -Force -EA SilentlyContinue; while ((Get-VM $cfg.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 } }
        Set-VMFirmware $cfg.Name -EnableSecureBoot On; Set-VMKeyProtector $cfg.Name -NewLocalKeyProtector; Enable-VMTPM $cfg.Name
        if ($iso -and (Test-Path $iso)) {
            Add-VMDvdDrive $cfg.Name -Path $iso
            $dvd = Get-VMDvdDrive $cfg.Name; $hdd = Get-VMHardDiskDrive $cfg.Name
            if ($dvd -and $hdd) { Set-VMFirmware $cfg.Name -BootOrder $dvd, $hdd }
            Log "ISO attached" "SUCCESS"
        }
        Write-Host ""; Box "VM CREATED: $($cfg.Name)" "-"
        Log "CPU: $($cfg.CPU) | RAM: $($cfg.RAM)GB | Storage: $($cfg.Storage)GB" "SUCCESS"; Write-Host ""
        return $cfg.Name
    } "VM Creation"
    return if ($r.OK) { $r.R } else { $null }
}

function SetGPU($VMName=$null, $Pct=0, $GPUPath=$null, $GPUName=$null) {
    if (!$VMName) { $vm = SelectVM "GPU PARTITION VM"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Log "VM not found" "ERROR"; Write-Host ""; Pause; return $false }
    if (!$GPUPath) { $g = SelectGPU "SELECT GPU FOR PARTITIONING" -Partition; if (!$g) { return $false }; $GPUPath = $g.P; $GPUName = $g.N }
    if ($Pct -eq 0) { Write-Host ""; $Pct = [int](Input "GPU % to allocate (1-100)" { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 }) }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (!$GPUName) { $GPUName = (GPUName $GPUPath); if (!$GPUName) { $GPUName = "GPU" } }
    Box "GPU PARTITION"; Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"; Write-Host ""
    if (!(EnsureOff $VMName)) { Write-Host ""; Pause; return $false }
    $r = Try-Op {
        Spin "Configuring GPU partition..." 2
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue
        Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $GPUPath
        $max = [int](($Pct / 100) * 1e9); $opt = $max - 1
        Set-VMGpuPartitionAdapter $VMName -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        Write-Host ""; Box "GPU ALLOCATED: $Pct%" "-"; Write-Host ""; return $true
    } "GPU Config"
    if (!$r.OK) { Write-Host ""; Pause }
    return $r.OK
}

function RemoveGPU($VMName=$null) {
    if (!$VMName) { $vm = SelectVM "REMOVE GPU FROM VM"; if (!$vm) { return $false }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Log "VM not found" "ERROR"; Write-Host ""; Pause; return $false }
    if (!(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)) { Log "No GPU partition found on this VM" "WARN"; Write-Host ""; Pause; return $false }
    Box "REMOVE GPU PARTITION"; Log "Target VM: $VMName" "INFO"; Write-Host ""
    if (!(Confirm "Remove GPU partition and clean all driver files?")) { Log "Cancelled" "WARN"; return $false }
    Write-Host ""; if (!(EnsureOff $VMName)) { return $false }
    $ga = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    $gpu = if ($ga) { FindGPU $ga.InstancePath } else { $null }
    Spin "Removing GPU partition adapter..." 2
    if (!(Try-Op { Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA Stop; Log "GPU partition adapter removed" "SUCCESS" } "Remove GPU Adapter").OK) { Write-Host ""; Pause; return $false }
    Spin "Resetting memory-mapped IO settings..." 1
    if (!(Try-Op { Set-VM $VMName -GuestControlledCacheTypes $false -LowMemoryMappedIoSpace 0 -HighMemoryMappedIoSpace 0 -EA Stop; Log "Memory-mapped IO settings reset" "SUCCESS" } "Reset MMIO").OK) { Write-Host ""; Pause; return $false }
    $vhd = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhd) { Log "No VHD found - skipping driver cleanup" "WARN"; Write-Host ""; Box "GPU REMOVAL COMPLETE" "-"; Log "GPU partition and MMIO settings removed" "SUCCESS"; Write-Host ""; return $true }
    $mount = $null
    try {
        Write-Host ""; Spin "Mounting VM disk to clean drivers..." 2
        $mount = MountVHD $vhd
        $store = "$($mount.Path)\Windows\System32\HostDriverStore"
        if (Test-Path $store) {
            Spin "Removing driver repository files..." 2
            $fc = if (Test-Path "$store\FileRepository") { (Get-ChildItem "$store\FileRepository" -Recurse -File -EA SilentlyContinue | Measure-Object).Count } else { 0 }
            $dc = if (Test-Path "$store\FileRepository") { (Get-ChildItem "$store\FileRepository" -Directory -EA SilentlyContinue | Measure-Object).Count } else { 0 }
            Remove-Item "$store\*" -Recurse -Force -EA SilentlyContinue
            Log "Removed $fc files from $dc driver folders" "SUCCESS"
        } else { Log "HostDriverStore not found" "INFO" }
        if ($gpu) {
            Write-Host ""; Log "Removing system driver files..." "INFO"
            $drv = GetDrivers $gpu
            if ($drv -and $drv.Files) {
                $removed = 0
                foreach ($f in $drv.Files) {
                    $fp = "$($mount.Path)$($f.D)"
                    if (Test-Path $fp) { Remove-Item $fp -Force -EA SilentlyContinue; if (!(Test-Path $fp)) { $removed++; Log "- $($f.N)" "SUCCESS" } }
                }
                Write-Host ""; Log "Removed $removed system files" "SUCCESS"
            }
        } else { Log "Could not identify GPU - skipped system file cleanup" "WARN" }
        Write-Host ""; Box "GPU REMOVAL COMPLETE" "-"
        Log "GPU partition removed" "SUCCESS"; Log "MMIO settings reset" "SUCCESS"; Log "All driver files cleaned" "SUCCESS"
        Write-Host ""; return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - Windows may not be installed yet.`n" -ForegroundColor Yellow
        } else { Log "Driver cleanup failed: $($_.Exception.Message)" "WARN" }
        Write-Host ""; Box "GPU REMOVAL PARTIAL" "-"
        Log "GPU partition and MMIO settings removed successfully" "SUCCESS"
        Log "Driver cleanup skipped - could not access VM disk" "WARN"
        Write-Host "  Note: Driver files (if any) remain in the VM disk" -ForegroundColor Yellow
        Write-Host ""; return $true
    } finally { if ($mount) { Spin "Unmounting VM disk..." 1; UnmountVHD $mount $vhd } }
}

function InstallDrivers($VMName=$null) {
    if (!$VMName) { $vm = SelectVM "SELECT VM FOR DRIVERS"; if (!$vm) { return $false }; $VMName = $vm.Name }
    $ga = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if (!$ga) {
        Box "GPU DRIVER INJECTION" "-"; Log "No GPU partition assigned to VM: $VMName" "ERROR"; Write-Host ""
        Write-Host "  You must assign a GPU partition before installing drivers." -ForegroundColor Yellow
        Write-Host "  Use the 'GPU Partition' menu option first." -ForegroundColor Cyan; Write-Host ""; Pause; return $false
    }
    $gn = GPUName $ga.InstancePath; if (!$gn) { $gn = "GPU" }
    Box "GPU DRIVER INJECTION"; Log "Target VM: $VMName" "INFO"; Log "Detected GPU: $gn" "SUCCESS"; Write-Host ""
    $gpu = FindGPU $ga.InstancePath
    if (!$gpu) { Log "Could not find matching GPU driver on host" "ERROR"; Write-Host ""; Pause; return $false }
    $vhd = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhd) { Log "No VHD found" "ERROR"; Write-Host ""; Pause; return $false }
    if (!(EnsureOff $VMName)) { return $false }
    $mount = $null
    try {
        $drv = GetDrivers $gpu
        if (!$drv) { Write-Host ""; Pause; return $false }
        $mount = MountVHD $vhd
        Spin "Preparing destination..." 1
        $store = "$($mount.Path)\Windows\System32\HostDriverStore\FileRepository"
        EnsureDir $store
        Log "Copying $($drv.Folders.Count) driver folders..." "INFO"; Write-Host ""
        foreach ($f in $drv.Folders) {
            $n = Split-Path -Leaf $f; $d = Join-Path $store $n
            EnsureDir (Split-Path -Parent $d)
            $r = Try-Op { Copy-Item $f $d -Force -Recurse -EA Stop; Log "+ $n" "SUCCESS"; return $true } "Copy $n"
            if ($r.OK) { Write-Host "      ($((Get-ChildItem $d -Recurse -File -EA SilentlyContinue | Measure-Object).Count) files)" -ForegroundColor DarkGray }
            else { Log "! $n skipped" "WARN" }
        }
        Write-Host ""; Log "Copying $($drv.Files.Count) system files..." "INFO"
        foreach ($f in $drv.Files) {
            $dst = "$($mount.Path)$($f.D)"; EnsureDir (Split-Path -Parent $dst)
            Try-Op { Copy-Item $f.S $dst -Force -EA Stop; Log "+ $($f.N)" "SUCCESS" } "Copy $($f.N)" | Out-Null
        }
        Write-Host ""; Box "DRIVER INJECTION COMPLETE" "-"
        Log "Injected $($drv.Files.Count) files + $($drv.Folders.Count) folders" "SUCCESS"
        Write-Host ""; return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - install Windows first, then run driver injection." -ForegroundColor Yellow
        } else { Log "Failed: $($_.Exception.Message)" "ERROR" }
        Write-Host ""; Pause; return $false
    } finally { if ($mount) { Spin "Unmounting VM disk..." 1; UnmountVHD $mount $vhd } }
}

function ShowVMs {
    Box "VM OVERVIEW"; Log "Gathering VM information..." "INFO"; Write-Host ""
    $vms = Get-VM
    if (!$vms) { Log "No VMs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }
    $data = @($vms | ForEach-Object {
        $sz = 0; try { $v = Get-VHD -VMId $_.VMId -EA SilentlyContinue; if ($v) { $sz = [math]::Round($v.Size / 1GB) } } catch {}
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $st = @{Running=@{I="[*]";C="Green"}; Off=@{I="[ ]";C="Gray"}}[$_.State]
        if (!$st) { $st = @{I="[~]";C="Yellow"} }
        $gi = "None"; $ga = Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue
        if ($ga) { $gn = (GPUName $ga.InstancePath); if (!$gn) { $gn = "GPU" }; $gp = try { "$([math]::Round($ga.MaxPartitionVRAM / 1e9 * 100))%" } catch { "?" }; $gi = "$gn ($gp)" }
        [PSCustomObject]@{Icon=$st.I; Name=$_.Name; State=$_.State; CPU=$_.ProcessorCount; RAM=[math]::Round($mem / 1GB); Storage=$sz; GPU=$gi; RC=$st.C}
    })
    Table $data @(@{H="";P="Icon";C="RC"},@{H="VM Name";P="Name";C="RC"},@{H="State";P="State";C="RC"},@{H="CPU";P="CPU";C="RC"},@{H="RAM(GB)";P="RAM";C="RC"},@{H="Storage";P="Storage";C="RC"},@{H="GPU";P="GPU";C="RC"})
    Write-Host ""; Read-Host "  Press Enter"
}

function ShowGPUs {
    Box "GPU INFORMATION"; Log "Detecting GPUs..." "INFO"; Write-Host ""
    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if (!$gpus) { Log "No GPUs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }
    $pg = GetPartitionableGPUs
    $i = 1; $data = @($gpus | ForEach-Object {
        $ok = $_.Status -eq 'OK'; $si = if ($ok) { '[OK]' } else { '[X]' }; $sc = if ($ok) { 'Green' } else { 'Yellow' }
        $ip = $_.PNPDeviceID -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})" -and ($pg | Where-Object { $_.Name -match "VEN_$($matches[1]).*DEV_$($matches[2])" })
        $ps = if ($ip) { "Yes" } else { "No" }; $pc = if ($ip) { "Cyan" } else { "DarkGray" }
        $pn = if ($_.DriverProviderName) { $_.DriverProviderName.Trim() } elseif ($_.AdapterCompatibility) { $_.AdapterCompatibility.Trim() }
             elseif ($_.Name -match "(NVIDIA|AMD|Intel|ATI)") { $matches[1] } elseif ($_.InfSection -match "nv|nvidia") { "NVIDIA" }
             elseif ($_.InfSection -match "ati|amd") { "AMD" } elseif ($_.InfSection -match "intel") { "Intel" } else { "Unknown" }
        [PSCustomObject]@{Idx=$i++; IC="Yellow"; SI=$si; SC=$sc; N=$_.Name; NC="White"; D=if ($_.DriverVersion) { $_.DriverVersion.Trim() } else { "Unknown" }; DC="White"; P=$pn; PC="White"; Part=$ps; PartC=$pc}
    })
    Table $data @(@{H="#";P="Idx";C="IC"},@{H="Status";P="SI";C="SC"},@{H="GPU Name";P="N";C="NC"},@{H="Driver Version";P="D";C="DC"},@{H="Provider";P="P";C="PC"},@{H="Partitionable";P="Part";C="PartC"})
    Write-Host ""; Read-Host "  Press Enter"
}

function DeleteVM($VMName=$null) {
    if (!$VMName) { $vm = SelectVM "SELECT VM TO DELETE"; if (!$vm) { return $false }; $VMName = $vm.Name }
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) { Log "VM not found: $VMName" "ERROR"; Write-Host ""; Pause; return $false }
    Box "DELETE VM: $VMName"; Log "VM: $VMName" "INFO"; Log "State: $($vm.State)" "INFO"
    $vhd = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    $dvd = Get-VMDvdDrive $VMName -EA SilentlyContinue
    $isoPath = if ($dvd) { $dvd.Path } else { $null }
    $autoISO = $null
    if ($isoPath -and (Test-Path $isoPath)) {
        $dir = Split-Path -Parent $isoPath
        if ($dir -eq $script:Paths.ISO) { $autoISO = $isoPath; Log "Auto-install ISO: $autoISO" "INFO" }
        else { Log "External ISO: $isoPath (will not be deleted)" "INFO" }
    }
    if ($vhd) { Log "VHD: $vhd" "INFO" }
    Write-Host "`n  WARNING: This will permanently delete the VM!`n" -ForegroundColor Yellow
    if (!(Confirm "Delete VM '$VMName'?")) { Log "Cancelled" "WARN"; return $false }
    $delFiles = $false
    if ($vhd -or $autoISO) { Write-Host ""; if (Confirm "Also delete associated files?") { $delFiles = $true } }
    Write-Host ""
    if ($vm.State -ne "Off") { if (!(EnsureOff $VMName)) { Log "Failed to stop VM" "ERROR"; Write-Host ""; Pause; return $false } }
    $hasGPU = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if ($hasGPU) { Spin "Removing GPU partition..." 1; Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue; Log "GPU partition removed" "SUCCESS" }
    Spin "Removing VM..." 2
    if (!(Try-Op { Remove-VM $VMName -Force -EA Stop; Log "VM removed successfully" "SUCCESS" } "Remove VM").OK) { Write-Host ""; Pause; return $false }
    if ($delFiles) {
        Write-Host ""
        if ($vhd -and (Test-Path $vhd)) { Spin "Deleting VHD..." 2; Try-Op { Remove-Item $vhd -Force -EA Stop; Log "VHD deleted: $vhd" "SUCCESS" } "Delete VHD" | Out-Null }
        if ($autoISO -and (Test-Path $autoISO)) { Spin "Deleting auto-install ISO..." 1; Try-Op { Remove-Item $autoISO -Force -EA Stop; Log "ISO deleted: $autoISO" "SUCCESS" } "Delete ISO" | Out-Null }
    }
    Write-Host ""; Box "VM DELETED SUCCESSFULLY" "-"; Log "VM '$VMName' has been removed" "SUCCESS"
    if ($delFiles) { Log "Associated files deleted" "SUCCESS" }
    else { if ($vhd) { Log "VHD preserved: $vhd" "INFO" }; if ($autoISO) { Log "ISO preserved: $autoISO" "INFO" } }
    Write-Host ""; return $true
}
#endregion

#region Main Loop
$menu = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Delete VM", "List VMs", "GPU Info", "Exit")
while ($true) {
    $ch = Menu $menu "MAIN MENU"
    if ($ch -eq $null) { Log "Cancelled" "INFO"; continue }
    Write-Host ""
    switch ($ch) {
        0 { NewVM | Out-Null; Pause }
        1 { SetGPU | Out-Null; Pause }
        2 { RemoveGPU | Out-Null; Pause }
        3 { InstallDrivers | Out-Null; Pause }
        4 { DeleteVM | Out-Null; Pause }
        5 { ShowVMs }
        6 { ShowGPUs }
        7 { Log "Goodbye!" "INFO"; exit }
    }
}
#endregion
