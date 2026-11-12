#ifndef RUNNER_WINDOW_FRAME_H_
#define RUNNER_WINDOW_FRAME_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>
#include <vector>

// The app's own title bar (lib/window_frame.dart, channel
// "lumtub/window_frame"): the system caption is removed, Flutter draws the
// bar, and this answers the hit tests that make it draggable, snappable and
// the maximize button a Windows 11 snap-layout target.
class WindowFrame {
 public:
  WindowFrame(HWND window, flutter::BinaryMessenger* messenger);
  ~WindowFrame();

  // Handles the frame's window messages (before Flutter sees them); returns
  // true, with the result in |result|, when it did.
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result);

  // Flutter's view is a child window covering the whole client area, so
  // the hit tests for the bar reach it, not the frame. Hooked here, it
  // lets the bar's parts through to the frame.
  void AttachView(HWND view);

 private:
  // A rectangle in logical pixels, from the client area's top left.
  struct Box {
    double left = 0, top = 0, right = 0, bottom = 0;
  };

  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Send(const char* method, flutter::EncodableValue argument);
  void SetCustom(bool on);
  // Sizes Flutter's view to the client area, which a frame change alters
  // without a WM_SIZE.
  void FitView();
  // Writes a click the caption took to the app's log, for the first few.
  void TraceCaptionClick(LPARAM lparam);
  void ApplyMargins();
  bool Active() const;
  LRESULT HitTest(LPARAM lparam);
  static LRESULT CALLBACK ViewProc(HWND view, UINT message, WPARAM wparam, LPARAM lparam,
                                   UINT_PTR id, DWORD_PTR data);
  void SetButton(int state);
  void ReportMaximized(bool maximized);
  void ReportActive(bool active);

  HWND window_;
  HWND view_ = nullptr;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  bool custom_ = false;
  double caption_height_ = 0;
  bool has_maximize_ = false;
  Box maximize_;
  std::vector<Box> interactive_;
  int button_state_ = 0;
  bool tracking_ = false;
  bool maximized_ = false;
  bool active_ = true;
  int traces_ = 0;
};

#endif  // RUNNER_WINDOW_FRAME_H_
