#region VHD Operations
function SecureDir($P) {
    if (Test-Path $P) { return }
    New-Item $P -ItemType Directory -Force -EA Stop | Out-Null
    $acl = Get-Acl $P
    $acl.SetAccessRuleProtection($true, $false)
    @("S-1-5-18", "S-1-5-32-544") | ForEach-Object {
        $sid = [System.Security.Principal.SecurityIdentifier]$_
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($sid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    Set-Acl $P $acl
}

function MountVHD($VHD) {
    SecureDir $script:Paths.Mount
    $mp = Join-Path $script:Paths.Mount ("VMMount_" + [Guid]::NewGuid().ToString("N"))
    $disk = $null; $part = $null; $attachedPartitionNumber = $null
    try {
        SecureDir $mp; Spin "Mounting virtual disk..." 2
        $disk = Mount-VHD $VHD -NoDriveLetter -PassThru -EA Stop

        $partitions = @()
        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Update-Disk $disk.DiskNumber -EA SilentlyContinue
            $partitions = @(Get-Partition -DiskNumber $disk.DiskNumber -EA SilentlyContinue | Sort-Object Size -Descending)
            if ($partitions.Count -gt 0) { break }
            Start-Sleep -Milliseconds 500
        }
        if ($partitions.Count -eq 0) { throw "No partitions found on mounted disk" }

        $candidates = @($partitions | Where-Object { $_.Size -gt 5GB } | Sort-Object Size -Descending)
        if ($candidates.Count -eq 0) { $candidates = $partitions }

        Spin "Mounting partition..." 1
        foreach ($candidate in $candidates) {
            try {
                Add-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $candidate.PartitionNumber -AccessPath $mp -EA Stop
                $attachedPartitionNumber = $candidate.PartitionNumber
                if (Test-Path "$mp\Windows\System32") {
                    $part = $candidate
                    break
                }
            } catch {}

            if ($attachedPartitionNumber) {
                Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $attachedPartitionNumber -AccessPath $mp -EA SilentlyContinue
                $attachedPartitionNumber = $null
            }
        }

        if (!$part) { throw "Windows folder not found - is Windows installed?" }
        return @{Disk=$disk; Part=$part; Path=$mp; VHD=$VHD}
    } catch {
        if ($attachedPartitionNumber -and $disk) {
            Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $attachedPartitionNumber -AccessPath $mp -EA SilentlyContinue
        }
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
