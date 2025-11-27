if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}



#region Core Logging and UI Helpers



function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $colors = @{INFO='Cyan'; SUCCESS='Green'; WARN='Yellow'; ERROR='Red'; HEADER='Magenta'}
    $icons = @{INFO='>'; SUCCESS='+'; WARN='!'; ERROR='X'; HEADER='~'}
    Write-Host "  [$((Get-Date).ToString('HH:mm:ss'))] $($icons[$Level]) $Message" -ForegroundColor $colors[$Level]
}



function Write-Box {
    param([string]$Text, [string]$Style = "=", [int]$Width = 80)
    Write-Host "`n  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    Write-Host "  |  $($Text.PadRight($Width - 6))|" -ForegroundColor Cyan
    Write-Host "  +$($Style * ($Width - 4))+" -ForegroundColor Cyan
    if ($Style -eq "=") { Write-Host "" }
}



function Show-Banner {
    Clear-Host
    Write-Host "`n  GPU Virtualization Manager" -ForegroundColor Magenta
    Write-Host "  Manage and partition GPUs for Hyper-V virtual machines`n" -ForegroundColor Magenta
}



function Show-Spinner {
    param([string]$Message, [int]$Duration = 2)
    $spinner = @('|', '/', '-', '\')
    1..$Duration | ForEach-Object {
        Write-Host "`r  $($spinner[$_ % 4]) $Message" -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`r  + $Message" -ForegroundColor Green
}



function Show-SpinnerWithCondition {
    param([string]$Message, [scriptblock]$Condition, [int]$TimeoutSeconds = 60, [string]$SuccessMessage = $null)
    $spinner = @('|', '/', '-', '\')
    $spinnerIndex = 0
    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        if (& $Condition) {
            $finalMsg = if ($SuccessMessage) { $SuccessMessage } else { $Message }
            Write-Host "`r  + $finalMsg             " -ForegroundColor Green
            return $true
        }
        Write-Host "`r  $($spinner[$spinnerIndex % 4]) $Message ($i sec)" -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 500
        $spinnerIndex++
    }
    Write-Host "`r  X $Message - Timeout" -ForegroundColor Red
    return $false
}



function Invoke-WithErrorHandling {
    param(
        [scriptblock]$ScriptBlock,
        [string]$OperationName,
        [string]$SuccessMessage = $null,
        [scriptblock]$OnError = $null
    )
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



#region Menu and Selection Helpers



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
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq "UpArrow") {
            $selected = ($selected - 1 + $Items.Count) % $Items.Count
        } elseif ($key.Key -eq "DownArrow") {
            $selected = ($selected + 1) % $Items.Count
        } elseif ($key.Key -eq "Enter") {
            [Console]::SetCursorPosition(0, $menuStart + $Items.Count + 2)
            return $selected
        } elseif ($key.Key -eq "Escape") {
            [Console]::SetCursorPosition(0, $menuStart + $Items.Count + 2)
            return $null
        }
    }
}



function Get-ValidatedInput {
    param([string]$Prompt, [scriptblock]$Validator = {$true}, [string]$ErrorMessage = "Invalid input. Please try again.", [string]$DefaultValue = $null)
    do {
        $input = Read-Host "  $Prompt"
        if ([string]::IsNullOrWhiteSpace($input) -and $DefaultValue) {
            return $DefaultValue
        }
        if (& $Validator $input) {
            return $input
        }
        Write-Log $ErrorMessage "WARN"
    } while ($true)
}



function Confirm-Action {
    param([string]$Message, [bool]$DefaultYes = $false)
    $response = Read-Host "  $Message (Y/N)"
    if ($DefaultYes) {
        return $response -notmatch "^[Nn]$"
    }
    return $response -match "^[Yy]$"
}



#endregion



#region VM Operations Helpers



function Select-VM {
    param([string]$Title = "SELECT VIRTUAL MACHINE", [bool]$AllowRunning = $false)
    Write-Box $Title
    $vms = @(Get-VM | Where-Object { $AllowRunning -or $_.State -eq 'Off' })
    if ($vms.Count -eq 0) {
        Write-Log "No $(if (!$AllowRunning) { 'stopped ' })VMs found$(if (!$AllowRunning) { '. VMs must be powered off for this operation.' })" "ERROR"
        Write-Host ""
        return $null
    }
    $menuItems = @()
    $menuItems += $vms | ForEach-Object { Format-VMMenuItem $_ }
    $menuItems += "< Cancel >"
    $selection = Select-Menu -Items $menuItems -Title $Title
    if ($selection -eq $null -or $selection -eq ($menuItems.Count - 1)) { return $null }
    return $vms[$selection]
}



function Format-VMMenuItem {
    param($VM)
    $ramSource = if ($VM.MemoryAssigned -gt 0) { $VM.MemoryAssigned } else { $VM.MemoryStartup }
    $ram = [math]::Round($ramSource / 1GB, 0)
    $gpuAdapter = Get-VMGpuPartitionAdapter $VM.Name -EA SilentlyContinue
    $gpu = if ($gpuAdapter) {
        try {
            $percent = [math]::Round(($gpuAdapter.MaxPartitionVRAM / 1000000000) * 100, 0)
            "$percent%"
        } catch { "?" }
    } else {
        "None"
    }
    return "$($VM.Name) | State: $($VM.State) | RAM: ${ram}GB | CPU: $($VM.ProcessorCount) | GPU: $gpu"
}



function Stop-VMSafe {
    param([string]$VMName)
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }
    Write-Host "`r  | Shutting down VM..." -ForegroundColor Cyan -NoNewline
    $result = Invoke-WithErrorHandling -OperationName "Stop VM" -ScriptBlock {
        Stop-VM $VMName -Force -EA Stop
        $success = Show-SpinnerWithCondition -Message "Shutting down VM" -Condition { (Get-VM $VMName).State -eq "Off" } -TimeoutSeconds 60 -SuccessMessage "VM shut down successfully"
        if ($success) { Start-Sleep -Seconds 2; return $true }
        Stop-VM $VMName -TurnOff -Force -EA Stop
        Start-Sleep -Seconds 3
        return $true
    }
    return $result.Success
}



function Test-VMState {
    param([string]$VMName, [string]$RequiredState = "Off")
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }
    if ($vm.State -ne $RequiredState -and $RequiredState -eq "Off") {
        return Stop-VMSafe -VMName $VMName
    }
    return $vm.State -eq $RequiredState
}



#endregion



#region Disk Operations Helpers



function Mount-VMDisk {
    param([string]$VHDPath)
    $mountPoint = "C:\Temp\VMMount_$(Get-Random)"
    $result = Invoke-WithErrorHandling -OperationName "Mount VHD" -ScriptBlock {
        New-Item $mountPoint -ItemType Directory -Force | Out-Null
        Show-Spinner "Mounting virtual disk..." 2
        $mounted = Mount-VHD $VHDPath -NoDriveLetter -PassThru -EA Stop
        Start-Sleep -Seconds 2
        Update-Disk $mounted.DiskNumber -EA SilentlyContinue
        $partition = Get-Partition -DiskNumber $mounted.DiskNumber -EA Stop | Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        if (!$partition) { throw "No valid partition found" }
        Show-Spinner "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $mounted.DiskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
        if (!(Test-Path "$mountPoint\Windows")) { throw "Windows directory not found" }
        return @{Mounted=$mounted; Partition=$partition; MountPoint=$mountPoint}
    }
    if ($result.Success) { return $result.Result }
    throw $result.Error
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



#region GPU Operations Helpers



# Map Device Instance Path (from Get-VMHostPartitionableGpu) to friendly GPU name via Win32_VideoController
function Get-GPUNameFromInstancePath {
    param([string]$InstancePath)

    if ([string]::IsNullOrWhiteSpace($InstancePath)) {
        return $null
    }

    # Extract PCI VEN/DEV from instance path
    # Example: \\?\PCI#VEN_10DE&DEV_2684&SUBSYS_... -> VEN_10DE, DEV_2684
    if ($InstancePath -match 'VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})') {
        $vendorId = $matches[1]
        $deviceId = $matches[2]

        # Match using Win32_VideoController PNPDeviceID
        $gpu = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object {
            $_.PNPDeviceID -like "*VEN_$vendorId*" -and $_.PNPDeviceID -like "*DEV_$deviceId*"
        } | Select-Object -First 1

        if ($gpu -and -not [string]::IsNullOrWhiteSpace($gpu.Name)) {
            return $gpu.Name
        }
    }

    return $null
}



function Select-GPUDevice {
    Write-Box "SELECT GPU DEVICE"
    $gpuDrivers = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
    if (-not $gpuDrivers -or $gpuDrivers.Count -eq 0) {
        Write-Log "No display adapters found" "ERROR"
        return $null
    }
    for ($i=0; $i -lt $gpuDrivers.Count; $i++) {
        $gpu = $gpuDrivers[$i]
        Write-Host "  [$($i + 1)] $($gpu.DeviceName)" -ForegroundColor Green
        Write-Host "       Provider: $($gpu.DriverProviderName) | Version: $($gpu.DriverVersion)" -ForegroundColor DarkGray
    }
    Write-Host ""
    $maxNum = $gpuDrivers.Count
    while ($true) {
        $selection = Read-Host "  Enter GPU number (1-$maxNum)"
        if ([int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 1 -and [int]$selection -le $maxNum) {
            return $gpuDrivers[[int]$selection - 1]
        }
        Write-Log "Please enter a valid number between 1 and $maxNum" "WARN"
    }
}



# Returns an object with InstancePath + FriendlyName, but Set-GPUPartition still uses InstancePath internally
function Select-GPUForPartition {
    Write-Box "SELECT GPU DEVICE FOR PARTITIONING"

    $gpus = @(Get-VMHostPartitionableGpu -EA SilentlyContinue)
    if (-not $gpus -or $gpus.Count -eq 0) {
        Write-Log "No assignable GPUs found" "ERROR"
        Write-Host ""
        return $null
    }

    $gpuList = @()
    for ($i=0; $i -lt $gpus.Count; $i++) {
        $gpu = $gpus[$i]

        # Officially, Name is the Device Instance path for Add-VMGpuPartitionAdapter -InstancePath[web:4][web:11]
        $instancePath = $gpu.Name
        if ([string]::IsNullOrWhiteSpace($instancePath)) {
            $instancePath = $gpu.Id
        }
        if ([string]::IsNullOrWhiteSpace($instancePath)) {
            $instancePath = "UNKNOWN_INSTANCE_PATH"
        }

        # Derive friendly GPU name from WMI
        $friendlyName = Get-GPUNameFromInstancePath -InstancePath $instancePath
        if ([string]::IsNullOrWhiteSpace($friendlyName)) {
            # Fallback if mapping fails
            $friendlyName = "GPU-$i"
        }

        $gpuList += [PSCustomObject]@{
            Index        = $i
            InstancePath = $instancePath
            FriendlyName = $friendlyName
        }

        Write-Host "  [$($i + 1)] $friendlyName" -ForegroundColor Green
        Write-Host "       Path: $instancePath" -ForegroundColor DarkGray
    }

    Write-Host ""
    if ($gpuList.Count -eq 0) {
        Write-Log "No valid GPU identifiers found" "ERROR"
        return $null
    }

    $maxNum = $gpuList.Count
    while ($true) {
        $selection = Read-Host "  Enter GPU number (1-$maxNum)"
        if ([int]::TryParse($selection, [ref]$null) -and [int]$selection -ge 1 -and [int]$selection -le $maxNum) {
            $selected = $gpuList[[int]$selection - 1]
            Write-Log "Selected GPU: $($selected.FriendlyName)" "SUCCESS"
            Write-Host ""
            return $selected
        }
        Write-Log "Please enter a valid number between 1 and $maxNum" "WARN"
    }
}



function Copy-ItemWithLogging {
    param([string]$SourcePath, [string]$DestinationPath, [string]$ItemName, [bool]$Recurse = $false)
    $destDir = Split-Path -Parent $DestinationPath
    New-DirectorySafe -Path $destDir
    $result = Invoke-WithErrorHandling -OperationName "Copy $ItemName" -ScriptBlock {
        $params = @{ Path = $SourcePath; Destination = $DestinationPath; Force = $true; ErrorAction = 'Stop' }
        if ($Recurse) { $params['Recurse'] = $true }
        Copy-Item @params
        Write-Log "+ $ItemName" "SUCCESS"
        return $true
    } -OnError { Write-Log "! ${ItemName}: Skipped" "WARN" }
    return $result.Success
}



function Get-DriverFiles {
    param([Object]$GPU)
    Write-Box "ANALYZING GPU DRIVERS" "-"
    Write-Log "GPU: $($GPU.DeviceName)" "INFO"
    Write-Log "Provider: $($GPU.DriverProviderName)" "INFO"
    Write-Log "Version: $($GPU.DriverVersion)" "INFO"; Write-Host ""
    Show-Spinner "Finding INF file from registry..." 1
    $registryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
    $infFileName = (Get-ChildItem -Path $registryPath -EA SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path $_.PSPath -EA SilentlyContinue
        if ($props.MatchingDeviceId -and ($GPU.DeviceID -like "*$($props.MatchingDeviceId)*" -or $props.MatchingDeviceId -like "*$($GPU.DeviceID)*")) {
            Write-Log "Found INF: $($props.InfPath)" "SUCCESS"
            $props.InfPath
        }
    }) | Select-Object -First 1
    if (-not $infFileName) {
        Write-Log "Could not find GPU in registry" "ERROR"
        return $null
    }
    $infFilePath = "C:\Windows\INF\$infFileName"
    if (!(Test-Path $infFilePath)) {
        Write-Log "INF file not found: $infFilePath" "ERROR"
        return $null
    }
    Show-Spinner "Reading INF file..." 1
    $infContent = Get-Content $infFilePath -Raw
    Show-Spinner "Parsing INF for file references..." 1
    $filePatterns = @('[\w\-\.]+\.sys','[\w\-\.]+\.dll','[\w\-\.]+\.exe','[\w\-\.]+\.cat','[\w\-\.]+\.inf','[\w\-\.]+\.bin','[\w\-\.]+\.vp','[\w\-\.]+\.cpa')
    $referencedFiles = $filePatterns | ForEach-Object { [regex]::Matches($infContent, $_, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) } | ForEach-Object { $_ | ForEach-Object { $_.Value } } | Sort-Object -Unique
    Write-Log "Found $($referencedFiles.Count) file references in INF" "SUCCESS"; Write-Host ""
    Show-Spinner "Locating files in system..." 2
    $searchPaths = @(
        @{Path="C:\Windows\System32\DriverStore\FileRepository"; Type="DriverStore"; Recurse=$true},
        @{Path="C:\Windows\System32"; Type="System32"; Recurse=$false},
        @{Path="C:\Windows\SysWow64"; Type="SysWow64"; Recurse=$false}
    )
    $foundFiles = @()
    $driverStoreFolders = @()
    $referencedFiles | ForEach-Object {
        $fileName = $_
        $found = $false
        $searchPaths | ForEach-Object {
            if ($found) { return }
            $searchArgs = @{Path=$_['Path']; Filter=$fileName; EA='SilentlyContinue'}
            if ($_['Recurse']) { $searchArgs['Recurse'] = $true }
            $result = Get-ChildItem @searchArgs | Select-Object -First 1
            if ($result) {
                $found = $true
                if ($_['Type'] -eq "DriverStore") {
                    if ($result.DirectoryName -notin $driverStoreFolders) { $driverStoreFolders += $result.DirectoryName }
                } else {
                    $foundFiles += [PSCustomObject]@{FileName=$fileName; FullPath=$result.FullName; DestPath=$result.FullName.Replace("C:","")}
                }
            }
        }
    }
    Write-Log "Located $($foundFiles.Count) system files + $($driverStoreFolders.Count) DriverStore folder(s)" "SUCCESS"; Write-Host ""
    return @{Files=$foundFiles; StoreFolders=$driverStoreFolders}
}
#endregion



#region VM Configuration and Setup



function Get-VMConfig {
    $presets = @(
        "Gaming       | 16GB RAM, 8 CPU,  256GB Storage",
        "Development  | 8GB RAM,  4 CPU,  128GB Storage",
        "ML Training  | 32GB RAM, 12 CPU, 512GB Storage",
        "Custom Configuration"
    )
    $presetData = @(
        @{Name="Gaming-VM"; RAM=16; CPU=8; Storage=256},
        @{Name="Dev-VM"; RAM=8; CPU=4; Storage=128},
        @{Name="ML-VM"; RAM=32; CPU=12; Storage=512}
    )
    $choice = Select-Menu -Items $presets -Title "VM CONFIGURATION"
    if ($choice -eq $null) { return $null }
    if ($choice -lt 3) {
        $preset = $presetData[$choice]; Write-Host ""
        $name = Read-Host "  VM Name (default: $($preset.Name))"
        $iso = Read-Host "  ISO Path (Enter to skip)"; Write-Host ""
        return @{
            Name    = $(if ($name) { $name } else { $preset.Name })
            RAM     = $preset.RAM
            CPU     = $preset.CPU
            Storage = $preset.Storage
            Path    = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
            ISO     = $iso
        }
    }
    Write-Box "CUSTOM VM CONFIGURATION" "-"
    return @{
        Name    = Get-ValidatedInput -Prompt "VM Name" -Validator { param($v) ![string]::IsNullOrWhiteSpace($v) }
        RAM     = [int](Get-ValidatedInput -Prompt "RAM in GB" -Validator { param($v) [int]::TryParse($v, [ref]$null) -and [int]$v -gt 0 })
        CPU     = [int](Get-ValidatedInput -Prompt "CPU Cores" -Validator { param($v) [int]::TryParse($v, [ref]$null) -and [int]$v -gt 0 })
        Storage = [int](Get-ValidatedInput -Prompt "Storage in GB" -Validator { param($v) [int]::TryParse($v, [ref]$null) -and [int]$v -gt 0 })
        Path    = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
        ISO     = (Read-Host "  ISO Path (Enter to skip)")
    }
}



function Initialize-VM {
    param($Config)
    if ($Config -eq $null) {
        Write-Log "VM configuration cancelled" "WARN"
        return $null
    }
    Write-Box "CREATING VIRTUAL MACHINE"
    Write-Log "VM: $($Config.Name) | RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "INFO"; Write-Host ""
    $vhdPath = Join-Path $Config.Path "$($Config.Name).vhdx"
    if (Get-VM $Config.Name -EA SilentlyContinue) {
        Write-Log "VM already exists" "ERROR"
        return $null
    }
    if (Test-Path $vhdPath) {
        if (!(Confirm-Action "VHDX exists. Overwrite?")) {
            Write-Log "Operation cancelled" "WARN"
            return $null
        }
        Remove-Item $vhdPath -Force
    }
    $result = Invoke-WithErrorHandling -OperationName "VM Creation" -ScriptBlock {
        Show-Spinner "Creating VM configuration..." 2
        New-DirectorySafe -Path $Config.Path
        New-VM -Name $Config.Name -MemoryStartupBytes ([int64]$Config.RAM * 1GB) -Generation 2 -NewVHDPath $vhdPath -NewVHDSizeBytes ([int64]$Config.Storage * 1GB) | Out-Null
        Show-Spinner "Configuring processor and memory..." 1
        Set-VMProcessor $Config.Name -Count $Config.CPU
        Set-VMMemory $Config.Name -DynamicMemoryEnabled $false
        Show-Spinner "Applying security settings..." 1
        Set-VM $Config.Name -CheckpointType Disabled -AutomaticStopAction ShutDown -AutomaticStartAction Nothing -AutomaticCheckpointsEnabled $false
        Set-VMHost -EnableEnhancedSessionMode $false
        Disable-VMIntegrationService $Config.Name -Name "Guest Service Interface", "VSS"
        Show-Spinner "Finalizing setup..." 1
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
        Write-Log "RAM: $($Config.RAM)GB | CPU: $($Config.CPU) | Storage: $($Config.Storage)GB" "SUCCESS"; Write-Host ""
        return $Config.Name
    }
    if ($result.Success) { return $result.Result } else { return $null }
}



function Set-GPUPartition {
    param(
        [string]$VMName,
        [int]$Percentage = 0,
        [string]$InstancePath = $null,
        [string]$GPUName = $null
    )

    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM FOR GPU PARTITION" -AllowRunning $false
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    if (!(Get-VM $VMName -EA SilentlyContinue)) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }

    # 1) Ask GPU FIRST
    if ([string]::IsNullOrWhiteSpace($InstancePath)) {
        $gpuSelection = Select-GPUForPartition
        if (-not $gpuSelection) {
            Write-Log "No GPU selected" "ERROR"
            return $false
        }
        $InstancePath = $gpuSelection.InstancePath
        $GPUName      = $gpuSelection.FriendlyName
    }

    # 2) Then ask PERCENTAGE (if not supplied)
    if ($Percentage -eq 0) {
        Write-Host ""
        $Percentage = [int](Get-ValidatedInput -Prompt "GPU Allocation % (1-100)" -Validator { param($v) [int]::TryParse($v, [ref]$null) -and [int]$v -ge 1 -and [int]$v -le 100 } -ErrorMessage "Please enter a number between 1 and 100")
    }
    $Percentage = [Math]::Max(1, [Math]::Min(100, $Percentage))

    if ([string]::IsNullOrWhiteSpace($GPUName)) {
        $GPUName = Get-GPUNameFromInstancePath -InstancePath $InstancePath
        if ([string]::IsNullOrWhiteSpace($GPUName)) {
            $GPUName = "GPU"
        }
    }

    Write-Box "CONFIGURING GPU PARTITION"
    Write-Log "VM: $VMName | GPU: $GPUName | Allocation: $Percentage%" "INFO"
    Write-Log "Instance Path: $InstancePath" "INFO"; Write-Host ""

    if (!(Test-VMState -VMName $VMName -RequiredState "Off")) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }

    $result = Invoke-WithErrorHandling -OperationName "GPU Configuration" -ScriptBlock {
        Show-Spinner "Configuring GPU..." 2
        Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue | Remove-VMGpuPartitionAdapter -EA SilentlyContinue
        Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $InstancePath
        $max = [int](($Percentage / 100) * 1000000000)
        $opt = $max - 1
        Set-VMGpuPartitionAdapter $VMName `
            -MinPartitionVRAM 1 -MaxPartitionVRAM $max -OptimalPartitionVRAM $opt `
            -MinPartitionEncode 1 -MaxPartitionEncode $max -OptimalPartitionEncode $opt `
            -MinPartitionDecode 1 -MaxPartitionDecode $max -OptimalPartitionDecode $opt `
            -MinPartitionCompute 1 -MaxPartitionCompute $max -OptimalPartitionCompute $opt
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB
        Write-Host ""
        Write-Box "GPU CONFIGURED: $Percentage%" "-"; Write-Host ""
        return $true
    }
    return $result.Success
}



function Install-GPUDrivers {
    param([string]$VMName)
    if (!$VMName) {
        $vm = Select-VM -Title "SELECT VM FOR DRIVER INJECTION" -AllowRunning $false
        if (!$vm) { return $false }
        $VMName = $vm.Name
    }
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) {
        Write-Log "VM not found: $VMName" "ERROR"
        return $false
    }
    $vhd = (Get-VMHardDiskDrive $VMName).Path
    if (!$vhd) {
        Write-Log "No VHD found" "ERROR"
        return $false
    }
    Write-Box "AUTO-DETECT & INSTALL GPU DRIVERS"
    Write-Log "Target: $VMName" "INFO"; Write-Host ""
    if (!(Test-VMState -VMName $VMName -RequiredState "Off")) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }
    try {
        $selectedGPU = Select-GPUDevice
        if (!$selectedGPU) { return $false }
        Write-Host ""
        $driverData = Get-DriverFiles -GPU $selectedGPU
        if (!$driverData) { return $false }
        $mountInfo = Mount-VMDisk -VHDPath $vhd
        $mp = $mountInfo.MountPoint
        Show-Spinner "Preparing VM disk..." 1
        $hostDriverStorePath = "$mp\Windows\System32\HostDriverStore\FileRepository"
        New-DirectorySafe -Path $hostDriverStorePath
        Write-Log "Copying $($driverData.StoreFolders.Count) DriverStore folders..." "INFO"; Write-Host ""
        $driverData.StoreFolders | ForEach-Object {
            $folderName = Split-Path -Leaf $_
            $destFolder = Join-Path $hostDriverStorePath $folderName
            $success = Copy-ItemWithLogging -SourcePath $_ -DestinationPath $destFolder -ItemName $folderName -Recurse $true
            if ($success) {
                $fileCount = (Get-ChildItem -Path $destFolder -Recurse -File -EA SilentlyContinue | Measure-Object).Count
                Write-Host "      ($fileCount files)" -ForegroundColor DarkGray
            }
        }
        Write-Host ""
        Write-Log "Copying $($driverData.Files.Count) system files..." "INFO"
        $driverData.Files | ForEach-Object {
            $destPath = "$mp$($_.DestPath)"
            Copy-ItemWithLogging -SourcePath $_.FullPath -DestinationPath $destPath -ItemName $_.FileName | Out-Null
        }
        Write-Host ""
        Write-Box "DRIVER INJECTION COMPLETE" "-"
        Write-Log "Injected $($driverData.Files.Count) files + $($driverData.StoreFolders.Count) folders to $VMName" "SUCCESS"; Write-Host ""
        return $true
    } catch {
        if ($_.Exception.Message -match "partition") {
            Write-Log "Windows not installed on this VM" "ERROR"
            Write-Host "  To inject drivers, please install Windows inside the VM first.`n" -ForegroundColor Yellow
            return $false
        } else {
            Write-Log "Injection failed: $_" "ERROR"
            return $false
        }
    } finally {
        Dismount-VMDisk -MountInfo $mountInfo -VHDPath $vhd
    }
}



function Copy-VMApps {
    $vm = Select-VM -Title "SELECT VM FOR APP COPY" -AllowRunning $false
    if (!$vm) { return $false }
    $VMName = $vm.Name
    $vhd = (Get-VMHardDiskDrive $VMName).Path
    if (!$vhd) {
        Write-Log "No VHD found" "ERROR"
        return $false
    }
    Write-Box "COPYING VM APPLICATIONS"
    Write-Log "Target: $VMName" "INFO"; Write-Host ""
    $vmAppsFolder = Join-Path (Split-Path -Parent $PSCommandPath) "VM Apps"
    if (!(Test-Path $vmAppsFolder)) {
        Write-Log "VM Apps folder not found" "ERROR"
        return $false
    }
    $zipFiles = Get-ChildItem $vmAppsFolder -Filter "*.zip" -File
    if (-not $zipFiles) {
        Write-Log "No zip files found" "WARN"
        return $false
    }
    Write-Log "Found $($zipFiles.Count) app(s)" "INFO"; Write-Host ""
    if (!(Test-VMState -VMName $VMName -RequiredState "Off")) {
        Write-Log "Failed to stop VM" "ERROR"
        return $false
    }
    try {
        $mountInfo = Mount-VMDisk -VHDPath $vhd
        $mp = $mountInfo.MountPoint
        Show-Spinner "Detecting user account..." 1
        $userProfile = Get-ChildItem "$mp\Users" -Directory -EA SilentlyContinue | Where-Object { $_.Name -notin @("Public","Administrator","Default","Default.migrated") } | Select-Object -First 1
        if (!$userProfile) {
            Write-Log "No user profile found" "ERROR"
            return $false
        }
        $destPath = "$mp\Users\$($userProfile.Name)\Downloads\VM Apps"
        New-DirectorySafe -Path $destPath
        Write-Log "Copying apps..." "INFO"
        $success = ($zipFiles | ForEach-Object {
            if (Copy-ItemWithLogging -SourcePath $_.FullName -DestinationPath $destPath -ItemName $_.Name) { $true }
        } | Measure-Object -Sum).Count
        Write-Host ""
        Write-Box "COPIED: $success/$($zipFiles.Count) files" "-"
        Write-Log "Location: Users\$($userProfile.Name)\Downloads\VM Apps" "INFO"; Write-Host ""
        return $true
    } catch {
        Write-Log "Copy failed: $_" "ERROR"
        return $false
    } finally {
        Dismount-VMDisk -MountInfo $mountInfo -VHDPath $vhd
    }
}



function Invoke-CompleteSetup {
    Write-Log "Starting complete setup..." "HEADER"; Write-Host ""
    $config = Get-VMConfig
    if ($config -eq $null) {
        Write-Log "Setup cancelled" "WARN"
        return
    }
    $vmName = Initialize-VM -Config $config
    if (!$vmName) { return }
    Write-Host ""

    # GPU FIRST
    $gpuSelection = Select-GPUForPartition
    if (-not $gpuSelection) {
        Write-Log "GPU selection cancelled" "WARN"
        return
    }

    # THEN PERCENTAGE
    $gpuPercent = Get-ValidatedInput -Prompt "GPU Allocation % (default: 50)" -Validator { param($v) [string]::IsNullOrWhiteSpace($v) -or ([int]::TryParse($v, [ref]$null) -and [int]$v -ge 1 -and [int]$v -le 100) } -DefaultValue "50"
    $gpuResult = Set-GPUPartition -VMName $vmName -Percentage ([int]$gpuPercent) -InstancePath $gpuSelection.InstancePath -GPUName $gpuSelection.FriendlyName
    if (!$gpuResult) {
        Write-Log "GPU config failed" "ERROR"
        return
    }
    Write-Host ""
    Write-Box "SETUP COMPLETE: $vmName" "-"
    Write-Log "Now attempting automatic GPU driver injection." "INFO"
    Write-Host ""
    $result = Install-GPUDrivers -VMName $vmName
    if (-not $result) {
        Write-Log "Driver injection could not complete." "WARN"
        Write-Host "Please install Windows inside the VM first, then run driver injection (option 3)." -ForegroundColor Yellow
    } else {
        Write-Log "Complete setup finished successfully." "SUCCESS"
    }
    Write-Host ""
}



#endregion



#region Information Display



function Show-VmInfo {
    Write-Box "HYPER-V VIRTUAL MACHINES"
    Write-Log "Gathering VM info..." "INFO"; Write-Host ""
    $vms = Get-VM
    if (-not $vms) {
        Write-Log "No VMs found" "WARN"; Write-Host ""
        Read-Host "  Press Enter"
        return
    }
    $line = "+{0}+{1}+{2}+{3}+{4}+{5}+" -f ('-'*20),('-'*10),('-'*9),('-'*9),('-'*11),('-'*9)
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ("  | {0,-18} | {1,-8} | {2,-7} | {3,-7} | {4,-9} | {5,-7} |" -f "VM", "State", "RAM(GB)", "CPU", "Storage", "GPU") -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor Cyan
    $vms | ForEach-Object {
        $vhdSize = 0
        try {
            $vhdInfo = $_.VMId | Get-VHD -EA SilentlyContinue
            if ($vhdInfo) { $vhdSize = [math]::Round($vhdInfo.Size / 1GB, 0) }
        } catch {}
        $ramSource = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $ram = [math]::Round($ramSource / 1GB, 0)
        $stateColor = if ($_.State -eq "Running") { "Green" } else { "Yellow" }
        $gpuAdapter = Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue
        $gpuPercent = "None"
        if ($gpuAdapter) {
            try {
                $gpuPercent = [math]::Round(($gpuAdapter.MaxPartitionVRAM / 1000000000) * 100, 0)
                $gpuPercent = "$gpuPercent%"
            } catch {
                $gpuPercent = "?"
            }
        }
        Write-Host ("  | {0,-18} | {1,-8} | {2,-7} | {3,-7} | {4,-9} | {5,-7} |" -f $_.Name, $_.State, $ram, $_.ProcessorCount, $vhdSize, $gpuPercent) -ForegroundColor $stateColor
    }
    Write-Host "  $line" -ForegroundColor Cyan
    Write-Host ""
    Read-Host "  Press Enter"
}



function Show-GpuInfo {
    Write-Box "HOST GPU INFORMATION"
    $gpus = Get-WmiObject Win32_VideoController -EA SilentlyContinue | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if ($gpus) {
        $gpus | ForEach-Object {
            Write-Host "  GPU: $($_.Name)" -ForegroundColor Green
            Write-Host "  Driver Version: $($_.DriverVersion)" -ForegroundColor Green
            Write-Host "  Driver Date: $($_.DriverDate)" -ForegroundColor Green
            $vramGB = $null; $vramSource = "unknown"
            if ($_.Name -like "*NVIDIA*") {
                try {
                    $nvidiaSmi = nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
                    if ($nvidiaSmi -and $nvidiaSmi -match '^\d+$') {
                        $vramGB = [math]::Round([int]$nvidiaSmi / 1024, 2)
                        $vramSource = "nvidia-smi"
                    }
                } catch {}
            } elseif ($_.Name -like "*AMD*" -or $_.Name -like "*Radeon*") {
                try {
                    $rocmOutput = rocm-smi --showmeminfo --showid 2>$null
                    if ($rocmOutput) {
                        $match = $rocmOutput | Select-String "GPU Memory:" | Select-Object -First 1
                        if ($match) {
                            $memMatch = [regex]::Matches($match.Line, '\d+')
                            if ($memMatch.Count -ge 2) {
                                $vramGB = [math]::Round([int]$memMatch[1].Value / 1024, 2)
                                $vramSource = "rocm-smi"
                            }
                        }
                    }
                } catch {}
            } elseif ($_.Name -like "*Intel*" -or $_.Name -like "*Arc*") {
                try {
                    $intelReg = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*" -Name "HardwareInformation.qxvram" -EA SilentlyContinue | Where-Object { $_."HardwareInformation.qxvram" } | Select-Object -First 1
                    if ($intelReg -and $intelReg."HardwareInformation.qxvram") {
                        $vramGB = [math]::Round([int]$intelReg."HardwareInformation.qxvram" / 1GB, 2)
                        $vramSource = "registry"
                    }
                } catch {}
            }
            if ($null -eq $vramGB -or $vramGB -eq 0) {
                if ($_.AdapterRAM -and $_.AdapterRAM -gt 0) {
                    $vramGB = [math]::Round($_.AdapterRAM / 1GB, 2)
                    $vramSource = "WMI (unreliable)"
                    Write-Host "  VRAM: $vramGB GB ($vramSource - may be inaccurate)" -ForegroundColor Yellow
                } else {
                    Write-Host "  VRAM: Unknown (no VRAM data available)" -ForegroundColor Yellow
                }
            } else {
                Write-Host "  VRAM: $vramGB GB ($vramSource)" -ForegroundColor Green
            }
            $status = if ($_.Status -eq "OK") { "OK" } else { $_.Status }
            Write-Host "  Status: $status" -ForegroundColor $(if ($status -eq "OK") { "Green" } else { "Yellow" })
            Write-Host ""
        }
    } else {
        Write-Log "No discrete GPU detected" "WARN"
    }
    Read-Host "  Press Enter"
}



#endregion



#region Main Menu Loop



$menuItems = @(
    "Create New VM",
    "Configure GPU Partition",
    "Inject GPU Drivers (Auto-Detect)",
    "Complete Setup (VM + GPU + Drivers)",
    "Update VM Drivers (Auto-Detect)",
    "List VMs",
    "Show Host GPU Info",
    "Copy VM Apps to Downloads",
    "Exit"
)
$selectedIndex = 0



while ($true) {
    $selectedIndex = Select-Menu -Items $menuItems -Title "MAIN MENU"
    if ($selectedIndex -eq $null) {
        Write-Log "Menu cancelled by user (ESC pressed)." "INFO"
        continue
    }
    Write-Host ""
    switch ($selectedIndex) {
        0 { Initialize-VM -Config (Get-VMConfig); Read-Host "`n  Press Enter" }
        1 { Set-GPUPartition; Read-Host "`n  Press Enter" }
        2 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        3 { Invoke-CompleteSetup; Read-Host "`n  Press Enter" }
        4 { Install-GPUDrivers; Read-Host "`n  Press Enter" }
        5 { Show-VmInfo }
        6 { Show-GpuInfo }
        7 { Copy-VMApps; Read-Host "`n  Press Enter" }
        8 { Write-Log "Exiting..." "INFO"; exit }
    }
    $selectedIndex = ($selectedIndex + 1) % $menuItems.Count
}



#endregion
