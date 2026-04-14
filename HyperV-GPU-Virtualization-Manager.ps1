if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs; exit
}

$moduleFiles = @(
    "src\Config.Helpers.ps1",
    "src\Gpu.Helpers.ps1",
    "src\Vhd.Operations.ps1",
    "src\Vm.Helpers.ps1",
    "src\AutoInstallIso.ps1",
    "src\Main.Functions.ps1"
)

foreach ($moduleFile in $moduleFiles) {
    $modulePath = Join-Path $PSScriptRoot $moduleFile
    if (!(Test-Path $modulePath)) { throw "Required module file not found: $modulePath" }
    . $modulePath
}

function InvokeStartupPreflight {
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
        Log "Hyper-V cmdlets unavailable: $($missingCmdlets -join ', ')" "ERROR"
        Log "Enable Hyper-V and restart Windows, then run this tool again." "ERROR"
        return $false
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
    return $true
}

if (!(InvokeStartupPreflight)) {
    Pause
    exit 1
}

$menu = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Delete VM", "List VMs", "GPU Info", "Exit")
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
        7 { Log "Goodbye!" "INFO"; exit }
    }
}
