#region Main Functions
function NewVM {
    $items = @($script:Presets | ForEach-Object { $_.L }) + "Custom"
    $ch = Menu -Items $items -Title "VM CONFIG"
    if ($null -eq $ch) { return $null }
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

    if ($cfg.ISO -and !(Test-Path $cfg.ISO)) {
        Log "ISO path not found: $($cfg.ISO)" "WARN"
        if (!(Confirm "Continue creating VM without attaching an ISO?")) {
            Log "Cancelled" "WARN"
            return $null
        }
        $cfg.ISO = $null
    }

    $iso = $null
    if ($cfg.ISO -and (Test-Path $cfg.ISO)) {
        Write-Host ""
        if (Confirm "Enable automated Windows installation? (Skips most setup screens)") {
            $imageSelection = $null
            $localAccountConfig = $null
            $imageOptions = GetWindowsInstallImageOptions $cfg.ISO
            if ($imageOptions -and $imageOptions.Count -gt 0) {
                $imageSelection = PromptWindowsInstallImageSelection $imageOptions
            } else {
                Log "Could not enumerate Windows installation options; setup edition selection will remain manual." "INFO"
            }

            if (Confirm "Set local username/password in unattended setup?") {
                $unattendUsername = Read-Host "  Username (leave empty for default: User)"
                $unattendPassword = Read-Host "  Password (can be empty)"
                $localAccountConfig = [PSCustomObject]@{
                    Username = "$unattendUsername"
                    Password = "$unattendPassword"
                }

                $effectiveUsername = if ([string]::IsNullOrWhiteSpace($unattendUsername)) { "User" } else { $unattendUsername.Trim() }
                Log ("Unattended local account will be created: {0}" -f $effectiveUsername) "INFO"
            }

            $iso = NewAutoISO $cfg.ISO $cfg.Name $imageSelection $localAccountConfig
            if ($iso) { Log "Will use automated installation ISO" "SUCCESS"; Write-Host "" }
            else {
                Log "Falling back to original ISO" "WARN"
                if ($script:LastAutoUnattendFallbackPath) {
                    Log "autounattend.xml exported: $script:LastAutoUnattendFallbackPath" "INFO"
                    Log "Use this file with your installation media if you still want unattended setup." "INFO"
                }
                $iso = $cfg.ISO
                Write-Host ""
            }
        } else { $iso = $cfg.ISO }
    }
    Box "CREATING VM"; Log "VM: $($cfg.Name) | vCPU: $($cfg.CPU) | RAM: $(FormatCapacityFromGB $cfg.RAM) | Storage: $(FormatCapacityFromGB $cfg.Storage)" "INFO"; Write-Host ""
    $vhd = Join-Path $cfg.Path "$($cfg.Name).vhdx"
    if (Get-VM $cfg.Name -EA SilentlyContinue) { Log "VM already exists" "ERROR"; return $false }
    if ((Test-Path $vhd) -and !(Confirm "VHDX exists. Overwrite?")) { Log "Cancelled" "WARN"; return $null }
    if (Test-Path $vhd) { Remove-Item $vhd -Force }

    $requiredBytes = ([int64]$cfg.Storage * 1GB) + 2GB
    $freeBytes = GetFreeBytesForPath $vhd
    if ($null -eq $freeBytes) {
        Log "Could not verify free disk space for VHD target path. Continuing anyway." "WARN"
    } elseif ($freeBytes -lt $requiredBytes) {
        $reqGB = [Math]::Ceiling($requiredBytes / 1GB)
        $freeGB = [Math]::Floor($freeBytes / 1GB)
        Log "Insufficient free disk space for VHD creation. Required ~${reqGB}GB, available ${freeGB}GB." "ERROR"
        return $false
    }

    $r = Try-Op {
        Spin "Creating VM..." 2; EnsureDir $cfg.Path
        New-VM -Name $cfg.Name -MemoryStartupBytes ([int64]$cfg.RAM * 1GB) -Generation 2 -NewVHDPath $vhd -NewVHDSizeBytes ([int64]$cfg.Storage * 1GB) | Out-Null
        Spin "Configuring..." 1
        Set-VMProcessor $cfg.Name -Count $cfg.CPU
        Set-VMMemory $cfg.Name -DynamicMemoryEnabled $false
        $vmSettings = @{
            Name = $cfg.Name
            CheckpointType = "Disabled"
            AutomaticStopAction = "ShutDown"
            AutomaticStartAction = "Nothing"
            AutomaticCheckpointsEnabled = $false
        }
        if (TestHyperVCmdletParameter "Set-VM" "EnhancedSessionTransportType") {
            $vmSettings.EnhancedSessionTransportType = "VMBus"
        }
        Set-VM @vmSettings
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
        Log "vCPU: $($cfg.CPU) | RAM: $(FormatCapacityFromGB $cfg.RAM) | Storage: $(FormatCapacityFromGB $cfg.Storage)" "SUCCESS"; Write-Host ""
        return $cfg.Name
    } "VM Creation"
    if ($r.OK) { return $r.R } else { return $false }
}

function ResolveGuestSystemDestinationPath($DestinationPath) {
    if (-not $script:DriverStorePrefix) {
        $script:DriverStorePrefix = '\Windows\System32\DriverStore\FileRepository\'
        $script:DriverStorePrefixNorm = $script:DriverStorePrefix.ToLowerInvariant()
        $script:HostDriverStoreRoot = '\Windows\System32\HostDriverStore\FileRepository'
    }

    $relDest = "$DestinationPath"
    if ([string]::IsNullOrWhiteSpace($relDest)) { return $null }

    if ($relDest -match '^[A-Za-z]:') { $relDest = $relDest.Substring(2) }
    $relDest = $relDest.Trim()
    $relDest = $relDest -replace '/', '\'
    $relDest = $relDest -replace '\\+', '\'
    if (!$relDest.StartsWith('\')) { $relDest = '\' + $relDest.TrimStart('\') }

    $normalized = $relDest.ToLowerInvariant()
    if ($normalized -eq '\windows\system32\cmd.exe') { return $null }

    if ($normalized.StartsWith($script:DriverStorePrefixNorm)) {
        $tail = $relDest.Substring($script:DriverStorePrefix.Length).TrimStart([char]'\')
        if ($tail) { return "$($script:HostDriverStoreRoot)\$tail" }
        return $script:HostDriverStoreRoot
    }

    return $relDest
}

function SetGPU($VMName=$null, $Pct=0, $GPUPath=$null, $GPUName=$null) {
    if (!$VMName) { $vm = SelectVM "GPU PARTITION VM"; if (!$vm) { return $null }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Log "VM not found" "ERROR"; Write-Host ""; return $false }
    if (!$GPUPath) {
        $g = SelectGPU "SELECT GPU FOR PARTITIONING" -Partition
        if (!$g) { return $null }
        $GPUPath = $g.P
        $GPUName = $g.N
    }
    if ($Pct -eq 0) { Write-Host ""; $Pct = [int](Input "GPU % to allocate (1-100)" { [int]::TryParse($_, [ref]$null) -and [int]$_ -ge 1 -and [int]$_ -le 100 }) }
    $Pct = [Math]::Max(1, [Math]::Min(100, $Pct))
    if (!$GPUName) { $GPUName = (GPUName $GPUPath); if (!$GPUName) { $GPUName = "GPU" } }
    Box "GPU PARTITION"; Log "VM: $VMName | GPU: $GPUName | $Pct%" "INFO"; Write-Host ""
    if (!(EnsureOff $VMName)) { Write-Host ""; return $false }
    $r = Try-Op {
        Spin "Configuring GPU partition..." 2
        $existing = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)
        $target = $null
        $targetKey = GetGpuIdentityKey $GPUPath
        if ($targetKey) {
            $target = $existing | Where-Object { (GetGpuIdentityKey $_.InstancePath) -eq $targetKey } | Select-Object -First 1
        }

        $supportsInstancePath = ($GPUPath -and (TestHyperVCmdletParameter "Add-VMGpuPartitionAdapter" "InstancePath"))
        if (!$target) {
            if ($supportsInstancePath) {
                $target = Add-VMGpuPartitionAdapter -VMName $VMName -InstancePath $GPUPath -Passthru -EA Stop
            } else {
                if ($GPUPath) { Log "This Windows build does not support -InstancePath; specific multi-GPU targeting may be limited." "WARN" }
                if ($existing) {
                    $target = $existing | Select-Object -First 1
                } else {
                    $target = Add-VMGpuPartitionAdapter -VMName $VMName -Passthru -EA Stop
                }
            }
        }

        if (!$target) { throw "Unable to determine target GPU partition adapter." }

        $partitionableGpu = GetPartitionableGpuByPath $GPUPath
        $vramAlloc = GetGpuPartitionResourceAllocation -PartitionableGpu $partitionableGpu -ResourceName "VRAM" -Percent $Pct -Fallback 1000000000
        $encodeAlloc = GetGpuPartitionResourceAllocation -PartitionableGpu $partitionableGpu -ResourceName "Encode" -Percent $Pct -Fallback 1000000000
        $decodeAlloc = GetGpuPartitionResourceAllocation -PartitionableGpu $partitionableGpu -ResourceName "Decode" -Percent $Pct -Fallback 1000000000
        $computeAlloc = GetGpuPartitionResourceAllocation -PartitionableGpu $partitionableGpu -ResourceName "Compute" -Percent $Pct -Fallback 1000000000
        $partitionParams = @{
            MinPartitionVRAM = $vramAlloc.Min
            MaxPartitionVRAM = $vramAlloc.Max
            OptimalPartitionVRAM = $vramAlloc.Optimal
            MinPartitionEncode = $encodeAlloc.Min
            MaxPartitionEncode = $encodeAlloc.Max
            OptimalPartitionEncode = $encodeAlloc.Optimal
            MinPartitionDecode = $decodeAlloc.Min
            MaxPartitionDecode = $decodeAlloc.Max
            OptimalPartitionDecode = $decodeAlloc.Optimal
            MinPartitionCompute = $computeAlloc.Min
            MaxPartitionCompute = $computeAlloc.Max
            OptimalPartitionCompute = $computeAlloc.Optimal
        }

        $supportsAdapterId = TestHyperVCmdletParameter "Set-VMGpuPartitionAdapter" "AdapterId"
        if ($supportsAdapterId -and $target.AdapterId) {
            Set-VMGpuPartitionAdapter -VMName $VMName -AdapterId $target.AdapterId @partitionParams -EA Stop
        } else {
            Set-VMGpuPartitionAdapter -VMGpuPartitionAdapter $target @partitionParams -EA Stop
        }
        Set-VM $VMName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace 1GB -HighMemoryMappedIoSpace 32GB

        $applied = $null
        if ($supportsAdapterId -and $target.AdapterId) {
            $applied = Get-VMGpuPartitionAdapter -VMName $VMName -AdapterId $target.AdapterId -EA SilentlyContinue | Select-Object -First 1
        }
        if (!$applied -and $targetKey) {
            $applied = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue) | Where-Object { (GetGpuIdentityKey $_.InstancePath) -eq $targetKey } | Select-Object -First 1
        }
        if (!$applied) {
            $applied = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue) | Select-Object -First 1
        }
        if ($applied -and $vramAlloc.Capacity -gt 0 -and $applied.MaxPartitionVRAM -gt 0) {
            $effectivePct = [Math]::Round(([decimal]$applied.MaxPartitionVRAM / [decimal]$vramAlloc.Capacity) * 100)
            $effectivePct = [Math]::Max(1, [Math]::Min(100, [int]$effectivePct))
            Log "Applied partition VRAM max $($applied.MaxPartitionVRAM) (~$effectivePct% of detected capacity)." "INFO"
        }

        Write-Host ""; Box "GPU ALLOCATED: $Pct%" "-"; Write-Host ""; return $true
    } "GPU Config"
    if (!$r.OK) { Write-Host "" }
    return $r.OK
}

function RemoveGPU($VMName=$null) {
    if (!$VMName) { $vm = SelectVM "REMOVE GPU FROM VM"; if (!$vm) { return $null }; $VMName = $vm.Name }
    if (!(Get-VM $VMName -EA SilentlyContinue)) { Log "VM not found" "ERROR"; Write-Host ""; return $false }
    $allAdapters = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)
    if (!$allAdapters) { Log "No GPU partition found on this VM" "WARN"; Write-Host ""; return $false }

    $allEntries = @(GetGpuDisplayEntries -Adapters $allAdapters)
    Box "REMOVE GPU PARTITION"; Log "Target VM: $VMName" "INFO"; Write-Host ""

    $items = @()
    for ($i = 0; $i -lt $allEntries.Count; $i++) {
        $items += ("GPU{0}: {1}" -f ($i + 1).ToString("00"), $allEntries[$i].Label)
    }
    if ($allEntries.Count -gt 1) { $items += "All GPU partitions" }
    $items += "< Cancel >"

    $sel = Menu -Items $items -Title "SELECT GPU PARTITION TO REMOVE"
    if ($null -eq $sel -or $sel -eq ($items.Count - 1)) { Log "Cancelled" "WARN"; return $null }

    $removeAll = ($allEntries.Count -gt 1 -and $sel -eq ($items.Count - 2))
    if ($removeAll) {
        $selectedAdapters = $allAdapters
        $selectedEntries = $allEntries
    } else {
        $selectedAdapters = @($allAdapters[$sel])
        $selectedEntries = @($allEntries[$sel])
    }

    $selectedLabel = if ($removeAll) { "All GPU partitions" } else { $selectedEntries[0].Label }
    Log "Selection: $selectedLabel" "INFO"
    Write-Host ""

    if (!(Confirm "Remove the selected GPU partition assignment(s) from '$VMName'?")) { Log "Cancelled" "WARN"; return $null }
    $cleanDrivers = Confirm "Also remove matching injected driver files from the VM disk for the selected GPU partition(s)?"

    Write-Host ""; if (!(EnsureOff $VMName)) { return $false }

    $gpuList = @()
    $seenGpuIds = @{}
    foreach ($a in $selectedAdapters) {
        $meta = ResolvePartitionableDevice $a.InstancePath
        $gpu = if ($meta -and $meta.Class) { FindGPU $a.InstancePath $meta.Class } else { FindGPU $a.InstancePath }
        if ($gpu) {
            $gpuIdKey = if ($gpu.DeviceID) { "$($gpu.DeviceID)".ToLowerInvariant() } else { "" }
            if (!$seenGpuIds.ContainsKey($gpuIdKey)) {
                $seenGpuIds[$gpuIdKey] = $true
                $gpuList += $gpu
            }
        }
    }

    Spin "Removing selected GPU partition adapter(s)..." 2
    if (!(Try-Op {
        $supportsAdapterId = TestHyperVCmdletParameter "Remove-VMGpuPartitionAdapter" "AdapterId"
        if ($supportsAdapterId) {
            foreach ($a in $selectedAdapters) {
                if ($a.AdapterId) {
                    Remove-VMGpuPartitionAdapter -VMName $VMName -AdapterId $a.AdapterId -EA Stop | Out-Null
                } else {
                    $a | Remove-VMGpuPartitionAdapter -EA Stop
                }
            }
        } else {
            $selectedAdapters | Remove-VMGpuPartitionAdapter -EA Stop
        }
        Log "Selected GPU partition adapter(s) removed" "SUCCESS"
    } "Remove GPU Adapter").OK) { Write-Host ""; return $false }

    $remainingAdapters = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)
    $mmioReset = $false
    if (!$remainingAdapters) {
        Spin "Resetting memory-mapped IO settings..." 1
        if (!(Try-Op { Set-VM $VMName -GuestControlledCacheTypes $false -LowMemoryMappedIoSpace 0 -HighMemoryMappedIoSpace 0 -EA Stop; Log "Memory-mapped IO settings reset" "SUCCESS" } "Reset MMIO").OK) { Write-Host ""; return $false }
        $mmioReset = $true
    } else {
        Log "Other GPU partitions remain assigned; MMIO settings left unchanged" "INFO"
    }

    if (!$cleanDrivers) {
        Write-Host ""; Box "GPU REMOVAL COMPLETE" "-"
        Log "Selected GPU partition(s) removed" "SUCCESS"
        if ($mmioReset) { Log "MMIO settings reset" "SUCCESS" } else { Log "MMIO settings preserved for remaining GPU partition(s)" "INFO" }
        Log "Driver cleanup skipped by user choice" "INFO"
        Write-Host ""; return $true
    }

    $vhd = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhd) {
        Log "No VHD found - skipping driver cleanup" "WARN"
        Write-Host ""; Box "GPU REMOVAL COMPLETE" "-"
        Log "Selected GPU partition(s) removed" "SUCCESS"
        if ($mmioReset) { Log "MMIO settings reset" "SUCCESS" } else { Log "MMIO settings preserved for remaining GPU partition(s)" "INFO" }
        Write-Host ""; return $true
    }

    $mount = $null
    try {
        Write-Host ""; Spin "Mounting VM disk to clean drivers..." 2
        $mount = MountVHD $vhd

        if ($gpuList) {
            Write-Host ""; Log "Removing system driver files..." "INFO"
            $removedFolders = 0
            $removedFiles = 0
            $removedFolderFiles = 0
            $cleanupFailures = 0
            $selectedGpuIds = @($gpuList | ForEach-Object { $_.DeviceID } | Where-Object { $_ } | Select-Object -Unique)
            $manifestEntries = @(ReadDriverManifest $mount.Path)
            $usedManifest = $false

            if ($manifestEntries -and $selectedGpuIds) {
                $targetEntries = @($manifestEntries | Where-Object { $_.GpuDeviceId -and ($selectedGpuIds -contains $_.GpuDeviceId) })
                if ($targetEntries) {
                    $usedManifest = $true
                    $mountRoot = [System.IO.Path]::GetFullPath($mount.Path)
                    $residualManifestEntries = @()

                    foreach ($entry in $targetEntries) {
                        $remainingFoldersForEntry = @()
                        $remainingFilesForEntry = @()

                        foreach ($relFolder in @($entry.Folders)) {
                            $trimRel = "$relFolder".TrimStart([char[]]@('\', '/'))
                            if ([string]::IsNullOrWhiteSpace($trimRel)) { continue }
                            $absFolder = [System.IO.Path]::GetFullPath((Join-Path $mount.Path $trimRel))
                            if (!$absFolder.StartsWith($mountRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $cleanupFailures++
                                $remainingFoldersForEntry += "$relFolder"
                                continue
                            }
                            if (Test-Path -LiteralPath $absFolder) {
                                $folderFileCount = @(Get-ChildItem -LiteralPath $absFolder -Recurse -File -EA SilentlyContinue).Count
                                Remove-Item -LiteralPath $absFolder -Recurse -Force -EA SilentlyContinue
                                if (!(Test-Path -LiteralPath $absFolder)) {
                                    $removedFolders++
                                    $removedFolderFiles += $folderFileCount
                                    Log "- folder $(Split-Path -Leaf $absFolder) ($folderFileCount files)" "SUCCESS"
                                } else {
                                    $cleanupFailures++
                                    $remainingFoldersForEntry += "$relFolder"
                                    Log "- folder $(Split-Path -Leaf $absFolder) (could not remove)" "WARN"
                                }
                            }
                        }

                        foreach ($relFile in @($entry.Files)) {
                            $trimRel = "$relFile".TrimStart([char[]]@('\', '/'))
                            if ([string]::IsNullOrWhiteSpace($trimRel)) { continue }
                            $absFile = [System.IO.Path]::GetFullPath((Join-Path $mount.Path $trimRel))
                            if (!$absFile.StartsWith($mountRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $cleanupFailures++
                                $remainingFilesForEntry += "$relFile"
                                continue
                            }
                            if (Test-Path -LiteralPath $absFile) {
                                Remove-Item -LiteralPath $absFile -Force -EA SilentlyContinue
                                if (!(Test-Path -LiteralPath $absFile)) {
                                    $removedFiles++
                                    Log "- $(Split-Path -Leaf $absFile)" "SUCCESS"
                                } else {
                                    $cleanupFailures++
                                    $remainingFilesForEntry += "$relFile"
                                    Log "- $(Split-Path -Leaf $absFile) (could not remove)" "WARN"
                                }
                            }
                        }

                        if (($remainingFoldersForEntry.Count -gt 0) -or ($remainingFilesForEntry.Count -gt 0)) {
                            $residualManifestEntries += [PSCustomObject]@{
                                EntryId = if ($entry.EntryId) { $entry.EntryId } else { [Guid]::NewGuid().Guid }
                                CapturedUtc = if ($entry.CapturedUtc) { $entry.CapturedUtc } else { (Get-Date).ToUniversalTime().ToString("o") }
                                VMName = if ($entry.VMName) { $entry.VMName } else { $VMName }
                                GpuDeviceId = $entry.GpuDeviceId
                                GpuName = $entry.GpuName
                                Resolver = if ($entry.Resolver) { $entry.Resolver } else { "Unknown" }
                                InfPath = if ($entry.PSObject.Properties["InfPath"]) { $entry.InfPath } else { $null }
                                Missing = @($entry.Missing)
                                Folders = @($remainingFoldersForEntry | Sort-Object -Unique)
                                Files = @($remainingFilesForEntry | Sort-Object -Unique)
                            }
                        }
                    }

                    $targetEntryIds = @($targetEntries | ForEach-Object { $_.EntryId } | Where-Object { $_ })
                    $remainingManifestBase = if ($targetEntryIds) {
                        @($manifestEntries | Where-Object { $targetEntryIds -notcontains $_.EntryId })
                    } else {
                        @($manifestEntries | Where-Object { $_.GpuDeviceId -notin $selectedGpuIds })
                    }
                    $remainingManifest = @($remainingManifestBase + $residualManifestEntries)
                    WriteDriverManifest $mount.Path $remainingManifest
                    if ($residualManifestEntries.Count -gt 0) {
                        Log "Retained $($residualManifestEntries.Count) manifest record(s) for leftover paths" "WARN"
                    }
                    Log "Cleaned files using manifest records" "INFO"
                }
            }

            if (!$usedManifest) {
                $folderMap = @{}
                $fileMap = @{}
                $destResolveCache = @{}
                foreach ($gpu in $gpuList) {
                    $drv = GetDrivers $gpu
                    if ($drv) {
                        foreach ($folder in $drv.Folders) {
                            $leaf = Split-Path -Leaf $folder
                            if ($leaf) {
                                $k = "$leaf".ToLowerInvariant()
                                if (!$folderMap.ContainsKey($k)) { $folderMap[$k] = $leaf }
                            }
                        }
                        foreach ($f in $drv.Files) {
                            $rawDest = "$($f.D)"
                            if ($destResolveCache.ContainsKey($rawDest)) { $mappedDest = $destResolveCache[$rawDest] }
                            else {
                                $mappedDest = ResolveGuestSystemDestinationPath $rawDest
                                $destResolveCache[$rawDest] = $mappedDest
                            }
                            if (!$mappedDest) { continue }
                            $k = "$mappedDest".ToLowerInvariant()
                            if (!$fileMap.ContainsKey($k)) {
                                $fileMap[$k] = [PSCustomObject]@{N=$f.N; S=$f.S; D=$mappedDest}
                            }
                        }
                    }
                }

                $repo = "$($mount.Path)\Windows\System32\HostDriverStore\FileRepository"
                if (Test-Path $repo) {
                    foreach ($leaf in $folderMap.Values) {
                        $fp = Join-Path $repo $leaf
                        if (Test-Path $fp) {
                            $folderFileCount = @(Get-ChildItem -LiteralPath $fp -Recurse -File -EA SilentlyContinue).Count
                            Remove-Item -LiteralPath $fp -Recurse -Force -EA SilentlyContinue
                            if (!(Test-Path -LiteralPath $fp)) {
                                $removedFolders++
                                $removedFolderFiles += $folderFileCount
                                Log "- folder $leaf ($folderFileCount files)" "SUCCESS"
                            } else {
                                $cleanupFailures++
                                Log "- folder $leaf (could not remove)" "WARN"
                            }
                        }
                    }
                }

                $allFiles = @($fileMap.Values)
                if ($allFiles) {
                    foreach ($f in $allFiles) {
                        $relDest = "$($f.D)"
                        if ([string]::IsNullOrWhiteSpace($relDest)) { continue }
                        $fp = "$($mount.Path)$relDest"
                        if (Test-Path $fp) {
                            Remove-Item -LiteralPath $fp -Force -EA SilentlyContinue
                            if (!(Test-Path -LiteralPath $fp)) {
                                $removedFiles++
                                Log "- $($f.N)" "SUCCESS"
                            } else {
                                $cleanupFailures++
                                Log "- $($f.N) (could not remove)" "WARN"
                            }
                        }
                    }
                }
            }

            if (($removedFiles -gt 0) -or ($removedFolders -gt 0)) {
                $totalRemovedFiles = $removedFiles + $removedFolderFiles
                Write-Host ""; Log "Removed $totalRemovedFiles file(s): $removedFiles explicit system path(s) + $removedFolderFiles file(s) from $removedFolders removed folder(s)" "SUCCESS"
                if ($cleanupFailures -gt 0) {
                    Log "$cleanupFailures path(s) could not be removed" "WARN"
                }
            } else {
                Log "No matching injected driver files found for the selected GPU partition(s)" "INFO"
            }
        } else { Log "Could not identify selected partition device drivers - skipped system file cleanup" "WARN" }

        Write-Host ""; Box "GPU REMOVAL COMPLETE" "-"
        Log "Selected GPU partition(s) removed" "SUCCESS"
        if ($mmioReset) { Log "MMIO settings reset" "SUCCESS" } else { Log "MMIO settings preserved for remaining GPU partition(s)" "INFO" }
        Log "Selected driver file cleanup completed" "SUCCESS"
        Write-Host ""; return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - Windows may not be installed yet.`n" -ForegroundColor Yellow
        } else { Log "Driver cleanup failed: $($_.Exception.Message)" "WARN" }
        Write-Host ""; Box "GPU REMOVAL PARTIAL" "-"
        Log "Selected GPU partition(s) removed successfully" "SUCCESS"
        if ($mmioReset) { Log "MMIO settings reset" "SUCCESS" } else { Log "MMIO settings preserved for remaining GPU partition(s)" "INFO" }
        Log "Driver cleanup skipped - could not access VM disk" "WARN"
        Write-Host "  Note: Driver files (if any) remain in the VM disk" -ForegroundColor Yellow
        Write-Host ""; return $true
    } finally { if ($mount) { Spin "Unmounting VM disk..." 1; UnmountVHD $mount $vhd } }
}

function InstallDrivers($VMName=$null) {
    if (!$VMName) { $vm = SelectVM "SELECT VM FOR DRIVERS"; if (!$vm) { return $null }; $VMName = $vm.Name }
    $ga = @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue)
    if (!$ga) {
        Box "GPU DRIVER INJECTION" "-"; Log "No GPU partition assigned to VM: $VMName" "ERROR"; Write-Host ""
        Write-Host "  You must assign a GPU partition before installing drivers." -ForegroundColor Yellow
        Write-Host "  Use the 'GPU Partition' menu option first." -ForegroundColor Cyan; Write-Host ""; return $false
    }

    $entries = @(GetGpuDisplayEntries -Adapters $ga)
    $adapterRows = @()
    for ($i = 0; $i -lt $ga.Count; $i++) {
        $label = if ($entries.Count -gt $i -and $entries[$i].Label) { $entries[$i].Label } else { "GPU" }
        $adapterRows += [PSCustomObject]@{
            Adapter = $ga[$i]
            MenuLabel = ("GPU{0}: {1}" -f ($i + 1).ToString("00"), $label)
            EntryLabel = $label
        }
    }

    $selectedRows = @()
    $selectedAdapters = @()
    if ($adapterRows.Count -gt 1) {
        $items = @($adapterRows | ForEach-Object { $_.MenuLabel }) + "All assigned GPU partitions" + "< Cancel >"
        $sel = Menu -Items $items -Title "SELECT GPU DRIVER TARGET"
        if ($null -eq $sel -or $sel -eq ($items.Count - 1)) { Log "Cancelled" "WARN"; return $null }
        if ($sel -eq ($items.Count - 2)) {
            $selectedRows = @($adapterRows)
        } else {
            $selectedRows = @($adapterRows[$sel])
        }
    } else {
        $selectedRows = @($adapterRows[0])
    }

    $selectedAdapters = @($selectedRows | ForEach-Object { $_.Adapter })

    $selectedLabels = @($selectedRows | ForEach-Object { $_.EntryLabel } | Select-Object -Unique)
    Box "GPU DRIVER INJECTION"; Log "Target VM: $VMName" "INFO"; Log "Selected GPU(s): $($selectedLabels -join ', ')" "SUCCESS"; Write-Host ""

    $gpuList = @()
    $seenGpuIds = @{}
    foreach ($a in $selectedAdapters) {
        $meta = ResolvePartitionableDevice $a.InstancePath
        $gpu = if ($meta -and $meta.Class) { FindGPU $a.InstancePath $meta.Class } else { FindGPU $a.InstancePath }
        if ($gpu) {
            $gpuIdKey = if ($gpu.DeviceID) { "$($gpu.DeviceID)".ToLowerInvariant() } else { "" }
            if (!$seenGpuIds.ContainsKey($gpuIdKey)) {
                $seenGpuIds[$gpuIdKey] = $true
                $gpuList += $gpu
            }
        }
    }
    if (!$gpuList) {
        Log "Could not find matching device driver(s) for the selected partition(s)" "ERROR"
        Write-Host "  Note: Ensure the selected partitionable device has an installed host driver package." -ForegroundColor Yellow
        Write-Host ""; return $false
    }

    $skipExisting = Confirm "Skip unchanged files that already exist in the VM disk? (uses hash comparison)"

    $vhd = (Get-VMHardDiskDrive $VMName -EA SilentlyContinue).Path
    if (!$vhd) { Log "No VHD found" "ERROR"; Write-Host ""; return $false }
    if (!(EnsureOff $VMName)) { return $false }
    $mount = $null
    try {
        $folderMap = @{}
        $fileMap = @{}
        $gpuDriverMap = @{}
        $destResolveCache = @{}
        foreach ($gpu in $gpuList) {
            $drv = GetDrivers $gpu
            if ($drv) {
                if ($gpu.DeviceID) { $gpuDriverMap[$gpu.DeviceID] = $drv }
                foreach ($folder in $drv.Folders) {
                    $k = "$folder".ToLowerInvariant()
                    if (!$folderMap.ContainsKey($k)) { $folderMap[$k] = $folder }
                }
                foreach ($f in $drv.Files) {
                    $rawDest = "$($f.D)"
                    if ($destResolveCache.ContainsKey($rawDest)) { $mappedDest = $destResolveCache[$rawDest] }
                    else {
                        $mappedDest = ResolveGuestSystemDestinationPath $rawDest
                        $destResolveCache[$rawDest] = $mappedDest
                    }
                    if (!$mappedDest) { continue }
                    $k = "$mappedDest".ToLowerInvariant()
                    if (!$fileMap.ContainsKey($k)) {
                        $fileMap[$k] = [PSCustomObject]@{N=$f.N; S=$f.S; D=$mappedDest}
                    }
                }
                if ($drv.Missing -and $drv.Missing.Count -gt 0) {
                    Log "$($gpu.DeviceName): $($drv.Missing.Count) unresolved INF reference(s)" "WARN"
                }
            }
        }

        $drv = @{Folders=@($folderMap.Values); Files=@($fileMap.Values)}
        if ((!$drv.Folders) -and (!$drv.Files)) { Log "No driver files were resolved for the selected partition device(s)" "ERROR"; Write-Host ""; return $false }

        $mount = MountVHD $vhd
        Spin "Preparing destination..." 1
        $store = "$($mount.Path)\Windows\System32\HostDriverStore\FileRepository"
        EnsureDir $store

        $copiedFolders = 0
        $copiedFiles = 0
        $skippedFiles = 0

        Log "Copying $($drv.Folders.Count) driver folders..." "INFO"; Write-Host ""
        foreach ($f in $drv.Folders) {
            $n = Split-Path -Leaf $f; $d = Join-Path $store $n

            if ($skipExisting) {
                EnsureDir $d
                $folderCopied = 0
                $folderSkipped = 0
                $srcFiles = @(Get-ChildItem $f -Recurse -File -EA SilentlyContinue)
                $preparedFolderDirs = @{ "$($d.ToLowerInvariant())" = $true }
                foreach ($sf in $srcFiles) {
                    $rel = $sf.FullName.Substring($f.Length).TrimStart([char]'\')
                    $dstFile = Join-Path $d $rel
                    $dstParent = Split-Path -Parent $dstFile
                    $dstParentKey = "$dstParent".ToLowerInvariant()
                    if (!$preparedFolderDirs.ContainsKey($dstParentKey)) {
                        EnsureDir $dstParent
                        $preparedFolderDirs[$dstParentKey] = $true
                    }
                    if ((Test-Path $dstFile) -and (TestFileContentEqual $sf.FullName $dstFile)) { $folderSkipped++; $skippedFiles++; continue }
                    Copy-Item $sf.FullName $dstFile -Force -EA Stop
                    $folderCopied++; $copiedFiles++
                }
                $copiedFolders++
                Log "+ $n ($folderCopied copied, $folderSkipped skipped)" "SUCCESS"
            } else {
                EnsureDir (Split-Path -Parent $d)
                $r = Try-Op { Copy-Item $f $d -Force -Recurse -EA Stop; return $true } "Copy $n"
                if ($r.OK) {
                    $folderFileCount = (Get-ChildItem $d -Recurse -File -EA SilentlyContinue | Measure-Object).Count
                    $copiedFolders++
                    $copiedFiles += $folderFileCount
                    Log "+ $n" "SUCCESS"
                    Write-Host "      ($folderFileCount files)" -ForegroundColor DarkGray
                } else { Log "! $n skipped" "WARN" }
            }
        }

        Write-Host ""; Log "Copying $($drv.Files.Count) system files..." "INFO"
        $preparedSystemDirs = @{}
        foreach ($f in $drv.Files) {
            $relDest = "$($f.D)"
            if ([string]::IsNullOrWhiteSpace($relDest)) { continue }
            $dst = "$($mount.Path)$relDest"
            $dstParent = Split-Path -Parent $dst
            $dstParentKey = "$dstParent".ToLowerInvariant()
            if (!$preparedSystemDirs.ContainsKey($dstParentKey)) {
                $mk = Try-Op { New-Item -ItemType Directory -Path $dstParent -Force -EA Stop | Out-Null; return $true } "Prepare path $relDest"
                if (!$mk.OK) { continue }
                $preparedSystemDirs[$dstParentKey] = $true
            }
            if ($skipExisting -and (Test-Path $dst) -and (TestFileContentEqual $f.S $dst)) { $skippedFiles++; continue }
            $ok = (Try-Op { Copy-Item $f.S $dst -Force -EA Stop; return $true } "Copy $($f.N)").OK
            if ($ok) { $copiedFiles++; Log "+ $($f.N)" "SUCCESS" }
        }

        $existingManifest = @(ReadDriverManifest $mount.Path)
        $selectedGpuIds = @($gpuList | ForEach-Object { $_.DeviceID } | Where-Object { $_ } | Select-Object -Unique)
        $keptManifest = @($existingManifest | Where-Object { $_.GpuDeviceId -notin $selectedGpuIds })
        $newManifest = @()

        foreach ($gpu in $gpuList) {
            if (!$gpu.DeviceID) { continue }
            if (!$gpuDriverMap.ContainsKey($gpu.DeviceID)) { continue }

            $gpuDrv = $gpuDriverMap[$gpu.DeviceID]
            $folderDest = @($gpuDrv.Folders | ForEach-Object { "\Windows\System32\HostDriverStore\FileRepository\$(Split-Path -Leaf $_)" } | Sort-Object -Unique)
            $fileDest = @(
                $gpuDrv.Files |
                ForEach-Object {
                    $rawDest = "$($_.D)"
                    if ($destResolveCache.ContainsKey($rawDest)) { $destResolveCache[$rawDest] }
                    else {
                        $mappedDest = ResolveGuestSystemDestinationPath $rawDest
                        $destResolveCache[$rawDest] = $mappedDest
                        $mappedDest
                    }
                } |
                Where-Object { $_ } |
                Sort-Object -Unique
            )
            if ((!$folderDest) -and (!$fileDest)) { continue }

            $newManifest += [PSCustomObject]@{
                EntryId = [Guid]::NewGuid().Guid
                CapturedUtc = (Get-Date).ToUniversalTime().ToString("o")
                VMName = $VMName
                GpuDeviceId = $gpu.DeviceID
                GpuName = $gpu.DeviceName
                Resolver = if ($gpuDrv.Strategy) { $gpuDrv.Strategy } else { "Unknown" }
                InfPath = if ($gpuDrv.InfPath) { $gpuDrv.InfPath } else { $null }
                Missing = @($gpuDrv.Missing)
                Folders = $folderDest
                Files = $fileDest
            }
        }

        WriteDriverManifest $mount.Path @($keptManifest + $newManifest)
        if ($newManifest.Count -gt 0) { Log "Driver manifest updated with $($newManifest.Count) GPU record(s)" "INFO" }

        Write-Host ""; Box "DRIVER INJECTION COMPLETE" "-"
        Log "Copied $copiedFiles file(s) across $copiedFolders folder copy operation(s)" "SUCCESS"
        if ($skipExisting) { Log "Skipped $skippedFiles existing file(s)" "INFO" }
        Write-Host ""; return $true
    } catch {
        if ($_.Exception.Message -match "MSFT_Partition|partition|No valid partition|Windows folder not found") {
            Log "Is Windows installed in this VM?" "ERROR"
            Write-Host "  The VM disk could not be mounted - install Windows first, then run driver injection." -ForegroundColor Yellow
        } else { Log "Failed: $($_.Exception.Message)" "ERROR" }
        Write-Host ""; return $false
    } finally { if ($mount) { Spin "Unmounting VM disk..." 1; UnmountVHD $mount $vhd } }
}

function ShowVMs {
    Box "VM OVERVIEW"; Log "Gathering VM information..." "INFO"; Write-Host ""
    $vms = Get-VM
    if (!$vms) { Log "No VMs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }

    $gpuAdapterMap = GetVmGpuAdapterMap $vms

    $data = @($vms | ForEach-Object {
        $storage = "0GB"
        try {
            $v = Get-VHD -VMId $_.VMId -EA SilentlyContinue
            if ($v) { $storage = FormatCapacityFromBytes $v.Size }
        } catch {}
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $ram = FormatCapacityFromBytes $mem
        $st = @{Running=@{I="[*]";C="Green"}; Off=@{I="[ ]";C="Gray"}}[$_.State]
        if (!$st) { $st = @{I="[~]";C="Yellow"} }
        $ga = if ($gpuAdapterMap.ContainsKey($_.Name)) { @($gpuAdapterMap[$_.Name]) } else { @() }
        $gi = if ($ga) { GpuSummary -Adapters $ga } else { "None" }
        [PSCustomObject]@{Icon=$st.I; Name=$_.Name; State=$_.State; vCPU=$_.ProcessorCount; RAM=$ram; Storage=$storage; GPU=$gi; RC=$st.C}
    })
    Table $data @(@{H="";P="Icon";C="RC"},@{H="VM Name";P="Name";C="RC"},@{H="State";P="State";C="RC"},@{H="vCPU";P="vCPU";C="RC"},@{H="RAM";P="RAM";C="RC"},@{H="Storage";P="Storage";C="RC"},@{H="GPU";P="GPU";C="RC"})
    Write-Host ""; Read-Host "  Press Enter"
}

function ShowGPUs {
    Box "GPU INFORMATION"; Log "Detecting GPUs..." "INFO"; Write-Host ""
    $gpus = @(GetCompatManagementInstances "Win32_VideoController") | Where-Object { $_.Name -notlike "*Microsoft*" -and $_.Name -notlike "*Remote*" }
    if (!$gpus) { Log "No GPUs found" "WARN"; Write-Host ""; Read-Host "  Press Enter"; return }
    $pg = GetPartitionableGPUs
    $partitionPaths = @($pg | ForEach-Object { GetPartitionablePath $_ })

    $partitionIdentity = @{}
    foreach ($pp in $partitionPaths) {
        if ("$pp" -match "VEN_([0-9A-Fa-f]{4}).*DEV_([0-9A-Fa-f]{4})") {
            $key = "VEN_$($matches[1].ToUpperInvariant())&DEV_$($matches[2].ToUpperInvariant())"
            $partitionIdentity[$key] = $true
        }
    }

    $i = 1; $data = @($gpus | ForEach-Object {
        $ok = $_.Status -eq 'OK'; $si = if ($ok) { '[OK]' } else { '[X]' }; $sc = if ($ok) { 'Green' } else { 'Yellow' }
        $ip = $false
        if ($_.PNPDeviceID -match "VEN_([0-9A-Fa-f]{4})&DEV_([0-9A-Fa-f]{4})") {
            $idKey = "VEN_$($matches[1].ToUpperInvariant())&DEV_$($matches[2].ToUpperInvariant())"
            $ip = $partitionIdentity.ContainsKey($idKey)
        }
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
    if (!$VMName) { $vm = SelectVM "SELECT VM TO DELETE"; if (!$vm) { return $null }; $VMName = $vm.Name }
    $vm = Get-VM $VMName -EA SilentlyContinue
    if (!$vm) { Log "VM not found: $VMName" "ERROR"; Write-Host ""; return $false }
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
    if (!(Confirm "Delete VM '$VMName'?")) { Log "Cancelled" "WARN"; return $null }
    $delFiles = $false
    if ($vhd -or $autoISO) { Write-Host ""; if (Confirm "Also delete associated files?") { $delFiles = $true } }
    Write-Host ""
    if ($vm.State -ne "Off") { if (!(EnsureOff $VMName)) { Log "Failed to stop VM" "ERROR"; Write-Host ""; return $false } }
    $hasGPU = Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue
    if ($hasGPU) { Spin "Removing GPU partition..." 1; $hasGPU | Remove-VMGpuPartitionAdapter -EA SilentlyContinue; Log "GPU partition removed" "SUCCESS" }
    Spin "Removing VM..." 2
    if (!(Try-Op { Remove-VM $VMName -Force -EA Stop; Log "VM removed successfully" "SUCCESS" } "Remove VM").OK) { Write-Host ""; return $false }
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
