<#
.SYNOPSIS
    Native Windows installer for the ATO Agent Collection (NIST 800-53 evidence
    collection skills + agents).

.DESCRIPTION
    The ATO collection is a self-contained subset of AgentSkills under ato/.
    This script is the Windows entry point: it locates Git Bash (offering to
    install Git for Windows if missing) and forwards arguments to the
    bundled ato/install.sh.

    The ato/ folder is independently shareable — copy it onto a shared drive
    (or a separate repo, internal share, archive) and `install.ps1` works
    the same way.

.PARAMETER For
    Comma-separated list of CLIs. Any of:
    claude, opencode, kilo, codex, gemini, pi, cursor.

.PARAMETER Ref
    Git ref to install when fetching remotely. Default: main.

.PARAMETER Repo
    Source GitHub repo (must contain ato/). Default: AI-Strategy-LLC/AgentSkills.

.PARAMETER Dest
    Override install root. When set, each CLI installs under <Dest>/<cli>/.

.PARAMETER From
    Local checkout path. May be either the AgentSkills repo root (we'll
    auto-detect ato/ inside it) or the ato/ folder itself.

.PARAMETER List
    Print what would be installed; write nothing.

.PARAMETER Uninstall
    Remove everything previously installed by this script. Combine with
    -For to restrict to specific CLIs.

.PARAMETER KeepCache
    After install, move the extracted source to <KeepCache>.

.PARAMETER Yes
    Do not prompt; assume yes.

.PARAMETER SkipGitInstall
    If Git Bash is missing, fail rather than offering to install.

.EXAMPLE
    PS> ./install.ps1 -For claude

.EXAMPLE
    PS> ./install.ps1 -For claude,cursor -List

.EXAMPLE
    # One-liner: download to temp and run with parameters.
    # The first line bypasses execution policy for THIS session only — needed
    # to run a .ps1 fetched at runtime on default Windows ExecutionPolicy.
    PS> Set-ExecutionPolicy Bypass -Scope Process -Force
    PS> $u = 'https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/ato/install.ps1'
    PS> $f = "$env:TEMP\ato-install.ps1"
    PS> iwr -useb $u -OutFile $f; & $f -For claude

.LINK
    https://github.com/AI-Strategy-LLC/AgentSkills (see ato/README.md)
#>

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$For,
    [string]$Ref = "main",
    [string]$Repo = "AI-Strategy-LLC/AgentSkills",
    [string]$Dest,
    [string]$From,
    [string]$KeepCache,
    [switch]$List,
    [switch]$Uninstall,
    [switch]$Yes,
    [switch]$SkipGitInstall
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers (kept identical to install.ps1 so the two scripts stay in lockstep)
# ---------------------------------------------------------------------------

function Write-Info($msg)  { Write-Host "ato/install.ps1: $msg" -ForegroundColor Cyan }
function Write-Warn2($msg) { Write-Host "ato/install.ps1: $msg" -ForegroundColor Yellow }
function Write-Err2($msg)  { Write-Host "ato/install.ps1: $msg" -ForegroundColor Red }

function Find-Bash {
    $cmd = Get-Command bash.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Install-GitForWindows {
    [CmdletBinding()]
    param([switch]$AssumeYes)

    Write-Info 'Git for Windows is required (provides Git Bash, curl, tar).'

    if (-not $AssumeYes) {
        $ans = Read-Host 'Install Git for Windows now? [y/N]'
        if ($ans -notmatch '^(y|Y|yes|YES)$') {
            Write-Warn2 'Aborted. Install Git for Windows from https://git-scm.com/download/win and re-run.'
            return $false
        }
    }

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info 'Installing via winget...'
        $wingetArgs = @(
            'install', '--id', 'Git.Git', '-e',
            '--source', 'winget',
            '--accept-source-agreements',
            '--accept-package-agreements'
        )
        $proc = Start-Process -FilePath 'winget' -ArgumentList $wingetArgs -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) { return $true }
        Write-Warn2 "winget install exited with $($proc.ExitCode); trying Chocolatey..."
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-Info 'Installing via Chocolatey...'
        $proc = Start-Process -FilePath 'choco' -ArgumentList @('install', 'git', '-y') -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) { return $true }
        Write-Warn2 "choco install exited with $($proc.ExitCode)."
    }

    Write-Err2 'Neither winget nor Chocolatey is available, or both failed.'
    Write-Err2 'Please install Git for Windows manually from:'
    Write-Err2 '    https://git-scm.com/download/win'
    Write-Err2 'Then open a NEW PowerShell window and re-run this script.'
    return $false
}

function Get-AtoRoot {
    # If running from a clone (or the ato/ folder directly), return the path
    # to the ato/install.sh we should run. Otherwise return $null.
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { return $null }
    $scriptDir = Split-Path -Parent $scriptPath
    $local = Join-Path $scriptDir 'install.sh'
    if (Test-Path -LiteralPath $local) { return $local }
    return $null
}

function Convert-ToBashPath([string]$winPath) {
    if ([string]::IsNullOrEmpty($winPath)) { return $winPath }
    if ($winPath -match '^([A-Za-z]):[\\/](.*)$') {
        $drive = $matches[1].ToLower()
        $rest  = $matches[2] -replace '\\', '/'
        return "/$drive/$rest"
    }
    return ($winPath -replace '\\', '/')
}

# ---------------------------------------------------------------------------
# Build bash arg list
# ---------------------------------------------------------------------------

$bashArgs = @()
if ($For)       { $bashArgs += @('--for', $For) }
if ($Ref)       { $bashArgs += @('--ref', $Ref) }
if ($Repo)      { $bashArgs += @('--repo', $Repo) }
if ($Dest)      { $bashArgs += @('--dest', (Convert-ToBashPath $Dest)) }
if ($From)      { $bashArgs += @('--from', (Convert-ToBashPath $From)) }
if ($KeepCache) { $bashArgs += @('--keep-cache', (Convert-ToBashPath $KeepCache)) }
if ($List)      { $bashArgs += '--list' }
if ($Uninstall) { $bashArgs += '--uninstall' }
if ($Yes)       { $bashArgs += '--yes' }

# ---------------------------------------------------------------------------
# Locate or install Git Bash
# ---------------------------------------------------------------------------

$bash = Find-Bash
if (-not $bash) {
    if ($SkipGitInstall) {
        Write-Err2 'Git Bash not found and -SkipGitInstall set; aborting.'
        exit 2
    }
    if (-not (Install-GitForWindows -AssumeYes:$Yes)) { exit 1 }
    $bash = Find-Bash
    if (-not $bash) {
        Write-Err2 'Git Bash still not found after install. Open a new PowerShell window and re-run.'
        exit 1
    }
}
Write-Info "Using bash at: $bash"

# ---------------------------------------------------------------------------
# Run ato/install.sh — local copy if alongside this script, otherwise fetch
# ---------------------------------------------------------------------------

$localSh = Get-AtoRoot
if ($localSh) {
    Write-Info "Running local: $localSh"
    & $bash $localSh @bashArgs
    $code = $LASTEXITCODE
} else {
    $url = "https://raw.githubusercontent.com/$Repo/$Ref/ato/install.sh"
    Write-Info "Fetching: $url"
    $tmp = New-TemporaryFile
    $tmpSh = "$($tmp.FullName).sh"
    Move-Item -LiteralPath $tmp.FullName -Destination $tmpSh
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmpSh
        & $bash $tmpSh @bashArgs
        $code = $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $tmpSh -Force -ErrorAction SilentlyContinue
    }
}

exit $code
