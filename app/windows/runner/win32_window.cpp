#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>
#include <windowsx.h>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr UINT_PTR kFlutterChildSubclassId = 1;
constexpr int kTitlebarHeight = 48;
constexpr int kCaptionButtonWidth = 46;

void SetImmersiveDarkMode(HWND window, BOOL dark) {
  if (FAILED(DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                                   &dark, sizeof(dark)))) {
    // Early Windows 10 dark-mode implementations used attribute 19.
    DwmSetWindowAttribute(window, 19, &dark, sizeof(dark));
  }
}

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);
  // Keep the native thick frame/shadow and system commands, but make the
  // entire visible frame client-rendered before Flutter's first frame.
  const MARGINS margins = {1, 1, 1, 1};
  DwmExtendFrameIntoClientArea(window, &margins);
  SetWindowPos(window, nullptr, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE |
                   SWP_FRAMECHANGED);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  LRESULT frame_result;
  if (HandleCustomFrameMessage(hwnd, message, wparam, lparam, &frame_result)) {
    return frame_result;
  }
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      CancelMaximizePress();
      SetMaximizeHovered(false);
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      const bool maximized = IsZoomed(hwnd) != FALSE;
      const bool changed = window_state_.maximized != maximized ||
                           window_state_.maximize_hovered;
      window_state_.maximized = maximized;
      window_state_.maximize_hovered = false;
      if (changed) {
        OnWindowStateChanged();
      }
      return 0;
    }

    case WM_ACTIVATE: {
      const bool active = LOWORD(wparam) != WA_INACTIVE;
      if (!active) {
        CancelMaximizePress();
      }
      const bool changed = window_state_.active != active ||
                           (!active && window_state_.maximize_hovered);
      window_state_.active = active;
      if (!active) {
        window_state_.maximize_hovered = false;
      }
      if (changed) {
        OnWindowStateChanged();
      }
      if (active && child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;
    }

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;

    case WM_SETTINGCHANGE:
      UpdateTheme(hwnd);
      break;
  }

  LRESULT dwm_result;
  if (DwmDefWindowProc(hwnd, message, wparam, lparam, &dwm_result)) {
    return dwm_result;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

bool Win32Window::SetChildContent(HWND content) {
  DetachChildContent();
  if (!SetWindowSubclass(content, ChildSubclassProc, kFlutterChildSubclassId,
                         reinterpret_cast<DWORD_PTR>(this))) {
    return false;
  }
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  if (GetActiveWindow() == window_handle_) {
    SetFocus(child_content_);
  }
  return true;
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  CancelMaximizePress();
  DetachChildContent();
}

void Win32Window::ConfigureCustomFrame(bool dark) {
  dark_ = dark ? TRUE : FALSE;
  has_app_theme_ = true;
  UpdateTheme(window_handle_);
}

const Win32Window::WindowState& Win32Window::GetWindowState() const {
  return window_state_;
}

void Win32Window::OnWindowStateChanged() {}

void Win32Window::UpdateTheme(HWND const window) {
  if (has_app_theme_) {
    SetImmersiveDarkMode(window, dark_);
    return;
  }

  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    SetImmersiveDarkMode(window, enable_dark_mode);
  }
}

LRESULT Win32Window::HitTest(POINT screen_point) const noexcept {
  POINT point = screen_point;
  ScreenToClient(window_handle_, &point);
  RECT client;
  GetClientRect(window_handle_, &client);
  if (!PtInRect(&client, point)) {
    return HTNOWHERE;
  }

  const UINT dpi = GetDpiForWindow(window_handle_);
  if (!IsZoomed(window_handle_)) {
    const int border_x = GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) +
                         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    const int border_y = GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) +
                         GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
    const bool left = point.x < border_x;
    const bool right = point.x >= client.right - border_x;
    const bool top = point.y < border_y;
    const bool bottom = point.y >= client.bottom - border_y;
    if (top) {
      return left ? HTTOPLEFT : (right ? HTTOPRIGHT : HTTOP);
    }
    if (bottom) {
      return left ? HTBOTTOMLEFT : (right ? HTBOTTOMRIGHT : HTBOTTOM);
    }
    if (left) {
      return HTLEFT;
    }
    if (right) {
      return HTRIGHT;
    }
  }

  if (point.y < MulDiv(kTitlebarHeight, dpi, 96)) {
    const int controls_left =
        client.right - MulDiv(3 * kCaptionButtonWidth, dpi, 96);
    const int maximize_left =
        client.right - MulDiv(2 * kCaptionButtonWidth, dpi, 96);
    const int close_left =
        client.right - MulDiv(kCaptionButtonWidth, dpi, 96);
    if (point.x < controls_left) {
      return HTCAPTION;
    }
    if (point.x >= maximize_left && point.x < close_left) {
      return HTMAXBUTTON;
    }
  }
  return HTCLIENT;
}

bool Win32Window::HandleCustomFrameMessage(
    HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam,
    LRESULT* result) noexcept {
  switch (message) {
    case WM_NCCALCSIZE: {
      if (!wparam) {
        break;
      }
      // Returning zero removes the native caption without removing any window
      // styles. A maximized thick-frame window extends beyond the work area;
      // clip its client bounds so Flutter's header stays entirely on-screen.
      RECT* client =
          &reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam)->rgrc[0];
      if (IsZoomed(hwnd)) {
        MONITORINFO monitor_info = {};
        monitor_info.cbSize = sizeof(monitor_info);
        if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                           &monitor_info)) {
          const RECT& work = monitor_info.rcWork;
          if (client->left < work.left) client->left = work.left;
          if (client->top < work.top) client->top = work.top;
          if (client->right > work.right) client->right = work.right;
          if (client->bottom > work.bottom) client->bottom = work.bottom;
        }
      }
      *result = 0;
      return true;
    }
    case WM_NCHITTEST: {
      *result = HitTest({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
      return true;
    }
    case WM_NCMOUSEMOVE: {
      SetMaximizeHovered(wparam == HTMAXBUTTON);
      if (!tracking_nc_mouse_) {
        TRACKMOUSEEVENT tracking = {sizeof(TRACKMOUSEEVENT),
                                    TME_LEAVE | TME_NONCLIENT, hwnd, 0};
        tracking_nc_mouse_ = TrackMouseEvent(&tracking) != FALSE;
      }
      // Keep standard non-client hover processing alongside the custom visuals.
      *result = DefWindowProc(hwnd, message, wparam, lparam);
      return true;
    }
    case WM_NCMOUSELEAVE: {
      tracking_nc_mouse_ = false;
      SetMaximizeHovered(false);
      *result = DefWindowProc(hwnd, message, wparam, lparam);
      return true;
    }
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      if (wparam == HTMAXBUTTON) {
        // Default caption-button tracking assumes the OS caption geometry.
        // Track our custom button, then use the native system command exactly
        // once on an inside release.
        maximize_pressed_ = true;
        SetCapture(hwnd);
        SetMaximizeHovered(true);
        *result = 0;
        return true;
      }
      break;
    case WM_MOUSEMOVE:
      if (maximize_pressed_) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ClientToScreen(hwnd, &point);
        SetMaximizeHovered(HitTest(point) == HTMAXBUTTON);
        *result = 0;
        return true;
      }
      break;
    case WM_LBUTTONUP:
      if (maximize_pressed_) {
        POINT point = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
        ClientToScreen(hwnd, &point);
        FinishMaximizePress(point);
        *result = 0;
        return true;
      }
      break;
    case WM_NCLBUTTONUP:
      if (maximize_pressed_) {
        FinishMaximizePress({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
        *result = 0;
        return true;
      }
      if (wparam == HTMAXBUTTON) {
        // A release with no matching press must not reach default tracking.
        *result = 0;
        return true;
      }
      break;
    case WM_CAPTURECHANGED:
      if (reinterpret_cast<HWND>(lparam) != hwnd && maximize_pressed_) {
        maximize_pressed_ = false;
        SetMaximizeHovered(false);
      }
      break;
    case WM_CANCELMODE:
      CancelMaximizePress();
      SetMaximizeHovered(false);
      break;
  }
  return false;
}

void Win32Window::SetMaximizeHovered(bool hovered) {
  if (window_state_.maximize_hovered != hovered) {
    window_state_.maximize_hovered = hovered;
    OnWindowStateChanged();
  }
}

void Win32Window::CancelMaximizePress() {
  if (maximize_pressed_) {
    maximize_pressed_ = false;
    if (GetCapture() == window_handle_) {
      ReleaseCapture();
    }
  }
}

void Win32Window::FinishMaximizePress(POINT screen_point) {
  const bool activate = GetCapture() == window_handle_ &&
                        HitTest(screen_point) == HTMAXBUTTON;
  CancelMaximizePress();
  SetMaximizeHovered(false);
  if (activate) {
    SendMessage(window_handle_, WM_SYSCOMMAND,
                IsZoomed(window_handle_) ? SC_RESTORE : SC_MAXIMIZE, 0);
  }
}

void Win32Window::DetachChildContent() {
  if (child_content_ != nullptr) {
    RemoveWindowSubclass(child_content_, ChildSubclassProc,
                         kFlutterChildSubclassId);
    child_content_ = nullptr;
  }
}

LRESULT CALLBACK Win32Window::ChildSubclassProc(
    HWND window, UINT message, WPARAM wparam, LPARAM lparam,
    UINT_PTR subclass_id, DWORD_PTR reference_data) noexcept {
  auto* owner = reinterpret_cast<Win32Window*>(reference_data);
  if (message == WM_NCHITTEST) {
    const LRESULT hit =
        owner->HitTest({GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)});
    if (hit != HTCLIENT && hit != HTNOWHERE) {
      // Flutter's child HWND covers every client pixel. Let Windows continue
      // hit testing at the parent for its drag, Snap and resize regions.
      return HTTRANSPARENT;
    }
  } else if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(window, ChildSubclassProc, subclass_id);
    if (owner->child_content_ == window) {
      owner->child_content_ = nullptr;
    }
  }
  return DefSubclassProc(window, message, wparam, lparam);
}
