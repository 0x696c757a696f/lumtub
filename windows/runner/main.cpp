#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Open centred on the primary monitor's work area, in logical pixels.
  RECT work_area{};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const double scale_factor =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromPoint(POINT{0, 0}, MONITOR_DEFAULTTOPRIMARY)) / 96.0;
  const int work_width = static_cast<int>((work_area.right - work_area.left) / scale_factor);
  const int work_height = static_cast<int>((work_area.bottom - work_area.top) / scale_factor);
  const int width = std::min(1280, std::max(work_width - 40, 640));
  const int height = std::min(800, std::max(work_height - 40, 480));
  const int left = static_cast<int>(work_area.left / scale_factor) + std::max((work_width - width) / 2, 0);
  const int top = static_cast<int>(work_area.top / scale_factor) + std::max((work_height - height) / 2, 0);
  Win32Window::Point origin(static_cast<unsigned int>(left), static_cast<unsigned int>(top));
  Win32Window::Size size(static_cast<unsigned int>(width), static_cast<unsigned int>(height));
  if (!window.Create(L"YTPlus", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
