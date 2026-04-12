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
    if ($Path -and $Path -match "VEN_([0-9A-Fa-f]{4}).*DEV_([0-9A-Fa-f]{4})") {
        return [PSCustomObject]@{VEN=$matches[1].ToUpperInvariant(); DEV=$matches[2].ToUpperInvariant()}
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

function FindGPU($Path) {
    $ids = GetPciIdsFromPath $Path
    if ($ids) {
        Get-WmiObject Win32_PnPSignedDriver -EA SilentlyContinue |
            Where-Object { $_.DeviceClass -eq "Display" -and $_.DeviceID -like "*VEN_$($ids.VEN)*DEV_$($ids.DEV)*" } |
            Select-Object -First 1
    }
}

function SelectGPU($Title="SELECT GPU", [switch]$Partition) {
    if ($Partition) {
        $gpus = GetPartitionableGPUs
        if (!$gpus) { Box $Title; Log "No partitionable GPUs found" "ERROR"; Write-Host ""; return $null }
        $list = @(); $i = 0
        foreach ($g in $gpus) {
            $p = GetPartitionablePath $g
            $meta = ResolvePartitionableDevice $p
            if ($meta -and $meta.Name) { $n = $meta.Name }
            elseif ($meta -and $meta.VEN -and $meta.DEV) { $n = "Unknown Device (VEN_$($meta.VEN) DEV_$($meta.DEV))" }
            else { $n = "Unknown Partitionable Adapter #$($i + 1)" }

            $label = $n
            if ($meta -and $meta.Class -and $meta.Class -ne "Display") { $label = "$label [$($meta.Class)]" }

            $list += [PSCustomObject]@{
                I = $i
                P = $p
                N = $n
                L = $label
                C = if ($meta) { $meta.Class } else { $null }
                V = if ($meta) { $meta.Vendor } else { $null }
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
        if ($pick.C -and $pick.C -ne "Display") {
            Write-Host "  Device class: $($pick.C)" -ForegroundColor DarkYellow
            Write-Host "  Possible non-display accelerator (for example NPU)." -ForegroundColor DarkYellow
        } elseif ((!$pick.N -or $pick.N -like "Unknown*") -and $pick.VEN -and $pick.DEV) {
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
