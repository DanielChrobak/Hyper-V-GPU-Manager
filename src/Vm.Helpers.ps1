#region VM Helpers
function SelectVM($Title="SELECT VM", $State="Any") {
    Box $Title
    $vms = @(Get-VM | Where-Object { $State -eq "Any" -or $_.State -eq $State })
    if (!$vms) { Log "No $(if ($State -ne 'Any') { "$State " })VMs found" "ERROR"; Write-Host ""; return $null }
    $items = @($vms | ForEach-Object {
        $mem = if ($_.MemoryAssigned -gt 0) { $_.MemoryAssigned } else { $_.MemoryStartup }
        $ga = @(Get-VMGpuPartitionAdapter $_.Name -EA SilentlyContinue)
        $si = switch ($_.State) { "Running" { "[*]" } "Off" { "[ ]" } default { "[~]" } }
        $sc = switch ($_.State) { "Running" { "[Running]" } "Off" { "[Stopped]" } default { "[$($_.State)]" } }
        $base = "$si $($_.Name.PadRight(20)) $sc CPU:$($_.ProcessorCount) RAM:$([math]::Round($mem / 1GB))GB"

        if (!$ga) {
            "$base GPU:None"
        } else {
            $entries = @(GetGpuDisplayEntries -Adapters $ga)
            if (!$entries) {
                "$base GPU:Unknown"
            } elseif ($entries.Count -eq 1) {
                "$base`nGPU: $($entries[0].Label)"
            } else {
                $idx = 1
                $lines = @($entries | ForEach-Object {
                    $line = ("GPU{0}: {1}" -f $idx.ToString("00"), $_.Label)
                    $idx++
                    $line
                })
                "$base`n$($lines -join "`n")"
            }
        }
    }) + "< Cancel >"
    $sel = Menu -Items $items -Title $Title
    if ($sel -eq $null -or $sel -eq ($items.Count - 1)) { return $null }
    return $vms[$sel]
}

function StopVM($Name) {
    $vm = Get-VM $Name -EA SilentlyContinue
    if (!$vm -or $vm.State -eq "Off") { return $true }
    Log "VM is running - attempting graceful shutdown..." "WARN"
    return (Try-Op {
        Stop-VM $Name -Force -EA Stop
        if (Spin "Shutting down VM" -Cond { (Get-VM $Name).State -eq "Off" } -Timeout 60 -SuccessMsg "VM shut down") { Start-Sleep 2; return $true }
        Stop-VM $Name -TurnOff -Force -EA Stop; Start-Sleep 3; return $true
    } "Stop VM").OK
}

function EnsureOff($Name) {
    $v = Get-VM $Name -EA SilentlyContinue
    if (!$v) { Log "VM not found: $Name" "ERROR"; return $false }
    return ($v.State -eq "Off") -or (StopVM $Name)
}
#endregion
