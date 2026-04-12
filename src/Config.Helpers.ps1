#region Config & Helpers
$script:Paths = @{VHD="C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"; Mount="C:\ProgramData\HyperV-Mounts"; ISO="C:\ProgramData\HyperV-ISOs"}
$script:GPUReg = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}"
$script:Presets = @(
    @{L="Gaming | 8CPU, 16GB, 256GB"; N="Gaming-VM"; C=8; R=16; S=256},
    @{L="Development | 4CPU, 8GB, 128GB"; N="Dev-VM"; C=4; R=8; S=128},
    @{L="ML Training | 12CPU, 32GB, 512GB"; N="ML-VM"; C=12; R=32; S=512}
)

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
        if (& $V $i) { return $i }
        Log "Invalid input for: $P" "WARN"
    } while ($true)
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
                    $idx = [int]$k.KeyChar - 1
                    if ($idx -lt $Items.Count) { return $idx }
                }
            }
        }
    }
}
#endregion
