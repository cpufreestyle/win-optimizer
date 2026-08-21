<#
.SYNOPSIS
    WebUI 视觉效果优化 — 列出/应用，返回 JSON
.DESCRIPTION
    -Action list : 列出可选模式（最佳性能/平衡/自定义）及当前设置
    -Action apply: 应用指定模式（value=1 最佳性能 / 2 平衡 / 3 自定义）
#>
param(
    [ValidateSet("list", "apply")]$Action = "list",
    [int]$Value = 1
)

function Out-Json {
    param($obj)
    $obj | ConvertTo-Json -Depth 4 -Compress
}

$ErrorActionPreference = "Stop"

$modes = @(
    @{Value=1; Title="最佳性能"; Desc="关闭所有动画和特效，仅保留字体平滑。适合老旧电脑，最大化响应速度。"; Safe=$true}
    @{Value=2; Title="平衡模式"; Desc="关闭大部分动画，保留基本效果。适合日常使用。"; Safe=$true}
    @{Value=3; Title="自定义";   Desc="逐项选择要关闭的效果，精细控制。"; Safe=$false}
)

# 读取当前 VisualFXSetting（0=让Windows选择/1=最佳外观/2=自定义平衡/3=自定义）
function Get-CurrentMode {
    try {
        $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (Test-Path $k) {
            $v = (Get-ItemProperty -Path $k -ErrorAction SilentlyContinue).VisualFXSetting
            return [int]$v
        }
    } catch {}
    return $null
}

try {
    if ($Action -eq "list") {
        $cur = Get-CurrentMode
        $list = @()
        foreach ($m in $modes) {
            $list += [PSCustomObject]@{
                value = $m.Value
                title = $m.Title
                desc  = $m.Desc
                safe  = $m.Safe
            }
        }
        Out-Json ([PSCustomObject]@{
            ok = $true
            modes = $list
            current = $cur
        })
    }
    elseif ($Action -eq "apply") {
        $target = $modes | Where-Object { $_.Value -eq $Value }
        if (-not $target) { Out-Json ([PSCustomObject]@{ ok=$false; error="无效模式: $Value" }); exit }

        $visualKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        if (-not (Test-Path $visualKey)) { New-Item -Path $visualKey -Force | Out-Null }
        # 始终用自定义模式承载我们的细项设置
        Set-ItemProperty -Path $visualKey -Name "VisualFXSetting" -Value 3 -Type DWord

        $perfKey = "HKCU:\Control Panel\Desktop"
        $advKey  = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        $dwmKey  = "HKCU:\Software\Microsoft\Windows\DWM"

        $msg = ""
        if ($Value -eq 1) {
            # 最佳性能
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "0" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "0" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $advKey -Name "ListviewAlphaSelect" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $msg = "最佳性能"
        }
        elseif ($Value -eq 2) {
            # 平衡
            Set-ItemProperty -Path $perfKey -Name "DragFullWindows" -Value "1" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "FontSmoothing" -Value "2" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $perfKey -Name "MenuShowDelay" -Value "100" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            Set-ItemProperty -Path $dwmKey -Name "EnableAeroPeek" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $msg = "平衡模式"
        }
        else {
            # 自定义：仅关任务栏动画
            Set-ItemProperty -Path $advKey -Name "TaskbarAnimations" -Value 0 -Type DWord -ErrorAction SilentlyContinue
            $msg = "自定义"
        }

        # 重启资源管理器使生效
        try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue; Start-Sleep 1; Start-Process explorer } catch {}

        Out-Json ([PSCustomObject]@{ ok = $true; applied = $msg; value = $Value })
    }
} catch {
    Out-Json ([PSCustomObject]@{ ok = $false; error = $_.Exception.Message })
}
