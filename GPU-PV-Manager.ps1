if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

#region Core UI & Logging

$script:Colors = @{INFO='Cyan'; SUCCESS='Green'; WARN='Yellow'; ERROR='Red'; HEADER='Magenta'}
$script:Icons = @{INFO='>'; SUCCESS='+'; WARN='!'; ERROR='X'; HEADER='~'}
$script:Spinner = @('|', '/', '-', '\')

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $($script:Icons[$Level]) $Message" -ForegroundColor $script:Colors[$Level]
}

function Write-Box { param([string]$Text, [string]$Style = "=", [int]$Width = 80)
    Write-Host "`n  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    Write-Host "  |  $($Text.PadRight($Width - 6))|" -ForegroundColor Cyan
    Write-Host "  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    if ($Style -eq "=") { Write-Host "" }
}

function Show-Banner { Clear-Host
    Write-Host "`n  GPU Virtualization Manager" -ForegroundColor Magenta
    Write-Host "  Manage and partition GPUs for Hyper-V virtual machines`n" -ForegroundColor Magenta
}

function Show-Spinner {
    param([string]$Message, [int]$Duration = 2, [scriptblock]$Condition = $null, [int]$TimeoutSeconds = 60, [string]$SuccessMessage = $null)
    if ($Condition) {
        for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
            if (& $Condition) {
                $msg = if ($SuccessMessage) { $SuccessMessage } else { $Message }
                Write-Host "`r  + $msg             " -ForegroundColor Green
                return $true
            }
            Write-Host "`r  $($script:Spinner[$i % 4]) $Message ($i sec)" -ForegroundColor Cyan -NoNewline
            Start-Sleep -Milliseconds 500
        }
        Write-Host "`r  X $Message - Timeout" -ForegroundColor Red
        return $false
    }
    1..$Duration | ForEach-Object {
        Write-Host "`r  $($script:Spinner[$_ % 4]) $Message" -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`r  + $Message" -ForegroundColor Green
}

function Invoke-WithErrorHandling {
    param([scriptblock]$ScriptBlock, [string]$OperationName, [string]$SuccessMessage = $null, [scriptblock]$OnError = $null)
    try {
        $result = & $ScriptBlock
        if ($SuccessMessage) { Write-Log $SuccessMessage "SUCCESS" }
        return @{Success=$true; Result=$result}
    } catch {
        Write-Log "$OperationName failed: $_" "ERROR"
        if ($OnError) { & $OnError }
        return @{Success=$false; Error=$_}
    }
}

#endregion

#region Menu & Selection

function Select-Menu {
    param([string[]]$Items, [string]$Title = "MENU")
    $selected = 0; $last = -1
    Show-Banner
    Write-Host "  > $Title`n  |  Use UP/DOWN arrows, ENTER to select, ESC to cancel`n  |" -ForegroundColor Cyan
    $menuStart = [Console]::CursorTop
    $Items | ForEach-Object { Write-Host "  |     $_" -ForegroundColor White }
    Write-Host "  |`n  >$('=' * 76)`n" -ForegroundColor Cyan
    while ($true) {
        if ($selected -ne $last) {
            if ($last -ge 0) {
                [Console]::SetCursorPosition(0, $menuStart + $last)
                Write-Host "  |     $($Items[$last])" -ForegroundColor White
            }
            [Console]::SetCursorPosition(0, $menuStart + $selected)
            Write-Host "  |  >> $($Items[$selected])" -ForegroundColor Green
            $last = $selected
        }
        switch ([Console]::ReadKey($true).Key) {
            "UpArrow" { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
            "DownArrow" { $selected = ($selected + 1) % $Items.Count }
            "Enter" { [Console]::SetCursorPosition(0, $menuStart + $Items.Count + 2); return $selected }
            "Escape" { [Console]::SetCursorPosition(0, $menuStart + $Items.Count + 2); return $null }
        }
    }
}

function Get-ValidatedInput {
    param([string]$Prompt, [scriptblock]$Validator = {$true}, [string]$ErrorMessage = "Invalid input.", [string]$DefaultValue = $null)
    do {
        $input = Read-Host "  $Prompt"
        if ([string]::IsNullOrWhiteSpace($input) -and $DefaultValue) { return $DefaultValue }
        if (& $Validator $input) { return $input }
        Write-Log $ErrorMessage "WARN"
    } while ($true)
}

function Confirm-Action {
    param([string]$Message, [bool]$DefaultYes = $false)
    $resp = Read-Host "  $Message (Y/N)"
    return if ($DefaultYes) { $resp -notmatch "^[Nn]$" } else { $resp -match "^[Yy]$" }
}

#endregion

#region VM Operations

function Select-VM {
    param([string]$Title = "SELECT VM", [bool]$AllowRunning = $false)
    Write-Box $Title
    $vms = @(Get-VM | Where-Object { $AllowRunning -or $_.State -eq 'Off' })
    if (!$vms -or $vms.Count -eq 0) {
        Write-Log "No $(if (!$AllowRunning) { 'stopped ' })VMs found" "ERROR"
        Write-Host ""
        return $null
    }
    $items = @() + ($vms | ForEach-Object {
        $m = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $g = (Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue) | ForEach-Object { "$([math]::Round($_.MaxPartitionVRAM / 1.0e+09 * 100, 0))%" }
        "$($_.Name) | $($_.State) | $([math]::Round($m / 1GB, 0))GB | CPU: $($_.ProcessorCount) | GPU: $(if ($g) { $g } else { 'None' })"
    }) + "< Cancel >"
    $sel = Select-Menu -Items $items -Title $Title
    if ($sel -eq $null -or $sel -eq ($items.Count - 1)) {
        return $null
    } else {
        return $vms[$sel]
    }
}

function Stop-VMSafe {
    param([string]$VMName)
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }
    $r = Invoke-WithErrorHandling -OperationName "Stop VM" -ScriptBlock {
        Stop-VM $VMName -Force -EA Stop
        $ok = Show-Spinner -Message "Shutting down VM" -Condition { (Get-VM $VMName).State -eq "Off" } -TimeoutSeconds 60 -SuccessMessage "VM shut down"
        if ($ok) { Start-Sleep -Seconds 2; return $true }
        Stop-VM $VMName -TurnOff -Force -EA Stop; Start-Sleep -Seconds 3; return $true
    }
    return $r.Success
}

function Test-VMState {
    param([string]$VMName, [string]$RequiredState = "Off")
    $v = Get-VM $VMName -EA SilentlyContinue
    if (!$v) { Write-Log "VM not found: $VMName" "ERROR"; return $false }
    if ($v.State -ne $RequiredState -and $RequiredState -eq "Off") { return Stop-VMSafe -VMName $VMName }
    return $v.State -eq $RequiredState
}

#endregion

#region Disk Operations

function Mount-VMDisk {
    param([string]$VHDPath)
    $mp = "C:\Temp\VMMount_$(Get-Random)"
    $r = Invoke-WithErrorHandling -OperationName "Mount VHD" -ScriptBlock {
        New-Item $mp -ItemType Directory -Force | Out-Null
        Show-Spinner "Mounting virtual disk..." 2
        $m = Mount-VHD $VHDPath -NoDriveLetter -PassThru -EA Stop
        Start-Sleep -Seconds 2
        Update-Disk $m.DiskNumber -EA SilentlyContinue
        $p = Get-Partition -DiskNumber $m.DiskNumber -EA Stop | Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        if (!$p) { throw "No valid partition" }
        Show-Spinner "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $m.DiskNumber -PartitionNumber $p.PartitionNumber -AccessPath $mp
        if (!(Test-Path "$mp\Windows")) { throw "Windows not found" }
        return @{Mounted=$m; Partition=$p; MountPoint=$mp}
    }
    if ($r.Success) { return $r.Result }; throw $r.Error
}

function Dismount-VMDisk {
    param($MountInfo, [string]$VHDPath)
    if ($MountInfo.Mounted -and $MountInfo.Partition) {
        Remove-PartitionAccessPath -DiskNumber $MountInfo.Mounted.DiskNumber -PartitionNumber $MountInfo.Partition.PartitionNumber -AccessPath $MountInfo.MountPoint -EA SilentlyContinue
    }
    if ($VHDPath) { Dismount-VHD $VHDPath -EA SilentlyContinue }
    if ($MountInfo.MountPoint) { Remove-Item $MountInfo.MountPoint -Recurse -Force -EA SilentlyContinue }
}

function New-DirectorySafe {
    param([string]$Path)
    if (!(Test-Path $Path)) { New-Item -Path $Path -ItemType Directory -Force -EA SilentlyContinue | Out-Null }
}

#endregion

#region GPU Operations

function Get-GPUNameFromInstancePath {
    param([string]$InstancePath)
    if ([string]::IsNullOrWhiteSpace($InstancePath) -or $InstancePath -notmatch 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') { return $null }
    $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.PNPDeviceID -like "*VEN_$($matches[1])*" -and $_.PNPDeviceID -like "*DEV_$($matches[2])*" } | Select-Object -First 1
    if ($gpu -and $gpu.Name) {
        return $gpu.Name
    } else {
        return $null
    }
}

function Select-GPUDevice {
    Write-Box "SELECT GPU DEVICE"
    $gpus = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
    if (!$gpus -or $gpus.Count -eq 0) { Write-Log "No GPUs found" "ERROR"; return $null }
    $gpus | ForEach-Object -Begin { $i=1 } { Write-Host "  [$i] $($_.DeviceName)" -ForegroundColor Green
        Write-Host "      Provider: $($_.DriverProviderName) | Version: $($_.DriverVersion)" -ForegroundColor DarkGray; $i++ }
    Write-Host ""
    while ($true) {
        $sel = Read-Host "  Enter GPU # (1-$($gpus.Count))"
        if ([int]::TryParse($sel, [ref]$null) -and [int]$sel -ge 1 -and [int]$sel -le $gpus.Count) { return $gpus[[int]$sel - 1] }
        Write-Log "Enter 1-$($gpus.Count)" "WARN"
    }
}

function Select-GPUForPartition {
    Write-Box "SELECT GPU FOR PARTITIONING"
    $gpus = @(Get-VMHostPartitionableGpu -EA SilentlyContinue)
    if (!$gpus -or $gpus.Count -eq 0) { Write-Log "No assignable GPUs" "ERROR"; Write-Host ""; return $null }

    $lst = @()
    $gpus | ForEach-Object -Begin { $i=0 } {
        $ip = if ([string]::IsNullOrWhiteSpace($_.Name)) { $_.Id } else { $_.Name }
        $fn = Get-GPUNameFromInstancePath -InstancePath $ip
        if (!$fn) { $fn = "GPU-$i" }
        $lst += [PSCustomObject]@{Index=$i; InstancePath=$ip; FriendlyName=$fn}
        Write-Host "  [$($i + 1)] $fn" -ForegroundColor Green
        Write-Host "      Path: $ip" -ForegroundColor DarkGray
        $i++
    }
    Write-Host ""
    while ($true) {
        $sel = Read-Host "  Enter GPU # (1-$($lst.Count))"
        if ([int]::TryParse($sel, [ref]$null) -and [int]$sel -ge 1 -and [int]$sel -le $lst.Count) {
            $s = $lst[[int]$sel - 1]
            Write-Log "Selected: $($s.FriendlyName)" "SUCCESS"
            Write-Host ""
            return $s
        }
        Write-Log "Enter 1-$($lst.Count)" "WARN"
    }
}

function Copy-ItemWithLogging {
    param([string]$Src, [string]$Dst, [string]$Name, [bool]$Rec = $false)
    New-DirectorySafe -Path (Split-Path -Parent $Dst)
    $r = Invoke-WithErrorHandling -OperationName "Copy $Name" -ScriptBlock {
        $p = @{Path=$Src; Destination=$Dst; Force=$true; EA='Stop'}
        if ($Rec) { $p['Recurse']=$true }
        Copy-Item @p
        Write-Log "+ $Name" "SUCCESS"
        return $true
    } -OnError { Write-Log "! $Name`: Skipped" "WARN" }
    return $r.Success
}

function Get-DriverFiles {
    param([Object]$GPU)
    Write-Box "ANALYZING GPU DRIVERS" "-"
    Write-Log "GPU: $($GPU.DeviceName)" "INFO"
    Write-Log "Provider: $($GPU.DriverProviderName) | Version: $($GPU.DriverVersion)" "INFO"; Write-Host ""

    Show-Spinner "Finding INF..." 1
    $rp = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $inf = (Get-ChildItem -Path $rp -EA SilentlyContinue | ForEach-Object {
        $pr = Get-ItemProperty -Path $_.PSPath -EA SilentlyContinue
        if ($pr.MatchingDeviceId -and ($GPU.DeviceID -like "*$($pr.MatchingDeviceId)*" -or $pr.MatchingDeviceId -like "*$($GPU.DeviceID)*")) {
            Write-Log "Found: $($pr.InfPath)" "SUCCESS"
            $pr.InfPath
        }
    }) | Select-Object -First 1

    if (!$inf) { Write-Log "GPU not in registry" "ERROR"; return $null }
    $ip = "C:\Windows\INF\$inf"
    if (!(Test-Path $ip)) { Write-Log "INF not found: $ip" "ERROR"; return $null }

    Show-Spinner "Reading INF..." 1
    $ic = Get-Content $ip -Raw
    Show-Spinner "Parsing files..." 1

    $fp = @('[\w\-\.]+\.sys','[\w\-\.]+\.dll','[\w\-\.]+\.exe','[\w\-\.]+\.cat','[\w\-\.]+\.inf','[\w\-\.]+\.bin','[\w\-\.]+\.vp','[\w\-\.]+\.cpa')
    $rf = @()
    $fp | ForEach-Object {
        [regex]::Matches($ic, $_, 2) | ForEach-Object { $rf += $_.Value }
    }
    $rf = $rf | Sort-Object -Unique
    Write-Log "Found $($rf.Count) references" "SUCCESS"; Write-Host ""
    Show-Spinner "Locating files..." 2

    $sp = @(
        @{P="C:\Windows\System32\DriverStore\FileRepository"; T="DriverStore"; R=$true},
        @{P="C:\Windows\System32"; T="System32"; R=$false},
        @{P="C:\Windows\SysWow64"; T="SysWow64"; R=$false}
    )
    $ff = @(); $df = @()

    $rf | ForEach-Object {
        $fn = $_; $fd = $false
        foreach ($s in $sp) {
            if ($fd) { break }
            $sa = @{Path=$s.P; Filter=$fn; EA='SilentlyContinue'}
            if ($s.R) { $sa['Recurse']=$true }
            $res = Get-ChildItem @sa | Select-Object -First 1
            if ($res) {
                $fd = $true
                if ($s.T -eq "DriverStore") {
                    if ($res.DirectoryName -notin $df) { $df += $res.DirectoryName }
                } else {
                    $ff += [PSCustomObject]@{FileName=$fn; FullPath=$res.FullName; DestPath=$res.FullName.Replace("C:","")}
                }
            }
        }
    }

    Write-Log "Located $($ff.Count) files + $($df.Count) folders" "SUCCESS"; Write-Host ""
    return @{Files=$ff; StoreFolders=$df}
}

#endregion

#region VM Configuration

function Get-VMConfig {
    $pre = @("Gaming | 16GB, 8CPU, 256GB", "Development | 8GB, 4CPU, 128GB", "ML Training | 32GB, 12CPU, 512GB", "Custom")
    $pd = @(@{N="Gaming-VM"; R=16; C=8; S=256}, @{N="Dev-VM"; R=8; C=4; S=128}, @{N="ML-VM"; R=32; C=12; S=512})
    $ch = Select-Menu -Items $pre -Title "VM CONFIG"
    if ($ch -eq $null) { return $null }
    if ($ch -lt 3) {
        $pt = $pd[$ch]
        Write-Host ""
        $nm = Read-Host "  Name (default: $($pt.N))"
        $iso = Read-Host "  ISO (skip)"
        Write-Host ""
        return @{Name=$(if ($nm) { $nm } else { $pt.N }); RAM=$pt.R; CPU=$pt.C; Storage=$pt.S; Path="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"; ISO=$iso}
    }
    Write-Box "CUSTOM CONFIG" "-"
    return @{
        Name=(Get-ValidatedInput -Prompt "VM Name" -Validator { ![string]::IsNullOrWhiteSpace($_) })
        RAM=[int](Get-ValidatedInput -Prompt "RAM (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        CPU=[int](Get-ValidatedInput -Prompt "CPU Cores" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Storage=[int](Get-ValidatedInput -Prompt "Storage (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Path="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
        ISO=(Read-Host "  ISO (skip)")
    }
}

function Initialize-VM {
    param($Config)
    if (!$Config) { Write-Log "Cancelled" "WARN"; return $null }
    Write-Box "CREATING VM"
    Write-Log "VM: $($Config.Name) | RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "INFO"; Write-Host ""

    $vh = Join-Path $Config.Path "$($Config.Name).vhdx"
    if (Get-VM $Config.Name -EA SilentlyContinue) { Write-Log "VM exists" "ERROR"; return $null }
    if (Test-Path $vh) {
        if (!(Confirm-Action "VHDX exists. Overwrite?")) { Write-Log "Cancelled" "WARN"; return $null }
        Remove-Item $vh -Force
    }

    $r = Invoke-WithErrorHandling -OperationName "VM Creation" -ScriptBlock {
        Show-Spinner "Creating..." 2
        New-DirectorySafe -Path $Config.Path
        New-VM -Name $Config.Name -MemoryStartupBytes ([int64]$Config.RAM * 1GB) -Generation 2 -NewVHDPath $vh -NewVHDSizeBytes ([int64]$Config.Storage * 1GB) | Out-Null
        Show-Spinner "Configuring..." 1
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -AutomaticCheckpointsEnabled $false
        Set-VMHost -EnableEnhancedSessionMode $false
        Disable-VMIntegrationService $Config.Name -Name "Guest Service Interface", "VSS"
        Show-Spinner "Finalizing..." 1
        Stop-VM $Config.Name -Force -EA SilentlyContinue
        while ((Get-VM $Config.Name).State -ne "Off") { Start-Sleep -Milliseconds 500 }
        Set-VMFirmware $Config.Name -EnableSecureBoot On
        Set-VMKeyProtector $Config.Name -NewLocalKeyProtector
        Enable-VMTPM $Config.Name
        if ($Config.ISO -and (Test-Path $Config.ISO)) {
            Add-VMDvdDrive $Config.Name -Path $Config.ISO
            $d = Get-VMDvdDrive $Config.Name; $h = Get-VMHardDiskDrive $Config.Name
            if ($d -and $h) { Set-VMFirmware $Config.Name -BootOrder $d, $h }
            Write-Log "ISO attached" "SUCCESS"
        }
        Write-Host ""
        Write-Box "VM CREATED: $($Config.Name)" "-"
        Write-Log "RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "SUCCESS"; Write-Host ""
        return $Config.Name
    }
    if ($r.Success) {
        return $r.Result
    } else {
        return $null
    }
}

function Set-GPUPartition {
    param([string]$VMName, [int]$Pct = 0, [string]$Path = $null, [string]$GPUName = $null)
    if (!$VMName) {
        $v = Select-VM -Title "GPU PARTITION VM" -AllowRunning $false
        if (!$v) { return $false }
        $VMName = $v.Name
    }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Write-Log "VM not found" "ERROR"; return $false }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $g = Select-GPUForPartition
        if (!$g) { Write-Log "No GPU selected" "ERROR"; return $false }
        $Path = $g.InstancePath
        $GPUName = $g.FriendlyName
    }

    if ($Pct -eq 0) {
        Write-Host ""
        $Pct = [int](Get-ValidatedInput -Prompt "GPU % (1-100)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 })
    }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (!$GPUName) { $GPUName = Get-GPUNameFromInstancePath -InstancePath $Path; if (!$GPUName) { $GPUName = "GPU" } }

    Write-Box "GPU PARTITION"
    Write-Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"
    Write-Log "Path: $Path" "INFO"; Write-Host ""

    if (!(Test-VMState -VMName $VMName)) { Write-Log "Failed to stop VM" "ERROR"; return $false }

    $r = Invoke-WithErrorHandling -OperationName "GPU Config" -ScriptBlock {
        Show-Spinner "Configuring..." 2
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue
        Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $Path
        $m = [int](($Pct / 100) * 1.0e+09); $o = $m - 1
        Set-VMGpuPartitionAdapter $VMName -MinPartitionVRAM 1 -MaxPartitionVRAM $m -OptimalPartitionVRAM $o `
            -MinPartitionEncode 1 -MaxPartitionEncode $m -OptimalPartitionEncode $o `
            -MinPartitionDecode 1 -MaxPartitionDecode $m -OptimalPartitionDecode $o `
            -MinPartitionCompute 1 -MaxPartitionCompute $m -OptimalPartitionCompute $o
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        Write-Host ""; Write-Box "GPU: $Pct%" "-"; Write-Host ""
        return $true
    }
    return $r.Success
}

function Install-GPUDrivers {
    param([string]$VMName)
    if (!$VMName) {
        $v = Select-VM -Title "DRIVER VM" -AllowRunning $false
        if (!$v) { return $false }
        $VMName = $v.Name
    }
    $v = Get-VM $VMName -EA SilentlyContinue
    if (!$v) { Write-Log "VM not found" "ERROR"; return $false }
    $vh = (Get-VMHardDiskDrive $VMName).Path
    if (!$vh) { Write-Log "No VHD" "ERROR"; return $false }

    Write-Box "GPU DRIVERS"
    Write-Log "Target: $VMName" "INFO"; Write-Host ""
    if (!(Test-VMState -VMName $VMName)) { Write-Log "Failed to stop VM" "ERROR"; return $false }

    try {
        $g = Select-GPUDevice
        if (!$g) { return $false }
        Write-Host ""
        $d = Get-DriverFiles -GPU $g
        if (!$d) { return $false }

        $mi = Mount-VMDisk -VHDPath $vh
        $mp = $mi.MountPoint
        Show-Spinner "Preparing..." 1
        $hds = "$mp\Windows\System32\HostDriverStore\FileRepository"
        New-DirectorySafe -Path $hds

        Write-Log "Copying $($d.StoreFolders.Count) folders..." "INFO"; Write-Host ""
        $d.StoreFolders | ForEach-Object {
            $fn = Split-Path -Leaf $_
            $df = Join-Path $hds $fn
            if (Copy-ItemWithLogging -Src $_ -Dst $df -Name $fn -Rec $true) {
                $c = (Get-ChildItem -Path $df -Recurse -File -EA SilentlyContinue | Measure-Object).Count
                Write-Host "      ($c files)" -ForegroundColor DarkGray
            }
        }

        Write-Host ""
        Write-Log "Copying $($d.Files.Count) files..." "INFO"
        $d.Files | ForEach-Object {
            $dp = "$mp$($_.DestPath)"
            Copy-ItemWithLogging -Src $_.FullPath -Dst $dp -Name $_.FileName | Out-Null
        }

        Write-Host ""
        Write-Box "INJECTION COMPLETE" "-"
        Write-Log "Injected $($d.Files.Count) files + $($d.StoreFolders.Count) folders" "SUCCESS"; Write-Host ""
        return $true
    } catch {
        if ($_.Exception.Message -match "partition") {
            Write-Log "Windows not installed" "ERROR"
            Write-Host "  Install Windows in VM first, then run driver injection.`n" -ForegroundColor Yellow
        } else {
            Write-Log "Failed: $_" "ERROR"
        }
        return $false
    } finally {
        Dismount-VMDisk -MountInfo $mi -VHDPath $vh
    }
}

function Copy-VMApps {
    $v = Select-VM -Title "APP COPY VM" -AllowRunning $false
    if (!$v) { return $false }
    $vh = (Get-VMHardDiskDrive $v.Name).Path
    if (!$vh) { Write-Log "No VHD" "ERROR"; return $false }

    Write-Box "COPY VM APPS"
    Write-Log "Target: $($v.Name)" "INFO"; Write-Host ""

    $af = Join-Path (Split-Path -Parent $PSCommandPath) "VM Apps"
    if (!(Test-Path $af)) { Write-Log "Apps folder not found" "ERROR"; return $false }
    $zf = Get-ChildItem $af -Filter "*.zip" -File
    if (!$zf) { Write-Log "No zips" "WARN"; return $false }
    Write-Log "Found $($zf.Count) app(s)" "INFO"; Write-Host ""
    if (!(Test-VMState -VMName $v.Name)) { Write-Log "Failed" "ERROR"; return $false }

    try {
        $mi = Mount-VMDisk -VHDPath $vh
        $mp = $mi.MountPoint
        Show-Spinner "Detecting user..." 1
        $up = Get-ChildItem "$mp\Users" -Directory -EA SilentlyContinue | Where-Object { $_.Name -notin @("Public","Administrator","Default","Default.migrated") } | Select-Object -First 1
        if (!$up) { Write-Log "No user" "ERROR"; return $false }

        $dp = "$mp\Users\$($up.Name)\Downloads\VM Apps"
        New-DirectorySafe -Path $dp
        Write-Log "Copying..." "INFO"
        $ok = ($zf | ForEach-Object { if (Copy-ItemWithLogging -Src $_.FullName -Dst $dp -Name $_.Name) { 1 } else { 0 } } | Measure-Object -Sum).Sum

        Write-Host ""
        Write-Box "COPIED: $ok/$($zf.Count)" "-"
        Write-Log "Location: Users\$($up.Name)\Downloads\VM Apps" "INFO"; Write-Host ""
        return $true
    } catch {
        Write-Log "Failed: $_" "ERROR"; return $false
    } finally {
        Dismount-VMDisk -MountInfo $mi -VHDPath $vh
    }
}

function Invoke-CompleteSetup {
    Write-Log "Starting setup..." "HEADER"; Write-Host ""
    $c = Get-VMConfig
    if (!$c) { Write-Log "Cancelled" "WARN"; return }
    $vm = Initialize-VM -Config $c
    if (!$vm) { return }
    Write-Host ""

    $g = Select-GPUForPartition
    if (!$g) { Write-Log "Cancelled" "WARN"; return }
    $gp = Get-ValidatedInput -Prompt "GPU % (default: 50)" -Validator { [string]::IsNullOrWhiteSpace($_) -or ([int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100) } -DefaultValue "50"
    $gr = Set-GPUPartition -VMName $vm -Pct ([int]$gp) -Path $g.InstancePath -GPUName $g.FriendlyName
    if (!$gr) { Write-Log "Failed" "ERROR"; return }

    Write-Host ""
    Write-Box "SETUP: $vm" "-"
    Write-Log "Attempting driver injection..." "INFO"; Write-Host ""

    $dr = Install-GPUDrivers -VMName $vm
    if (!$dr) {
        Write-Log "Could not complete" "WARN"
        Write-Host "Install Windows in VM first, then run injection.`n" -ForegroundColor Yellow
    } else {
        Write-Log "Success!" "SUCCESS"
    }
    Write-Host ""
}

#endregion

#region Information Display

function Show-VmInfo {
    Write-Box "VMs"
    Write-Log "Gathering..." "INFO"; Write-Host ""
    $vms = Get-VM
    if (!$vms) { Write-Log "None" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }

    $l = "+{0}+{1}+{2}+{3}+{4}+{5}+" -f ('-'*20),('-'*10),('-'*9),('-'*9),('-'*11),('-'*9)
    Write-Host "  $l" -ForegroundColor Cyan
    Write-Host ("  | {0,-18} | {1,-8} | {2,-7} | {3,-7} | {4,-9} | {5,-7} |" -f "VM", "State", "RAM(GB)", "CPU", "Storage", "GPU") -ForegroundColor Cyan
    Write-Host "  $l" -ForegroundColor Cyan

    $vms | ForEach-Object {
        $sz = 0
        try { $vi = $_.VMId | Get-VHD -EA SilentlyContinue; if ($vi) { $sz = [math]::Round($vi.Size / 1GB, 0) } } catch {}
        $m = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $sc = if ($_.State -eq "Running") { "Green" } else { "Yellow" }
        $gp = "None"
        $ga = Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue
        if ($ga) { $gp = try { "$([math]::Round($ga.MaxPartitionVRAM / 1.0e+09 * 100, 0))%" } catch { "?" } }
        Write-Host ("  | {0,-18} | {1,-8} | {2,-7} | {3,-7} | {4,-9} | {5,-7} |" -f $_.Name, $_.State, [math]::Round($m / 1GB, 0), $_.ProcessorCount, $sz, $gp) -ForegroundColor $sc
    }
    Write-Host "  $l" -ForegroundColor Cyan; Write-Host ""
    Read-Host "  Press Enter"
}

function Show-GpuInfo {
    Write-Box "GPU INFO"
    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if ($gpus) {
        $gpus | ForEach-Object {
            Write-Host "  GPU: $($_.Name)" -ForegroundColor Green
            Write-Host "  Driver: $($_.DriverVersion) ($($_.DriverDate))" -ForegroundColor Green

            $vg = $null; $vs = "unknown"
            if ($_.Name -like "*NVIDIA*") {
                try { $ns = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null; if ($ns -and $ns -match '^\d+$') { $vg = [math]::Round([int]$ns / 1024, 2); $vs = "nvidia-smi" } } catch {}
            } elseif ($_.Name -like "*AMD*" -or $_.Name -like "*Radeon*") {
                try { $rs = rocm-smi --showmeminfo --showid 2>$null; if ($rs) { $m = $rs | Select-String "GPU Memory:" | Select-Object -First 1; if ($m) { $rm = [regex]::Matches($m.Line, '\d+'); if ($rm.Count -ge 2) { $vg = [math]::Round([int]$rm[1].Value / 1024, 2); $vs = "rocm-smi" } } } } catch {}
            } elseif ($_.Name -like "*Intel*" -or $_.Name -like "*Arc*") {
                try { $ir = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*" -Name "HardwareInformation.qxvram" -EA SilentlyContinue | Select-Object -First 1; if ($ir -and $ir."HardwareInformation.qxvram") { $vg = [math]::Round([int]$ir."HardwareInformation.qxvram" / 1GB, 2); $vs = "registry" } } catch {}
            }

            if (!$vg -or $vg -eq 0) {
                if ($_.AdapterRAM -and $_.AdapterRAM -gt 0) {
                    Write-Host "  VRAM: $([math]::Round($_.AdapterRAM / 1GB, 2)) GB (WMI - may be inaccurate)" -ForegroundColor Yellow
                } else {
                    Write-Host "  VRAM: Unknown" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  VRAM: $vg GB ($vs)" -ForegroundColor Green
            }
            $st = if ($_.Status -eq "OK") { "OK" } else { $_.Status }
            Write-Host "  Status: $st" -ForegroundColor $(if ($st -eq "OK") { "Green" } else { "Yellow" })
            Write-Host ""
        }
    } else {
        Write-Log "No GPU" "WARN"
    }
    Read-Host "  Press Enter"
}

#endregion

#region Main Loop

$items = @("Create VM", "GPU Partition", "Install Drivers", "Complete Setup", "Update Drivers", "List VMs", "GPU Info", "Copy Apps", "Exit")
$idx = 0
while ($true) {
    $idx = Select-Menu -Items $items -Title "MENU"
    if ($idx -eq $null) { Write-Log "Cancelled" "INFO"; continue }
    Write-Host ""
    switch ($idx) {
        0 { Initialize-VM -Config (Get-VMConfig); Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition; Read-Host "`n  Press Enter" }
        2 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        3 { Invoke-CompleteSetup; Read-Host "`n  Press Enter" }
        4 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        5 { Show-VmInfo }
        6 { Show-GpuInfo }
        7 { Copy-VMApps; Read-Host "`n  Press Enter" }
        8 { Write-Log "Exiting" "INFO"; exit }
    }
    $idx = ($idx + 1) % $items.Count
}

#endregion
