# The window glass check (docs/specs/window-glass.md): puts a magenta window
# behind the app, takes the pictures of the screen it asks for (runGlassCheck
# in lib/app/smoke_check.dart) and measures whether the magenta showed
# through (packaging/glass_measure.py).
#
#   glass-check.ps1 <lumtub.exe> <output folder>
param([string]$Exe, [string]$Out)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class GlassWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect rect, int size);
}
'@
[GlassWindow]::SetProcessDPIAware() | Out-Null

# What should show through: a magenta window over the whole screen, in a
# process of its own so it keeps drawing.
$backdrop = Join-Path $Out 'backdrop.ps1'
@'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$form = New-Object Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.WindowState = 'Maximized'
$form.BackColor = [Drawing.Color]::FromArgb(255, 0, 255)
$form.ShowInTaskbar = $false
[Windows.Forms.Application]::Run($form)
'@ | Set-Content -Path $backdrop
$behind = Start-Process -FilePath powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $backdrop -PassThru
Start-Sleep -Seconds 4

$personalize = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction SilentlyContinue
Write-Output "Windows $([Environment]::OSVersion.Version), transparency effects: $($personalize.EnableTransparency)"
$env:LUMTUB_SHOWCASE = $Out
$env:LUMTUB_GLASS_CHECK = '1'
$app = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $Out 'stdout.txt') -RedirectStandardError (Join-Path $Out 'stderr.txt')
$clock = [Diagnostics.Stopwatch]::StartNew()
while (-not $app.HasExited -and $clock.Elapsed.TotalSeconds -lt 300) {
  foreach ($want in Get-ChildItem -Path $Out -Filter 'want-*' -File -ErrorAction SilentlyContinue) {
    $name = $want.Name.Substring(5)
    $app.Refresh()
    $window = $app.MainWindowHandle
    if ($window -ne [IntPtr]::Zero) {
      [GlassWindow]::SetForegroundWindow($window) | Out-Null
      Start-Sleep -Milliseconds 500
      $rect = New-Object GlassWindow+Rect
      # DWMWA_EXTENDED_FRAME_BOUNDS: the visible frame, without the shadow.
      [GlassWindow]::DwmGetWindowAttribute($window, 9, [ref]$rect, 16) | Out-Null
      $width = $rect.Right - $rect.Left
      $height = $rect.Bottom - $rect.Top
      if ($width -gt 0 -and $height -gt 0) {
        # The screen as shown, the desktop window manager's blending and all.
        $bitmap = New-Object Drawing.Bitmap $width, $height, ([Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
        $temp = Join-Path $Out "$name.tmp.png"
        $bitmap.Save($temp, [Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bitmap.Dispose()
        Move-Item -Force $temp (Join-Path $Out "$name.png")
      }
    }
    Remove-Item -Force $want.FullName
  }
  Start-Sleep -Milliseconds 500
}
if (-not $app.HasExited) { Stop-Process -Id $app.Id -Force }
Stop-Process -Id $behind.Id -Force -ErrorAction SilentlyContinue
Remove-Item -Force $backdrop -ErrorAction SilentlyContinue
Copy-Item (Join-Path $env:LOCALAPPDATA 'Lumtub\logs\lumtub.log') $Out -ErrorAction SilentlyContinue
Get-ChildItem $Out | Format-Table Name, Length
Select-String -Path (Join-Path $Out 'lumtub.log') -Pattern 'glass' -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { $_.Line }
python (Join-Path $PSScriptRoot '..\..\packaging\glass_measure.py') $Out
exit $LASTEXITCODE
