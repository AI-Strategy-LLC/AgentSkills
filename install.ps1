<#
.SYNOPSIS
    Native Windows installer for AgentSkills (multi-CLI AI skills + agents).

.DESCRIPTION
    AgentSkills is a bash-based installer at heart. On Windows we use Git Bash
    (shipped with Git for Windows) to run install.sh — it provides bash plus
    the standard POSIX tools (curl, tar, awk, sed) the installer needs, and
    handles the Windows-path translation transparently.

    This script:
      1. Locates Git Bash. If missing, offers to install Git for Windows
         via winget (preferred) or Chocolatey, with a manual download link
         as the last-resort fallback.
      2. Forwards the user's arguments to install.sh — either the local
         install.sh (when run from a clone) or a freshly-downloaded copy
         from the configured GitHub repo.

.PARAMETER For
    Comma-separated list of CLIs to install for. Any of:
    claude, opencode, kilo, codex, gemini, pi, cursor.
    If omitted, the bash installer prompts in TTY mode (or errors in non-TTY).

.PARAMETER Ref
    Git ref (branch, tag, or SHA) to install from. Default: main.

.PARAMETER Repo
    Source GitHub repo. Default: AI-Strategy-LLC/AgentSkills.

.PARAMETER Dest
    Override install root. When set, each CLI installs under <Dest>/<cli>/.

.PARAMETER From
    Install from a local checkout instead of fetching. Useful for development
    and smoke tests. The checkout must contain skills/global-scope/ and
    agents/base/global-scope/ at its root.

.PARAMETER List
    Print what would be installed; write nothing.

.PARAMETER Uninstall
    Remove everything this script previously installed. Combine with -For
    to restrict to specific CLIs.

.PARAMETER KeepCache
    After install, move the extracted source to <KeepCache>.

.PARAMETER Yes
    Do not prompt; assume yes.

.PARAMETER SkipGitInstall
    If Git Bash is missing, fail rather than offering to install. Useful in
    CI or for scripted setups that handle git provisioning externally.

.EXAMPLE
    PS> ./install.ps1 -For claude

.EXAMPLE
    PS> ./install.ps1 -For claude,cursor -Ref v1.0.0

.EXAMPLE
    # One-liner: download to temp and run with parameters.
    # The first line bypasses execution policy for THIS session only — needed
    # to run a .ps1 fetched at runtime on default Windows ExecutionPolicy.
    PS> Set-ExecutionPolicy Bypass -Scope Process -Force
    PS> $u = 'https://raw.githubusercontent.com/AI-Strategy-LLC/AgentSkills/main/install.ps1'
    PS> $f = "$env:TEMP\agentskills-install.ps1"
    PS> iwr -useb $u -OutFile $f; & $f -For claude

.LINK
    https://github.com/AI-Strategy-LLC/AgentSkills
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
# Helpers
# ---------------------------------------------------------------------------

function Write-Info($msg)  { Write-Host "install.ps1: $msg" -ForegroundColor Cyan }
function Write-Warn2($msg) { Write-Host "install.ps1: $msg" -ForegroundColor Yellow }
function Write-Err2($msg)  { Write-Host "install.ps1: $msg" -ForegroundColor Red }

function Find-Bash {
    # Look for bash.exe in PATH first, then known Git for Windows install paths.
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

    # Prefer winget (built into Win10 1809+/Win11), fall back to Chocolatey.
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

function Get-RepoRoot {
    # If running from a clone, return the repo root. Otherwise return $null.
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { return $null }
    $scriptDir = Split-Path -Parent $scriptPath
    if (Test-Path -LiteralPath (Join-Path $scriptDir 'install.sh')) {
        return $scriptDir
    }
    return $null
}

function Convert-ToBashPath([string]$winPath) {
    # Git Bash typically auto-converts Windows paths, but be explicit:
    # C:\Users\foo  →  /c/Users/foo
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
# Run install.sh — local copy if we're in a clone, otherwise fetch
# ---------------------------------------------------------------------------

$repoRoot = Get-RepoRoot
if ($repoRoot) {
    $installSh = Join-Path $repoRoot 'install.sh'
    Write-Info "Running local: $installSh"
    & $bash $installSh @bashArgs
    $code = $LASTEXITCODE
} else {
    $url = "https://raw.githubusercontent.com/$Repo/$Ref/install.sh"
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
