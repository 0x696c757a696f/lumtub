#include "window_placement.h"

#include <cstdio>
#include <string>

// Kept as the raw WINDOWPLACEMENT in %LOCALAPPDATA%\YTPlus\config\window.bin.

namespace {

std::wstring PlacementFile() {
  wchar_t buffer[MAX_PATH * 2];
  const DWORD length = ::GetEnvironmentVariableW(L"LOCALAPPDATA", buffer, MAX_PATH * 2);
  if (length == 0 || length >= MAX_PATH * 2) return L"";
  return std::wstring(buffer, length) + L"\\YTPlus\\config\\window.bin";
}

// media_kit's fullscreen drops the caption and covers the whole monitor.
bool IsFullscreen(HWND window) {
  if (::GetWindowLongPtr(window, GWL_STYLE) & WS_CAPTION) return false;
  RECT rect{};
  MONITORINFO monitor{sizeof(MONITORINFO)};
  if (!::GetWindowRect(window, &rect) ||
      !::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
    return false;
  }
  return ::EqualRect(&rect, &monitor.rcMonitor);
}

}  // namespace

bool RestoreWindowPlacement(HWND window) {
  const std::wstring path = PlacementFile();
  if (path.empty()) return false;
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"rb") != 0 || file == nullptr) return false;
  WINDOWPLACEMENT placement{};
  const size_t read = fread(&placement, 1, sizeof(placement), file);
  fclose(file);
  if (read != sizeof(placement) || placement.length != sizeof(placement)) return false;
  RECT& normal = placement.rcNormalPosition;
  if (normal.right - normal.left < 320 || normal.bottom - normal.top < 240) return false;
  // Skip a place on a monitor that is no longer connected.
  if (::MonitorFromRect(&normal, MONITOR_DEFAULTTONULL) == nullptr) return false;
  const bool maximized = placement.showCmd == SW_SHOWMAXIMIZED;
  placement.showCmd = SW_HIDE;
  placement.flags = 0;
  ::SetWindowPlacement(window, &placement);
  return maximized;
}

void SaveWindowPlacement(HWND window) {
  // Neither fullscreen nor the small picture-in-picture window (set by
  // lib/app_window.dart) is the size to open at next time.
  if (IsFullscreen(window) || ::GetProp(window, L"YTPlusPictureInPicture")) return;
  WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
  if (!::GetWindowPlacement(window, &placement)) return;
  if (placement.showCmd == SW_SHOWMINIMIZED) {
    placement.showCmd = (placement.flags & WPF_RESTORETOMAXIMIZED) ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL;
  }
  const std::wstring path = PlacementFile();
  if (path.empty()) return;
  FILE* file = nullptr;
  if (_wfopen_s(&file, path.c_str(), L"wb") != 0 || file == nullptr) return;
  fwrite(&placement, 1, sizeof(placement), file);
  fclose(file);
}
