function Show-HyperVGpuCliHelp {
    Write-Host ""
    Box "CLI COMMANDS" "-"
    Write-Host "  Command values:" -ForegroundColor Gray
    Write-Host "    interactive      Start menu-driven UI (default)" -ForegroundColor Gray
    Write-Host "    preflight        Run startup checks only" -ForegroundColor Gray
    Write-Host "    create-vm        Create VM without prompts" -ForegroundColor Gray
    Write-Host "    set-gpu          Assign GPU partition without prompts" -ForegroundColor Gray
    Write-Host "    remove-gpu       Remove GPU partition without prompts" -ForegroundColor Gray
    Write-Host "    install-drivers  Inject host drivers into VM without prompts" -ForegroundColor Gray
    Write-Host "    delete-vm        Delete VM without prompts" -ForegroundColor Gray
    Write-Host "    list-vms         Show VM inventory" -ForegroundColor Gray
    Write-Host "    list-gpus        Show host GPU inventory" -ForegroundColor Gray
    Write-Host "    help             Show this command help" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Examples:" -ForegroundColor Gray
    Write-Host "    .\HyperV-GPU-Virtualization-Manager.ps1 -Command create-vm -Preset gaming -VMName GameVM -IsoPath C:\ISOs\Win11.iso -OverwriteVhd" -ForegroundColor Gray
    Write-Host "    .\HyperV-GPU-Virtualization-Manager.ps1 -Command set-gpu -VMName GameVM -GpuPath '<instance path>' -GpuPercent 50" -ForegroundColor Gray
    Write-Host "    .\HyperV-GPU-Virtualization-Manager.ps1 -Command list-vms -Json" -ForegroundColor Gray
    Write-Host ""
}

function Write-HyperVGpuCliResult($Result, [switch]$Json) {
    if ($Json) {
        $Result | ConvertTo-Json -Depth 10
        return
    }

    if ($Result.Success) {
        if ($Result.Message) { Log $Result.Message "SUCCESS" }
    } else {
        if ($Result.Message) { Log $Result.Message "ERROR" }
    }

    if ($null -eq $Result.Data) { return }

    if ($Result.Data -is [System.Array]) {
        if ($Result.Data.Count -eq 0) {
            Log "No results." "INFO"
            return
        }
        $Result.Data | Format-Table -AutoSize
        return
    }

    $Result.Data | Format-List
}

function Resolve-HyperVGpuCliVmConfig(
    [string]$Preset,
    [string]$VMName,
    [int]$Cpu,
    [int]$RamGB,
    [int]$StorageGB,
    [string]$VhdPath,
    [string]$IsoPath
) {
    $presetKey = if ($Preset) { $Preset.ToLowerInvariant() } else { "development" }

    $presetDefaults = switch ($presetKey) {
        "gaming" { [PSCustomObject]@{Name="Gaming-VM"; Cpu=8; Ram=16; Storage=256} }
        "development" { [PSCustomObject]@{Name="Dev-VM"; Cpu=4; Ram=8; Storage=128} }
        "ml" { [PSCustomObject]@{Name="ML-VM"; Cpu=12; Ram=32; Storage=512} }
        "ml-training" { [PSCustomObject]@{Name="ML-VM"; Cpu=12; Ram=32; Storage=512} }
        "custom" { $null }
        default { $null }
    }

    $resolvedName = if ($VMName) { $VMName } elseif ($presetDefaults) { $presetDefaults.Name } else { $null }
    $resolvedCpu = if ($Cpu -gt 0) { $Cpu } elseif ($presetDefaults) { $presetDefaults.Cpu } else { 0 }
    $resolvedRam = if ($RamGB -gt 0) { $RamGB } elseif ($presetDefaults) { $presetDefaults.Ram } else { 0 }
    $resolvedStorage = if ($StorageGB -gt 0) { $StorageGB } elseif ($presetDefaults) { $presetDefaults.Storage } else { 0 }

    if ([string]::IsNullOrWhiteSpace($resolvedName) -or $resolvedCpu -le 0 -or $resolvedRam -le 0 -or $resolvedStorage -le 0) {
        Log "create-vm requires VMName, Cpu, RamGB, and StorageGB (or a preset with defaults)." "ERROR"
        return $null
    }

    return [PSCustomObject]@{
        Name = $resolvedName
        Cpu = $resolvedCpu
        RamGB = $resolvedRam
        StorageGB = $resolvedStorage
        VhdPath = if ($VhdPath) { $VhdPath } else { $script:Paths.VHD }
        IsoPath = if ($IsoPath) { $IsoPath } else { $null }
    }
}

function Invoke-HyperVGpuCliCommand(
    [string]$Command,
    [string]$VMName,
    [string]$GpuPath,
    [string]$GpuName,
    [int]$GpuPercent,
    [string]$Preset,
    [int]$Cpu,
    [int]$RamGB,
    [int]$StorageGB,
    [string]$VhdPath,
    [string]$IsoPath,
    [switch]$EnableAutoInstall,
    [int]$InstallImageIndex,
    [string]$UnattendUsername,
    [string]$UnattendPassword,
    [switch]$OverwriteVhd,
    [switch]$All,
    [switch]$CleanDrivers,
    [switch]$SkipExisting,
    [switch]$DeleteFiles,
    [switch]$Force,
    [switch]$Json
) {
    $cmd = if ($Command) { $Command.ToLowerInvariant() } else { "interactive" }

    switch ($cmd) {
        "interactive" {
            return (Start-HyperVGpuInteractiveMenu)
        }

        "help" {
            Show-HyperVGpuCliHelp
            return $true
        }

        "preflight" {
            $result = Invoke-HyperVGpuApiPreflight
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "create-vm" {
            $cfg = Resolve-HyperVGpuCliVmConfig -Preset $Preset -VMName $VMName -Cpu $Cpu -RamGB $RamGB -StorageGB $StorageGB -VhdPath $VhdPath -IsoPath $IsoPath
            if (!$cfg) { return $false }

            $imageSelection = $null
            if ($InstallImageIndex -gt 0) {
                $imageSelection = [PSCustomObject]@{
                    Index = $InstallImageIndex
                    Name = "Image-$InstallImageIndex"
                }
            }

            $localAccount = $null
            if ($UnattendUsername -or $UnattendPassword) {
                $localAccount = [PSCustomObject]@{
                    Username = if ($UnattendUsername) { $UnattendUsername } else { "" }
                    Password = if ($UnattendPassword) { $UnattendPassword } else { "" }
                }
            }

            $result = Invoke-HyperVGpuApiCreateVm -Name $cfg.Name -Cpu $cfg.Cpu -RamGB $cfg.RamGB -StorageGB $cfg.StorageGB -VhdPath $cfg.VhdPath -IsoPath $cfg.IsoPath -EnableAutoInstall:$EnableAutoInstall -ImageSelection $imageSelection -LocalAccountConfig $localAccount -OverwriteVhd:$OverwriteVhd
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "set-gpu" {
            if ([string]::IsNullOrWhiteSpace($VMName) -or [string]::IsNullOrWhiteSpace($GpuPath) -or $GpuPercent -le 0) {
                Log "set-gpu requires VMName, GpuPath, and GpuPercent (1-100)." "ERROR"
                return $false
            }

            $result = Invoke-HyperVGpuApiSetGpu -VmName $VMName -Percent $GpuPercent -GpuPath $GpuPath -GpuName $GpuName
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "remove-gpu" {
            if ([string]::IsNullOrWhiteSpace($VMName)) {
                Log "remove-gpu requires VMName." "ERROR"
                return $false
            }

            $effectiveAll = if ($All -or [string]::IsNullOrWhiteSpace($GpuPath)) { $true } else { $false }
            $result = Invoke-HyperVGpuApiRemoveGpu -VmName $VMName -GpuPath $GpuPath -All:$effectiveAll -CleanDrivers:$CleanDrivers
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "install-drivers" {
            if ([string]::IsNullOrWhiteSpace($VMName)) {
                Log "install-drivers requires VMName." "ERROR"
                return $false
            }

            $effectiveAll = if ($All -or [string]::IsNullOrWhiteSpace($GpuPath)) { $true } else { $false }
            $result = Invoke-HyperVGpuApiInstallDrivers -VmName $VMName -GpuPath $GpuPath -All:$effectiveAll -SkipExisting:$SkipExisting
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "delete-vm" {
            if ([string]::IsNullOrWhiteSpace($VMName)) {
                Log "delete-vm requires VMName." "ERROR"
                return $false
            }

            $result = Invoke-HyperVGpuApiDeleteVm -VmName $VMName -DeleteFiles:$DeleteFiles -Force:$Force
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "list-vms" {
            $result = Invoke-HyperVGpuApiListVms
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        "list-gpus" {
            $result = Invoke-HyperVGpuApiListGpus
            Write-HyperVGpuCliResult -Result $result -Json:$Json
            return [bool]$result.Success
        }

        default {
            Log "Unknown command: $Command" "ERROR"
            Show-HyperVGpuCliHelp
            return $false
        }
    }
}
