#region Config & Helpers
$script:DefaultPaths = @{VHD="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"; Mount="C:\ProgramData\HyperV-Mounts"; ISO="C:\ProgramData\HyperV-ISOs"}
$script:GPUReg = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$script:DefaultPresets = @(
    @{K="gaming"; L="Gaming | 8vCPU, 16GB, 256GB"; N="Gaming-VM"; C=8; R=16; S=256},
    @{K="development"; L="Development | 4vCPU, 8GB, 128GB"; N="Dev-VM"; C=4; R=8; S=128},
    @{K="ml-training"; L="ML Training | 12vCPU, 32GB, 512GB"; N="ML-VM"; C=12; R=32; S=512}
)

$script:Paths = @{} + $script:DefaultPaths
$script:Presets = @($script:DefaultPresets | ForEach-Object { @{} + $_ })
$script:DefaultPresetKey = "development"
$script:VmProfileSchemaVersion = 1
$script:VmProfileStores = @{}

function GetHyperVGpuObjectValue($Obj, [string]$Name, $Default=$null) {
    if ($null -eq $Obj) { return $Default }

    if ($Obj -is [hashtable]) {
        if ($Obj.ContainsKey($Name)) { return $Obj[$Name] }
        return $Default
    }

    $prop = $Obj.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function GetHyperVGpuProfileMapKey([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }
    return $Name.Trim().ToLowerInvariant()
}

function ConvertToHyperVGpuPresetKey([string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key)) { return $null }
    $normalized = $Key.Trim().ToLowerInvariant()
    if ($normalized -eq "ml") { $normalized = "ml-training" }
    $normalized = ($normalized -replace "[^a-z0-9]+", "-").Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
    return $normalized
}

function ConvertToHyperVGpuPositiveInt($Value) {
    $parsed = 0
    if ([int]::TryParse("$Value", [ref]$parsed) -and $parsed -gt 0) {
        return [int]$parsed
    }
    return 0
}

function GetHyperVGpuPresetDefinition([string]$PresetKey) {
    $lookupKey = ConvertToHyperVGpuPresetKey $PresetKey
    if ([string]::IsNullOrWhiteSpace($lookupKey)) { return $null }

    foreach ($preset in @($script:Presets)) {
        if ($preset.K -eq $lookupKey) {
            return [PSCustomObject]@{
                Key = "$($preset.K)"
                Label = "$($preset.L)"
                Name = "$($preset.N)"
                Cpu = [int]$preset.C
                Ram = [int]$preset.R
                Storage = [int]$preset.S
            }
        }
    }

    return $null
}

function GetHyperVGpuPresetDefinitions {
    return @($script:Presets | ForEach-Object {
        [PSCustomObject]@{
            Key = "$($_.K)"
            Label = "$($_.L)"
            Name = "$($_.N)"
            Cpu = [int]$_.C
            Ram = [int]$_.R
            Storage = [int]$_.S
        }
    })
}

function GetHyperVGpuVmProfileStorePath([string]$ProjectRoot=$PSScriptRoot) {
    return (Join-Path $ProjectRoot ".hyperv-gpu-manager.vm-profiles.json")
}

function NewHyperVGpuVmProfileStore([string]$ProjectRoot=$PSScriptRoot) {
    return [PSCustomObject]@{
        Path = (GetHyperVGpuVmProfileStorePath -ProjectRoot $ProjectRoot)
        DefaultProfile = $null
        Profiles = @{}
    }
}

function ConvertToHyperVGpuVmProfileObject($Profile) {
    if ($null -eq $Profile) { return $null }

    $name = GetHyperVGpuObjectValue $Profile "Name"
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }

    $vmName = GetHyperVGpuObjectValue $Profile "VmName" (GetHyperVGpuObjectValue $Profile "VMName")
    if ([string]::IsNullOrWhiteSpace($vmName)) { $vmName = $name }

    $cpu = ConvertToHyperVGpuPositiveInt (GetHyperVGpuObjectValue $Profile "Cpu" (GetHyperVGpuObjectValue $Profile "CPU"))
    $ramGB = ConvertToHyperVGpuPositiveInt (GetHyperVGpuObjectValue $Profile "RamGB" (GetHyperVGpuObjectValue $Profile "RAM"))
    $storageGB = ConvertToHyperVGpuPositiveInt (GetHyperVGpuObjectValue $Profile "StorageGB" (GetHyperVGpuObjectValue $Profile "Storage"))
    if ($cpu -le 0 -or $ramGB -le 0 -or $storageGB -le 0) { return $null }

    $vhdPath = GetHyperVGpuObjectValue $Profile "VhdPath" (GetHyperVGpuObjectValue $Profile "Path")
    if ([string]::IsNullOrWhiteSpace($vhdPath)) { $vhdPath = $script:Paths.VHD }

    $isoPath = GetHyperVGpuObjectValue $Profile "IsoPath" (GetHyperVGpuObjectValue $Profile "ISO")
    if ([string]::IsNullOrWhiteSpace($isoPath)) { $isoPath = $null }

    $enableAutoInstall = [bool](GetHyperVGpuObjectValue $Profile "EnableAutoInstall" $false)

    $installImageIndex = 0
    $rawInstallImageIndex = GetHyperVGpuObjectValue $Profile "InstallImageIndex" 0
    [int]::TryParse("$rawInstallImageIndex", [ref]$installImageIndex) | Out-Null
    if ($installImageIndex -lt 0) { $installImageIndex = 0 }

    $unattendUsername = GetHyperVGpuObjectValue $Profile "UnattendUsername"
    if ([string]::IsNullOrWhiteSpace($unattendUsername)) { $unattendUsername = $null }

    $unattendPassword = GetHyperVGpuObjectValue $Profile "UnattendPassword"
    if ([string]::IsNullOrWhiteSpace($unattendPassword)) { $unattendPassword = $null }

    $overwriteVhd = [bool](GetHyperVGpuObjectValue $Profile "OverwriteVhd" $false)

    return [PSCustomObject]@{
        Name = "$name"
        VmName = "$vmName"
        Cpu = [int]$cpu
        RamGB = [int]$ramGB
        StorageGB = [int]$storageGB
        VhdPath = "$vhdPath"
        IsoPath = if ($isoPath) { "$isoPath" } else { $null }
        EnableAutoInstall = [bool]$enableAutoInstall
        InstallImageIndex = [int]$installImageIndex
        UnattendUsername = if ($unattendUsername) { "$unattendUsername" } else { $null }
        UnattendPassword = if ($unattendPassword) { "$unattendPassword" } else { $null }
        OverwriteVhd = [bool]$overwriteVhd
    }
}

function ImportHyperVGpuVmProfileStore([string]$ProjectRoot=$PSScriptRoot) {
    $store = NewHyperVGpuVmProfileStore -ProjectRoot $ProjectRoot
    if (!(Test-Path $store.Path)) { return $store }

    $raw = $null
    try {
        $raw = Get-Content $store.Path -Raw -EA Stop
    } catch {
        Log "Could not read VM profile store: $($store.Path)" "WARN"
        return $store
    }

    if ([string]::IsNullOrWhiteSpace($raw)) { return $store }

    $doc = $null
    try {
        $doc = $raw | ConvertFrom-Json -EA Stop
    } catch {
        Log "Could not parse VM profile store. Ignoring invalid JSON at $($store.Path)." "WARN"
        return $store
    }

    $defaultProfile = GetHyperVGpuObjectValue $doc "DefaultProfile"
    if (![string]::IsNullOrWhiteSpace($defaultProfile)) {
        $store.DefaultProfile = "$defaultProfile"
    }

    $rawProfiles = GetHyperVGpuObjectValue $doc "Profiles" @()
    if ($rawProfiles -isnot [System.Array]) { $rawProfiles = @($rawProfiles) }

    foreach ($rawProfile in @($rawProfiles)) {
        $profile = ConvertToHyperVGpuVmProfileObject $rawProfile
        if (!$profile) { continue }
        $store.Profiles[(GetHyperVGpuProfileMapKey $profile.Name)] = $profile
    }

    if (![string]::IsNullOrWhiteSpace($store.DefaultProfile)) {
        $defaultKey = GetHyperVGpuProfileMapKey $store.DefaultProfile
        if (!$defaultKey -or !$store.Profiles.ContainsKey($defaultKey)) {
            $store.DefaultProfile = $null
        }
    }

    return $store
}

function ExportHyperVGpuVmProfileStore($Store) {
    if ($null -eq $Store -or [string]::IsNullOrWhiteSpace($Store.Path)) { return $false }

    $profileList = @()
    foreach ($entry in @($Store.Profiles.GetEnumerator() | Sort-Object Key)) {
        $profile = $entry.Value
        if (!$profile) { continue }

        $profileList += [PSCustomObject]@{
            Name = "$($profile.Name)"
            VmName = "$($profile.VmName)"
            Cpu = [int]$profile.Cpu
            RamGB = [int]$profile.RamGB
            StorageGB = [int]$profile.StorageGB
            VhdPath = "$($profile.VhdPath)"
            IsoPath = if ($profile.IsoPath) { "$($profile.IsoPath)" } else { $null }
            EnableAutoInstall = [bool]$profile.EnableAutoInstall
            InstallImageIndex = [int]$profile.InstallImageIndex
            UnattendUsername = if ($profile.UnattendUsername) { "$($profile.UnattendUsername)" } else { $null }
            UnattendPassword = if ($profile.UnattendPassword) { "$($profile.UnattendPassword)" } else { $null }
            OverwriteVhd = [bool]$profile.OverwriteVhd
        }
    }

    $doc = [PSCustomObject]@{
        SchemaVersion = [int]$script:VmProfileSchemaVersion
        DefaultProfile = if ($Store.DefaultProfile) { "$($Store.DefaultProfile)" } else { $null }
        Profiles = $profileList
    }

    $parent = Split-Path -Parent $Store.Path
    EnsureDir $parent

    $tmpPath = "$($Store.Path).tmp"
    try {
        $doc | ConvertTo-Json -Depth 16 | Out-File $tmpPath -Encoding UTF8 -Force
        Move-Item -Path $tmpPath -Destination $Store.Path -Force
        return $true
    } catch {
        if (Test-Path $tmpPath) { Remove-Item -Path $tmpPath -Force -EA SilentlyContinue }
        Log "Could not write VM profile store: $($Store.Path)" "ERROR"
        return $false
    }
}

function InitializeHyperVGpuVmProfiles([string]$ProjectRoot=$PSScriptRoot) {
    $script:VmProfileStores = @{
        project = ImportHyperVGpuVmProfileStore -ProjectRoot $ProjectRoot
    }
}

function GetHyperVGpuVmProfileInventory([string]$ProjectRoot=$PSScriptRoot) {
    if (!$script:VmProfileStores.ContainsKey("project")) {
        InitializeHyperVGpuVmProfiles -ProjectRoot $ProjectRoot
    }

    $inventory = @()
    $store = GetHyperVGpuObjectValue $script:VmProfileStores "project"
    if (!$store -or !$store.Profiles) { return $inventory }

    foreach ($entry in @($store.Profiles.GetEnumerator() | Sort-Object Key)) {
        $profile = $entry.Value
        if (!$profile) { continue }

        $isDefault = $false
        if (![string]::IsNullOrWhiteSpace($store.DefaultProfile)) {
            $isDefault = ((GetHyperVGpuProfileMapKey $store.DefaultProfile) -eq $entry.Key)
        }

        $inventory += [PSCustomObject]@{
            Name = "$($profile.Name)"
            IsDefault = [bool]$isDefault
            VmName = "$($profile.VmName)"
            Cpu = [int]$profile.Cpu
            RamGB = [int]$profile.RamGB
            StorageGB = [int]$profile.StorageGB
            VhdPath = "$($profile.VhdPath)"
            IsoPath = if ($profile.IsoPath) { "$($profile.IsoPath)" } else { $null }
            EnableAutoInstall = [bool]$profile.EnableAutoInstall
            InstallImageIndex = [int]$profile.InstallImageIndex
            UnattendUsername = if ($profile.UnattendUsername) { "$($profile.UnattendUsername)" } else { $null }
            UnattendPassword = if ($profile.UnattendPassword) { "$($profile.UnattendPassword)" } else { $null }
            OverwriteVhd = [bool]$profile.OverwriteVhd
            StorePath = "$($store.Path)"
        }
    }

    return $inventory
}

function GetHyperVGpuVmProfile([string]$Name, [string]$ProjectRoot=$PSScriptRoot) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $null }

    if (!$script:VmProfileStores.ContainsKey("project")) {
        InitializeHyperVGpuVmProfiles -ProjectRoot $ProjectRoot
    }
    $profileKey = GetHyperVGpuProfileMapKey $Name

    $store = $script:VmProfileStores["project"]
    if (!$store -or !$store.Profiles -or !$store.Profiles.ContainsKey($profileKey)) { return $null }

    $profile = $store.Profiles[$profileKey]
    if (!$profile) { return $null }

    return [PSCustomObject]@{
        Name = "$($profile.Name)"
        VmName = "$($profile.VmName)"
        Cpu = [int]$profile.Cpu
        RamGB = [int]$profile.RamGB
        StorageGB = [int]$profile.StorageGB
        VhdPath = "$($profile.VhdPath)"
        IsoPath = if ($profile.IsoPath) { "$($profile.IsoPath)" } else { $null }
        EnableAutoInstall = [bool]$profile.EnableAutoInstall
        InstallImageIndex = [int]$profile.InstallImageIndex
        UnattendUsername = if ($profile.UnattendUsername) { "$($profile.UnattendUsername)" } else { $null }
        UnattendPassword = if ($profile.UnattendPassword) { "$($profile.UnattendPassword)" } else { $null }
        OverwriteVhd = [bool]$profile.OverwriteVhd
        StorePath = "$($store.Path)"
    }

    return $null
}

function SaveHyperVGpuVmProfile(
    [string]$Name,
    [string]$ProjectRoot=$PSScriptRoot,
    [string]$VmName,
    [int]$Cpu,
    [int]$RamGB,
    [int]$StorageGB,
    [string]$VhdPath,
    [string]$IsoPath,
    [switch]$EnableAutoInstall,
    [int]$InstallImageIndex=0,
    [string]$UnattendUsername,
    [string]$UnattendPassword,
    [switch]$OverwriteVhd,
    [switch]$SetDefault
) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Log "VM profile name is required." "ERROR"
        return $null
    }

    if (!$script:VmProfileStores.ContainsKey("project")) {
        InitializeHyperVGpuVmProfiles -ProjectRoot $ProjectRoot
    }

    $store = $script:VmProfileStores["project"]
    if (!$store) {
        Log "Could not access VM profile store." "ERROR"
        return $null
    }

    $rawProfile = [PSCustomObject]@{
        Name = $Name
        VmName = if ($VmName) { $VmName } else { $Name }
        Cpu = $Cpu
        RamGB = $RamGB
        StorageGB = $StorageGB
        VhdPath = if ($VhdPath) { $VhdPath } else { $script:Paths.VHD }
        IsoPath = if ($IsoPath) { $IsoPath } else { $null }
        EnableAutoInstall = [bool]$EnableAutoInstall
        InstallImageIndex = [int]$InstallImageIndex
        UnattendUsername = if ($UnattendUsername) { $UnattendUsername } else { $null }
        UnattendPassword = if ($UnattendPassword) { $UnattendPassword } else { $null }
        OverwriteVhd = [bool]$OverwriteVhd
    }

    $profile = ConvertToHyperVGpuVmProfileObject $rawProfile
    if (!$profile) {
        Log "Invalid VM profile data. Name, VM name, CPU, RAM, and Storage are required." "ERROR"
        return $null
    }

    $profileKey = GetHyperVGpuProfileMapKey $profile.Name
    $store.Profiles[$profileKey] = $profile

    if ($SetDefault) {
        $store.DefaultProfile = $profile.Name
    } elseif ([string]::IsNullOrWhiteSpace($store.DefaultProfile)) {
        $store.DefaultProfile = $profile.Name
    }

    if (!(ExportHyperVGpuVmProfileStore $store)) {
        return $null
    }

    return [PSCustomObject]@{
        Name = "$($profile.Name)"
        IsDefault = [bool]((GetHyperVGpuProfileMapKey $store.DefaultProfile) -eq $profileKey)
        VmName = "$($profile.VmName)"
        Cpu = [int]$profile.Cpu
        RamGB = [int]$profile.RamGB
        StorageGB = [int]$profile.StorageGB
        VhdPath = "$($profile.VhdPath)"
        IsoPath = if ($profile.IsoPath) { "$($profile.IsoPath)" } else { $null }
        EnableAutoInstall = [bool]$profile.EnableAutoInstall
        InstallImageIndex = [int]$profile.InstallImageIndex
        UnattendUsername = if ($profile.UnattendUsername) { "$($profile.UnattendUsername)" } else { $null }
        UnattendPassword = if ($profile.UnattendPassword) { "$($profile.UnattendPassword)" } else { $null }
        OverwriteVhd = [bool]$profile.OverwriteVhd
        StorePath = "$($store.Path)"
    }
}

function SetHyperVGpuVmProfileDefault([string]$Name, [string]$ProjectRoot=$PSScriptRoot) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Log "VM profile name is required." "ERROR"
        return $false
    }

    if (!$script:VmProfileStores.ContainsKey("project")) {
        InitializeHyperVGpuVmProfiles -ProjectRoot $ProjectRoot
    }

    $store = $script:VmProfileStores["project"]
    if (!$store) { return $false }

    $profileKey = GetHyperVGpuProfileMapKey $Name
    if (!$store.Profiles.ContainsKey($profileKey)) {
        Log "VM profile '$Name' does not exist." "ERROR"
        return $false
    }

    $store.DefaultProfile = $store.Profiles[$profileKey].Name
    if (!(ExportHyperVGpuVmProfileStore $store)) {
        return $false
    }

    return $true
}

function RemoveHyperVGpuVmProfile([string]$Name, [string]$ProjectRoot=$PSScriptRoot) {
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Log "VM profile name is required." "ERROR"
        return $false
    }

    if (!$script:VmProfileStores.ContainsKey("project")) {
        InitializeHyperVGpuVmProfiles -ProjectRoot $ProjectRoot
    }

    $store = $script:VmProfileStores["project"]
    if (!$store) { return $false }

    $profileKey = GetHyperVGpuProfileMapKey $Name
    if (!$store.Profiles.ContainsKey($profileKey)) {
        Log "VM profile '$Name' does not exist." "ERROR"
        return $false
    }

    $removedName = "$($store.Profiles[$profileKey].Name)"
    [void]$store.Profiles.Remove($profileKey)

    if (![string]::IsNullOrWhiteSpace($store.DefaultProfile) -and ((GetHyperVGpuProfileMapKey $store.DefaultProfile) -eq $profileKey)) {
        $next = @($store.Profiles.GetEnumerator() | Sort-Object Key | Select-Object -First 1)
        $store.DefaultProfile = if ($next) { "$($next[0].Value.Name)" } else { $null }
    }

    if (!(ExportHyperVGpuVmProfileStore $store)) {
        return $false
    }

    Log "VM profile '$removedName' removed." "SUCCESS"
    return $true
}

$script:UI = @{
    Accent = "Cyan"
    Title = "White"
    Muted = "DarkGray"
    Text = "Gray"
    Info = "Cyan"
    Success = "Green"
    Warn = "Yellow"
    Error = "Red"
}

function FitText($Text, $Width) {
    if ($null -eq $Text) { $Text = "" }
    if ($Width -lt 4) { return "" }
    if ($Text.Length -gt $Width) { return $Text.Substring(0, $Width - 3) + "..." }
    return $Text
}

function CenterText($Text, $Width) {
    $t = FitText $Text $Width
    $pad = [Math]::Max(0, $Width - $t.Length)
    $left = [Math]::Floor($pad / 2)
    $right = $pad - $left
    return (" " * $left) + $t + (" " * $right)
}

function AppHeader {
    $w = [Math]::Min(108, [Math]::Max(66, [Console]::WindowWidth - 4))
    $line = "=" * ($w - 4)
    Write-Host ""
    Write-Host ("  +{0}+" -f $line) -ForegroundColor $script:UI.Accent
    Write-Host ("  | {0} |" -f (CenterText "HYPER-V GPU PARAVIRTUALIZATION MANAGER" ($w - 6))) -ForegroundColor $script:UI.Title
    Write-Host ("  | {0} |" -f (CenterText "GPU-PV orchestration for Windows 10/11 Hyper-V" ($w - 6))) -ForegroundColor $script:UI.Muted
    Write-Host ("  +{0}+" -f $line) -ForegroundColor $script:UI.Accent
    Write-Host ""
}

function Log($M, $L="INFO") {
    $level = if ($L) { $L.ToUpperInvariant() } else { "INFO" }
    $c = @{INFO=$script:UI.Info; SUCCESS=$script:UI.Success; WARN=$script:UI.Warn; ERROR=$script:UI.Error; HEADER=$script:UI.Accent}
    $tag = @{INFO="INFO"; SUCCESS="DONE"; WARN="WARN"; ERROR="FAIL"; HEADER="HEAD"}
    if (!$c.ContainsKey($level)) { $level = "INFO" }
    Write-Host ("  [{0}] [{1}] {2}" -f (Get-Date).ToString("HH:mm:ss"), $tag[$level], $M) -ForegroundColor $c[$level]
}

function Box($T, $S="=", $W=80) {
    $w = [Math]::Min(120, [Math]::Max($W, [Math]::Max(48, $T.Length + 10)))
    $title = FitText $T ($w - 6)
    $border = if ($S -eq "=") { "=" } else { "-" }
    $titleColor = if ($S -eq "=") { $script:UI.Accent } else { $script:UI.Title }
    Write-Host ""
    Write-Host ("  +{0}+" -f ($border * ($w - 4))) -ForegroundColor $script:UI.Accent
    Write-Host ("  | {0} |" -f (CenterText $title ($w - 6))) -ForegroundColor $titleColor
    Write-Host ("  +{0}+" -f ($border * ($w - 4))) -ForegroundColor $script:UI.Accent
    Write-Host ""
}

function Spin($M, $D=2, $Cond=$null, $Timeout=60, $SuccessMsg=$null) {
    $s = "[   ]","[=  ]","[== ]","[===]"
    if ($Cond) {
        for ($i = 0; $i -lt $Timeout; $i++) {
            if (& $Cond) { Write-Host "`r  [DONE] $(if ($SuccessMsg) { $SuccessMsg } else { $M })                    " -ForegroundColor $script:UI.Success; return $true }
            Write-Host "`r  $($s[$i % $s.Count]) $M ($i sec)" -ForegroundColor $script:UI.Info -NoNewline
            Start-Sleep -Milliseconds 500
        }
        Write-Host "`r  [FAIL] $M - Timeout" -ForegroundColor $script:UI.Error; return $false
    }
    1..$D | ForEach-Object { Write-Host "`r  $($s[$_ % $s.Count]) $M" -ForegroundColor $script:UI.Info -NoNewline; Start-Sleep -Milliseconds 170 }
    Write-Host "`r  [DONE] $M" -ForegroundColor $script:UI.Success
}

function Try-Op($Code, $Op, $Ok=$null, $OnFail=$null) {
    try { $r = & $Code; if ($Ok) { Log $Ok "SUCCESS" }; return @{OK=$true; R=$r} }
    catch { Log "$Op failed: $_" "ERROR"; if ($OnFail) { & $OnFail }; return @{OK=$false; E=$_} }
}

function EnsureDir($P) { if (!(Test-Path $P)) { New-Item $P -ItemType Directory -Force -EA SilentlyContinue | Out-Null } }

function GetFreeBytesForPath($Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $root = [System.IO.Path]::GetPathRoot($fullPath)
        if ([string]::IsNullOrWhiteSpace($root)) { return $null }

        $driveName = $root.TrimEnd([char]'\').TrimEnd([char]':')
        if ([string]::IsNullOrWhiteSpace($driveName)) { return $null }

        $drive = Get-PSDrive -Name $driveName -EA SilentlyContinue
        if ($drive -and $drive.Free -ge 0) { return [int64]$drive.Free }

        if (Get-Command Get-Volume -EA SilentlyContinue) {
            $vol = Get-Volume -DriveLetter $driveName -EA SilentlyContinue | Select-Object -First 1
            if ($vol -and $vol.SizeRemaining -ge 0) { return [int64]$vol.SizeRemaining }
        }
    } catch {}
    return $null
}

function GetDriverManifestFilePath($MountPath) {
    if ([string]::IsNullOrWhiteSpace($MountPath)) { return $null }
    return (Join-Path $MountPath "Windows\System32\HostDriverStore\gpu-driver-manifest.json")
}

function ReadDriverManifest($MountPath) {
    $manifestPath = GetDriverManifestFilePath $MountPath
    if (!$manifestPath -or !(Test-Path $manifestPath)) { return @() }
    $backupPath = "$manifestPath.bak"

    foreach ($candidate in @($manifestPath, $backupPath)) {
        if (!(Test-Path $candidate)) { continue }
        try {
            $raw = Get-Content $candidate -Raw -EA Stop
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            $parsed = $raw | ConvertFrom-Json -EA Stop
            if ($candidate -ne $manifestPath) {
                Log "Driver manifest fallback in use: $candidate" "WARN"
            }
            if ($parsed -is [System.Array]) { return @($parsed) }
            return @($parsed)
        } catch {
            if ($candidate -eq $manifestPath) {
                Log "Could not parse driver manifest at $manifestPath. Trying backup copy." "WARN"
            }
        }
    }

    Log "Could not parse driver manifest at $manifestPath. A new manifest will be created." "WARN"
    return @()
}

function WriteDriverManifest($MountPath, $Entries) {
    $manifestPath = GetDriverManifestFilePath $MountPath
    if (!$manifestPath) { return }
    EnsureDir (Split-Path -Parent $manifestPath)

    $tempPath = "$manifestPath.tmp"
    $backupPath = "$manifestPath.bak"
    try {
        if (Test-Path $manifestPath) {
            Copy-Item -Path $manifestPath -Destination $backupPath -Force -EA SilentlyContinue
        }

        @($Entries) | ConvertTo-Json -Depth 8 | Out-File $tempPath -Encoding UTF8 -Force
        Move-Item -Path $tempPath -Destination $manifestPath -Force
    } catch {
        if (Test-Path $tempPath) { Remove-Item -Path $tempPath -Force -EA SilentlyContinue }
        throw
    }
}

function TestFileContentEqual($SourcePath, $DestinationPath) {
    if (!(Test-Path $SourcePath) -or !(Test-Path $DestinationPath)) { return $false }
    try {
        $srcItem = Get-Item $SourcePath -EA Stop
        $dstItem = Get-Item $DestinationPath -EA Stop
        if ($srcItem.Length -ne $dstItem.Length) { return $false }
        $srcHash = (Get-FileHash -Path $SourcePath -Algorithm SHA256 -EA Stop).Hash
        $dstHash = (Get-FileHash -Path $DestinationPath -Algorithm SHA256 -EA Stop).Hash
        return ($srcHash -eq $dstHash)
    } catch {
        return $false
    }
}

function Confirm($M) {
    while ($true) {
        $r = (Read-Host "  [Confirm] $M [Y/N]").Trim()
        if ($r -match "^[Yy]$") { return $true }
        if ($r -match "^[Nn]$") { return $false }
        Log "Please answer Y or N." "WARN"
    }
}

function Pause { Read-Host "`n  Press Enter to return to the menu" | Out-Null }

function Input($P, $V={$true}, $D=$null) {
    do {
        $label = if ($D) { "  $P [$D]" } else { "  $P" }
        $i = Read-Host $label
        if (!$i -and $D) { return $D }

        $isValid = $false

        try {
            $result = & $V $i
            if ($result -is [System.Array]) { $result = $result | Select-Object -Last 1 }
            $isValid = [bool]$result
        } catch {
            $isValid = $false
        }

        if (!$isValid) {
            try {
                $pipelineResult = $i | ForEach-Object $V | Select-Object -Last 1
                $isValid = [bool]$pipelineResult
            } catch {
                $isValid = $false
            }
        }

        if ($isValid) { return $i }
        Log "Invalid input for: $P" "WARN"
    } while ($true)
}

function FormatCapacityFromGB($ValueGB) {
    if ($null -eq $ValueGB) { return "0GB" }
    $gb = [double]$ValueGB
    if ($gb -lt 0) { $gb = 0 }

    if ($gb -ge 1024) {
        $tb = $gb / 1024
        if ([Math]::Abs($tb - [Math]::Round($tb)) -lt 0.01) { return ("{0}TB" -f [int][Math]::Round($tb)) }
        return ("{0:0.##}TB" -f $tb)
    }

    if ([Math]::Abs($gb - [Math]::Round($gb)) -lt 0.01) { return ("{0}GB" -f [int][Math]::Round($gb)) }
    return ("{0:0.##}GB" -f $gb)
}

function FormatCapacityFromBytes($Bytes) {
    if ($null -eq $Bytes) { return "0GB" }
    return (FormatCapacityFromGB ([double]$Bytes / 1GB))
}

function Table($Data, $Cols) {
    if (!$Data) { return }
    $widths = $Cols | ForEach-Object { $p = $_.P; [Math]::Max($_.H.Length, ($Data | ForEach-Object { "$($_.$p)".Length } | Measure-Object -Max).Maximum) }
    $sep = "  +" + (($widths | ForEach-Object { '-' * ($_ + 2) }) -join '+') + "+"
    Write-Host $sep -ForegroundColor $script:UI.Accent
    Write-Host ("  |" + (($Cols | ForEach-Object -Begin {$j=0} { " $($_.H.PadRight($widths[$j++])) " }) -join '|') + "|") -ForegroundColor $script:UI.Title
    Write-Host $sep -ForegroundColor $script:UI.Accent
    $row = 0
    foreach ($r in $Data) {
        Write-Host "  |" -ForegroundColor $script:UI.Accent -NoNewline
        for ($j = 0; $j -lt $Cols.Count; $j++) {
            $v = "$($r.($Cols[$j].P))"
            $c = if ($Cols[$j].C -and $r.($Cols[$j].C)) { $r.($Cols[$j].C) } elseif (($row % 2) -eq 0) { "Gray" } else { "DarkGray" }
            Write-Host " $($v.PadRight($widths[$j])) " -ForegroundColor $c -NoNewline
            Write-Host "|" -ForegroundColor $script:UI.Accent -NoNewline
        }
        Write-Host ""
        $row++
    }
    Write-Host $sep -ForegroundColor $script:UI.Accent
}

function WrapText($Text, $Width) {
    $w = [Math]::Max(12, $Width)
    $out = @()
    $source = if ($null -eq $Text) { "" } else { "$Text" }
    $chunks = $source -split "`r?`n"

    foreach ($chunk in $chunks) {
        $remaining = "$chunk"
        if ($remaining.Length -eq 0) { $out += ""; continue }

        while ($remaining.Length -gt $w) {
            $slice = $remaining.Substring(0, $w)
            $breakAt = $slice.LastIndexOf(' ')
            if ($breakAt -lt [Math]::Floor($w / 3)) { $breakAt = $w }

            $line = $remaining.Substring(0, $breakAt).TrimEnd()
            if ($line.Length -eq 0) { $line = $remaining.Substring(0, $w); $breakAt = $w }
            $out += $line
            $remaining = $remaining.Substring($breakAt).TrimStart()
        }

        $out += $remaining
    }

    if (!$out) { return @("") }
    return $out
}

function DrawMenu($Items, $Title, $Sel) {
    Clear-Host
    AppHeader
    Box $Title "-" 72

    $itemWidth = [Math]::Max(26, [Console]::WindowWidth - 16)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $lines = @(WrapText -Text $Items[$i] -Width $itemWidth)
        $num = ($i + 1).ToString().PadLeft(2, '0')
        $prefix = if ($i -eq $Sel) { ("  > [{0}] " -f $num) } else { ("    [{0}] " -f $num) }
        $contPrefix = " " * $prefix.Length

        if ($i -eq $Sel) {
            Write-Host ($prefix + $lines[0]) -ForegroundColor $script:UI.Success
            for ($j = 1; $j -lt $lines.Count; $j++) {
                Write-Host ($contPrefix + $lines[$j]) -ForegroundColor $script:UI.Success
            }
        } else {
            Write-Host ($prefix + $lines[0]) -ForegroundColor $script:UI.Text
            for ($j = 1; $j -lt $lines.Count; $j++) {
                Write-Host ($contPrefix + $lines[$j]) -ForegroundColor $script:UI.Text
            }
        }
    }
    Write-Host ""
    Write-Host "  Controls: Up/Down, W/S, Enter select, Esc cancel, 1-9 quick select" -ForegroundColor $script:UI.Muted
    Write-Host ""
}

function Menu($Items, $Title="MENU") {
    $sel = 0
    while ($true) {
        DrawMenu -Items $Items -Title $Title -Sel $sel
        $k = [Console]::ReadKey($true)
        switch ($k.Key) {
            "UpArrow" { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            "DownArrow" { $sel = ($sel + 1) % $Items.Count }
            "W" { $sel = ($sel - 1 + $Items.Count) % $Items.Count }
            "S" { $sel = ($sel + 1) % $Items.Count }
            "Enter" { return $sel }
            "Escape" { return $null }
            default {
                if ($k.KeyChar -match "^[1-9]$") {
                    $idx = [int]$k.KeyChar.ToString() - 1
                    if ($idx -lt $Items.Count) { return $idx }
                }
            }
        }
    }
}
#endregion
