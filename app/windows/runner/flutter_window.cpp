#include "flutter_window.h"

#include <limits>
#include <optional>
#include <windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/method_result_functions.h>

#include "flutter/generated_plugin_registrant.h"

namespace {


bool Utf16FromUtf8(const std::string& utf8, std::wstring* utf16) {
  if (utf8.find('\0') != std::string::npos ||
      utf8.size() > static_cast<size_t>((std::numeric_limits<int>::max)())) {
    return false;
  }
  if (utf8.empty()) {
    utf16->clear();
    return true;
  }
  const int length = static_cast<int>(utf8.size());
  const int wide_length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), length, nullptr, 0);
  if (wide_length == 0) {
    return false;
  }
  utf16->resize(wide_length);
  return MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(), length,
                             utf16->data(), wide_length) == wide_length;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  host_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "skyport/host",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "skyport/window",
          &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success();
          return;
        }
        if (call.method_name() == "toggleMaximize") {
          SendMessage(GetHandle(), WM_SYSCOMMAND,
                      IsZoomed(GetHandle()) ? SC_RESTORE : SC_MAXIMIZE, 0);
          result->Success();
          return;
        }
        if (call.method_name() == "close") {
          // Acceptance only: WM_CLOSE still awaits skyport/host approval.
          if (!PostMessage(GetHandle(), WM_CLOSE, 0, 0)) {
            result->Error("window_error", "Unable to request window close.");
            return;
          }
          result->Success();
          return;
        }
        if (call.method_name() != "configure") {
          result->NotImplemented();
          return;
        }
        const auto* arguments =
            std::get_if<flutter::EncodableMap>(call.arguments());
        if (arguments == nullptr) {
          result->Error("invalid_arguments", "Expected a configuration map.");
          return;
        }
        const auto find = [arguments](const char* key)
            -> const flutter::EncodableValue* {
          const auto entry =
              arguments->find(flutter::EncodableValue(std::string(key)));
          return entry == arguments->end() ? nullptr : &entry->second;
        };
        const auto* dark = std::get_if<bool>(find("dark"));
        const auto* title = std::get_if<std::string>(find("title"));
        if (dark == nullptr || title == nullptr) {
          result->Error("invalid_arguments",
                        "Expected a dark boolean and a title string.");
          return;
        }
        std::wstring wide_title;
        if (!Utf16FromUtf8(*title, &wide_title)) {
          result->Error("invalid_arguments",
                        "The title must be valid UTF-8 without NUL characters.");
          return;
        }
        if (!SetWindowTextW(GetHandle(), wide_title.c_str())) {
          result->Error("window_error", "Unable to update the window title.");
          return;
        }
        ConfigureCustomFrame(*dark);
        result->Success(EncodeWindowState());
      });
  if (!SetChildContent(flutter_controller_->view()->GetNativeWindow())) {
    return false;
  }

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  // Remove the child subclass while its HWND and this owner are still alive.
  Win32Window::OnDestroy();
  window_channel_ = nullptr;
  host_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && host_channel_) {
    if (!close_pending_) {
      close_pending_ = true;
      host_channel_->InvokeMethod(
          "requestClose", nullptr,
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [this, hwnd](const flutter::EncodableValue* result) {
                close_pending_ = false;
                const bool* approved = result == nullptr
                    ? nullptr : std::get_if<bool>(result);
                if (approved != nullptr && *approved) {
                  DestroyWindow(hwnd);
                }
              },
              [this](const std::string&, const std::string&,
                     const flutter::EncodableValue*) { close_pending_ = false; },
              [this]() { close_pending_ = false; }));
    }
    return 0;
  }

  LRESULT frame_result;
  if (HandleCustomFrameMessage(hwnd, message, wparam, lparam, &frame_result)) {
    return frame_result;
  }
  switch (message) {
    case WM_SIZE:
    case WM_ACTIVATE:
    case WM_DPICHANGED:
    case WM_SYSCOMMAND:
    case WM_NCACTIVATE:
    case WM_NCPAINT:
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONUP:
    case WM_NCLBUTTONDBLCLK:
    case WM_NCRBUTTONDOWN:
    case WM_NCRBUTTONUP:
    case WM_NCRBUTTONDBLCLK:
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_GETMINMAXINFO: {
      auto info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd);
      info->ptMinTrackSize.x = MulDiv(320, dpi, 96);
      info->ptMinTrackSize.y = MulDiv(480, dpi, 96);
      return 0;
    }

    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

flutter::EncodableValue FlutterWindow::EncodeWindowState() const {
  const auto& state = GetWindowState();
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("maximized"),
       flutter::EncodableValue(state.maximized)},
      {flutter::EncodableValue("active"), flutter::EncodableValue(state.active)},
      {flutter::EncodableValue("maximizeHovered"),
       flutter::EncodableValue(state.maximize_hovered)},
  });
}

void FlutterWindow::OnWindowStateChanged() {
  if (window_channel_) {
    window_channel_->InvokeMethod(
        "windowState",
        std::make_unique<flutter::EncodableValue>(EncodeWindowState()));
  }
}
