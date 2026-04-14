function Start-HyperVGpuInteractiveMenu {
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
            7 { Log "Goodbye!" "INFO"; return $true }
        }
    }
}
