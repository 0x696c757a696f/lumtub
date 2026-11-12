#include "window_frame.h"

#include <commctrl.h>
#include <dwmapi.h>

#include <cmath>

#include <flutter/standard_method_codec.h>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

// Picture in picture (lib/app_window.dart) has no frame to replace.
bool InPictureInPicture(HWND window) {
  return ::GetProp(window, L"LumtubPictureInPicture") != nullptr;
}

double ScaleOf(HWND window) {
  const UINT dpi = ::GetDpiForWindow(window);
  return (dpi == 0 ? 96 : dpi) / 96.0;
}

// The sizing border Windows reserves around a maximized window.
int FrameThickness(HWND window) {
  const UINT dpi = ::GetDpiForWindow(window);
  return ::GetSystemMetricsForDpi(SM_CYFRAME, dpi) + ::GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

double Number(const EncodableValue& value) {
  if (const auto* real = std::get_if<double>(&value)) return *real;
  if (const auto* narrow = std::get_if<int32_t>(&value)) return *narrow;
  if (const auto* wide = std::get_if<int64_t>(&value)) return static_cast<double>(*wide);
  return 0;
}

// left, top, right, bottom
bool ReadBox(const EncodableValue& value, double out[4]) {
  const auto* list = std::get_if<EncodableList>(&value);
  if (!list || list->size() != 4) return false;
  for (int i = 0; i < 4; ++i) out[i] = Number((*list)[i]);
  return true;
}

const EncodableValue* Find(const EncodableValue* arguments, const char* key) {
  const auto* map = arguments ? std::get_if<EncodableMap>(arguments) : nullptr;
  if (!map) return nullptr;
  const auto it = map->find(EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

}  // namespace

WindowFrame::WindowFrame(HWND window, flutter::BinaryMessenger* messenger) : window_(window) {
  channel_ = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "lumtub/window_frame", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) { HandleCall(call, std::move(result)); });
}

WindowFrame::~WindowFrame() {
  channel_->SetMethodCallHandler(nullptr);
  if (view_) ::RemoveWindowSubclass(view_, ViewProc, 1);
}

void WindowFrame::AttachView(HWND view) {
  if (view_) ::RemoveWindowSubclass(view_, ViewProc, 1);
  view_ = view;
  if (view_) ::SetWindowSubclass(view_, ViewProc, 1, reinterpret_cast<DWORD_PTR>(this));
}

LRESULT CALLBACK WindowFrame::ViewProc(HWND view, UINT message, WPARAM wparam, LPARAM lparam,
                                       UINT_PTR id, DWORD_PTR data) {
  auto* frame = reinterpret_cast<WindowFrame*>(data);
  if (message == WM_NCHITTEST && frame->Active() && frame->HitTest(lparam) != HTCLIENT) {
    // Passed on to the frame below, which answers caption, maximize
    // button or top edge for the same point.
    return HTTRANSPARENT;
  }
  if (message == WM_NCDESTROY) {
    ::RemoveWindowSubclass(view, ViewProc, id);
    frame->view_ = nullptr;
  }
  return ::DefSubclassProc(view, message, wparam, lparam);
}

void WindowFrame::Send(const char* method, EncodableValue argument) {
  channel_->InvokeMethod(method, std::make_unique<EncodableValue>(std::move(argument)));
}

void WindowFrame::HandleCall(const flutter::MethodCall<EncodableValue>& call,
                             std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const std::string& method = call.method_name();
  const EncodableValue* args = call.arguments();
  if (method == "setCustom") {
    const auto* on = args ? std::get_if<bool>(args) : nullptr;
    SetCustom(on && *on);
  } else if (method == "minimize") {
    // The shell sees the resulting WM_SIZE, so minimize-to-tray still applies.
    ::ShowWindow(window_, SW_MINIMIZE);
  } else if (method == "toggleMaximize") {
    ::ShowWindow(window_, ::IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
  } else if (method == "close") {
    // What the system close button ends in, so Dart's exit request and
    // close-to-tray still run.
    ::PostMessage(window_, WM_CLOSE, 0, 0);
  } else if (method == "startDrag" || method == "startResize") {
    // Hit-testing moves and sizes the window.
  } else if (method == "setCaption") {
    const EncodableValue* height = Find(args, "height");
    caption_height_ = height ? Number(*height) : 0;
    double box[4];
    const EncodableValue* maximize = Find(args, "maximize");
    has_maximize_ = maximize && ReadBox(*maximize, box);
    if (has_maximize_) maximize_ = {box[0], box[1], box[2], box[3]};
    interactive_.clear();
    const EncodableValue* interactive = Find(args, "interactive");
    if (const auto* list = interactive ? std::get_if<EncodableList>(interactive) : nullptr) {
      for (const auto& item : *list) {
        if (ReadBox(item, box)) interactive_.push_back({box[0], box[1], box[2], box[3]});
      }
    }
  } else if (method == "state") {
    result->Success(EncodableValue(EncodableMap{
        {EncodableValue("maximized"), EncodableValue(::IsZoomed(window_) != FALSE)},
        {EncodableValue("active"), EncodableValue(active_)},
    }));
    return;
  } else {
    result->NotImplemented();
    return;
  }
  result->Success();
}

// The frame is replaced only for the normal window: fullscreen (media_kit
// drops the caption style) and picture in picture already cover everything.
bool WindowFrame::Active() const {
  return custom_ && (::GetWindowLongPtr(window_, GWL_STYLE) & WS_CAPTION) == WS_CAPTION &&
         !InPictureInPicture(window_);
}

void WindowFrame::SetCustom(bool on) {
  custom_ = on;
  ApplyMargins();
  ::SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  FitView();
  if (!on) SetButton(0);
}

void WindowFrame::FitView() {
  if (!view_) return;
  RECT client{};
  if (!::GetClientRect(window_, &client)) return;
  RECT now{};
  ::GetWindowRect(view_, &now);
  ::MapWindowPoints(HWND_DESKTOP, window_, reinterpret_cast<POINT*>(&now), 2);
  if (now.left == 0 && now.top == 0 && now.right == client.right && now.bottom == client.bottom) return;
  ::MoveWindow(view_, 0, 0, client.right, client.bottom, TRUE);
}

void WindowFrame::TraceCaptionClick(LPARAM lparam) {
  if (traces_ >= 20) return;
  ++traces_;
  POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
  ::ScreenToClient(window_, &point);
  RECT view{};
  if (view_) {
    ::GetWindowRect(view_, &view);
    ::MapWindowPoints(HWND_DESKTOP, window_, reinterpret_cast<POINT*>(&view), 2);
  }
  RECT client{};
  ::GetClientRect(window_, &client);
  EncodableList boxes;
  for (const Box& box : interactive_) {
    boxes.push_back(EncodableValue(EncodableList{EncodableValue(box.left), EncodableValue(box.top),
                                                 EncodableValue(box.right), EncodableValue(box.bottom)}));
  }
  Send("captionClick", EncodableValue(EncodableMap{
      {EncodableValue("x"), EncodableValue(static_cast<int32_t>(point.x))},
      {EncodableValue("y"), EncodableValue(static_cast<int32_t>(point.y))},
      {EncodableValue("scale"), EncodableValue(ScaleOf(window_))},
      {EncodableValue("view"), EncodableValue(EncodableList{
          EncodableValue(static_cast<int32_t>(view.left)), EncodableValue(static_cast<int32_t>(view.top)),
          EncodableValue(static_cast<int32_t>(view.right)), EncodableValue(static_cast<int32_t>(view.bottom))})},
      {EncodableValue("client"), EncodableValue(EncodableList{
          EncodableValue(static_cast<int32_t>(client.right)), EncodableValue(static_cast<int32_t>(client.bottom))})},
      {EncodableValue("caption"), EncodableValue(caption_height_)},
      {EncodableValue("boxes"), EncodableValue(boxes)},
      {EncodableValue("zoomed"), EncodableValue(::IsZoomed(window_) != FALSE)},
  }));
}

// One pixel of glass keeps the shadow and, on Windows 11, the rounded
// corners and border.
void WindowFrame::ApplyMargins() {
  const MARGINS margins{0, 0, custom_ ? 1 : 0, 0};
  ::DwmExtendFrameIntoClientArea(window_, &margins);
}

void WindowFrame::SetButton(int state) {
  if (state == button_state_) return;
  button_state_ = state;
  Send("maximizeButton", EncodableValue(state));
}

void WindowFrame::ReportMaximized(bool maximized) {
  if (maximized == maximized_) return;
  maximized_ = maximized;
  Send("maximized", EncodableValue(maximized));
}

void WindowFrame::ReportActive(bool active) {
  if (active == active_) return;
  active_ = active;
  Send("active", EncodableValue(active));
}

LRESULT WindowFrame::HitTest(LPARAM lparam) {
  // The side and bottom borders are still the system's.
  const LRESULT system = ::DefWindowProc(window_, WM_NCHITTEST, 0, lparam);
  const bool zoomed = ::IsZoomed(window_) != FALSE;
  POINT point{static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
  ::ScreenToClient(window_, &point);
  const double scale = ScaleOf(window_);
  const bool top_edge = !zoomed && point.y < std::lround(6 * scale);
  // Only the sizing borders are taken from the system. Its caption, menu
  // and button answers come from the frame it would draw, which is not
  // there: taken while that frame is not yet recalculated, they would
  // cover the menus with the caption.
  switch (system) {
    case HTLEFT:
      return top_edge ? HTTOPLEFT : HTLEFT;
    case HTRIGHT:
      return top_edge ? HTTOPRIGHT : HTRIGHT;
    case HTBOTTOM:
    case HTBOTTOMLEFT:
    case HTBOTTOMRIGHT:
    case HTTOPLEFT:
    case HTTOPRIGHT:
    case HTNOWHERE:
    case HTERROR:
    case HTTRANSPARENT:
      return system;
    case HTTOP:
      if (!zoomed) return HTTOP;
      break;
  }
  if (top_edge) return HTTOP;
  if (caption_height_ <= 0 || point.y < 0 || point.y >= std::lround(caption_height_ * scale)) return HTCLIENT;
  auto inside = [&](const Box& box) {
    return point.x >= std::lround(box.left * scale) && point.x < std::lround(box.right * scale) &&
           point.y >= std::lround(box.top * scale) && point.y < std::lround(box.bottom * scale);
  };
  if (has_maximize_ && inside(maximize_)) return HTMAXBUTTON;
  for (const Box& box : interactive_) {
    if (inside(box)) return HTCLIENT;
  }
  return HTCAPTION;
}

bool WindowFrame::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (!wparam || !Active()) return false;
      // The system works out the borders it keeps (left, right, bottom);
      // the top then goes back to the window's own, so the client area
      // covers the caption. A maximized window hangs over the monitor by
      // the sizing border, which is cut off again.
      auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
      const LONG top = params->rgrc[0].top;
      const LRESULT system = ::DefWindowProc(window_, message, wparam, lparam);
      if (system != 0) {
        *result = system;
        return true;
      }
      params->rgrc[0].top = ::IsZoomed(window_) ? top + FrameThickness(window_) : top;
      *result = 0;
      return true;
    }
    case WM_NCHITTEST:
      if (!Active()) return false;
      *result = HitTest(lparam);
      return true;
    case WM_NCMOUSEMOVE:
      if (!Active()) return false;
      if (wparam == HTMAXBUTTON) {
        if (!tracking_) {
          TRACKMOUSEEVENT track{sizeof(track), TME_LEAVE | TME_NONCLIENT, window_, 0};
          tracking_ = ::TrackMouseEvent(&track) != FALSE;
        }
        if (button_state_ == 0) SetButton(1);
        *result = 0;
        return true;
      }
      SetButton(0);
      return false;
    case WM_NCMOUSELEAVE:
      tracking_ = false;
      SetButton(0);
      return false;
    case WM_NCLBUTTONDOWN:
      if (Active() && wparam == HTCAPTION) TraceCaptionClick(lparam);
      if (!Active() || wparam != HTMAXBUTTON) return false;
      // Left to the system this would draw a classic button.
      SetButton(2);
      *result = 0;
      return true;
    case WM_NCLBUTTONUP:
      if (!Active() || wparam != HTMAXBUTTON) return false;
      if (button_state_ == 2) ::ShowWindow(window_, ::IsZoomed(window_) ? SW_RESTORE : SW_MAXIMIZE);
      SetButton(1);
      *result = 0;
      return true;
    case WM_SIZE:
      if (wparam == SIZE_MAXIMIZED) {
        ReportMaximized(true);
      } else if (wparam == SIZE_RESTORED) {
        ReportMaximized(false);
      }
      return false;
    case WM_ACTIVATE:
      ReportActive(LOWORD(wparam) != WA_INACTIVE);
      return false;
    case WM_NCACTIVATE:
      ReportActive(wparam != FALSE);
      return false;
  }
  return false;
}
