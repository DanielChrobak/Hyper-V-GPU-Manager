#region GPU Helpers
function GetPartitionableGPUs {
    # Prefer newer cmdlet when present; fall back for older Windows builds.
    $hostCmd = Get-Command Get-VMHostPartitionableGpu -EA SilentlyContinue
    $legacyCmd = Get-Command Get-VMPartitionableGpu -EA SilentlyContinue

    if ($hostCmd) {
        try { return @(Get-VMHostPartitionableGpu -EA Stop) }
        catch {
            if ($legacyCmd) {
                try { return @(Get-VMPartitionableGpu -EA Stop) }
                catch { return @() }
            }
            return @()
        }
    }

    if ($legacyCmd) {
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

function ResolvePartitionableDevice($Path) {
    $ids = GetPciIdsFromPath $Path
    if (!$ids) { return $null }

    $ven = $ids.VEN
    $dev = $ids.DEV

    $video = Get-WmiObject Win32_VideoController -EA SilentlyContinue |
        Where-Object { $_.PNPDeviceID -like "*VEN_$ven*DEV_$dev*" } |
        Select-Object -First 1
    if ($video) {
        return [PSCustomObject]@{
            Name = $video.Name
            Class = "Display"
            Vendor = if ($video.AdapterCompatibility) { $video.AdapterCompatibility } else { $null }
            DeviceId = $video.PNPDeviceID
            VEN = $ven
            DEV = $dev
        }
    }

    $pnp = Get-WmiObject Win32_PnPEntity -EA SilentlyContinue |
        Where-Object { $_.PNPDeviceID -like "*VEN_$ven*DEV_$dev*" } |
        Select-Object -First 1
    if ($pnp) {
        $signed = Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue |
            Where-Object { $_.DeviceID -eq $pnp.PNPDeviceID } |
            Select-Object -First 1
        return [PSCustomObject]@{
            Name = if ($pnp.Name) { $pnp.Name } elseif ($signed.DeviceName) { $signed.DeviceName } else { $null }
            Class = if ($signed.DeviceClass) { $signed.DeviceClass } elseif ($pnp.PNPClass) { $pnp.PNPClass } else { "Unknown" }
            Vendor = if ($signed.DriverProviderName) { $signed.DriverProviderName } else { $null }
            DeviceId = $pnp.PNPDeviceID
            VEN = $ven
            DEV = $dev
        }
    }

    return [PSCustomObject]@{
        Name = $null
        Class = "Unknown"
        Vendor = $null
        DeviceId = $null
        VEN = $ven
        DEV = $dev
    }
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
        $name = GPUName $a.InstancePath
        if (!$name) {
            $meta = ResolvePartitionableDevice $a.InstancePath
            if ($meta -and $meta.Name) { $name = $meta.Name }
            elseif ($meta -and $meta.VEN -and $meta.DEV) { $name = "VEN_$($meta.VEN)/DEV_$($meta.DEV)" }
        }
        if (!$name) { $name = "GPU" }

        $pct = "?"
        try {
            if ($a.MaxPartitionVRAM -gt 0) { $pct = "$([math]::Round(($a.MaxPartitionVRAM / 1e9) * 100))%" }
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

    $driverCandidates = @(
        Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue |
            Where-Object { $_.DeviceID -like "*VEN_$($ids.VEN)*DEV_$($ids.DEV)*" }
    )
    if (!$driverCandidates) { return $null }

    if ($PreferredClass) {
        $preferred = $driverCandidates |
            Where-Object { $_.DeviceClass -and $_.DeviceClass.Equals("$PreferredClass", [System.StringComparison]::OrdinalIgnoreCase) } |
            Select-Object -First 1
        if ($preferred) { return $preferred }
    }

    $display = $driverCandidates |
        Where-Object { $_.DeviceClass -and $_.DeviceClass.Equals("Display", [System.StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($display) { return $display }

    return ($driverCandidates | Select-Object -First 1)
}

function SelectGPU($Title="SELECT GPU", [switch]$Partition) {
    if ($Partition) {
        $gpus = GetPartitionableGPUs
        if (!$gpus) { Box $Title; Log "No partitionable devices found" "ERROR"; Write-Host ""; return $null }
        $list = @(); $i = 0
        foreach ($g in $gpus) {
            $p = GetPartitionablePath $g
            $meta = ResolvePartitionableDevice $p
            $driver = if ($meta -and $meta.Class) { FindGPU $p $meta.Class } else { FindGPU $p }

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
        $list = @(Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue | Where-Object { $_.DeviceClass -eq "Display" })
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
    $m = [regex]::Match($clean, '(?i)^[A-Za-z]:\\windows\\system32\\driverstore\\filerepository\\([^\\]+)')
    if (!$m.Success) { return $null }
    $folder = $m.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($folder)) { return $null }
    $base = Join-Path $env:windir "System32\DriverStore\FileRepository"
    return (Join-Path $base $folder).TrimEnd('\\')
}

function ResolveInfPathForGpu($GPU) {
    if ($GPU -and $GPU.PSObject.Properties["InfName"] -and $GPU.InfName) {
        $direct = Join-Path "$env:windir\INF" $GPU.InfName
        if (Test-Path $direct) { return $direct }
    }

    if (!$GPU -or !$GPU.DeviceID) { return $null }
    $inf = Get-ChildItem $script:GPUReg -EA SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -EA SilentlyContinue
        if ($p.MatchingDeviceId -and ($GPU.DeviceID -like "*$($p.MatchingDeviceId)*" -or $p.MatchingDeviceId -like "*$($GPU.DeviceID)*")) { $p.InfPath }
    } | Select-Object -First 1
    if (!$inf) { return $null }

    $infPath = Join-Path "$env:windir\INF" $inf
    if (Test-Path $infPath) { return $infPath }
    return $null
}

function GetInfReferences($InfPath) {
    if (!(Test-Path $InfPath)) { return @() }
    $content = Get-Content $InfPath -Raw -EA SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($content)) { return @() }

    $patterns = @('\.sys','\.dll','\.exe','\.cat','\.inf','\.bin','\.vp','\.cpa','\.dat','\.cfg','\.json','\.ini','\.mui','\.pnf')
    $refs = @($patterns | ForEach-Object {
        [regex]::Matches($content, "[\w\-\.]+$_", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | ForEach-Object { $_.Value }
    } | Sort-Object -Unique)
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
        $assoc = @(Get-WmiObject Win32_PnPSignedDriverCIMDataFile -EA SilentlyContinue | Where-Object { $_.Antecedent -eq $antecedent })
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
        $svc = Get-WmiObject Win32_SystemDriver -EA SilentlyContinue | Where-Object { $_.Name -eq $serviceName } | Select-Object -First 1
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
        foreach ($r in $refs) {
            $found = $false
            foreach ($sp in $search) {
                $f = Get-ChildItem -Path $sp.P -Filter $r -Recurse:$sp.R -EA SilentlyContinue | Select-Object -First 1
                if ($f) {
                    & $addResolved $f.FullName
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
