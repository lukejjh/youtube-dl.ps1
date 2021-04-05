Write-Host @"
                    _         _                   _ _ 
                   | |       | |                 | | |
  _   _  ___  _   _| |_ _   _| |__   ___ _____ __| | |
 | | | |/ _ \| | | | __| | | | '_ \ / _ \_____/ _' | |
 | |_| | (_) | |_| | |_| |_| | |_) |  __/    | (_| | |
  \__, |\___/ \__,_|\__|\__,_|_.__/ \___|     \__,_|_|
   __/ |                                              
  |___/                                               
                                                      
"@
$Host.UI.RawUI.WindowTitle = "youtube-dl"

# Possible config file paths
$CONFIG_NAME = "config.json"
$ConfigLocations = @(
  (Join-Path $PSScriptRoot $CONFIG_NAME),
  (Join-Path $env:APPDATA "youtube-dl.ps1\${CONFIG_NAME}")
)

# Default config
$DefaultConfig = @{
  "YouTubeDLPath" = "youtube-dl"
  "RandomName" = $false
  "QuitWhenFinished" = $false
  "Sounds" = $false
  "WatchClipboard" = $false
  "AudioExtraction" = $false
  "SaveLocations" = @(
    (Join-Path $env:USERPROFILE "Downloads"),
    (Join-Path $env:USERPROFILE "Desktop"),
    (Join-Path $env:USERPROFILE "Videos\YouTube")
  )
}

# Variables
$Config = @{}
$Processes = @{}
$ClipboardOld = ""

# Menu functions
function PrintHelp {
  Write-Host (@(
    "h  help (this screen)",
    "c  change to custom directory",
    "d  save current settings as default in config file",
    "q  toggle quit after download(s) finished $(GetSettingStateText "QuitWhenFinished")",
    "r  toggle random output file name $(GetSettingStateText "RandomName")",
    "s  toggle sounds $(GetSettingStateText "Sounds")",
    "x  toggle audio extraction mode $(GetSettingStateText "AudioExtraction")",
    "w  watch clipboard"
  ) -join "`r`n")
  Write-Host "`r`n$(GetLocations)`r`n"
}

function ChangeLocation {
  Write-Host "Current directory: $((Get-Location).Path)"
  SetLocationCustom ((Read-Host "New directory") -replace "`"")
}

function SaveDefaults {
  try { $Config | ConvertTo-Json | Out-File $ConfigPath }
  catch { Write-Host "Failed to save config file." -ForegroundColor Red; return }
  Write-Host "Defaults saved to config file." -ForegroundColor Green
}

function ToggleQuitWhenFinished {
  ToggleSetting "QuitWhenFinished" "Quit after download(s) finished is {0}."
}

function ToggleRandomName {
  ToggleSetting "RandomName" "Random output file name is {0}."
}

function ToggleSounds {
  ToggleSetting "Sounds" "Sounds are {0}."
  if ($Config.Sounds) {
    Write-Host "1 beep = download started"
    Write-Host "2 beeps = download(s) finished"
  }
}

function ToggleAudioExtraction {
  ToggleSetting "AudioExtraction" "Audio extraction mode is {0}."
}

function WatchClipboard {
  Write-Host "Watching clipboard..."
  while ($true) {
    $Clipboard = Get-Clipboard
    if ($Clipboard -ne $ClipboardOld) {
      if ($Clipboard -match "https?://") {
        Write-Host "Found URL on clipboard: $Clipboard" -ForegroundColor Green
        DownloadVideo $Clipboard $false
      }
    }
    $ClipboardOld = $Clipboard
    CheckProgress
    Start-Sleep -Milliseconds 100
  }
}

# General functions
function GetRandomName {
  $CHARSET = [char[]]"abcdefghijklmnopqrstuvwxyz0123456789"
  $BaseName = $(
    for($i = 0; $i -le 8; $i++) {
      $CHARSET[(Get-Random $CHARSET.Length)]
    }
  ) -join ""
  $BaseName
}

function GetLocations {
  $(
    for ($i = 0; $i -lt $Config.SaveLocations.Length; $i++) {
      "$($i+1)  $($Config.SaveLocations[$i])"
    }
  ) -join "`r`n"
}

function SetLocation([int]$Index) {
  SetLocationCustom $Config.SaveLocations[$Index-1]
}

function SetLocationCustom([string]$Directory) {
  if ($Directory.Length -eq 0) { $Directory = $false }
  if (Test-Path $Directory -PathType Container) {
    Set-Location "$Directory\"
    $NewPath = (Get-Location).Path
    Write-Host "Current directory: $NewPath`r`n"
    $Host.UI.RawUI.WindowTitle = "youtube-dl - $NewPath"
  } else {
    Write-Host "Invalid directory path. Directory unchanged." -ForegroundColor Red
  }
}

function ToggleSetting([string]$Setting, [string]$OutputFormatString) {
  $Config[$Setting] = !($Config[$Setting])
  Write-Host ($OutputFormatString -f ("off", "on")[$Config[$Setting]]) -ForegroundColor ("Red", "Green")[$Config[$Setting]]
}

function GetSettingStateText([string]$Setting) {
  $ESC = [char]27
  $State = ("off", "on")[$Config[$Setting]]
  $Colour = (90, 32)[$Config[$Setting]]
  
  "$ESC[90m[$ESC[0m$ESC[${Colour}m${State}$ESC[0m$ESC[90m]$ESC[0m"
}

function ResolveDependency([string]$ConfigName, [string]$Executable, [string]$DownloadURL) {
  $ExecutableBaseName = $Executable -replace ".exe$"

  if ($Config[$ConfigName].toLower() -eq $ExecutableBaseName) {
    # e.g. youtube-dl
    $ExecutableHere = Join-Path $PSScriptRoot $Executable
    if (Test-Path ($ExecutableHere)) {
      # Alongside script
      $ExecutablePathResolved = $ExecutableHere
    } elseif (Get-Command $ExecutableBaseName -ErrorAction SilentlyContinue) {
      # In PATH
      $ExecutablePathResolved = $ExecutableBaseName
    } else {
      # No match
      Write-Warning "$ExecutableBaseName not found in script directory or PATH."
      Write-Warning "Update $CONFIG_NAME with its path or press Enter to download it now."
      Pause
      Invoke-WebRequest $DownloadURL -OutFile $ExecutableHere
      Write-Host
      $ExecutablePathResolved = $ExecutableHere
    }
  } elseif (Test-Path $Config[$ConfigName]) {
    # e.g. C:\path\to\youtube-dl.exe and exists
    $ExecutablePathResolved = $Config[$ConfigName]
  } else {
    # e.g. C:\path\to\youtube-dl.exe and doesn't exist
    Write-Warning "`"$($Config[$ConfigName])`" wasn't found."
    Write-Warning "Update $CONFIG_NAME with the correct path or press Enter to download it to that location now."
    Pause
    Invoke-WebRequest $DownloadURL -OutFile $Config[$ConfigName]
    Write-Host
    $ExecutablePathResolved = $Config[$ConfigName]
  }
}

function DownloadVideo([string]$URL, [bool]$Wait) {
  $YouTubeDLArgs = @()
  $YouTubeDLArgs += "`"$URL`""
  if ($Config.AudioExtraction) {
    $YouTubeDLArgs += "--audio-format=mp3", "-x"
  }
  if ($Config.RandomName) {
    $YouTubeDLArgs += "-o", "`"$(GetRandomName).%(ext)s`""
  }

  if ($Config.Sounds) { [System.Console]::Beep(3000, 100) }
  # TODO: Perhaps use PowerShell jobs instead of spawning multiple -Wait:$false processes.
  $p = Start-Process $Config["YouTubeDLPath"] $YouTubeDLArgs -NoNewWindow -PassThru -Wait:$Wait
  $Processes[$p.Id] = $p
}

function CheckProgress {
  if ($Processes.Count -eq 0) {
    return
  }
  $ToRemove = @()
  $Processes.Keys | ForEach-Object {
    if ($Processes[$_].HasExited) {
      $ToRemove += $_
    }
  }
  $ToRemove | ForEach-Object { $Processes.Remove($_) }
  if ($Processes.Count -eq 0) {
    Write-Host "All processes have finished." -ForegroundColor Green
    if ($Config.Sounds) { [System.Console]::Beep(1000, 200); Start-Sleep -Milliseconds 100; [System.Console]::Beep(1000, 200) }
    if ($Config.QuitWhenFinished) {
      Write-Host "Quitting..." -ForegroundColor Green
      Start-Sleep 1
      exit
    }
  }
}

# Look for config file
$Config = $DefaultConfig
foreach ($c in $ConfigLocations) {
  if (Test-Path $c) { $ConfigPath = $c; break }
}
if (!$ConfigPath) {
  $ConfigPath = $ConfigLocations[0]
  Write-Warning "No $CONFIG_NAME present. Creating one with defaults now: `"$ConfigPath`""
  SaveDefaults
} else {
  try {
    $ConfigObject = Get-Content $ConfigPath | ConvertFrom-Json
    $ConfigObject.PSObject.Properties | ForEach-Object { $Config[$_.Name] = $_.Value }
  }
  catch {
    Write-Warning "Error parsing `"$ConfigPath`"."
    Write-Warning "Check for syntax errors or file access problems. Falling back to config defaults."
  }
}

# Resolve dependencies
ResolveDependency "YouTubeDLPath" "youtube-dl.exe" "https://yt-dl.org/downloads/latest/youtube-dl.exe"
#ResolveDependency "FFmpegPath" "ffmpeg.exe" ""

# Initialise
PrintHelp
SetLocation 1

# Main prompt loop
:prompt while ($true) {
  Write-Host "> " -NoNewline -ForegroundColor Yellow
  $PromptInput = (Read-Host) -replace "\s"
  
  # Numeric input (directory selection)
  if ($PromptInput -match "^\d+$") {
    $InputInt = $PromptInput -as [int]
    if ($InputInt -ge 1 -and $InputInt -le $Config.SaveLocations.length) {
      SetLocation($InputInt)
    }
    continue
  }

  # Single character alphabetical input (main menu)
  switch ($PromptInput.ToLower()) {
    "?" { PrintHelp; continue prompt }
    "h" { PrintHelp; continue prompt }
    "c" { ChangeLocation; continue prompt }
    "d" { SaveDefaults; continue prompt }
    "q" { ToggleQuitWhenFinished; continue prompt }
    "r" { ToggleRandomName; continue prompt }
    "s" { ToggleSounds; continue prompt }
    "x" { ToggleAudioExtraction; continue prompt }
    "w" { WatchClipboard; continue prompt }
  }

  # URL input (call youtube-dl)
  if ($PromptInput -imatch "^https?://") {
    DownloadVideo $PromptInput $true
    CheckProgress
  }
}

Pause
