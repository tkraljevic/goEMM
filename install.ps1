# goEMM installer for Windows.
#
# The PowerShell twin of install.sh, and it makes the same promise: every
# step fails loudly. The manual instructions this replaces did not.
#
#   - Invoke-WebRequest follows a redirect to a sign-in page and saves the
#     PAGE, cheerfully, as emm.exe. The failure surfaces much later as a
#     program that will not start.
#   - GitHub's asset address answers 200 with the asset's JSON description
#     unless asked for octet-stream — another success status carrying the
#     wrong bytes.
#   - Nothing verified a checksum, and nothing checked the installed file
#     could actually run.
#
# So: the checksum is compared explicitly against the manifest entry for
# the exact asset name, and the binary has to prove itself by running.
#
# Usage:
#   irm <url>/install.ps1 | iex
#   $env:EMM_TOKEN = '...'          while the downloads repo is private
#   $env:EMM_INSTALL_DIR = 'C:\x'   install somewhere else (testing)
#   .\install.ps1 -Force            reinstall over an existing copy

[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Host_    = if ($env:EMM_HOST) { $env:EMM_HOST } else { 'https://api.github.com' }
$Repo     = if ($env:EMM_REPO) { $env:EMM_REPO } else { 'tkraljevic/goEMM' }
# No token by default, on purpose — see install.sh for why.
$Token    = $env:EMM_TOKEN
$Dir      = if ($env:EMM_INSTALL_DIR) { $env:EMM_INSTALL_DIR } else { Join-Path $env:USERPROFILE '.emm' }

function Die($msg) { Write-Host ''; Write-Error $msg -ErrorAction Continue; exit 1 }

function Auth-Headers($accept) {
    $h = @{ 'Accept' = $accept; 'User-Agent' = 'goEMM-installer' }
    if ($Token) { $h['Authorization'] = "Bearer $Token" }
    return $h
}

# --- which build ------------------------------------------------------
$arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { Die "goEMM has no build for $($env:PROCESSOR_ARCHITECTURE). Supported: amd64 and arm64." }
}
$asset = "emm-windows-$arch.exe"
Write-Host "Installing goEMM for windows/$arch into $Dir"

# --- already here? ----------------------------------------------------
$target = Join-Path $Dir 'emm.exe'
if ((Test-Path $target) -and -not $Force) {
    $have = try { & $target version 2>$null } catch { $null }
    Die @"
goEMM is already installed at $target$(if ($have) { " ($have)" }).

To move to the newest version, use its own updater, which keeps a copy of
the one it replaces:

  $target update

To install over it anyway:  .\install.ps1 -Force
"@
}

# --- which version ----------------------------------------------------
try {
    $rel = Invoke-RestMethod -Headers (Auth-Headers 'application/vnd.github+json') `
        -Uri "$Host_/repos/$Repo/releases/latest"
} catch {
    $code = try { $_.Exception.Response.StatusCode.value__ } catch { $null }
    if ($code -eq 401 -or $code -eq 404) {
        Die @"
$Host_ answered $code for the release listing.

While the downloads repository is private, an installer needs a token that
can read it:
  `$env:EMM_TOKEN = '...'

Nothing was installed.
"@
    }
    Die "Could not reach $Host_. Check the network, then try again.`nNothing was installed."
}
$ver = $rel.tag_name
if (-not $ver -or -not $ver.StartsWith('v')) {
    Die "Could not read the latest version from the release listing. Nothing was installed."
}
Write-Host "Newest release: $ver"

# --- download and prove it is what it claims --------------------------
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("emm-install-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    function Get-Asset($name, $out) {
        # By asset id, not by a tidy download URL: on a private repository
        # the browser download address answers 404 even with a valid token.
        $a = $rel.assets | Where-Object { $_.name -eq $name } | Select-Object -First 1
        if (-not $a) {
            Die @"
Release $ver publishes no $name.

That means the release is incomplete, not that anything is wrong here.
Nothing was installed.
"@
        }
        Invoke-WebRequest -Headers (Auth-Headers 'application/octet-stream') `
            -Uri "$Host_/repos/$Repo/releases/assets/$($a.id)" -OutFile $out
        # A release host can answer 200 with something that is not the file.
        $head = [System.IO.File]::ReadAllBytes($out)[0..([Math]::Min(14, (Get-Item $out).Length - 1))]
        $text = ([System.Text.Encoding]::ASCII.GetString($head)).ToLower()
        if ($text -like '*<!doctype html*' -or $text -like '*<html*') {
            Remove-Item $out -Force
            Die @"
That download returned a web page instead of a file.

The token is probably wrong or expired. Set a working one:
  `$env:EMM_TOKEN = '...'
"@
        }
    }

    $binPath  = Join-Path $tmp $asset
    $sumsPath = Join-Path $tmp 'SHA256SUMS.txt'
    Get-Asset $asset  $binPath
    Get-Asset 'SHA256SUMS.txt' $sumsPath

    $want = $null
    foreach ($line in Get-Content $sumsPath) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -eq 2 -and ($parts[1].Trim() -replace '^\*', '') -eq $asset) {
            $want = $parts[0].Trim().ToLower()
        }
    }
    if (-not $want) {
        Die @"
The checksum file does not list $asset.

That means the release is incomplete, not that your download is bad.
Nothing was installed.
"@
    }
    $got = (Get-FileHash -Algorithm SHA256 $binPath).Hash.ToLower()
    if ($want -ne $got) {
        Die @"
The download does not match its published checksum.

  expected  $want
  got       $got

Nothing was installed. Try again; if it repeats, say so — a mismatch that
survives a retry is worth knowing about.
"@
    }
    Write-Host 'Checksum verified.'

    # --- put it in place and make it prove itself ---------------------
    New-Item -ItemType Directory -Force -Path $Dir | Out-Null
    Move-Item -Force $binPath $target
    # Downloaded files carry a zone marker that makes the first run pop a
    # SmartScreen dialog instead of a message. Clearing it here is the same
    # decision the user would make in that dialog, taken before it
    # interrupts them.
    try { Unblock-File -Path $target } catch { }

    $installed = try { & $target version 2>$null } catch { $null }
    if (-not $installed) {
        Die @"
The binary was installed but will not run.

  $target version

failed. The file is in place; nothing else was changed.
"@
    }
    Write-Host "Installed: $installed"

    Write-Host ''
    Write-Host 'Next:'
    Write-Host "  $target demo          see what it does, on a throwaway database"
    Write-Host "  $target setup         connect your AI assistants"
    Write-Host "  $target setup path    so you can type 'emm' from anywhere"
}
finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
