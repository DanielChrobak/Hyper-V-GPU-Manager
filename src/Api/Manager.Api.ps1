#region API Results
function New-HyperVGpuApiResult($Operation, $Success, $Data=$null, $Message=$null) {
    return [PSCustomObject]@{
        Operation = $Operation
        Success = [bool]$Success
        Data = $Data
        Message = if ($Message) { "$Message" } else { $null }
        TimestampUtc = (Get-Date).ToUniversalTime().ToString("o")
    }
}
#endregion

#region API Preflight
function Invoke-HyperVGpuApiPreflight {
    Box "STARTUP CHECKS" "-"

    $requiredCmdlets = @(
        "Get-VM",
        "New-VM",
        "Set-VM",
        "Get-VMGpuPartitionAdapter",
        "Add-VMGpuPartitionAdapter",
        "Set-VMGpuPartitionAdapter",
        "Remove-VMGpuPartitionAdapter"
    )
    $missingCmdlets = @($requiredCmdlets | Where-Object { !(Get-Command $_ -EA SilentlyContinue) })
    if ($missingCmdlets.Count -gt 0) {
        $message = "Hyper-V cmdlets unavailable: $($missingCmdlets -join ', ')"
        Log $message "ERROR"
        Log "Enable Hyper-V and restart Windows, then run this tool again." "ERROR"
        return (New-HyperVGpuApiResult -Operation "preflight" -Success $false -Message $message)
    }

    $edition = $null
    try { $edition = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -EA Stop).EditionID } catch {}
    if ($edition -and $edition -match "Home") {
        Log "Detected Windows edition '$edition'. Hyper-V GPU workloads are typically unavailable on Home editions." "WARN"
    }

    $vmms = Get-Service -Name "vmms" -EA SilentlyContinue
    if ($vmms -and $vmms.Status -ne "Running") {
        Log "Hyper-V Virtual Machine Management service is not running." "WARN"
    }

    $partitionable = @()
    try { $partitionable = @(GetPartitionableGPUs) } catch {}
    if ($partitionable.Count -gt 0) {
        Log "Detected $($partitionable.Count) partitionable host device(s)." "SUCCESS"
    } else {
        Log "No partitionable devices detected right now. GPU Partition may fail until host prerequisites are met." "WARN"
    }

    Write-Host ""
    return (New-HyperVGpuApiResult -Operation "preflight" -Success $true -Message "Preflight checks completed.")
}
#endregion

#region API Query
function Get-HyperVGpuVmSummary {
    $vms = @(Get-VM -EA SilentlyContinue)
    if (!$vms) { return @() }

    $gpuAdapterMap = GetVmGpuAdapterMap $vms
    return @($vms | ForEach-Object {
        $storage = "0GB"
        try {
            $v = Get-VHD -VMId $_.VMId -EA SilentlyContinue
            if ($v) { $storage = FormatCapacityFromBytes $v.Size }
        } catch {}

        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $ram = FormatCapacityFromBytes $mem

        $ga = if ($gpuAdapterMap.ContainsKey($_.Name)) { @($gpuAdapterMap[$_.Name]) } else { @() }
        $gpu = if ($ga) { GpuSummary -Adapters $ga } else { "None" }

        [PSCustomObject]@{
            Name = $_.Name
            State = "$($_.State)"
            Cpu = [int]$_.ProcessorCount
            Ram = $ram
            Storage = $storage
            Gpu = $gpu
        }
    })
}

function Get-HyperVGpuHostGpuSummary {
    $gpus = @(GetCompatManagementInstances "Win32_VideoController") | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if (!$gpus) { return @() }

    $partitionPaths = @(GetPartitionableGPUs | ForEach-Object { GetPartitionablePath $_ })
    $partitionIdentity = @{}
    foreach ($pp in $partitionPaths) {
        if ("$pp" -match "VEN_([0-9A-Fa-f]{4}).*DEV_([0-9A-Fa-f]{4})") {
            $key = "VEN_$($matches[1].ToUpperInvariant())&DEV_$($matches[2].ToUpperInvariant())"
            $partitionIdentity[$key] = $true
        }
    }

    return @($gpus | ForEach-Object {
        $partitionable = $false
        if ($_.PNPDeviceID -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") {
            $idKey = "VEN_$($matches[1].ToUpperInvariant())&DEV_$($matches[2].ToUpperInvariant())"
            $partitionable = $partitionIdentity.ContainsKey($idKey)
        }

        [PSCustomObject]@{
            Name = $_.Name
            Status = "$($_.Status)"
            DriverVersion = if ($_.DriverVersion) { "$($_.DriverVersion)" } else { "Unknown" }
            Provider = if ($_.DriverProviderName) { "$($_.DriverProviderName)" } elseif ($_.AdapterCompatibility) { "$($_.AdapterCompatibility)" } else { "Unknown" }
            Partitionable = [bool]$partitionable
            DeviceId = if ($_.PNPDeviceID) { "$($_.PNPDeviceID)" } else { $null }
        }
    })
}
#endregion

#region API Actions
function Invoke-HyperVGpuApiCreateVm(
    [string]$Name,
    [int]$Cpu,
    [int]$RamGB,
    [int]$StorageGB,
    [string]$VhdPath,
    [string]$IsoPath,
    [switch]$EnableAutoInstall,
    $ImageSelection=$null,
    $LocalAccountConfig=$null,
    [switch]$OverwriteVhd
) {
    $cfg = [PSCustomObject]@{
        Name = $Name
        CPU = $Cpu
        RAM = $RamGB
        Storage = $StorageGB
        Path = if ($VhdPath) { $VhdPath } else { $script:Paths.VHD }
        ISO = if ($IsoPath) { $IsoPath } else { $null }
    }

    $result = NewVM -Config $cfg -NonInteractive -EnableAutoInstall:$EnableAutoInstall -ImageSelection $ImageSelection -LocalAccountConfig $LocalAccountConfig -OverwriteVhd:$OverwriteVhd
    if ($result -is [string] -and ![string]::IsNullOrWhiteSpace($result)) {
        return (New-HyperVGpuApiResult -Operation "create-vm" -Success $true -Data ([PSCustomObject]@{ VmName = $result }) -Message "VM created successfully.")
    }

    if ($null -eq $result) {
        return (New-HyperVGpuApiResult -Operation "create-vm" -Success $false -Message "VM creation cancelled.")
    }

    return (New-HyperVGpuApiResult -Operation "create-vm" -Success $false -Message "VM creation failed.")
}

function Invoke-HyperVGpuApiSetGpu(
    [string]$VmName,
    [int]$Percent,
    [string]$GpuPath,
    [string]$GpuName
) {
    $result = SetGPU -VMName $VmName -Pct $Percent -GPUPath $GpuPath -GPUName $GpuName -NonInteractive
    return (New-HyperVGpuApiResult -Operation "set-gpu" -Success ([bool]$result) -Data ([PSCustomObject]@{ VmName = $VmName; Percent = $Percent; GpuPath = $GpuPath }) -Message (if ($result) { "GPU partition configured." } else { "GPU partition configuration failed." }))
}

function Invoke-HyperVGpuApiRemoveGpu(
    [string]$VmName,
    [string]$GpuPath,
    [switch]$All,
    [switch]$CleanDrivers
) {
    $result = RemoveGPU -VMName $VmName -GPUPath $GpuPath -All:$All -CleanDrivers:$CleanDrivers -NonInteractive
    return (New-HyperVGpuApiResult -Operation "remove-gpu" -Success ([bool]$result) -Data ([PSCustomObject]@{ VmName = $VmName; GpuPath = $GpuPath; All = [bool]$All; CleanDrivers = [bool]$CleanDrivers }) -Message (if ($result) { "GPU partition removed." } else { "GPU partition removal failed." }))
}

function Invoke-HyperVGpuApiInstallDrivers(
    [string]$VmName,
    [string]$GpuPath,
    [switch]$All,
    [switch]$SkipExisting
) {
    $result = InstallDrivers -VMName $VmName -GPUPath $GpuPath -All:$All -SkipExisting:$SkipExisting -NonInteractive
    return (New-HyperVGpuApiResult -Operation "install-drivers" -Success ([bool]$result) -Data ([PSCustomObject]@{ VmName = $VmName; GpuPath = $GpuPath; All = [bool]$All; SkipExisting = [bool]$SkipExisting }) -Message (if ($result) { "Driver injection completed." } else { "Driver injection failed." }))
}

function Invoke-HyperVGpuApiDeleteVm(
    [string]$VmName,
    [switch]$DeleteFiles,
    [switch]$Force
) {
    $result = DeleteVM -VMName $VmName -DeleteFiles:$DeleteFiles -Force:$Force -NonInteractive
    return (New-HyperVGpuApiResult -Operation "delete-vm" -Success ([bool]$result) -Data ([PSCustomObject]@{ VmName = $VmName; DeleteFiles = [bool]$DeleteFiles }) -Message (if ($result) { "VM deleted." } else { "VM deletion failed." }))
}

function Invoke-HyperVGpuApiListVms {
    $data = @(Get-HyperVGpuVmSummary)
    return (New-HyperVGpuApiResult -Operation "list-vms" -Success $true -Data $data -Message "VM inventory collected.")
}

function Invoke-HyperVGpuApiListGpus {
    $data = @(Get-HyperVGpuHostGpuSummary)
    return (New-HyperVGpuApiResult -Operation "list-gpus" -Success $true -Data $data -Message "Host GPU inventory collected.")
}
#endregion
