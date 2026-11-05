# Starts the built app with LUMTUB_SHOWCASE and takes the pictures it asks
# for (see runShowcase in lib/app/smoke_check.dart) of its window.
#
#   showcase.ps1 <lumtub.exe> <output folder>
param([string]$Exe, [string]$Out)
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$Out = (Resolve-Path $Out).Path

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class ShowcaseWindow {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect rect, int size);
}
'@
[ShowcaseWindow]::SetProcessDPIAware() | Out-Null

$env:LUMTUB_SHOWCASE = $Out
$app = Start-Process -FilePath $Exe -PassThru -RedirectStandardOutput (Join-Path $Out 'stdout.txt') -RedirectStandardError (Join-Path $Out 'stderr.txt')
$clock = [Diagnostics.Stopwatch]::StartNew()
while (-not $app.HasExited -and $clock.Elapsed.TotalSeconds -lt 900) {
  foreach ($want in Get-ChildItem -Path $Out -Filter 'want-*' -File -ErrorAction SilentlyContinue) {
    $name = $want.Name.Substring(5)
    $app.Refresh()
    $window = $app.MainWindowHandle
    if ($window -ne [IntPtr]::Zero) {
      [ShowcaseWindow]::SetForegroundWindow($window) | Out-Null
      Start-Sleep -Milliseconds 300
      $rect = New-Object ShowcaseWindow+Rect
      # DWMWA_EXTENDED_FRAME_BOUNDS: the visible frame, without the shadow.
      [ShowcaseWindow]::DwmGetWindowAttribute($window, 9, [ref]$rect, 16) | Out-Null
      $width = $rect.Right - $rect.Left
      $height = $rect.Bottom - $rect.Top
      if ($width -gt 0 -and $height -gt 0) {
        $bitmap = New-Object Drawing.Bitmap $width, $height
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
Copy-Item (Join-Path $env:LOCALAPPDATA 'Lumtub\logs\lumtub.log') $Out -ErrorAction SilentlyContinue
Get-ChildItem $Out | Format-Table Name, Length
Get-Content (Join-Path $Out 'lumtub.log') -Tail 40 -ErrorAction SilentlyContinue
