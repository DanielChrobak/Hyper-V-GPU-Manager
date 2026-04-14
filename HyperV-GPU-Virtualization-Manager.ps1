param(
    [ValidateSet("interactive", "preflight", "create-vm", "set-gpu", "remove-gpu", "install-drivers", "delete-vm", "list-vms", "list-gpus", "help")]
    [string]$Command = "interactive",
    [string]$VMName,
    [string]$GpuPath,
    [string]$GpuName,
    [ValidateRange(0, 100)]
    [int]$GpuPercent = 0,
    [ValidateSet("gaming", "development", "ml", "ml-training", "custom")]
    [string]$Preset = "development",
    [int]$Cpu = 0,
    [int]$RamGB = 0,
    [int]$StorageGB = 0,
    [string]$VhdPath,
    [string]$IsoPath,
    [switch]$EnableAutoInstall,
    [int]$InstallImageIndex = 0,
    [string]$UnattendUsername,
    [string]$UnattendPassword,
    [switch]$OverwriteVhd,
    [switch]$All,
    [switch]$CleanDrivers,
    [switch]$SkipExisting,
    [switch]$DeleteFiles,
    [switch]$Force,
    [switch]$SkipPreflight,
    [switch]$Json
)

function Get-RelaunchArgumentList([string]$ScriptPath, [hashtable]$BoundParameters) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath)
    foreach ($key in ($BoundParameters.Keys | Sort-Object)) {
        $value = $BoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) {
                $args += "-$key"
            }
            continue
        }

        if ($null -eq $value) { continue }
        if ($value -is [string] -and [string]::IsNullOrWhiteSpace($value)) { continue }

        $args += "-$key"
        $args += "$value"
    }
    return $args
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    $relaunchArgs = Get-RelaunchArgumentList -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters
    Start-Process powershell.exe -ArgumentList $relaunchArgs -Verb RunAs | Out-Null
    exit
}

$moduleFiles = @(
    "src\Core\Config.Helpers.ps1",
    "src\Core\Gpu\Gpu.Helpers.ps1",
    "src\Core\Vhd.Operations.ps1",
    "src\Core\Vm.Helpers.ps1",
    "src\Core\AutoInstallIso.ps1",
    "src\Core\Main.Actions.ps1",
    "src\Api\Manager.Api.ps1",
    "src\Cli\Interactive.Menu.ps1",
    "src\Cli\Command.Dispatcher.ps1"
)

foreach ($moduleFile in $moduleFiles) {
    $modulePath = Join-Path $PSScriptRoot $moduleFile
    if (!(Test-Path $modulePath)) { throw "Required module file not found: $modulePath" }
    . $modulePath
}

if (!$SkipPreflight -and $Command -ne "help" -and $Command -ne "preflight") {
    $preflightResult = Invoke-HyperVGpuApiPreflight
    if (!$preflightResult.Success) {
        if ($Json) {
            $preflightResult | ConvertTo-Json -Depth 10
        }
        if ($Command -eq "interactive") {
            Pause
        }
        exit 1
    }
}

$ok = Invoke-HyperVGpuCliCommand -Command $Command -VMName $VMName -GpuPath $GpuPath -GpuName $GpuName -GpuPercent $GpuPercent -Preset $Preset -Cpu $Cpu -RamGB $RamGB -StorageGB $StorageGB -VhdPath $VhdPath -IsoPath $IsoPath -EnableAutoInstall:$EnableAutoInstall -InstallImageIndex $InstallImageIndex -UnattendUsername $UnattendUsername -UnattendPassword $UnattendPassword -OverwriteVhd:$OverwriteVhd -All:$All -CleanDrivers:$CleanDrivers -SkipExisting:$SkipExisting -DeleteFiles:$DeleteFiles -Force:$Force -Json:$Json
if (!$ok) {
    exit 1
}
