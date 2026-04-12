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

$menu = @("Create VM", "GPU Partition", "Unassign GPU", "Install Drivers", "Delete VM", "List VMs", "GPU Info", "Exit")
while ($true) {
    $ch = Menu $menu "MAIN MENU"
    if ($null -eq $ch) { Log "Cancelled" "INFO"; continue }
    Write-Host ""
    switch ($ch) {
        0 { NewVM | Out-Null; Pause }
        1 { SetGPU | Out-Null; Pause }
        2 { RemoveGPU | Out-Null; Pause }
        3 { InstallDrivers | Out-Null; Pause }
        4 { DeleteVM | Out-Null; Pause }
        5 { ShowVMs }
        6 { ShowGPUs }
        7 { Log "Goodbye!" "INFO"; exit }
    }
}
