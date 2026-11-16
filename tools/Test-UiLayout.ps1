#requires -Version 7.0
<#
UI 布局审计（离屏，不需要管理员权限）

在真实 WinForms 布局跑完后，逐页检查两类问题：
  1) OVERLAP  —— 两个「可见文字/可交互」控件的矩形相交（字体重叠的根因）
  2) CLIP     —— 控件文字量超出自身宽/高（文字被裁掉、显示不全）

用法：
  pwsh -NoProfile -File .\tools\Test-UiLayout.ps1
  pwsh -NoProfile -File .\tools\Test-UiLayout.ps1 -Sizes 853x448,1024x720
  pwsh -NoProfile -File .\tools\Test-UiLayout.ps1 -Render -OutDir "$env:TEMP\pcopt-audit"

退出码：0 = 无问题；1 = 发现 OVERLAP/CLIP
#>
[CmdletBinding()]
param(
    [string[]]$Sizes = @('900x640', '1024x720', '1280x880', '1600x900'),
    [double]$Scale = 0,
    [string]$OutDir = '',
    [switch]$Render,
    [int]$MaxPrint = 40
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

# 离屏启动：不弹窗、不查更新、不要求管理员
$env:PCOPT_HEADLESS_RENDER = '1'
$env:PCOPT_RENDER_OUT = ''
# 模拟高 DPI 缩放（1.0 / 1.25 / 1.5）；不传则用真实 DPI
if ($Scale -gt 0) {
    $env:PCOPT_UI_SCALE = $Scale.ToString([System.Globalization.CultureInfo]::InvariantCulture)
} else {
    Remove-Item Env:PCOPT_UI_SCALE -ErrorAction SilentlyContinue
}
. (Join-Path $repoRoot 'OptimizeGUI.ps1')

$scaleTag = if ($Scale -gt 0) { " @${Scale}x" } else { '' }

$skipLeafTypes = @(
    'Panel', 'TableLayoutPanel', 'FlowLayoutPanel', 'GroupBox', 'SplitContainer',
    'SplitterPanel', 'TabControl', 'TabPage', 'PictureBox', 'ProgressBar',
    'TrackBar', 'Splitter', 'DataGridView', 'PropertyGrid'
)

$textTypes = @('Label', 'LinkLabel', 'Button', 'CheckBox', 'RadioButton')

function Get-AuditRects {
    param([System.Windows.Forms.Control]$Root)

    $result = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        foreach ($child in $node.Controls) {
            if ($child.Controls.Count -gt 0) { $stack.Push($child) }
        }
        if ($node -is [System.Windows.Forms.Control] -and $node -ne $Root) {
            $typeName = $node.GetType().Name
            if ($skipLeafTypes -contains $typeName) { continue }
            if (-not $node.Visible) { continue }
            if ($node.Width -le 0 -or $node.Height -le 0) { continue }
            try {
                $origin = $node.PointToScreen([System.Drawing.Point]::Empty)
            } catch { continue }
            if ($origin.X -lt -3000) { continue }
            $result.Add([pscustomobject]@{
                    Control = $node
                    Type    = $typeName
                    Name    = [string]$node.Name
                    Text    = [string]$node.Text
                    X       = [int]$origin.X
                    Y       = [int]$origin.Y
                    W       = [int]$node.Width
                    H       = [int]$node.Height
                })
        }
    }
    return $result
}

function Get-SizeList {
    param([string[]]$Specs)
    foreach ($spec in $Specs) {
        if ($spec -match '^\s*(\d+)\s*[xX, ]\s*(\d+)\s*$') {
            [pscustomobject]@{ W = [int]$Matches[1]; H = [int]$Matches[2]; Label = $spec.Trim() }
        }
    }
}

function Get-PageGrids {
    param([System.Windows.Forms.Control]$Root)

    $list = [System.Collections.Generic.List[object]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Root)
    while ($stack.Count -gt 0) {
        $node = $stack.Pop()
        foreach ($child in $node.Controls) {
            if ($child -is [System.Windows.Forms.DataGridView]) {
                $list.Add($child)
                continue
            }
            if ($child.Controls.Count -gt 0) { $stack.Push($child) }
        }
    }
    return $list
}

function Get-GridColumnNeedWidth {
    param($Grid, $Column)

    $headerFont = $Grid.ColumnHeadersDefaultCellStyle.Font
    if (-not $headerFont) { $headerFont = $Grid.Font }
    $need = 0
    if (-not [string]::IsNullOrWhiteSpace($Column.HeaderText)) {
        $need = [System.Windows.Forms.TextRenderer]::MeasureText([string]$Column.HeaderText, $headerFont).Width + 24
    }

    $cellFont = $Grid.DefaultCellStyle.Font
    if (-not $cellFont) { $cellFont = $Grid.Font }
    $maxRows = [math]::Min($Grid.Rows.Count, 400)
    for ($r = 0; $r -lt $maxRows; $r++) {
        $row = $Grid.Rows[$r]
        if ($row.IsNewRow) { continue }
        $val = $row.Cells[$Column.Index].Value
        if ($null -eq $val) { continue }
        $txt = [string]$val
        if ($txt.Length -eq 0) { continue }
        $w = [System.Windows.Forms.TextRenderer]::MeasureText($txt, $cellFont).Width + 18
        if ($w -gt $need) { $need = $w }
    }
    return $need
}

function Add-GridFindings {
    param($Grid, [string]$PageKey, [string]$SizeLabel, $Findings)

    if ($null -eq $Grid) { return }
    try {
        $visibleCols = @($Grid.Columns | Where-Object { $_.Visible })
    } catch { return }
    if ($visibleCols.Count -eq 0) { return }

    $totalNeeded = 0
    foreach ($col in $visibleCols) {
        $need = 0
        try { $need = Get-GridColumnNeedWidth -Grid $Grid -Column $col } catch { continue }
        if ($need -le 0) { continue }
        $totalNeeded += $need
        if ($col.Width -lt ($need - 10)) {
            $Findings.Add([pscustomobject]@{
                    Kind   = 'GRID_COL'
                    Size   = $SizeLabel
                    Page   = $PageKey
                    A      = "列[$($col.HeaderText)] 宽 $($col.Width)"
                    ARect  = ''
                    B      = "需要宽 $need"
                    BRect  = ''
                    Amount = "$($need - $col.Width)px"
                })
        }
    }

    $fillMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    if ($Grid.AutoSizeColumnsMode -ne $fillMode) {
        $clientW = $Grid.ClientSize.Width
        if ($Grid.RowHeadersVisible) { $clientW -= $Grid.RowHeadersWidth }
        if ($clientW -gt 0 -and $totalNeeded -gt ($clientW + 4)) {
            $Findings.Add([pscustomobject]@{
                    Kind   = 'GRID_HSCROLL'
                    Size   = $SizeLabel
                    Page   = $PageKey
                    A      = "表格可见宽 $clientW"
                    ARect  = ''
                    B      = "列合计需要 $totalNeeded"
                    BRect  = ''
                    Amount = "$($totalNeeded - $clientW)px"
                })
        }
    }
}

$findings = [System.Collections.Generic.List[object]]::new()
$pageOrder = @('Dashboard', 'Guided', 'Health', 'Clean', 'Services', 'Startup',
    'Visual', 'Power', 'Disk', 'Network', 'Backup', 'Update', 'About')

foreach ($size in (Get-SizeList $Sizes)) {
    $MainForm.Size = New-Object System.Drawing.Size($size.W, $size.H)
    [System.Windows.Forms.Application]::DoEvents()

    foreach ($pageKey in $pageOrder) {
        if (-not $script:Pages.ContainsKey($pageKey)) { continue }
        $page = $script:Pages[$pageKey]
        if (-not $page) { continue }
        $page.Visible = $true
        $page.BringToFront()
        $page.AutoScrollPosition = New-Object System.Drawing.Point(0, 0)
        [System.Windows.Forms.Application]::DoEvents()

        $rects = Get-AuditRects -Root $page
        $sizeLabel = "$($size.Label)$scaleTag"

        for ($i = 0; $i -lt $rects.Count; $i++) {
            $a = $rects[$i]
            for ($j = $i + 1; $j -lt $rects.Count; $j++) {
                $b = $rects[$j]
                $overW = [math]::Min($a.X + $a.W, $b.X + $b.W) - [math]::Max($a.X, $b.X)
                $overH = [math]::Min($a.Y + $a.H, $b.Y + $b.H) - [math]::Max($a.Y, $b.Y)
                if ($overW -gt 2 -and $overH -gt 2) {
                    $findings.Add([pscustomobject]@{
                            Kind   = 'OVERLAP'
                            Size   = $sizeLabel
                            Page   = $pageKey
                            A      = "$($a.Type):$($a.Text)"
                            ARect  = "$($a.X),$($a.Y) $($a.W)x$($a.H)"
                            B      = "$($b.Type):$($b.Text)"
                            BRect  = "$($b.X),$($b.Y) $($b.W)x$($b.H)"
                            Amount = "$overW x $overH"
                        })
                }
            }
        }

        foreach ($r in $rects) {
            if ($textTypes -notcontains $r.Type) { continue }
            if ([string]::IsNullOrWhiteSpace($r.Text)) { continue }
            $ctl = $r.Control
            $measured = [System.Windows.Forms.TextRenderer]::MeasureText(
                [string]$ctl.Text, $ctl.Font,
                (New-Object System.Drawing.Size(0, 0)),
                [System.Windows.Forms.TextFormatFlags]::NoPadding)
            $needH = $measured.Height + 4
            if ($needH -gt $r.H) {
                $findings.Add([pscustomobject]@{
                        Kind   = 'CLIP_V'
                        Size   = $sizeLabel
                        Page   = $pageKey
                        A      = "$($r.Type):$($r.Text)"
                        ARect  = "$($r.X),$($r.Y) $($r.W)x$($r.H)"
                        B      = "需要高 $needH"
                        BRect  = ''
                        Amount = "$($needH - $r.H)px"
                    })
            }
            if (($textTypes -contains $r.Type) -and -not $ctl.AutoSize -and -not $ctl.AutoEllipsis) {
                $pad = if ($r.Type -eq 'Label') { 4 } else { 16 }
                $needW = $measured.Width + $pad
                if ($needW -gt $r.W) {
                    $findings.Add([pscustomobject]@{
                            Kind   = 'CLIP_H'
                            Size   = $sizeLabel
                            Page   = $pageKey
                            A      = "$($r.Type):$($r.Text)"
                            ARect  = "$($r.X),$($r.Y) $($r.W)x$($r.H)"
                            B      = "需要宽 $needW"
                            BRect  = ''
                            Amount = "$($needW - $r.W)px (pad $pad)"
                        })
                }
            }
        }

        foreach ($grid in (Get-PageGrids -Root $page)) {
            Add-GridFindings -Grid $grid -PageKey $pageKey -SizeLabel $sizeLabel -Findings $findings
        }

        if ($Render -and $OutDir) {
            [System.IO.Directory]::CreateDirectory($OutDir) | Out-Null
            $bmp = New-Object System.Drawing.Bitmap($page.Width, $page.Height)
            try {
                $page.DrawToBitmap($bmp, (New-Object System.Drawing.Rectangle(0, 0, $page.Width, $page.Height)))
                $file = Join-Path $OutDir ("{0}-{1}x{2}-top.png" -f $pageKey, $size.W, $size.H)
                $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
            } finally { $bmp.Dispose() }
        }
    }
}

foreach ($key in $pageOrder) {
    if ($script:Pages.ContainsKey($key)) { $script:Pages[$key].Visible = ($key -eq 'Dashboard') }
}

$Total = $findings.Count
"PAGES=$($pageOrder.Count) SIZES=$($Sizes -join ';') FINDINGS=$Total"

if ($Total -gt 0) {
    $grouped = $findings | Group-Object Kind, Page | Sort-Object Name
    foreach ($g in $grouped) {
        "[{0}] {1} 条" -f $g.Name, $g.Count
    }
    ""
    $findings | Select-Object -First $MaxPrint |
        ForEach-Object {
            "{0} {1} {2} | {3} @{4} <-> {5} @{6} ({7})" -f `
                $_.Kind, $_.Size, $_.Page, $_.A, $_.ARect, $_.B, $_.BRect, $_.Amount
        }
    exit 1
}

"CLEAN"
exit 0
