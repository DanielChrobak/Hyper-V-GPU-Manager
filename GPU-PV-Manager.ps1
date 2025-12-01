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
$script:GPURegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
#endregion

#region Core UI & Logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $($script:Icons[$Level]) $Message" -ForegroundColor $script:Colors[$Level]
}

function Write-Box { 
    param([string]$Text, [string]$Style = "=", [int]$Width = 80, [int]$MinWidth = 40, [int]$MaxWidth = 140)
    $actualWidth = [Math]::Min($MaxWidth, [Math]::Max($Width, [Math]::Max($MinWidth, $Text.Length + 6)))
    $displayText = if ($Text.Length -gt ($actualWidth - 6)) { $Text.Substring(0, $actualWidth - 9) + "..." } else { $Text }
    Write-Host "`n  +$($Style * ($actualWidth - 4))+" -ForegroundColor Cyan
    Write-Host "  |  $($displayText.PadRight($actualWidth - 6))|" -ForegroundColor Cyan
    Write-Host "  +$($Style * ($actualWidth - 4))+" -ForegroundColor Cyan
    if ($Style -eq "=") { Write-Host "" }
}

function Show-Banner { 
    Clear-Host
    Write-Host "`n  GPU Virtualization Manager" -ForegroundColor Magenta
    Write-Host "  Manage and partition GPUs for Hyper-V virtual machines`n" -ForegroundColor Magenta
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
    1..$Duration | ForEach-Object {
        Write-Host "`r  $($script:Spinner[$_ % 4]) $Message" -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 150
    }
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

function New-Dir { 
    param([string]$Path)
    if (!(Test-Path $Path)) { New-Item $Path -ItemType Directory -Force -EA SilentlyContinue | Out-Null }
}
#endregion

#region Menu System
function Select-Menu {
    param([string[]]$Items, [string]$Title = "MENU")
    $sel = 0; $last = -1
    Show-Banner
    Write-Host "  > $Title`n  |  Use UP/DOWN arrows, ENTER to select, ESC to cancel`n  |" -ForegroundColor Cyan
    $menuTop = [Console]::CursorTop
    $Items | ForEach-Object { Write-Host "  |     $_" -ForegroundColor White }
    Write-Host "  |`n  >$('=' * 76)`n" -ForegroundColor Cyan
    
    while ($true) {
        if ($sel -ne $last) {
            if ($last -ge 0) {
                [Console]::SetCursorPosition(0, $menuTop + $last)
                Write-Host "  |     $($Items[$last])" -ForegroundColor White
            }
            [Console]::SetCursorPosition(0, $menuTop + $sel)
            Write-Host "  |  >> $($Items[$sel])" -ForegroundColor Green
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

function Confirm { 
    param([string]$Msg)
    return (Read-Host "  $Msg (Y/N)") -match "^[Yy]$"
}
#endregion

#region VM Management
function Select-VM {
    param([string]$Title = "SELECT VM", [bool]$AllowRunning = $false)
    Write-Box $Title
    $vms = @(Get-VM | Where-Object { $AllowRunning -or $_.State -eq 'Off' })
    if (!$vms) { Write-Log "No $(if (!$AllowRunning) { 'stopped ' })VMs found" "ERROR"; Write-Host ""; return $null }
    
    $items = @($vms | ForEach-Object {
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $gpu = (Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue) | ForEach-Object { "$([math]::Round($_.MaxPartitionVRAM / 1e9 * 100))%" }
        "$($_.Name) | $($_.State) | $([math]::Round($mem / 1GB))GB | CPU: $($_.ProcessorCount) | GPU: $(if ($gpu) { $gpu } else { 'None' })"
    }) + "< Cancel >"
    
    $sel = Select-Menu -Items $items -Title $Title
    if ($sel -eq $null -or $sel -eq ($items.Count - 1)) { return $null }
    return $vms[$sel]
}

function Stop-VMSafe {
    param([string]$VMName)
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }
    
    $r = Invoke-Safe -Op "Stop VM" -Code {
        Stop-VM $VMName -Force -EA Stop
        $ok = Show-Spinner -Message "Shutting down VM" -Condition { (Get-VM $VMName).State -eq "Off" } -TimeoutSeconds 60 -SuccessMessage "VM shut down"
        if ($ok) { Start-Sleep 2; return $true }
        Stop-VM $VMName -TurnOff -Force -EA Stop
        Start-Sleep 3
        return $true
    }
    return $r.Success
}

function Ensure-VMOff {
    param([string]$VMName)
    $v = Get-VM $VMName -EA SilentlyContinue
    if (!$v) { Write-Log "VM not found: $VMName" "ERROR"; return $false }
    if ($v.State -ne "Off") { return Stop-VMSafe -VMName $VMName }
    return $true
}
#endregion

#region VHD Operations
function New-SecureDir {
    param([string]$Path)
    if (!(Test-Path $Path)) {
        New-Item $Path -ItemType Directory -Force -EA Stop | Out-Null
        $acl = Get-Acl -Path $Path
        $acl.SetAccessRuleProtection($true, $false)
        
        $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "NT AUTHORITY\SYSTEM", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($systemRule)
        
        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($adminRule)
        
        Set-Acl -Path $Path -AclObject $acl
    }
}

function Mount-VMDisk {
    param([string]$VHDPath)
    New-SecureDir -Path $script:MountBasePath
    $mountPoint = Join-Path $script:MountBasePath "VMMount_$(Get-Random)"
    
    $disk = $null
    $part = $null
    
    try {
        New-SecureDir -Path $mountPoint
        Show-Spinner "Mounting virtual disk..." 2
        $disk = Mount-VHD $VHDPath -NoDriveLetter -PassThru -EA Stop
        Start-Sleep 2
        Update-Disk $disk.DiskNumber -EA SilentlyContinue
        
        $part = Get-Partition -DiskNumber $disk.DiskNumber -EA Stop | 
                Where-Object { $_.Size -gt 10GB } | 
                Sort-Object Size -Descending | 
                Select-Object -First 1
        if (!$part) { throw "No valid partition found" }
        
        Show-Spinner "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mountPoint
        if (!(Test-Path "$mountPoint\Windows")) { throw "Windows folder not found - is Windows installed?" }
        
        return @{Disk=$disk; Partition=$part; Path=$mountPoint; VHDPath=$VHDPath}
    } catch {
        if ($part -and $disk) {
            Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mountPoint -EA SilentlyContinue
        }
        if ($disk) {
            Dismount-VHD $VHDPath -EA SilentlyContinue
        }
        if (Test-Path $mountPoint) {
            Remove-Item $mountPoint -Recurse -Force -EA SilentlyContinue
        }
        throw
    }
}

function Dismount-VMDisk {
    param($Mount, [string]$VHDPath)
    
    if ($Mount) {
        if ($Mount.Disk -and $Mount.Partition -and $Mount.Path) {
            Remove-PartitionAccessPath -DiskNumber $Mount.Disk.DiskNumber -PartitionNumber $Mount.Partition.PartitionNumber -AccessPath $Mount.Path -EA SilentlyContinue
        }
        if ($Mount.VHDPath) {
            Dismount-VHD $Mount.VHDPath -EA SilentlyContinue
        }
        if ($Mount.Path -and (Test-Path $Mount.Path)) {
            Remove-Item $Mount.Path -Recurse -Force -EA SilentlyContinue
        }
    }
    
    if ($VHDPath) {
        Dismount-VHD $VHDPath -EA SilentlyContinue
    }
}
#endregion

#region GPU Functions
function Get-GPUFriendlyName {
    param([string]$InstancePath)
    if ([string]::IsNullOrWhiteSpace($InstancePath) -or $InstancePath -notmatch 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') { return $null }
    
    $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | 
           Where-Object { $_.PNPDeviceID -like "*VEN_$($matches[1])*" -and $_.PNPDeviceID -like "*DEV_$($matches[2])*" } | 
           Select-Object -First 1
    
    if ($gpu) { return $gpu.Name } else { return $null }
}

function Select-GPU {
    param([string]$Title = "SELECT GPU", [switch]$ForPartition)
    Write-Box $Title
    
    if ($ForPartition) {
        $gpus = @(Get-VMHostPartitionableGpu -EA SilentlyContinue)
        if (!$gpus) { Write-Log "No partitionable GPUs found" "ERROR"; Write-Host ""; return $null }
        
        $list = @()
        $gpus | ForEach-Object -Begin { $i=0 } {
            $path = if ([string]::IsNullOrWhiteSpace($_.Name)) { $_.Id } else { $_.Name }
            $name = Get-GPUFriendlyName -InstancePath $path
            if (!$name) { $name = "GPU-$i" }
            $list += [PSCustomObject]@{Index=$i; Path=$path; Name=$name}
            Write-Host "  [$($i + 1)] $name" -ForegroundColor Green
            $i++
        }
    } else {
        $gpus = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
        if (!$gpus) { Write-Log "No GPUs found" "ERROR"; return $null }
        
        $gpus | ForEach-Object -Begin { $i=1 } {
            Write-Host "  [$i] $($_.DeviceName)" -ForegroundColor Green
            Write-Host "      Provider: $($_.DriverProviderName) | Version: $($_.DriverVersion)" -ForegroundColor DarkGray
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
        if ($props.MatchingDeviceId -and ($GPU.DeviceID -like "*$($props.MatchingDeviceId)*" -or $props.MatchingDeviceId -like "*$($GPU.DeviceID)*")) {
            Write-Log "Found: $($props.InfPath)" "SUCCESS"
            $props.InfPath
        }
    } | Select-Object -First 1
    
    if (!$inf) { Write-Log "GPU not found in registry" "ERROR"; return $null }
    $infPath = "C:\Windows\INF\$inf"
    if (!(Test-Path $infPath)) { Write-Log "INF file missing: $infPath" "ERROR"; return $null }
    
    Show-Spinner "Parsing driver files..." 1
    $content = Get-Content $infPath -Raw
    $patterns = @('[\w\-\.]+\.sys','[\w\-\.]+\.dll','[\w\-\.]+\.exe','[\w\-\.]+\.cat','[\w\-\.]+\.inf','[\w\-\.]+\.bin','[\w\-\.]+\.vp','[\w\-\.]+\.cpa')
    $refs = @()
    $patterns | ForEach-Object { [regex]::Matches($content, $_, 2) | ForEach-Object { $refs += $_.Value } }
    $refs = $refs | Sort-Object -Unique
    Write-Log "Found $($refs.Count) file references" "SUCCESS"
    Write-Host ""
    
    Show-Spinner "Locating files on disk..." 2
    $searchPaths = @(
        @{Path="C:\Windows\System32\DriverStore\FileRepository"; Type="Store"; Recurse=$true},
        @{Path="C:\Windows\System32"; Type="Sys32"; Recurse=$false},
        @{Path="C:\Windows\SysWow64"; Type="Wow64"; Recurse=$false}
    )
    
    $files = @(); $folders = @()
    foreach ($ref in $refs) {
        foreach ($sp in $searchPaths) {
            $found = Get-ChildItem -Path $sp.Path -Filter $ref -Recurse:$sp.Recurse -EA SilentlyContinue | Select-Object -First 1
            if ($found) {
                if ($sp.Type -eq "Store") {
                    if ($found.DirectoryName -notin $folders) { $folders += $found.DirectoryName }
                } else {
                    $files += [PSCustomObject]@{Name=$ref; Source=$found.FullName; Dest=$found.FullName.Replace("C:","")}
                }
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
    $r = Invoke-Safe -Op "Copy $Name" -Code {
        $params = @{Path=$Src; Destination=$Dst; Force=$true; EA='Stop'}
        if ($Recurse) { $params['Recurse']=$true }
        Copy-Item @params
        Write-Log "+ $Name" "SUCCESS"
        return $true
    } -OnFail { Write-Log "! $Name skipped" "WARN" }
    return $r.Success
}
#endregion

#region VM Creation
$script:VMPresets = @(
    @{Label="Gaming | 16GB, 8CPU, 256GB"; Name="Gaming-VM"; RAM=16; CPU=8; Storage=256},
    @{Label="Development | 8GB, 4CPU, 128GB"; Name="Dev-VM"; RAM=8; CPU=4; Storage=128},
    @{Label="ML Training | 32GB, 12CPU, 512GB"; Name="ML-VM"; RAM=32; CPU=12; Storage=512}
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
        return @{
            Name = if ($name) { $name } else { $preset.Name }
            RAM = $preset.RAM; CPU = $preset.CPU; Storage = $preset.Storage
            Path = $script:VHDPath; ISO = $iso
        }
    }
    
    Write-Box "CUSTOM CONFIG" "-"
    return @{
        Name = Get-Input -Prompt "VM Name" -Validator { ![string]::IsNullOrWhiteSpace($_) }
        RAM = [int](Get-Input -Prompt "RAM (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        CPU = [int](Get-Input -Prompt "CPU Cores" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Storage = [int](Get-Input -Prompt "Storage (GB)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -gt 0 })
        Path = $script:VHDPath
        ISO = Read-Host "  ISO path (press Enter to skip)"
    }
}

function New-GpuVM {
    param($Config)
    if (!$Config) { Write-Log "Cancelled" "WARN"; return $null }
    
    Write-Box "CREATING VM"
    Write-Log "VM: $($Config.Name) | RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "INFO"
    Write-Host ""
    
    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"
    if (Get-VM $Config.Name -EA SilentlyContinue) { Write-Log "VM already exists" "ERROR"; return $null }
    if (Test-Path $vhdPath) {
        if (!(Confirm "VHDX exists. Overwrite?")) { Write-Log "Cancelled" "WARN"; return $null }
        Remove-Item $vhdPath -Force
    }
    
    $r = Invoke-Safe -Op "VM Creation" -Code {
        Show-Spinner "Creating VM..." 2
        New-Dir $Config.Path
        New-VM -Name $Config.Name -MemoryStartupBytes ([int64]$Config.RAM * 1GB) -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes ([int64]$Config.Storage * 1GB) | Out-Null
        
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
            $dvd = Get-VMDvdDrive $Config.Name
            $hdd = Get-VMHardDiskDrive $Config.Name
            if ($dvd -and $hdd) { Set-VMFirmware $Config.Name -BootOrder $dvd, $hdd }
            Write-Log "ISO attached" "SUCCESS"
        }
        
        Write-Host ""
        Write-Box "VM CREATED: $($Config.Name)" "-"
        Write-Log "RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "SUCCESS"
        Write-Host ""
        return $Config.Name
    }
    
    if ($r.Success) { return $r.Result } else { return $null }
}
#endregion

#region GPU Partitioning
function Set-GPUPartition {
    param([string]$VMName, [int]$Pct = 0, [string]$GPUPath = $null, [string]$GPUName = $null)
    
    if (!$VMName) {
        $vm = Select-VM -Title "GPU PARTITION VM"
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Write-Log "VM not found" "ERROR"; return $false }
    
    if (!$GPUPath) {
        $gpu = Select-GPU -Title "SELECT GPU FOR PARTITIONING" -ForPartition
        if (!$gpu) { return $false }
        $GPUPath = $gpu.Path
        $GPUName = $gpu.Name
    }
    
    if ($Pct -eq 0) {
        Write-Host ""
        $Pct = [int](Get-Input -Prompt "GPU % to allocate (1-100)" -Validator { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 })
    }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (!$GPUName) { $GPUName = Get-GPUFriendlyName $GPUPath; if (!$GPUName) { $GPUName = "GPU" } }
    
    Write-Box "GPU PARTITION"
    Write-Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"
    Write-Host ""
    
    if (!(Ensure-VMOff -VMName $VMName)) { return $false }
    
    $r = Invoke-Safe -Op "GPU Config" -Code {
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
        
        Write-Host ""
        Write-Box "GPU ALLOCATED: $Pct%" "-"
        Write-Host ""
        return $true
    }
    return $r.Success
}

function Remove-GPUPartition {
    param([string]$VMName)
    
    if (!$VMName) {
        $vm = Select-VM -Title "REMOVE GPU FROM VM" -AllowRunning $false
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    
    $vmObj = Get-VM $VMName -EA SilentlyContinue
    if (!$vmObj) { Write-Log "VM not found" "ERROR"; return $false }
    
    $gpuAdapter = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if (!$gpuAdapter) {
        Write-Log "No GPU partition found on this VM" "WARN"
        Write-Host ""
        return $false
    }
    
    Write-Box "REMOVE GPU PARTITION"
    Write-Log "Target VM: $VMName" "INFO"
    Write-Host ""
    
    if (!(Confirm "Remove GPU partition and clean driver files?")) {
        Write-Log "Cancelled" "WARN"
        return $false
    }
    Write-Host ""
    
    if (!(Ensure-VMOff -VMName $VMName)) { return $false }
    
    $r = Invoke-Safe -Op "Remove GPU Adapter" -Code {
        Show-Spinner "Removing GPU partition adapter..." 2
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA Stop
        Write-Log "GPU partition adapter removed" "SUCCESS"
        return $true
    }
    if (!$r.Success) { Write-Host ""; return $false }
    
    $r = Invoke-Safe -Op "Reset MMIO Settings" -Code {
        Show-Spinner "Resetting memory-mapped IO settings..." 1
        Set-VM $VMName -GuestControlledCacheTypes $false -LowMemoryMappedIoSpace 0 -HighMemoryMappedIoSpace 0 -EA Stop
        Write-Log "Memory-mapped IO settings reset" "SUCCESS"
        return $true
    }
    if (!$r.Success) { Write-Host ""; return $false }
    
    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) {
        Write-Log "No VHD found - skipping driver cleanup" "WARN"
        Write-Host ""
        Write-Box "GPU REMOVAL COMPLETE" "-"
        Write-Log "GPU partition and MMIO settings removed" "SUCCESS"
        Write-Host ""
        return $true
    }
    
    $mount = $null
    try {
        Write-Host ""
        Show-Spinner "Mounting VM disk to clean drivers..." 2
        $mount = Mount-VMDisk -VHDPath $vhdPath
        $hostDriverStore = "$($mount.Path)\Windows\System32\HostDriverStore"
        
        if (Test-Path $hostDriverStore) {
            Show-Spinner "Removing driver files..." 2
            $fileCount = 0
            $folderCount = 0
            if (Test-Path "$hostDriverStore\FileRepository") {
                $folders = Get-ChildItem "$hostDriverStore\FileRepository" -Directory -EA SilentlyContinue
                $folderCount = ($folders | Measure-Object).Count
                $fileCount = (Get-ChildItem "$hostDriverStore\FileRepository" -Recurse -File -EA SilentlyContinue | Measure-Object).Count
            }
            Remove-Item "$hostDriverStore\*" -Recurse -Force -EA SilentlyContinue
            Write-Log "Removed $fileCount files from $folderCount driver folders" "SUCCESS"
        } else {
            Write-Log "HostDriverStore not found - no drivers to clean" "INFO"
        }
        
        Write-Host ""
        Write-Box "GPU REMOVAL COMPLETE" "-"
        Write-Log "GPU partition removed" "SUCCESS"
        Write-Log "MMIO settings reset" "SUCCESS"
        Write-Log "Driver files cleaned" "SUCCESS"
        Write-Host ""
        return $true
    } catch {
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Write-Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - Windows may not be installed yet.`n" -ForegroundColor Yellow
        } else {
            Write-Log "Driver cleanup failed: $errorMsg" "WARN"
        }
        Write-Host ""
        Write-Box "GPU REMOVAL PARTIAL" "-"
        Write-Log "GPU partition and MMIO settings removed successfully" "SUCCESS"
        Write-Log "Driver cleanup skipped - could not access VM disk" "WARN"
        Write-Host ""
        return $true
    } finally {
        if ($mount) {
            Show-Spinner "Unmounting VM disk..." 1
            Dismount-VMDisk -Mount $mount -VHDPath $vhdPath
        }
    }
}
#endregion

#region Driver Injection
function Install-GPUDrivers {
    param([string]$VMName)
    
    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM FOR DRIVERS"
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    
    $vhdPath = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhdPath) { Write-Log "No VHD found" "ERROR"; return $false }
    
    Write-Box "GPU DRIVER INJECTION"
    Write-Log "Target: $VMName" "INFO"
    Write-Host ""
    
    if (!(Ensure-VMOff -VMName $VMName)) { return $false }
    
    $mount = $null
    try {
        $gpu = Select-GPU -Title "SELECT GPU FOR DRIVERS"
        if (!$gpu) { return $false }
        Write-Host ""
        
        $drivers = Get-DriverFiles -GPU $gpu
        if (!$drivers) { return $false }
        
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
                $count = (Get-ChildItem $dest -Recurse -File -EA SilentlyContinue | Measure-Object).Count
                Write-Host "      ($count files)" -ForegroundColor DarkGray
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
        $errorMsg = $_.Exception.Message
        if ($errorMsg -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Write-Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - install Windows first, then run driver injection.`n" -ForegroundColor Yellow
        } else {
            Write-Log "Failed: $errorMsg" "ERROR"
        }
        return $false
    } finally {
        if ($mount) {
            Show-Spinner "Unmounting VM disk..." 1
            Dismount-VMDisk -Mount $mount -VHDPath $vhdPath
        }
    }
}

function Copy-VMApps {
    $vm = Select-VM -Title "SELECT VM FOR APPS"
    if (!$vm) { return $false }
    
    $vhdPath = (Get-VMHardDiskDrive $vm.Name -EA SilentlyContinue).Path
    if (!$vhdPath) { Write-Log "No VHD found" "ERROR"; return $false }
    
    Write-Box "COPY APPS TO VM"
    Write-Log "Target: $($vm.Name)" "INFO"
    Write-Host ""
    
    $appsFolder = Join-Path (Split-Path -Parent $PSCommandPath) "VM Apps"
    if (!(Test-Path $appsFolder)) { Write-Log "'VM Apps' folder not found next to script" "ERROR"; return $false }
    
    $zips = Get-ChildItem $appsFolder -Filter "*.zip" -File
    if (!$zips) { Write-Log "No zip files found" "WARN"; return $false }
    Write-Log "Found $($zips.Count) app(s) to copy" "INFO"
    Write-Host ""
    
    if (!(Ensure-VMOff -VMName $vm.Name)) { return $false }
    
    $mount = $null
    try {
        $mount = Mount-VMDisk -VHDPath $vhdPath
        Show-Spinner "Finding user profile..." 1
        
        $user = Get-ChildItem "$($mount.Path)\Users" -Directory -EA SilentlyContinue | 
                Where-Object { $_.Name -notin @("Public","Administrator","Default","Default.migrated") } | 
                Select-Object -First 1
        if (!$user) { Write-Log "No user profile found" "ERROR"; return $false }
        
        $dest = "$($mount.Path)\Users\$($user.Name)\Downloads\VM Apps"
        New-Dir $dest
        
        Write-Log "Copying to $($user.Name)'s Downloads..." "INFO"
        $copied = ($zips | ForEach-Object { if (Copy-Logged -Src $_.FullName -Dst $dest -Name $_.Name) { 1 } else { 0 } } | Measure-Object -Sum).Sum
        
        Write-Host ""
        Write-Box "COPIED: $copied/$($zips.Count) apps" "-"
        Write-Log "Location: Users\$($user.Name)\Downloads\VM Apps" "INFO"
        Write-Host ""
        return $true
    } catch {
        Write-Log "Failed: $_" "ERROR"
        return $false
    } finally {
        if ($mount) {
            Show-Spinner "Unmounting VM disk..." 1
            Dismount-VMDisk -Mount $mount -VHDPath $vhdPath
        }
    }
}

function Invoke-CompleteSetup {
    Write-Log "Starting complete setup wizard..." "HEADER"
    Write-Host ""
    
    $config = Get-VMConfig
    if (!$config) { Write-Log "Cancelled" "WARN"; return }
    
    $vmName = New-GpuVM -Config $config
    if (!$vmName) { return }
    Write-Host ""
    
    $gpu = Select-GPU -Title "SELECT GPU FOR PARTITIONING" -ForPartition
    if (!$gpu) { Write-Log "Cancelled" "WARN"; return }
    
    $pct = Get-Input -Prompt "GPU % to allocate (default: 50)" -Validator { 
        [string]::IsNullOrWhiteSpace($_) -or ([int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100) 
    } -Default "50"
    
    if (!(Set-GPUPartition -VMName $vmName -Pct ([int]$pct) -GPUPath $gpu.Path -GPUName $gpu.Name)) { return }
    
    Write-Host ""
    Write-Box "ATTEMPTING DRIVER INJECTION" "-"
    
    if (!(Install-GPUDrivers -VMName $vmName)) {
        Write-Log "Driver injection skipped - install Windows first" "WARN"
        Write-Host "  Run 'Install Drivers' after Windows is installed.`n" -ForegroundColor Yellow
    } else {
        Write-Log "Complete setup finished successfully!" "SUCCESS"
    }
    Write-Host ""
}
#endregion

#region Info Display
function Show-VmInfo {
    Write-Box "VM OVERVIEW"
    Write-Log "Gathering VM information..." "INFO"
    Write-Host ""
    
    $vms = Get-VM
    if (!$vms) { Write-Log "No VMs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }
    
    $line = "+{0}+{1}+{2}+{3}+{4}+{5}+{6}+" -f ('-'*16),('-'*10),('-'*9),('-'*7),('-'*11),('-'*28),('-'*8)
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ("  | {0,-14} | {1,-8} | {2,-7} | {3,-5} | {4,-9} | {5,-26} | {6,-6} |" -f "VM", "State", "RAM(GB)", "CPU", "Storage", "GPU", "GPU %") -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor Cyan
    
    foreach ($vm in $vms) {
        $size = 0
        try { $vhd = Get-VHD -VMId $vm.VMId -EA SilentlyContinue; if ($vhd) { $size = [math]::Round($vhd.Size / 1GB) } } catch {}
        $mem = if ($vm.MemoryAssigned -gt 0) { $vm.MemoryAssigned } else { $vm.MemoryStartup }
        $color = if ($vm.State -eq "Running") { "Green" } else { "Yellow" }
        
        $gpuName = "None"
        $gpuPct = "-"
        $gpuAdapter = Get-VMGpuPartitionAdapter $vm.Name -EA SilentlyContinue
        if ($gpuAdapter) {
            $instancePath = $gpuAdapter.InstancePath
            $gpuName = Get-GPUFriendlyName -InstancePath $instancePath
            if (!$gpuName) { $gpuName = "GPU" }
            if ($gpuName.Length -gt 26) { $gpuName = $gpuName.Substring(0, 23) + "..." }
            $gpuPct = try { "$([math]::Round($gpuAdapter.MaxPartitionVRAM / 1e9 * 100))%" } catch { "?" }
        }
        
        $vmName = $vm.Name
        if ($vmName.Length -gt 14) { $vmName = $vmName.Substring(0, 11) + "..." }
        
        Write-Host ("  | {0,-14} | {1,-8} | {2,-7} | {3,-5} | {4,-9} | {5,-26} | {6,-6} |" -f $vmName, $vm.State, [math]::Round($mem / 1GB), $vm.ProcessorCount, $size, $gpuName, $gpuPct) -ForegroundColor $color
    }
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Press Enter"
}

function Show-GpuInfo {
    Write-Box "GPU INFORMATION"
    
    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | 
            Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    
    if (!$gpus) { Write-Log "No GPUs found" "WARN"; Read-Host "  Press Enter"; return }
    
    foreach ($gpu in $gpus) {
        Write-Host "  GPU: $($gpu.Name)" -ForegroundColor Green
        Write-Host "  Driver: $($gpu.DriverVersion)" -ForegroundColor Green
        Write-Host "  Status: $(if ($gpu.Status -eq 'OK') { 'OK' } else { $gpu.Status })" -ForegroundColor $(if ($gpu.Status -eq 'OK') { 'Green' } else { 'Yellow' })
        Write-Host ""
    }
    Read-Host "  Press Enter"
}
#endregion

#region Main Menu
$menuItems = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Complete Setup", "List VMs", "GPU Info", "Copy Apps", "Exit")

while ($true) {
    $choice = Select-Menu -Items $menuItems -Title "MAIN MENU"
    if ($choice -eq $null) { Write-Log "Cancelled" "INFO"; continue }
    Write-Host ""
    
    switch ($choice) {
        0 { New-GpuVM -Config (Get-VMConfig) | Out-Null; Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        2 { Remove-GPUPartition | Out-Null; Read-Host "`n  Press Enter" }
        3 { Install-GPUDrivers | Out-Null; Read-Host "`n  Press Enter" }
        4 { Invoke-CompleteSetup | Out-Null; Read-Host "`n  Press Enter" }
        5 { Show-VmInfo }
        6 { Show-GpuInfo }
        7 { Copy-VMApps | Out-Null; Read-Host "`n  Press Enter" }
        8 { Write-Log "Goodbye!" "INFO"; exit }
    }
}
#endregion
