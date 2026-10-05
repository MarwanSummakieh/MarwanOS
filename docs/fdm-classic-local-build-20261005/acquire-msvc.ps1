param([string[]]$PackageIds)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskCatalog = Get-Content -Raw 'C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances\8e9c3282\catalog.json' | ConvertFrom-Json
$taskDest = Join-Path $PSScriptRoot 'toolchain'
foreach ($taskPackageId in $PackageIds) {
    $taskPackages = @($taskCatalog.packages | Where-Object { $_.id -eq $taskPackageId -and ($_.language -eq 'en-US' -or $_.language -eq $null) })
    if ($taskPackages.Count -ne 1) { throw "Expected one package for $taskPackageId" }
    foreach ($taskPayload in $taskPackages[0].payloads) {
        $taskFile = Join-Path $PSScriptRoot "packages/$($taskPayload.fileName)"
        if (-not (Test-Path $taskFile)) {
            & curl.exe -fL --retry 2 --silent --show-error -o $taskFile $taskPayload.url
            if ($LASTEXITCODE -ne 0) { throw "Download failed: $taskPackageId" }
        }
        if ((Get-FileHash $taskFile -Algorithm SHA256).Hash.ToLower() -ne $taskPayload.sha256) { throw 'Checksum mismatch' }
        $taskZip = [System.IO.Compression.ZipFile]::OpenRead($taskFile)
        try {
            foreach ($taskEntry in $taskZip.Entries) {
                if (-not $taskEntry.FullName.StartsWith('Contents/') -or -not $taskEntry.Name) { continue }
                $taskTarget = [System.IO.Path]::GetFullPath((Join-Path $taskDest $taskEntry.FullName.Substring(9)))
                if (-not $taskTarget.StartsWith($taskDest + '\')) { throw 'Invalid package path' }
                New-Item -ItemType Directory -Force ([System.IO.Path]::GetDirectoryName($taskTarget)) | Out-Null
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($taskEntry,$taskTarget,$true)
            }
        } finally { $taskZip.Dispose() }
        Write-Output "Verified and extracted $taskPackageId"
    }
}
