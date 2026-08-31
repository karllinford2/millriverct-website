<#
  Full backup of the Mill River website project.
  Creates a timestamped snapshot containing:
    - site.bundle   : a complete, self-contained git bundle (full history, all branches/tags).
                       Restorable with: git clone site.bundle restored-site
    - site-files.zip: a plain zip of the current working tree (no .git), for quick browsing
                       without needing git at all.
    - cloudflare\   : DNS zone exports + Access app/policy config for millriverct.com and
                       millriverestuary.com, via a read-only Cloudflare API token stored in the
                       CLOUDFLARE_API_TOKEN user environment variable. Skipped (with a warning,
                       not a failure) if that variable isn't set.
    - manifest.txt  : commit hash, branch, remotes, and timestamp for this snapshot.

  Safe to run on demand or on a schedule. Never deletes anything from the working repo.
#>

$ErrorActionPreference = "Stop"

$RepoRoot   = Split-Path -Parent $PSScriptRoot
$Timestamp  = Get-Date -Format "yyyy-MM-dd_HHmm"
$BackupRoot = Join-Path $RepoRoot "backups"
$SnapDir    = Join-Path $BackupRoot $Timestamp
$LogFile    = Join-Path $BackupRoot "backup.log"

New-Item -ItemType Directory -Force -Path $SnapDir | Out-Null

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg
    Write-Output $line
    Add-Content -Path $LogFile -Value $line
}

Log "=== Backup started: $Timestamp ==="

try {
    Push-Location $RepoRoot

    # 1) Full git bundle (complete history, all branches/tags) — no network required.
    $BundlePath = Join-Path $SnapDir "site.bundle"
    git bundle create $BundlePath --all
    Log "Created git bundle: $BundlePath"

    # 2) Plain zip of the current working tree, excluding .git and backups themselves.
    $ZipPath = Join-Path $SnapDir "site-files.zip"
    $Items = Get-ChildItem -Path $RepoRoot -Force |
        Where-Object { $_.Name -notin @(".git", "backups") }
    Compress-Archive -Path $Items.FullName -DestinationPath $ZipPath -Force
    Log "Created working-tree zip: $ZipPath"

    # 3) Manifest with commit/branch/remote info.
    $CommitHash = git rev-parse HEAD
    $Branch     = git rev-parse --abbrev-ref HEAD
    $Remotes    = git remote -v | Out-String
    $Manifest = @"
Mill River website backup
Snapshot:   $Timestamp
Commit:     $CommitHash
Branch:     $Branch
Remotes:
$Remotes
Restore (full history):
  git clone "$BundlePath" restored-site

Restore (just the files, no history):
  Expand-Archive "$ZipPath" -DestinationPath restored-site-files
"@
    Set-Content -Path (Join-Path $SnapDir "manifest.txt") -Value $Manifest
    Log "Wrote manifest.txt"

    # 4) Cloudflare config export (DNS zone files + Access apps/policies) — optional, read-only.
    #    Requires CLOUDFLARE_API_TOKEN (a token scoped to Zone:DNS:Read + Account:Access:Apps and
    #    Policies:Read for millriverct.com and millriverestuary.com only).
    $CfToken = [Environment]::GetEnvironmentVariable("CLOUDFLARE_API_TOKEN", "User")
    if ([string]::IsNullOrWhiteSpace($CfToken)) {
        Log "Skipping Cloudflare config export: CLOUDFLARE_API_TOKEN not set."
    }
    else {
        try {
            $CfDir = Join-Path $SnapDir "cloudflare"
            New-Item -ItemType Directory -Force -Path $CfDir | Out-Null
            $Headers = @{ Authorization = "Bearer $CfToken" }

            # Resolve zone IDs for our two domains.
            $ZonesResp = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones" -Headers $Headers -Method Get
            $TargetZones = $ZonesResp.result | Where-Object { $_.name -in @("millriverct.com", "millriverestuary.com") }

            foreach ($zone in $TargetZones) {
                $ExportUri = "https://api.cloudflare.com/client/v4/zones/$($zone.id)/dns_records/export"
                $ZoneFile  = Invoke-RestMethod -Uri $ExportUri -Headers $Headers -Method Get
                $OutPath   = Join-Path $CfDir "dns-$($zone.name).txt"
                Set-Content -Path $OutPath -Value $ZoneFile
                Log "Exported DNS zone file: $OutPath"
            }

            # Access apps + their policies, for the account these zones belong to.
            if ($TargetZones.Count -gt 0) {
                $AccountId = $TargetZones[0].account.id
                $AppsResp  = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/access/apps" -Headers $Headers -Method Get
                $AccessExport = @()
                foreach ($app in $AppsResp.result) {
                    $PoliciesResp = Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/accounts/$AccountId/access/apps/$($app.id)/policies" -Headers $Headers -Method Get
                    $AccessExport += [PSCustomObject]@{
                        application = $app
                        policies    = $PoliciesResp.result
                    }
                }
                $AccessPath = Join-Path $CfDir "access-config.json"
                $AccessExport | ConvertTo-Json -Depth 10 | Set-Content -Path $AccessPath
                Log "Exported Access apps/policies: $AccessPath"
            }
        }
        catch {
            Log "WARNING: Cloudflare config export failed (rest of backup still succeeded): $($_.Exception.Message)"
        }
    }

    # 5) Retention: keep the most recent 30 snapshots, delete older ones.
    $AllSnaps = Get-ChildItem -Path $BackupRoot -Directory |
        Sort-Object Name -Descending
    if ($AllSnaps.Count -gt 30) {
        $ToRemove = $AllSnaps | Select-Object -Skip 30
        foreach ($old in $ToRemove) {
            Remove-Item -Recurse -Force $old.FullName
            Log "Pruned old snapshot: $($old.Name)"
        }
    }

    Log "=== Backup completed successfully: $SnapDir ==="
}
catch {
    Log "!!! Backup FAILED: $($_.Exception.Message)"
    throw
}
finally {
    Pop-Location
}
