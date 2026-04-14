function Resolve-HyperVGpuProjectRoot {
    if ($script:HyperVGpuProjectRoot -and (Test-Path $script:HyperVGpuProjectRoot)) {
        return "$($script:HyperVGpuProjectRoot)"
    }

    if ($PSScriptRoot) {
        $srcRoot = Split-Path -Parent $PSScriptRoot
        if ($srcRoot) {
            $repoRoot = Split-Path -Parent $srcRoot
            if ($repoRoot -and (Test-Path $repoRoot)) { return "$repoRoot" }
        }
    }

    return (Get-Location).Path
}

function Select-HyperVGpuVmProfile([string]$Title="SELECT VM PROFILE") {
    $projectRoot = Resolve-HyperVGpuProjectRoot
    $profiles = @(
        GetHyperVGpuVmProfileInventory -ProjectRoot $projectRoot |
        Sort-Object @{Expression = { if ($_.IsDefault) { 0 } else { 1 } } }, Name
    )

    if (!$profiles) {
        Log "No VM profiles found." "WARN"
        return $null
    }

    $items = @($profiles | ForEach-Object {
        $defaultTag = if ($_.IsDefault) { " [default]" } else { "" }
        "{0}{1} | VM:{2} | {3}vCPU, {4}GB, {5}GB" -f $_.Name, $defaultTag, $_.VmName, $_.Cpu, $_.RamGB, $_.StorageGB
    }) + "< Cancel >"

    $sel = Menu -Items $items -Title $Title
    if ($null -eq $sel -or $sel -eq ($items.Count - 1)) { return $null }
    return $profiles[$sel]
}

function Show-HyperVGpuVmProfileInventoryInteractive {
    Box "VM PROFILE TEMPLATES" "-"
    $projectRoot = Resolve-HyperVGpuProjectRoot
    $profiles = @(GetHyperVGpuVmProfileInventory -ProjectRoot $projectRoot | Sort-Object @{Expression = { if ($_.IsDefault) { 0 } else { 1 } } }, Name)
    if (!$profiles) {
        Log "No VM profiles found. Create one from this menu." "WARN"
        return
    }

    $rows = @($profiles | ForEach-Object {
        [PSCustomObject]@{
            Name = $_.Name
            VM = $_.VmName
            Cpu = $_.Cpu
            Ram = $_.RamGB
            Storage = $_.StorageGB
            Auto = if ($_.EnableAutoInstall) { "Yes" } else { "No" }
            Default = if ($_.IsDefault) { "Yes" } else { "No" }
        }
    })

    Table -Data $rows -Cols @(
        @{H="Name"; P="Name"},
        @{H="VM Name"; P="VM"},
        @{H="CPU"; P="Cpu"},
        @{H="RAM"; P="Ram"},
        @{H="Storage"; P="Storage"},
        @{H="AutoInstall"; P="Auto"},
        @{H="Default"; P="Default"}
    )
}

function Show-HyperVGpuVmProfileDetailsInteractive {
    $profile = Select-HyperVGpuVmProfile -Title "PROFILE DETAILS"
    if (!$profile) { return $null }

    Box "VM PROFILE: $($profile.Name)" "-"
    Log "VM Name: $($profile.VmName)" "INFO"
    Log "CPU: $($profile.Cpu)" "INFO"
    Log "RAM (GB): $($profile.RamGB)" "INFO"
    Log "Storage (GB): $($profile.StorageGB)" "INFO"
    Log "VHD Path: $($profile.VhdPath)" "INFO"
    Log "ISO Path: $(if ($profile.IsoPath) { $profile.IsoPath } else { "<none>" })" "INFO"
    Log "Auto Install: $(if ($profile.EnableAutoInstall) { "Yes" } else { "No" })" "INFO"
    if ($profile.EnableAutoInstall) {
        Log "Install Image Index: $(if ($profile.InstallImageIndex -gt 0) { $profile.InstallImageIndex } else { "<manual>" })" "INFO"
        Log "Unattend Username: $(if ($profile.UnattendUsername) { $profile.UnattendUsername } else { "<none>" })" "INFO"
        Log "Unattend Password: $(if ($profile.UnattendPassword) { "<set>" } else { "<empty>" })" "INFO"
    }
    Log "Overwrite VHD if exists: $(if ($profile.OverwriteVhd) { "Yes" } else { "No" })" "INFO"
    Log "Default profile: $(if ($profile.IsDefault) { "Yes" } else { "No" })" "INFO"
    return $true
}

function Prompt-HyperVGpuYesNo([string]$Message, [bool]$Default=$false) {
    $defaultText = if ($Default) { "Y" } else { "N" }
    while ($true) {
        $raw = (Read-Host "  $Message [Y/N] (default: $defaultText)").Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        if ($raw -match "^[Yy]$") { return $true }
        if ($raw -match "^[Nn]$") { return $false }
        Log "Please answer Y or N." "WARN"
    }
}

function Read-HyperVGpuOptionalNonNegativeInt([string]$Prompt, [int]$DefaultValue=0) {
    while ($true) {
        $defaultText = if ($DefaultValue -gt 0) { "$DefaultValue" } else { "0" }
        $raw = (Read-Host "  $Prompt [$defaultText]").Trim()
        if ([string]::IsNullOrWhiteSpace($raw)) { return [int]$DefaultValue }

        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -ge 0) {
            return [int]$parsed
        }
        Log "Enter a non-negative number." "WARN"
    }
}

function Select-HyperVGpuInstallImageIndex([string]$IsoPath, [int]$DefaultValue=0) {
    $defaultIndex = if ($DefaultValue -ge 0) { [int]$DefaultValue } else { 0 }

    if ([string]::IsNullOrWhiteSpace($IsoPath)) {
        return (Read-HyperVGpuOptionalNonNegativeInt -Prompt "Windows image index for unattended setup (0 = manual)" -DefaultValue $defaultIndex)
    }

    if (!(Test-Path $IsoPath)) {
        Log "ISO path not found; cannot enumerate Windows installation options." "WARN"
        return (Read-HyperVGpuOptionalNonNegativeInt -Prompt "Windows image index for unattended setup (0 = manual)" -DefaultValue $defaultIndex)
    }

    $imageOptions = @(GetWindowsInstallImageOptions $IsoPath)
    if (!$imageOptions -or $imageOptions.Count -eq 0) {
        return (Read-HyperVGpuOptionalNonNegativeInt -Prompt "Windows image index for unattended setup (0 = manual)" -DefaultValue $defaultIndex)
    }

    if ($defaultIndex -gt 0) {
        $defaultChoice = $imageOptions | Where-Object { $_.Index -eq $defaultIndex } | Select-Object -First 1
        if ($defaultChoice) {
            Log "Current saved install index: $defaultIndex ($($defaultChoice.Name))" "INFO"
        } else {
            Log "Current saved install index: $defaultIndex" "INFO"
        }
    }

    $selection = PromptWindowsInstallImageSelection $imageOptions
    if ($selection -and $selection.Index -gt 0) {
        return [int]$selection.Index
    }

    if ($defaultIndex -gt 0 -and (Prompt-HyperVGpuYesNo -Message "Keep existing install image index $defaultIndex for this profile?" -Default $true)) {
        return $defaultIndex
    }

    return 0
}

function Read-HyperVGpuVmProfileInput($SeedProfile=$null, [switch]$IncludeProfileName) {
    Box "VM PROFILE CONFIG" "-"

    $seedProfileName = if ($SeedProfile) { "$($SeedProfile.Name)" } else { $null }
    $seedVmName = if ($SeedProfile) { "$($SeedProfile.VmName)" } else { "" }
    $seedCpu = if ($SeedProfile -and $SeedProfile.Cpu -gt 0) { [int]$SeedProfile.Cpu } else { 4 }
    $seedRam = if ($SeedProfile -and $SeedProfile.RamGB -gt 0) { [int]$SeedProfile.RamGB } else { 8 }
    $seedStorage = if ($SeedProfile -and $SeedProfile.StorageGB -gt 0) { [int]$SeedProfile.StorageGB } else { 128 }
    $seedVhdPath = if ($SeedProfile -and $SeedProfile.VhdPath) { "$($SeedProfile.VhdPath)" } else { "$($script:Paths.VHD)" }
    $seedIsoPath = if ($SeedProfile -and $SeedProfile.IsoPath) { "$($SeedProfile.IsoPath)" } else { "" }
    $seedEnableAutoInstall = if ($SeedProfile) { [bool]$SeedProfile.EnableAutoInstall } else { $false }
    $seedInstallImageIndex = if ($SeedProfile -and $SeedProfile.InstallImageIndex -ge 0) { [int]$SeedProfile.InstallImageIndex } else { 0 }
    $seedUnattendUsername = if ($SeedProfile -and $SeedProfile.UnattendUsername) { "$($SeedProfile.UnattendUsername)" } else { "" }
    $seedUnattendPassword = if ($SeedProfile -and $SeedProfile.UnattendPassword) { "$($SeedProfile.UnattendPassword)" } else { "" }
    $seedOverwriteVhd = if ($SeedProfile) { [bool]$SeedProfile.OverwriteVhd } else { $false }

    $profileName = $seedProfileName
    if ($IncludeProfileName) {
        $profileName = Input "Profile Name" {
            param($value)
            ![string]::IsNullOrWhiteSpace("$value")
        } $seedProfileName
    }

    $vmName = Input "VM Name" {
        param($value)
        ![string]::IsNullOrWhiteSpace("$value")
    } $seedVmName

    $cpu = [int](Input "CPU Cores" {
        param($value)
        $parsed = 0
        [int]::TryParse("$value", [ref]$parsed) -and $parsed -gt 0
    } "$seedCpu")

    $ramGB = [int](Input "RAM (GB)" {
        param($value)
        $parsed = 0
        [int]::TryParse("$value", [ref]$parsed) -and $parsed -gt 0
    } "$seedRam")

    $storageGB = [int](Input "Storage (GB)" {
        param($value)
        $parsed = 0
        [int]::TryParse("$value", [ref]$parsed) -and $parsed -gt 0
    } "$seedStorage")

    $vhdPath = Input "VHD Root Path" {
        param($value)
        ![string]::IsNullOrWhiteSpace("$value")
    } $seedVhdPath

    $isoPrompt = if ($seedIsoPath) { "  ISO Path (press Enter to keep: $seedIsoPath)" } else { "  ISO Path (press Enter to skip)" }
    $isoInput = (Read-Host $isoPrompt).Trim()
    $isoPath = if ([string]::IsNullOrWhiteSpace($isoInput)) { $seedIsoPath } else { $isoInput }
    if ([string]::IsNullOrWhiteSpace($isoPath)) { $isoPath = $null }

    $enableAutoInstall = Prompt-HyperVGpuYesNo -Message "Enable automated Windows installation by default?" -Default:$seedEnableAutoInstall
    $installImageIndex = 0
    $unattendUsername = $null
    $unattendPassword = $null
    if ($enableAutoInstall) {
        $installImageIndex = Select-HyperVGpuInstallImageIndex -IsoPath $isoPath -DefaultValue $seedInstallImageIndex

        $seedHasCredential = (![string]::IsNullOrWhiteSpace($seedUnattendUsername) -or ![string]::IsNullOrWhiteSpace($seedUnattendPassword))
        $storeCredential = Prompt-HyperVGpuYesNo -Message "Store unattended username/password in this profile?" -Default:$seedHasCredential
        if ($storeCredential) {
            $userPrompt = if ($seedUnattendUsername) { "  Unattend Username [$seedUnattendUsername]" } else { "  Unattend Username [User]" }
            $rawUser = (Read-Host $userPrompt).Trim()
            if ([string]::IsNullOrWhiteSpace($rawUser)) {
                $unattendUsername = if ($seedUnattendUsername) { $seedUnattendUsername } else { "User" }
            } else {
                $unattendUsername = $rawUser
            }

            $passPrompt = if ($seedUnattendPassword) { "  Unattend Password [saved]" } else { "  Unattend Password [empty]" }
            $rawPass = Read-Host $passPrompt
            if ([string]::IsNullOrWhiteSpace($rawPass)) {
                $unattendPassword = if ($seedUnattendPassword) { $seedUnattendPassword } else { "" }
            } else {
                $unattendPassword = $rawPass
            }
        }
    }

    $overwriteVhd = Prompt-HyperVGpuYesNo -Message "Overwrite existing VHD automatically when this profile is used?" -Default:$seedOverwriteVhd

    return [PSCustomObject]@{
        Name = if ($profileName) { "$profileName" } else { $null }
        VmName = "$vmName"
        Cpu = [int]$cpu
        RamGB = [int]$ramGB
        StorageGB = [int]$storageGB
        VhdPath = "$vhdPath"
        IsoPath = if ($isoPath) { "$isoPath" } else { $null }
        EnableAutoInstall = [bool]$enableAutoInstall
        InstallImageIndex = [int]$installImageIndex
        UnattendUsername = if ($unattendUsername) { "$unattendUsername" } else { $null }
        UnattendPassword = if ($null -ne $unattendPassword) { "$unattendPassword" } else { $null }
        OverwriteVhd = [bool]$overwriteVhd
    }
}

function Save-HyperVGpuInteractiveVmProfile {
    $input = Read-HyperVGpuVmProfileInput -IncludeProfileName
    if (!$input -or [string]::IsNullOrWhiteSpace($input.Name)) { return $null }

    $projectRoot = Resolve-HyperVGpuProjectRoot
    $existing = @(GetHyperVGpuVmProfileInventory -ProjectRoot $projectRoot | Where-Object { $_.Name.Trim().ToLowerInvariant() -eq $input.Name.Trim().ToLowerInvariant() })
    if ($existing -and !(Confirm "Profile '$($input.Name)' already exists. Overwrite it?")) {
        Log "Cancelled" "WARN"
        return $null
    }

    $setDefault = if ($existing -and $existing[0].IsDefault) {
        Prompt-HyperVGpuYesNo -Message "Keep '$($input.Name)' as default profile?" -Default $true
    } else {
        Prompt-HyperVGpuYesNo -Message "Set '$($input.Name)' as default profile?" -Default $false
    }

    $saved = SaveHyperVGpuVmProfile -Name $input.Name -ProjectRoot $projectRoot -VmName $input.VmName -Cpu $input.Cpu -RamGB $input.RamGB -StorageGB $input.StorageGB -VhdPath $input.VhdPath -IsoPath $input.IsoPath -EnableAutoInstall:$input.EnableAutoInstall -InstallImageIndex $input.InstallImageIndex -UnattendUsername $input.UnattendUsername -UnattendPassword $input.UnattendPassword -OverwriteVhd:$input.OverwriteVhd -SetDefault:$setDefault
    if (!$saved) { return $false }

    Log "VM profile '$($saved.Name)' saved." "SUCCESS"
    return $true
}

function Edit-HyperVGpuInteractiveVmProfile {
    $profile = Select-HyperVGpuVmProfile -Title "SELECT PROFILE TO EDIT"
    if (!$profile) { return $null }

    $input = Read-HyperVGpuVmProfileInput -SeedProfile $profile
    if (!$input) { return $null }

    $setDefault = Prompt-HyperVGpuYesNo -Message "Set '$($profile.Name)' as default profile?" -Default $profile.IsDefault
    $projectRoot = Resolve-HyperVGpuProjectRoot
    $saved = SaveHyperVGpuVmProfile -Name $profile.Name -ProjectRoot $projectRoot -VmName $input.VmName -Cpu $input.Cpu -RamGB $input.RamGB -StorageGB $input.StorageGB -VhdPath $input.VhdPath -IsoPath $input.IsoPath -EnableAutoInstall:$input.EnableAutoInstall -InstallImageIndex $input.InstallImageIndex -UnattendUsername $input.UnattendUsername -UnattendPassword $input.UnattendPassword -OverwriteVhd:$input.OverwriteVhd -SetDefault:$setDefault
    if (!$saved) { return $false }

    Log "VM profile '$($saved.Name)' updated." "SUCCESS"
    return $true
}

function Set-HyperVGpuInteractiveVmProfileDefault {
    $profile = Select-HyperVGpuVmProfile -Title "SELECT DEFAULT PROFILE"
    if (!$profile) { return $null }

    $projectRoot = Resolve-HyperVGpuProjectRoot
    if (SetHyperVGpuVmProfileDefault -Name $profile.Name -ProjectRoot $projectRoot) {
        Log "Default VM profile set to '$($profile.Name)'." "SUCCESS"
        return $true
    }

    return $false
}

function Remove-HyperVGpuInteractiveVmProfile {
    $profile = Select-HyperVGpuVmProfile -Title "SELECT PROFILE TO DELETE"
    if (!$profile) { return $null }

    if (!(Confirm "Delete VM profile '$($profile.Name)'?")) {
        Log "Cancelled" "WARN"
        return $null
    }

    $projectRoot = Resolve-HyperVGpuProjectRoot
    return (RemoveHyperVGpuVmProfile -Name $profile.Name -ProjectRoot $projectRoot)
}

function Start-HyperVGpuProfilesMenu {
    $menu = @(
        "List VM Profiles",
        "View VM Profile Details",
        "Create VM Profile",
        "Edit VM Profile",
        "Delete VM Profile",
        "Set Default VM Profile",
        "Back"
    )

    while ($true) {
        $ch = Menu -Items $menu -Title "VM PROFILE TEMPLATES"
        if ($null -eq $ch -or $ch -eq ($menu.Count - 1)) { return $true }

        Write-Host ""
        switch ($ch) {
            0 { Show-HyperVGpuVmProfileInventoryInteractive; Pause }
            1 { $result = Show-HyperVGpuVmProfileDetailsInteractive; if ($null -ne $result) { Pause } }
            2 { $result = Save-HyperVGpuInteractiveVmProfile; if ($null -ne $result) { Pause } }
            3 { $result = Edit-HyperVGpuInteractiveVmProfile; if ($null -ne $result) { Pause } }
            4 { $result = Remove-HyperVGpuInteractiveVmProfile; if ($null -ne $result) { Pause } }
            5 { $result = Set-HyperVGpuInteractiveVmProfileDefault; if ($null -ne $result) { Pause } }
        }
    }
}

function Start-HyperVGpuInteractiveMenu {
    $menu = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Delete VM", "List VMs", "GPU Info", "VM Profiles", "Exit")
    while ($true) {
        $ch = Menu $menu "MAIN MENU"
        if ($null -eq $ch) { Log "Cancelled" "INFO"; continue }
        Write-Host ""
        switch ($ch) {
            0 { $createResult = NewVM; if ($null -ne $createResult) { Pause } }
            1 { $setResult = SetGPU; if ($null -ne $setResult) { Pause } }
            2 { $removeResult = RemoveGPU; if ($null -ne $removeResult) { Pause } }
            3 { $installResult = InstallDrivers; if ($null -ne $installResult) { Pause } }
            4 { $deleteResult = DeleteVM; if ($null -ne $deleteResult) { Pause } }
            5 { ShowVMs }
            6 { ShowGPUs }
            7 { Start-HyperVGpuProfilesMenu }
            8 { Log "Goodbye!" "INFO"; return $true }
        }
    }
}
