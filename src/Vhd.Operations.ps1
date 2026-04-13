#region VHD Operations
function SecureDir($P) {
    if (Test-Path $P) { return }
    New-Item $P -ItemType Directory -Force -EA Stop | Out-Null
    $acl = Get-Acl $P
    $acl.SetAccessRuleProtection($true, $false)
    @("NT AUTHORITY\SYSTEM", "BUILTIN\Administrators") | ForEach-Object {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($_, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")))
    }
    Set-Acl $P $acl
}

function MountVHD($VHD) {
    SecureDir $script:Paths.Mount
    $mp = Join-Path $script:Paths.Mount ("VMMount_" + [Guid]::NewGuid().ToString("N"))
    $disk = $null; $part = $null
    try {
        SecureDir $mp; Spin "Mounting virtual disk..." 2
        $disk = Mount-VHD $VHD -NoDriveLetter -PassThru -EA Stop
        Start-Sleep 2; Update-Disk $disk.DiskNumber -EA SilentlyContinue
        $part = Get-Partition -DiskNumber $disk.DiskNumber -EA Stop | Where-Object { $_.Size -gt 10GB } | Sort-Object Size -Descending | Select-Object -First 1
        if (!$part) { throw "No valid partition found" }
        Spin "Mounting partition..." 1
        Add-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mp
        if (!(Test-Path "$mp\Windows")) { throw "Windows folder not found - is Windows installed?" }
        return @{Disk=$disk; Part=$part; Path=$mp; VHD=$VHD}
    } catch {
        if ($part -and $disk) { Remove-PartitionAccessPath -DiskNumber $disk.DiskNumber -PartitionNumber $part.PartitionNumber -AccessPath $mp -EA SilentlyContinue }
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
