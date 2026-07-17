<#
.SYNOPSIS
    Common module - dot-sourced by each optimization script.
.DESCRIPTION
    Provides shared banner display and config-loading helpers so the
    individual scripts do not duplicate this code.
    Usage (at the top of each script, after the header comment block):
        . "$PSScriptRoot\Common.ps1"
#>

function Show-ModuleBanner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Foreground = "Cyan"
    )
    $sep = "============================================"
    Write-Host ""
    Write-Host $sep -ForegroundColor $Foreground
    Write-Host ("          " + $Title) -ForegroundColor $Foreground
    Write-Host $sep -ForegroundColor $Foreground
}

function Show-ModuleFooter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string[]]$Lines = @(),
        [string]$TitleColor = "Green",
        [string]$LineColor = "Gray"
    )
    $sep = "============================================"
    Write-Host ""
    Write-Host $sep -ForegroundColor Cyan
    Write-Host ("  " + $Title) -ForegroundColor $TitleColor
    foreach ($line in $Lines) {
        Write-Host ("  " + $line) -ForegroundColor $LineColor
    }
    Write-Host $sep -ForegroundColor Cyan
}

function Get-OptimizationConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    try {
        $config = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        return $config
    } catch {
        Write-Host "  [ERROR] Cannot read config file: $ConfigPath" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}
