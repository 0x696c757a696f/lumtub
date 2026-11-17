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

// The Windows build number; GetVersionEx answers what the manifest names.
DWORD WindowsBuild() {
  static const DWORD build = [] {
    using RtlGetVersion = LONG(WINAPI*)(OSVERSIONINFOW*);
    const auto get = reinterpret_cast<RtlGetVersion>(
        ::GetProcAddress(::GetModuleHandle(L"ntdll.dll"), "RtlGetVersion"));
    OSVERSIONINFOW info{sizeof(info)};
    return get && get(&info) == 0 ? info.dwBuildNumber : 0;
  }();
  return build;
}

// Windows 11 22H2 and later draw an acrylic backdrop of their own.
constexpr DWORD kSystemBackdropBuild = 22621;
// Windows 10 1803 and later blur with acrylic through the accent policy.
constexpr DWORD kAccentAcrylicBuild = 17134;

enum Accent { kAccentNone = 0, kAccentClear = 2, kAccentBlur = 3, kAccentAcrylic = 4 };

// The undocumented accent policy that TranslucentTB and the taskbar use.
// [frost] is 0xAARRGGBB: the colour laid over the blur, as Windows 10's
// own acrylic lays its tint, so the desktop behind reads as frosted glass
// rather than as a sharp picture.
void SetAccent(HWND window, Accent state, DWORD frost = 0) {
  struct AccentPolicy {
    int state;
    int flags;
    DWORD gradient;
    int animation;
  };
  struct CompositionData {
    int attribute;
    void* data;
    SIZE_T size;
  };
  using SetComposition = BOOL(WINAPI*)(HWND, CompositionData*);
  static const auto set_composition = reinterpret_cast<SetComposition>(
      ::GetProcAddress(::GetModuleHandle(L"user32.dll"), "SetWindowCompositionAttribute"));
  if (!set_composition) return;
  // The policy wants 0xAABBGGRR. Clear: a gradient of nothing, so the
  // desktop shows as it is (since Windows 8 the extended frame alone is
  // drawn solid). Flag 2: use the colour.
  const DWORD abgr = (frost & 0xFF00FF00u) | ((frost & 0xFFu) << 16) | ((frost >> 16) & 0xFFu);
  const DWORD gradient = state == kAccentClear ? 0u : abgr;
  AccentPolicy accent{state, state == kAccentNone ? 0 : 2, gradient, 0};
  CompositionData data{19 /* WCA_ACCENT_POLICY */, &accent, sizeof(accent)};
  set_composition(window, &data);
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
  if (message == WM_MOUSEMOVE && frame->pointer_hidden_) frame->PointerMoved();
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
  } else if (method == "setDesktopGlass") {
    auto flag = [&](const char* key) {
      const EncodableValue* value = Find(args, key);
      const bool* on = value ? std::get_if<bool>(value) : nullptr;
      return on && *on;
    };
    // The skin's glass colour, 0xAARRGGBB; Dart ints arrive as 32 or 64 bits.
    const EncodableValue* tint = Find(args, "tint");
    int64_t colour = 0;
    if (tint) {
      if (const auto* small = std::get_if<int32_t>(tint)) colour = static_cast<uint32_t>(*small);
      if (const auto* big = std::get_if<int64_t>(tint)) colour = *big;
    }
    result->Success(SetDesktopGlass(flag("on"), flag("dark"), flag("blur"), static_cast<DWORD>(colour)));
    return;
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
  } else if (method == "hidePointer") {
    HidePointer(args);
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
// corners and border. Windows 11's own acrylic shows only where the frame
// covers the window, so then it covers all of it; the accent policy (clear
// glass, and the blur before Windows 11) needs no frame, and the frame
// alone would be drawn solid over the desktop.
void WindowFrame::ApplyMargins() {
  const bool backdrop = glass_ && glass_blur_ && WindowsBuild() >= kSystemBackdropBuild;
  const MARGINS margins = backdrop ? MARGINS{-1, -1, -1, -1} : MARGINS{0, 0, custom_ ? 1 : 0, 0};
  ::DwmExtendFrameIntoClientArea(window_, &margins);
}

// Settings › Personalisation › Colours › Transparency effects. With them
// off, Windows draws its blur as a solid colour, which would hide the
// desktop the person asked to see, so the glass is left clear instead.
static bool TransparencyEffectsOn() {
  DWORD value = 1;
  DWORD size = sizeof(value);
  ::RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                 L"EnableTransparency", RRF_RT_REG_DWORD, nullptr, &value, &size);
  return value != 0;
}

EncodableValue WindowFrame::SetDesktopGlass(bool on, bool dark, bool blur, DWORD tint) {
  glass_ = on;
  // Half the skin's colour over the blur: frosted, as Windows 10's
  // acrylic is, with Flutter's own tint on top.
  glass_frost_ = (tint & 0x00FFFFFFu) | 0x80000000u;
  glass_blur_ = on && blur && TransparencyEffectsOn();
  ApplyMargins();
  if (on) {
    // The acrylic's own shade follows the skin's side, not the system's.
    const BOOL dark_mode = dark ? TRUE : FALSE;
    ::DwmSetWindowAttribute(window_, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark_mode, sizeof(dark_mode));
  } else {
    // Back to the system's light or dark title bar.
    ::SendMessage(window_, WM_DWMCOLORIZATIONCOLORCHANGED, 0, 0);
  }
  ApplyBlur(false);
  ::SetWindowPos(window_, nullptr, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ::InvalidateRect(window_, nullptr, TRUE);
  return EncodableValue(EncodableMap{
      {EncodableValue("shown"), EncodableValue(on)},
      {EncodableValue("blurred"), EncodableValue(glass_blur_)},
  });
}

// Windows 11 22H2 and later: the system's acrylic backdrop. Older ones:
// acrylic through the accent policy, which lags behind the mouse while
// the window is dragged or sized, so the plain blur stands in meanwhile;
// before 1803, the plain blur only.
void WindowFrame::ApplyBlur(bool moving) {
  const DWORD build = WindowsBuild();
  if (build >= kSystemBackdropBuild) {
    const int backdrop = !glass_ ? 0 /* DWMSBT_AUTO */ : glass_blur_ ? 3 /* DWMSBT_TRANSIENTWINDOW */ : 1 /* DWMSBT_NONE */;
    ::DwmSetWindowAttribute(window_, 38 /* DWMWA_SYSTEMBACKDROP_TYPE */, &backdrop, sizeof(backdrop));
    SetAccent(window_, glass_ && !glass_blur_ ? kAccentClear : kAccentNone);
    return;
  }
  if (!glass_blur_) {
    SetAccent(window_, glass_ ? kAccentClear : kAccentNone);
  } else {
    SetAccent(window_, build >= kAccentAcrylicBuild && !moving ? kAccentAcrylic : kAccentBlur, glass_frost_);
  }
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
    case WM_ENTERSIZEMOVE:
      if (glass_blur_) ApplyBlur(true);
      return false;
    case WM_EXITSIZEMOVE:
      if (glass_blur_) ApplyBlur(false);
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

void WindowFrame::HidePointer(const EncodableValue* area) {
  double box[4];
  if (!view_ || !area || !ReadBox(*area, box) || ::GetForegroundWindow() != window_) return;
  POINT point;
  if (!::GetCursorPos(&point)) return;
  const HWND under = ::WindowFromPoint(point);
  if (under != view_ && under != window_) return;
  POINT client = point;
  if (!::ScreenToClient(view_, &client)) return;
  const double scale = ScaleOf(window_);
  const double x = client.x / scale;
  const double y = client.y / scale;
  if (x < box[0] || y < box[1] || x >= box[2] || y >= box[3]) return;
  pointer_hidden_ = true;
  hidden_at_ = point;
  ::SetCursor(nullptr);
}

void WindowFrame::PointerMoved() {
  POINT point;
  if (!::GetCursorPos(&point) || (point.x == hidden_at_.x && point.y == hidden_at_.y)) return;
  pointer_hidden_ = false;
  // Flutter answers the move with the pointer it wants, which may be the
  // one it already had and so is not sent again.
  if (::GetCursor() == nullptr) ::SetCursor(::LoadCursor(nullptr, IDC_ARROW));
}
