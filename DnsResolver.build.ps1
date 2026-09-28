#! /usr/bin/pwsh
#Requires -Version 7.4 -Module InvokeBuild
param(
    [string]$Configuration = 'Release',
    [switch]$SkipHelp,
    [switch]$SkipTests
)

Write-Host "$($PSBoundParameters.GetEnumerator())" -ForegroundColor Cyan

$modulename = [System.IO.Path]::GetFileName($PSCommandPath) -replace '\.build\.ps1$'
# $modulename = 'PSTextMate'

$script:folders = @{
    ModuleName       = $modulename
    ProjectRoot      = $PSScriptRoot
    OutputPath       = Join-Path $PSScriptRoot 'output'
    ModuleSourcePath = Join-Path $PSScriptRoot 'module'
    DocsPath         = Join-Path $PSScriptRoot 'docs' 'en-US'
    TestPath         = Join-Path $PSScriptRoot 'tests'
    CsprojPath       = Join-Path $PSScriptRoot 'src' 'DnsResolver' 'DnsResolver.csproj'
}

task Clean {
    if (Test-Path $folders.OutputPath) {
        Remove-Item -Path $folders.OutputPath -Recurse -Force -ErrorAction 'Ignore'
    }
    New-Item -Path $folders.OutputPath -ItemType Directory -Force | Out-Null
}


task Build {
    if (-not (Test-Path $folders.CsprojPath)) {
        Write-Warning 'C# project not found, skipping Build'
        return
    }

    $ModuleFile = Get-Module (Join-Path $script:folders.ProjectRoot 'Module' "$($script:folders.ModuleName).psd1") -ListAvailable
    [xml]$csproj = Get-Content -Path $folders.CsprojPath -Raw
    $frameworks = $csproj.
    SelectNodes('//TargetFramework | //TargetFrameworks').
    '#text'.
    Split(';', [StringSplitOptions]::RemoveEmptyEntries)

    $dotnetArgs = @(
        'publish'
        $folders.CsprojPath
        '--configuration', $Configuration
        '--nologo'
        '--verbosity', 'minimal'
        ('-p:Version={0}' -f $ModuleFile.Version.ToString())
    )

    foreach ($fwork in $frameworks) {
        exec { dotnet @dotnetArgs --framework $fwork --output $folders.OutputPath }
    }
}

task ModuleFiles {
    if (Test-Path $folders.ModuleSourcePath) {
        Get-ChildItem -Path $folders.ModuleSourcePath -File | Copy-Item -Destination $folders.OutputPath -Force
    }
    else {
        Write-Warning "Module directory not found at: $($folders.ModuleSourcePath)"
    }
}

task GenerateHelp -if (-not $SkipHelp) {
    if (-not (Test-Path $folders.DocsPath)) {
        Write-Warning "Documentation path not found at: $($folders.DocsPath)"
        return
    }
    if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.PlatyPS)) {
        Write-Host '    Installing Microsoft.PowerShell.PlatyPS...' -ForegroundColor Yellow
        Install-Module -Name Microsoft.PowerShell.PlatyPS -Scope CurrentUser -Force -AllowClobber
    }

    Import-Module Microsoft.PowerShell.PlatyPS -ErrorAction Stop

    $modulePath = Join-Path $folders.OutputPath ($folders.ModuleName + '.psd1')
    if (-not (Test-Path $modulePath)) {
        Write-Warning "Module manifest not found at: $modulePath. Skipping help generation."
        return
    }

    Import-Module $modulePath -Force

    $helpOutputPath = Join-Path $folders.OutputPath 'en-US'
    New-Item -Path $helpOutputPath -ItemType Directory -Force | Out-Null

    $allCommandHelp = Get-ChildItem -Path $folders.DocsPath -Filter '*.md' -Recurse -File |
        Where-Object { $_.Name -ne "$($folders.ModuleName).md" } |
        Import-MarkdownCommandHelp
    if ($allCommandHelp.Count -gt 0) {
        $tempOutputPath = Join-Path $helpOutputPath 'temp'
        Export-MamlCommandHelp -CommandHelp $allCommandHelp -OutputFolder $tempOutputPath -Force | Out-Null
        $generatedFile = Get-ChildItem -Path $tempOutputPath -Filter '*.xml' -Recurse -File | Select-Object -First 1
        if ($generatedFile) {
            Move-Item -Path $generatedFile.FullName -Destination $helpOutputPath -Force
        }
        Remove-Item -Path $tempOutputPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

task Test -if (-not $SkipTests) {
    if (-not (Test-Path $folders.TestPath)) {
        Write-Warning "Test directory not found at: $($folders.TestPath)"
        return
    }

    Import-Module Pester -MinimumVersion 6.0.0 -ErrorAction Stop
    Import-Module (Join-Path $folders.OutputPath ($folders.ModuleName + '.psd1')) -ErrorAction Stop

    $pesterConfig = New-PesterConfiguration
    # $pesterConfig.Output.Verbosity = 'Detailed'
    $pesterConfig.Run.Path = $folders.TestPath
    $pesterConfig.Run.Throw = $true
    $pesterConfig.Debug.WriteDebugMessages = $false
    Invoke-Pester -Configuration $pesterConfig
}

# task DotNetTest -if (-not $SkipTests) {
#     $testProject = Join-Path $PSScriptRoot 'tests' 'DnsResolver.Tests' 'DnsResolver.Tests.csproj'
#     if (-not (Test-Path $testProject)) {
#         Write-Warning "Test project not found at: $testProject"
#         return
#     }
#     exec {
#         dotnet test $testProject --configuration $Configuration --nologo
#     }
# }

task CleanAfter {
    if ($script:folders.OutputPath -and (Test-Path $script:folders.OutputPath)) {
        Get-ChildItem $script:folders.OutputPath -File -Recurse | Where-Object { $_.Extension -in '.pdb', '.json' } | Remove-Item -Force -ErrorAction Ignore
    }
}


task All -Jobs Clean, Build, ModuleFiles, GenerateHelp, CleanAfter, Test
task BuildAndTest -Jobs Clean, Build, ModuleFiles, CleanAfter, Test
