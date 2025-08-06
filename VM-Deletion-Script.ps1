# VM-Deletion-Script.ps1 (VM and VHD Removal Tool)

function Log {
    param([string]$M, [string]$T = "INFO")
    Write-Host "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))][$T] $M"
}

function Show-Menu {
    Clear-Host
    Write-Host "===============================================" -ForegroundColor Red
    Write-Host "           VM DELETION TOOL v1.0              " -ForegroundColor Red
    Write-Host "===============================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "WARNING: This will permanently delete VM and VHD files!" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1. Delete specific VM and its VHD" -ForegroundColor Red
    Write-Host "2. List all VMs" -ForegroundColor Cyan
    Write-Host "3. Exit" -ForegroundColor Gray
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Red
}

function Get-AllVMs {
    try {
        $vms = Get-VM -ErrorAction Stop
        if ($vms.Count -eq 0) {
            Log "No VMs found on this system" "WARN"
            return $null
        }
        
        Log "Found $($vms.Count) VM(s):" "INFO"
        $vms | ForEach-Object { 
            $vmDisks = Get-VMHardDiskDrive -VMName $_.Name -ErrorAction SilentlyContinue
            $diskInfo = if ($vmDisks) { "VHD: $($vmDisks[0].Path)" } else { "No VHD attached" }
            Log "- $($_.Name) (State: $($_.State)) - $diskInfo" "INFO"
        }
        return $vms
    } catch {
        Log "Failed to retrieve VMs: $_" "ERROR"
        return $null
    }
}

function Remove-VMAndVHD {
    param([string]$VMName = $null)
    
    Log "=== VM DELETION MODULE ===" "INFO"
    
    # Get VM name if not provided
    if ([string]::IsNullOrWhiteSpace($VMName)) {
        Log "Available VMs:"
        $availableVMs = Get-AllVMs
        if (!$availableVMs) { return $false }
        
        Write-Host ""
        $VMName = Read-Host "Enter the name of the VM to delete"
        if ([string]::IsNullOrWhiteSpace($VMName)) {
            Log "No VM name provided" "ERROR"
            return $false
        }
    }
    
    # Check if VM exists
    try {
        $vm = Get-VM -Name $VMName -ErrorAction Stop
        Log "Found VM: $VMName (Generation: $($vm.Generation), State: $($vm.State))" "SUCCESS"
    } catch {
        Log "VM '$VMName' not found" "ERROR"
        return $false
    }
    
    # Get VM disk information
    $vmDisks = Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue
    $vhdPaths = @()
    
    if ($vmDisks) {
        foreach ($disk in $vmDisks) {
            $vhdPaths += $disk.Path
            Log "Found VHD: $($disk.Path)" "INFO"
        }
    } else {
        Log "No VHDs attached to VM '$VMName'" "WARN"
    }
    
    # Final confirmation
    Write-Host ""
    Write-Host "DELETION SUMMARY:" -ForegroundColor Yellow
    Write-Host "VM Name: $VMName" -ForegroundColor Yellow
    Write-Host "VM State: $($vm.State)" -ForegroundColor Yellow
    if ($vhdPaths.Count -gt 0) {
        Write-Host "VHDs to delete:" -ForegroundColor Yellow
        foreach ($path in $vhdPaths) {
            Write-Host "  - $path" -ForegroundColor Yellow
        }
    } else {
        Write-Host "No VHDs to delete" -ForegroundColor Yellow
    }
    Write-Host ""
    
    $confirmation = Read-Host "Are you sure you want to DELETE this VM and its VHDs? Type 'DELETE' to confirm"
    if ($confirmation -ne "DELETE") {
        Log "Deletion cancelled by user" "INFO"
        return $false
    }
    
    try {
        # Stop VM if running
        if ($vm.State -eq "Running") {
            Log "Stopping VM '$VMName'..."
            Stop-VM -Name $VMName -Force -ErrorAction Stop
            
            # Wait for VM to stop
            $timeout = 60
            $timer = [Diagnostics.Stopwatch]::StartNew()
            while ((Get-VM -Name $VMName).State -ne "Off" -and $timer.Elapsed.TotalSeconds -lt $timeout) {
                Start-Sleep 2
                Log "Waiting for VM to stop... ($([math]::Round($timer.Elapsed.TotalSeconds))s elapsed)" "INFO"
            }
            
            if ((Get-VM -Name $VMName).State -ne "Off") {
                Log "VM failed to stop within $timeout seconds" "ERROR"
                return $false
            }
            Log "VM stopped successfully" "SUCCESS"
        }
        
        # Remove VM
        Log "Removing VM '$VMName'..."
        Remove-VM -Name $VMName -Force -ErrorAction Stop
        Log "VM '$VMName' removed successfully" "SUCCESS"
        
        # Remove VHD files
        $deletedVHDs = 0
        $failedVHDs = 0
        
        foreach ($vhdPath in $vhdPaths) {
            try {
                if (Test-Path $vhdPath) {
                    Log "Deleting VHD: $vhdPath"
                    Remove-Item -Path $vhdPath -Force -ErrorAction Stop
                    Log "VHD deleted successfully: $vhdPath" "SUCCESS"
                    $deletedVHDs++
                } else {
                    Log "VHD not found at path: $vhdPath" "WARN"
                }
            } catch {
                Log "Failed to delete VHD '$vhdPath': $_" "ERROR"
                $failedVHDs++
            }
        }
        
        # Check for orphaned VHDs in default location
        $defaultVHDPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks"
        $orphanedVHD = "$defaultVHDPath\$VMName.vhdx"
        
        if (Test-Path $orphanedVHD) {
            Log "Found potential orphaned VHD: $orphanedVHD"
            if ((Read-Host "Delete orphaned VHD? (Y/N)") -match "^[Yy]$") {
                try {
                    Remove-Item -Path $orphanedVHD -Force -ErrorAction Stop
                    Log "Orphaned VHD deleted: $orphanedVHD" "SUCCESS"
                    $deletedVHDs++
                } catch {
                    Log "Failed to delete orphaned VHD: $_" "ERROR"
                    $failedVHDs++
                }
            }
        }
        
        # Summary
        Log "DELETION COMPLETED:" "SUCCESS"
        Log "- VM '$VMName' removed: YES" "SUCCESS"
        Log "- VHDs deleted: $deletedVHDs" "SUCCESS"
        if ($failedVHDs -gt 0) {
            Log "- VHDs failed to delete: $failedVHDs" "WARN"
        }
        
        return $true
        
    } catch {
        Log "Failed to delete VM '$VMName': $_" "ERROR"
        return $false
    }
}

function Remove-OrphanedVHDs {
    Log "=== ORPHANED VHD CLEANUP ===" "INFO"
    
    $vhdPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks"
    
    if (!(Test-Path $vhdPath)) {
        Log "VHD directory not found: $vhdPath" "ERROR"
        return
    }
    
    $vhdFiles = Get-ChildItem -Path $vhdPath -Filter "*.vhdx" -ErrorAction SilentlyContinue
    if (!$vhdFiles) {
        Log "No VHD files found in $vhdPath" "INFO"
        return
    }
    
    $allVMs = Get-VM -ErrorAction SilentlyContinue
    $attachedVHDs = @()
    
    if ($allVMs) {
        foreach ($vm in $allVMs) {
            $vmDisks = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue
            if ($vmDisks) {
                foreach ($disk in $vmDisks) {
                    $attachedVHDs += $disk.Path
                }
            }
        }
    }
    
    $orphanedVHDs = @()
    foreach ($vhdFile in $vhdFiles) {
        if ($vhdFile.FullName -notin $attachedVHDs) {
            $orphanedVHDs += $vhdFile
        }
    }
    
    if ($orphanedVHDs.Count -eq 0) {
        Log "No orphaned VHD files found" "INFO"
        return
    }
    
    Log "Found $($orphanedVHDs.Count) orphaned VHD file(s):" "WARN"
    foreach ($vhd in $orphanedVHDs) {
        $size = [math]::Round($vhd.Length / 1GB, 2)
        Log "- $($vhd.Name) (Size: ${size}GB)" "WARN"
    }
    
    if ((Read-Host "Delete all orphaned VHDs? (Y/N)") -match "^[Yy]$") {
        $deletedCount = 0
        foreach ($vhd in $orphanedVHDs) {
            try {
                Remove-Item -Path $vhd.FullName -Force -ErrorAction Stop
                Log "Deleted: $($vhd.Name)" "SUCCESS"
                $deletedCount++
            } catch {
                Log "Failed to delete $($vhd.Name): $_" "ERROR"
            }
        }
        Log "Cleanup completed: $deletedCount of $($orphanedVHDs.Count) VHDs deleted" "SUCCESS"
    }
}

# Main Script Execution
Log "Verifying administrative privileges"
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
    Log "Script requires elevation. Requesting admin rights..." "WARN"
    Start-Process powershell.exe "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}
Log "Administrative privileges confirmed" "SUCCESS"

do {
    Show-Menu
    $choice = Read-Host "Select an option (1-3)"
    
    switch ($choice) {
        "1" {
            $result = Remove-VMAndVHD
            if ($result) {
                Log "VM deletion completed successfully" "SUCCESS"
            }
            Write-Host ""
            Read-Host "Press Enter to return to menu"
        }
        "2" {
            Get-AllVMs | Out-Null
            Write-Host ""
            Read-Host "Press Enter to return to menu"
        }
        "3" {
            Log "Exiting VM Deletion Tool" "INFO"
            break
        }
        default {
            Log "Invalid selection. Please choose 1-3." "WARN"
            Start-Sleep 2
        }
    }
} while ($choice -ne "3")

Log "Script execution completed" "SUCCESS"
