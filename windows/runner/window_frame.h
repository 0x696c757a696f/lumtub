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

 private:
  // A rectangle in logical pixels, from the client area's top left.
  struct Box {
    double left = 0, top = 0, right = 0, bottom = 0;
  };

  void HandleCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Send(const char* method, flutter::EncodableValue argument);
  void SetCustom(bool on);
  bool Active() const;
  LRESULT HitTest(LPARAM lparam);
  void SetButton(int state);
  void ReportMaximized(bool maximized);
  void ReportActive(bool active);

  HWND window_;
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
};

#endif  // RUNNER_WINDOW_FRAME_H_
