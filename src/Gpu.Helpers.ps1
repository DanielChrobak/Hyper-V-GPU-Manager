#region GPU Helpers
function GetPartitionableGPUs {
    if (-not $script:GpuPartitionableCmdSupportInitialized) {
        # Detect supported cmdlets once per session; command availability does not change at runtime.
        $script:HasGetVmHostPartitionableGpu = [bool](Get-Command Get-VMHostPartitionableGpu -EA SilentlyContinue)
        $script:HasGetVmPartitionableGpu = [bool](Get-Command Get-VMPartitionableGpu -EA SilentlyContinue)
        $script:GpuPartitionableCmdSupportInitialized = $true
    }

    if ($script:HasGetVmHostPartitionableGpu) {
        try { return @(Get-VMHostPartitionableGpu -EA Stop) }
        catch {
            if ($script:HasGetVmPartitionableGpu) {
                try { return @(Get-VMPartitionableGpu -EA Stop) }
                catch { return @() }
            }
            return @()
        }
    }

    if ($script:HasGetVmPartitionableGpu) {
        try { return @(Get-VMPartitionableGpu -EA Stop) }
        catch { return @() }
    }

    return @()
}

function GetPartitionablePath($GpuObject) {
    if ($null -eq $GpuObject) { return $null }
    if ($GpuObject.PSObject.Properties["Name"] -and $GpuObject.Name) { return "$($GpuObject.Name)" }
    if ($GpuObject.PSObject.Properties["Id"] -and $GpuObject.Id) { return "$($GpuObject.Id)" }
    return "$GpuObject"
}

function GetPciIdsFromPath($Path) {
    if ($Path) {
        $idMatch = [regex]::Match($Path, 'VEN_([0-9A-Fa-f]{4}).*DEV_([0-9A-Fa-f]{4})')
        if ($idMatch.Success) {
            return [PSCustomObject]@{VEN=$idMatch.Groups[1].Value.ToUpperInvariant(); DEV=$idMatch.Groups[2].Value.ToUpperInvariant()}
        }
    }
    return $null
}

function GetGpuIdentityKey($Path) {
    if (!$Path) { return $null }
    $ids = GetPciIdsFromPath $Path
    if ($ids) { return "VEN_$($ids.VEN)&DEV_$($ids.DEV)" }
    return "$Path".ToUpperInvariant()
}

function GetPartitionableGpuByPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }

    $targetKey = GetGpuIdentityKey $Path
    $all = @(GetPartitionableGPUs)
    foreach ($gpu in $all) {
        $gpuPath = GetPartitionablePath $gpu
        if ([string]::IsNullOrWhiteSpace($gpuPath)) { continue }
        if ($gpuPath -eq $Path) { return $gpu }

        $gpuKey = GetGpuIdentityKey $gpuPath
        if ($targetKey -and $gpuKey -and ($gpuKey -eq $targetKey)) {
            return $gpu
        }
    }

    return $null
}

function GetGpuPartitionResourceCapacity($PartitionableGpu, $ResourceName, [UInt64]$Fallback=1000000000) {
    if (!$PartitionableGpu -or [string]::IsNullOrWhiteSpace($ResourceName)) {
        return [UInt64]$Fallback
    }

    $candidates = @("Total$ResourceName", "MaxPartition$ResourceName", "Available$ResourceName")
    foreach ($key in $candidates) {
        if (!$PartitionableGpu.PSObject.Properties[$key]) { continue }
        try {
            $value = [UInt64]$PartitionableGpu.$key
            if ($value -gt 0 -and $value -lt [UInt64]::MaxValue) { return $value }
        } catch {}
    }

    return [UInt64]$Fallback
}

function GetGpuPartitionResourceAllocation($PartitionableGpu, $ResourceName, $Percent, [UInt64]$Fallback=1000000000) {
    $pct = [Math]::Max(1, [Math]::Min(100, [int]$Percent))
    $capacity = GetGpuPartitionResourceCapacity -PartitionableGpu $PartitionableGpu -ResourceName $ResourceName -Fallback $Fallback
    $desired = [UInt64]([Math]::Max([decimal]1, [Math]::Floor(([decimal]$capacity * [decimal]$pct) / 100)))

    $minKey = "MinPartition$ResourceName"
    $maxKey = "MaxPartition$ResourceName"
    $minBound = [UInt64]0
    $maxBound = [UInt64]0

    if ($PartitionableGpu -and $PartitionableGpu.PSObject.Properties[$minKey]) {
        try {
            $value = [UInt64]$PartitionableGpu.$minKey
            if ($value -gt 0 -and $value -lt [UInt64]::MaxValue) { $minBound = $value }
        } catch {}
    }
    if ($PartitionableGpu -and $PartitionableGpu.PSObject.Properties[$maxKey]) {
        try {
            $value = [UInt64]$PartitionableGpu.$maxKey
            if ($value -gt 0 -and $value -lt [UInt64]::MaxValue) { $maxBound = $value }
        } catch {}
    }

    if ($maxBound -gt 0 -and $desired -gt $maxBound) { $desired = $maxBound }
    if ($minBound -gt 0 -and $desired -lt $minBound) { $desired = $minBound }

    $minValue = if ($minBound -gt 0) { $minBound } else { [UInt64]1 }
    if ($minValue -gt $desired) { $minValue = $desired }

    return [PSCustomObject]@{
        Min = $minValue
        Max = $desired
        Optimal = $desired
        Capacity = $capacity
        IsUnbounded = $false
    }
}

if (-not $script:GpuResolveCache) { $script:GpuResolveCache = @{} }
if (-not $script:GpuDriverCache) { $script:GpuDriverCache = @{} }
if (-not $script:GpuLookupCacheTtlSeconds) { $script:GpuLookupCacheTtlSeconds = 300 }
if (-not $script:HyperVCapabilityCache) { $script:HyperVCapabilityCache = @{} }
if (-not $script:GpuInfPathCache) { $script:GpuInfPathCache = @{} }
if (-not $script:GpuRegDeviceInfEntriesLoaded) { $script:GpuRegDeviceInfEntriesLoaded = $false }
if (-not $script:GpuRegDeviceInfEntries) { $script:GpuRegDeviceInfEntries = @() }

function TestHyperVCmdletParameter($CmdletName, $ParameterName) {
    if ([string]::IsNullOrWhiteSpace($CmdletName) -or [string]::IsNullOrWhiteSpace($ParameterName)) { return $false }

    $key = "$CmdletName|$ParameterName"
    if ($script:HyperVCapabilityCache.ContainsKey($key)) {
        return [bool]$script:HyperVCapabilityCache[$key]
    }

    $cmd = Get-Command $CmdletName -EA SilentlyContinue
    $supported = [bool]($cmd -and $cmd.Parameters.ContainsKey($ParameterName))
    $script:HyperVCapabilityCache[$key] = $supported
    return $supported
}

function GetCompatManagementInstances($ClassName, $Filter=$null) {
    if ([string]::IsNullOrWhiteSpace($ClassName)) { return @() }

    if ($null -eq $script:HasGetCimInstance) {
        $script:HasGetCimInstance = [bool](Get-Command Get-CimInstance -EA SilentlyContinue)
    }

    if ($script:HasGetCimInstance) {
        try {
            if ($Filter) { return @(Get-CimInstance -ClassName $ClassName -Filter $Filter -EA Stop) }
            return @(Get-CimInstance -ClassName $ClassName -EA Stop)
        } catch {}
    }

    try {
        if ($Filter) { return @(Get-WmiObject -Class $ClassName -Filter $Filter -EA Stop) }
        return @(Get-WmiObject -Class $ClassName -EA Stop)
    } catch {
        return @()
    }
}

function GetGpuCacheEntry($Cache, $Key) {
    if (!$Cache -or [string]::IsNullOrWhiteSpace($Key)) { return $null }
    if (!$Cache.ContainsKey($Key)) { return $null }

    $entry = $Cache[$Key]
    if (!$entry -or !$entry.PSObject.Properties["Expires"] -or !$entry.PSObject.Properties["Value"]) {
        [void]$Cache.Remove($Key)
        return $null
    }

    if ((Get-Date) -gt $entry.Expires) {
        [void]$Cache.Remove($Key)
        return $null
    }

    return $entry.Value
}

function SetGpuCacheEntry($Cache, $Key, $Value) {
    if (!$Cache -or [string]::IsNullOrWhiteSpace($Key)) { return }
    $Cache[$Key] = [PSCustomObject]@{
        Expires = (Get-Date).AddSeconds($script:GpuLookupCacheTtlSeconds)
        Value = $Value
    }
}

function ResolvePartitionableDevice($Path) {
    $ids = GetPciIdsFromPath $Path
    if (!$ids) { return $null }

    $ven = $ids.VEN
    $dev = $ids.DEV
    $cacheKey = "VEN_$ven&DEV_$dev"

    $cached = GetGpuCacheEntry $script:GpuResolveCache $cacheKey
    if ($null -ne $cached) { return $cached }

    $videoFilter = "PNPDeviceID LIKE '%VEN_$ven%DEV_$dev%'"
    $video = GetCompatManagementInstances "Win32_VideoController" $videoFilter | Select-Object -First 1
    if ($video) {
        $result = [PSCustomObject]@{
            Name = $video.Name
            Class = "Display"
            Vendor = if ($video.AdapterCompatibility) { $video.AdapterCompatibility } else { $null }
            DeviceId = $video.PNPDeviceID
            VEN = $ven
            DEV = $dev
        }
        SetGpuCacheEntry $script:GpuResolveCache $cacheKey $result
        return $result
    }

    $pnpFilter = "PNPDeviceID LIKE '%VEN_$ven%DEV_$dev%'"
    $pnp = GetCompatManagementInstances "Win32_PnPEntity" $pnpFilter | Select-Object -First 1
    if ($pnp) {
        $signed = $null
        if (!$pnp.Name -or !$pnp.PNPClass -or !$pnp.Manufacturer) {
            $escapedPnpDeviceId = "$($pnp.PNPDeviceID)".Replace('\\', '\\\\').Replace("'", "''")
            $signedFilter = "DeviceID='$escapedPnpDeviceId'"
            $signed = GetCompatManagementInstances "Win32_PnPSignedDriver" $signedFilter | Select-Object -First 1
        }

        $result = [PSCustomObject]@{
            Name = if ($pnp.Name) { $pnp.Name } elseif ($signed.DeviceName) { $signed.DeviceName } else { $null }
            Class = if ($signed.DeviceClass) { $signed.DeviceClass } elseif ($pnp.PNPClass) { $pnp.PNPClass } else { "Unknown" }
            Vendor = if ($signed.DriverProviderName) { $signed.DriverProviderName } elseif ($pnp.Manufacturer) { $pnp.Manufacturer } else { $null }
            DeviceId = $pnp.PNPDeviceID
            VEN = $ven
            DEV = $dev
        }
        SetGpuCacheEntry $script:GpuResolveCache $cacheKey $result
        return $result
    }

    $result = [PSCustomObject]@{
        Name = $null
        Class = "Unknown"
        Vendor = $null
        DeviceId = $null
        VEN = $ven
        DEV = $dev
    }

    SetGpuCacheEntry $script:GpuResolveCache $cacheKey $result
    return $result
}

function GPUName($Path) {
    $meta = ResolvePartitionableDevice $Path
    if ($meta -and $meta.Name) { return $meta.Name }
    return $null
}

function GetGpuDisplayEntries($Adapters) {
    $ga = @($Adapters)
    if (!$ga) { return @() }

    $entries = @()
    foreach ($a in $ga) {
        $meta = ResolvePartitionableDevice $a.InstancePath
        $name = if ($meta -and $meta.Name) { $meta.Name } elseif ($meta -and $meta.VEN -and $meta.DEV) { "VEN_$($meta.VEN)/DEV_$($meta.DEV)" } else { $null }
        if (!$name) { $name = "GPU" }

        $pct = "?"
        try {
            if ($a.MaxPartitionVRAM -gt 0) {
                $capacity = [UInt64]1000000000
                $partitionable = GetPartitionableGpuByPath $a.InstancePath
                if ($partitionable) {
                    $capacity = GetGpuPartitionResourceCapacity -PartitionableGpu $partitionable -ResourceName "VRAM" -Fallback 1000000000
                }

                if ($capacity -gt 0) {
                    $pctValue = [Math]::Round(([decimal]$a.MaxPartitionVRAM / [decimal]$capacity) * 100)
                    $pctValue = [Math]::Max(1, [Math]::Min(100, [int]$pctValue))
                    $pct = "$pctValue%"
                }
            }
        } catch {}

        $entries += [PSCustomObject]@{
            Name = $name
            Pct = $pct
            Label = "$name ($pct)"
        }
    }

    return $entries
}

function GpuSummary($VMName=$null, $Adapters=$null) {
    $ga = if ($Adapters) { @($Adapters) } elseif ($VMName) { @(Get-VMGpuPartitionAdapter $VMName -EA SilentlyContinue) } else { @() }
    if (!$ga) { return "None" }

    $entries = @(GetGpuDisplayEntries -Adapters $ga)
    if (!$entries) { return "None" }
    return (($entries | ForEach-Object { $_.Label }) -join ", ")
}

function FindGPU($Path, $PreferredClass=$null) {
    $ids = GetPciIdsFromPath $Path
    if (!$ids) { return $null }

    $cacheKey = "VEN_$($ids.VEN)&DEV_$($ids.DEV)|$($PreferredClass)"
    $cached = GetGpuCacheEntry $script:GpuDriverCache $cacheKey
    if ($null -ne $cached) { return $cached }

    $driverFilter = "DeviceID LIKE '%VEN_$($ids.VEN)%DEV_$($ids.DEV)%'"
    $driverCandidates = @(GetCompatManagementInstances "Win32_PnPSignedDriver" $driverFilter)
    if (!$driverCandidates) { return $null }

    if ($PreferredClass) {
        $preferred = $driverCandidates |
            Where-Object { $_.DeviceClass -and $_.DeviceClass.Equals("$PreferredClass", [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($preferred) {
            SetGpuCacheEntry $script:GpuDriverCache $cacheKey $preferred
            return $preferred
        }
    }

    $display = $driverCandidates |
        Where-Object { $_.DeviceClass -and $_.DeviceClass.Equals("Display", [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($display) {
        SetGpuCacheEntry $script:GpuDriverCache $cacheKey $display
        return $display
    }

    $fallback = ($driverCandidates | Select-Object -First 1)
    if ($fallback) { SetGpuCacheEntry $script:GpuDriverCache $cacheKey $fallback }
    return $fallback
}

function SelectGPU($Title="SELECT GPU", [switch]$Partition) {
    if ($Partition) {
        $gpus = GetPartitionableGPUs
        if (!$gpus) { Box $Title; Log "No partitionable devices found" "ERROR"; Write-Host ""; return $null }
        $list = @(); $i = 0
        foreach ($g in $gpus) {
            $p = GetPartitionablePath $g
            $meta = ResolvePartitionableDevice $p
            $driver = $null
            if (!$meta -or !$meta.Name -or !$meta.Class) {
                $driver = if ($meta -and $meta.Class) { FindGPU $p $meta.Class } else { FindGPU $p }
            }

            if ($meta -and $meta.Name) { $n = $meta.Name }
            elseif ($driver -and $driver.DeviceName) { $n = $driver.DeviceName }
            elseif ($meta -and $meta.VEN -and $meta.DEV) { $n = "Unknown Device (VEN_$($meta.VEN) DEV_$($meta.DEV))" }
            else { $n = "Unknown Partitionable Adapter #$($i + 1)" }

            $label = $n
            $className = if ($meta -and $meta.Class) { $meta.Class } elseif ($driver -and $driver.DeviceClass) { $driver.DeviceClass } else { $null }
            if ($className -and $className -ne "Display") { $label = "$label [$className]" }

            $list += [PSCustomObject]@{
                I = $i
                P = $p
                N = $n
                L = $label
                C = if ($meta -and $meta.Class) { $meta.Class } elseif ($driver -and $driver.DeviceClass) { $driver.DeviceClass } else { "Unknown" }
                V = if ($meta -and $meta.Vendor) { $meta.Vendor } elseif ($driver) { $driver.DriverProviderName } else { $null }
                VEN = if ($meta) { $meta.VEN } else { $null }
                DEV = if ($meta) { $meta.DEV } else { $null }
            }
            $i++
        }

        $items = @($list | ForEach-Object { $_.L }) + "< Cancel >"
        $sel = Menu -Items $items -Title $Title
        if ($null -eq $sel -or $sel -eq ($items.Count - 1)) { return $null }

        $pick = $list[$sel]
        Log "Selected: $($pick.N)" "SUCCESS"
        if ((!$pick.N -or $pick.N -like "Unknown*") -and $pick.VEN -and $pick.DEV) {
            Write-Host "  IDs: VEN_$($pick.VEN) DEV_$($pick.DEV)" -ForegroundColor DarkGray
            Write-Host "  Adapter path: $($pick.P)" -ForegroundColor DarkGray
        }
        Write-Host ""
        return $pick
    } else {
        $list = @(GetCompatManagementInstances "Win32_PnPSignedDriver" "DeviceClass='Display'")
        if (!$list) { Box $Title; Log "No GPUs found" "ERROR"; return $null }

        $items = @($list | ForEach-Object {
            $provider = if ($_.DriverProviderName) { $_.DriverProviderName } else { "Unknown Provider" }
            "$($_.DeviceName) | $provider"
        }) + "< Cancel >"

        $sel = Menu -Items $items -Title $Title
        if ($null -eq $sel -or $sel -eq ($items.Count - 1)) { return $null }
        return $list[$sel]
    }
}

function NormalizeDriverPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    $p = $Path.Trim().Trim('"')
    if ($p -match '^\\\\\?\?\\') { $p = $p.Substring(4) }
    elseif ($p -match '^\\\\\?\\') { $p = $p.Substring(4) }

    if ($p -match "^%SystemRoot%\\") { return (Join-Path $env:windir $p.Substring(12)) }
    if ($p -match "^\\SystemRoot\\") { return (Join-Path $env:windir $p.Substring(12)) }
    if ($p -match "^System32\\") { return (Join-Path (Join-Path $env:windir "System32") $p.Substring(9)) }
    return $p
}

function GetDriverStoreFolderRoot($Path) {
    $norm = NormalizeDriverPath $Path
    if (!$norm) { return $null }
    $clean = $norm -replace '/', '\\'
    $m = [regex]::Match($clean, '(?i)^[A-Za-z]:\\windows\\system32\\(hostdriverstore|driverstore)\\filerepository\\([^\\]+)')
    if (!$m.Success) { return $null }
    $storeRoot = $m.Groups[1].Value
    $folder = $m.Groups[2].Value
    if ([string]::IsNullOrWhiteSpace($folder)) { return $null }
    $base = Join-Path $env:windir "System32\$storeRoot\FileRepository"
    return (Join-Path $base $folder).TrimEnd([char]'\')
}

function ResolveInfPathForGpu($GPU) {
    if (!$GPU) { return $null }

    $deviceIdKey = $null
    if ($GPU.PSObject.Properties["DeviceID"] -and $GPU.DeviceID) {
        $deviceIdKey = "$($GPU.DeviceID)".ToLowerInvariant()
        if ($script:GpuInfPathCache.ContainsKey($deviceIdKey)) {
            return $script:GpuInfPathCache[$deviceIdKey]
        }
    }

    if ($GPU -and $GPU.PSObject.Properties["InfName"] -and $GPU.InfName) {
        $direct = Join-Path "$env:windir\INF" $GPU.InfName
        if (Test-Path $direct) {
            if ($deviceIdKey) { $script:GpuInfPathCache[$deviceIdKey] = $direct }
            return $direct
        }
    }

    if (!$GPU.DeviceID) { return $null }

    if (!$script:GpuRegDeviceInfEntriesLoaded) {
        $entries = @()
        Get-ChildItem $script:GPUReg -EA SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -EA SilentlyContinue
            if ($p.MatchingDeviceId -and $p.InfPath) {
                $entries += [PSCustomObject]@{
                    MatchingDeviceId = "$($p.MatchingDeviceId)"
                    InfPath = "$($p.InfPath)"
                }
            }
        }
        $script:GpuRegDeviceInfEntries = $entries
        $script:GpuRegDeviceInfEntriesLoaded = $true
    }

    $gpuDeviceId = "$($GPU.DeviceID)"
    $inf = @($script:GpuRegDeviceInfEntries | Where-Object {
        $_.MatchingDeviceId -and ($gpuDeviceId -like "*$($_.MatchingDeviceId)*" -or $_.MatchingDeviceId -like "*$gpuDeviceId*")
    } | Select-Object -First 1 -ExpandProperty InfPath)
    if (!$inf) {
        if ($deviceIdKey) { $script:GpuInfPathCache[$deviceIdKey] = $null }
        return $null
    }

    $infPath = Join-Path "$env:windir\INF" $inf
    if (Test-Path $infPath) {
        if ($deviceIdKey) { $script:GpuInfPathCache[$deviceIdKey] = $infPath }
        return $infPath
    }

    if ($deviceIdKey) { $script:GpuInfPathCache[$deviceIdKey] = $null }
    return $null
}

function GetInfReferences($InfPath) {
    if (!(Test-Path $InfPath)) { return @() }
    $content = Get-Content $InfPath -Raw -EA SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) { return @() }

    $pattern = '[\w\-\.]+\.(?:sys|dll|exe|cat|inf|bin|vp|cpa|dat|cfg|json|ini|mui|pnf)'
    $refs = @([regex]::Matches($content, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Value } | Sort-Object -Unique)
    return $refs
}

function GetDrivers($GPU) {
    Box "ANALYZING GPU DRIVERS" "-"
    if (!$GPU) { Log "No GPU metadata provided" "ERROR"; return $null }

    Log "GPU: $($GPU.DeviceName)" "INFO"
    Log "Provider: $($GPU.DriverProviderName) | Version: $($GPU.DriverVersion)" "INFO"
    Write-Host ""

    $resolvedMap = @{}
    $missingRefs = @()
    $refNameSet = @{}
    $strategy = "WmiAssociation"
    $serviceBinaryPath = $null

    $addResolved = {
        param($Candidate)
        $norm = NormalizeDriverPath $Candidate
        if (!$norm) { return }
        if (Test-Path $norm) { $resolvedMap[$norm.ToLowerInvariant()] = $norm }
    }

    Spin "Resolving package files..." 1
    $assoc = @()
    if ($GPU.DeviceID) {
        $modifiedDeviceId = "$($GPU.DeviceID)".Replace("\", "\\")
        $antecedent = "\\$env:COMPUTERNAME\ROOT\cimv2:Win32_PnPSignedDriver.DeviceID=" + '"' + $modifiedDeviceId + '"'
        $escapedAntecedent = "$antecedent".Replace("'", "''")
        $assocFilter = "Antecedent='$escapedAntecedent'"

        if ($null -eq $script:HasGetCimInstance) {
            $script:HasGetCimInstance = [bool](Get-Command Get-CimInstance -EA SilentlyContinue)
        }

        try {
            if ($script:HasGetCimInstance) {
                $assoc = @(Get-CimInstance -ClassName Win32_PnPSignedDriverCIMDataFile -Filter $assocFilter -EA Stop)
            } else {
                $assoc = @(Get-WmiObject -Class Win32_PnPSignedDriverCIMDataFile -Filter $assocFilter -EA Stop)
            }
        } catch {
            $assoc = @(Get-WmiObject Win32_PnPSignedDriverCIMDataFile -EA SilentlyContinue | Where-Object { $_.Antecedent -eq $antecedent })
        }
    }

    foreach ($a in $assoc) {
        $depMatch = [regex]::Match("$($a.Dependent)", 'Name="(.+)"')
        if ($depMatch.Success) {
            $path = $depMatch.Groups[1].Value -replace "\\\\", "\\"
            & $addResolved $path
        }
    }

    if ($assoc.Count -gt 0) { Log "Package association returned $($assoc.Count) file link(s)" "SUCCESS" }
    else { Log "Package association yielded no files; INF fallback will be used" "WARN" }

    $serviceName = $null
    if ($GPU.PSObject.Properties["DriverName"] -and $GPU.DriverName) { $serviceName = "$($GPU.DriverName)" }
    if ($serviceName) {
        $escapedServiceName = "$serviceName".Replace("'", "''")
        $serviceFilter = "Name='$escapedServiceName'"
        $svc = GetCompatManagementInstances "Win32_SystemDriver" $serviceFilter | Select-Object -First 1
        if (!$svc) {
            $svc = GetCompatManagementInstances "Win32_SystemDriver" | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
        }
        if ($svc -and $svc.PathName) {
            $bin = "$($svc.PathName)".Trim()
            $binPath = if ($bin.StartsWith('"')) {
                ([regex]::Match($bin, '^"([^"]+)"')).Groups[1].Value
            } else {
                $bin.Split(' ')[0]
            }
            if ($binPath) {
                $serviceBinaryPath = NormalizeDriverPath $binPath
                & $addResolved $binPath
            }
        }
    }

    Spin "Analyzing INF references..." 1
    $infPath = ResolveInfPathForGpu $GPU
    if ($infPath) {
        & $addResolved $infPath
        $refs = @(GetInfReferences $infPath)
        foreach ($r in $refs) {
            $refNameSet["$r".ToLowerInvariant()] = $true
        }
        Log "Found $($refs.Count) INF file reference(s)" "INFO"
        $search = @(
            @{P="C:\Windows\System32\DriverStore\FileRepository"; R=$true},
            @{P="C:\Windows\System32"; R=$false},
            @{P="C:\Windows\SysWow64"; R=$false},
            @{P="C:\Windows\INF"; R=$false}
        )

        $flatSearchIndex = @{}
        foreach ($r in $refs) {
            $found = $false
            foreach ($sp in $search) {
                $matchPath = $null

                if ($sp.R) {
                    $f = Get-ChildItem -LiteralPath $sp.P -Filter $r -Recurse -EA SilentlyContinue | Select-Object -First 1
                    if ($f) { $matchPath = $f.FullName }
                } else {
                    $indexKey = "$($sp.P)".ToLowerInvariant()
                    if (!$flatSearchIndex.ContainsKey($indexKey)) {
                        $index = @{}
                        if (Test-Path $sp.P) {
                            Get-ChildItem -LiteralPath $sp.P -File -EA SilentlyContinue | ForEach-Object {
                                $nameKey = "$($_.Name)".ToLowerInvariant()
                                if (!$index.ContainsKey($nameKey)) { $index[$nameKey] = $_.FullName }
                            }
                        }
                        $flatSearchIndex[$indexKey] = $index
                    }

                    $nameLookup = "$r".ToLowerInvariant()
                    $index = $flatSearchIndex[$indexKey]
                    if ($index.ContainsKey($nameLookup)) {
                        $matchPath = $index[$nameLookup]
                    }
                }

                if ($matchPath) {
                    & $addResolved $matchPath
                    $found = $true
                    break
                }
            }
            if (!$found) { $missingRefs += $r }
        }
    } else {
        Log "Could not resolve INF path for this GPU" "WARN"
    }

    if ($resolvedMap.Count -eq 0) {
        Log "No driver files were resolved" "ERROR"
        return $null
    }

    Spin "Classifying files..." 1
    $folderMap = @{}
    $fileMap = @{}

    foreach ($path in ($resolvedMap.Values | Sort-Object -Unique)) {
        $driverStoreRoot = GetDriverStoreFolderRoot $path
        if ($driverStoreRoot) {
            $folderMap[$driverStoreRoot.ToLowerInvariant()] = $driverStoreRoot
            continue
        }

        if ($path -match '^[A-Za-z]:\\') {
            $leaf = (Split-Path -Leaf $path).ToLowerInvariant()
            $isReferenced = ($refNameSet.Count -eq 0) -or $refNameSet.ContainsKey($leaf)
            $isServiceBinary = $false
            if ($serviceBinaryPath) {
                $isServiceBinary = $path.Equals($serviceBinaryPath, [System.StringComparison]::OrdinalIgnoreCase)
            }
            if (!$isReferenced -and !$isServiceBinary) { continue }

            $dest = $path -replace '^[A-Za-z]:', ''
            $key = $dest.ToLowerInvariant()
            if (!$fileMap.ContainsKey($key)) {
                $fileMap[$key] = [PSCustomObject]@{N=(Split-Path -Leaf $path); S=$path; D=$dest}
            }
        }
    }

    if ($assoc.Count -eq 0) { $strategy = "InfFallback" }
    elseif ($missingRefs.Count -gt 0) { $strategy = "WmiAssociation+InfFallback" }

    $files = @($fileMap.Values | Sort-Object D)
    $folders = @($folderMap.Values | Sort-Object)
    Log "Located $($files.Count) files + $($folders.Count) folders" "SUCCESS"
    if ($missingRefs.Count -gt 0) { Log "$($missingRefs.Count) INF reference(s) were unresolved" "WARN" }
    Write-Host ""

    return @{
        Files = $files
        Folders = $folders
        Missing = @($missingRefs | Sort-Object -Unique)
        Strategy = $strategy
        InfPath = $infPath
    }
}
#endregion
