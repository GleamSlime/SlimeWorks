#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "window_backdrop.h"

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  RegisterBackdropChannel();

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// 材质能力/开关走 MethodChannel 暴露给 Dart。Dart 侧的磨砂透明度必须以“材质真的
// 挂上了”为前提，而不是按平台名字猜，所以这里只提供查询和开关，不预设要挂哪种。
void FlutterWindow::RegisterBackdropChannel() {
  backdrop_channel_ = flutter::MethodChannel<flutter::EncodableValue>::Create(
      flutter_controller_->engine()->messenger(),
      "slime_works/desktop_backdrop", &flutter::StandardMethodCodec::GetInstance());

  backdrop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "getCapability") {
          const WindowsBackdropCapability capability =
              QueryWindowsBackdropCapability();
          // MethodResult::Success 收的是指针，所以先落一个具名值再取地址。
          const flutter::EncodableValue payload(flutter::EncodableMap{
              {flutter::EncodableValue("transparentEffectsEnabled"),
               flutter::EncodableValue(capability.transparent_effects_enabled)},
              {flutter::EncodableValue("publicBackdropSupported"),
               flutter::EncodableValue(capability.public_backdrop_supported)},
              {flutter::EncodableValue("legacyMicaSupported"),
               flutter::EncodableValue(capability.legacy_mica_supported)},
              {flutter::EncodableValue("buildNumber"),
               flutter::EncodableValue(static_cast<int>(
                   capability.build_number))},
          });
          result->Success(&payload);
          return;
        }
        if (method == "setBackdrop") {
          const flutter::EncodableValue* argument = call.args();
          const std::string* requested =
              argument == nullptr
                  ? nullptr
                  : std::get_if<std::string>(argument);
          WindowsBackdropKind kind =
              WindowsBackdropKindFromName(requested == nullptr
                                              ? nullptr
                                              : requested->c_str());
          if (kind == WindowsBackdropKind::None) {
            ClearWindowsBackdrop(GetHandle());
          } else {
            kind = ApplyWindowsBackdrop(GetHandle(), kind);
          }
          const flutter::EncodableValue applied_name(WindowsBackdropKindName(kind));
          result->Success(&applied_name);
          return;
        }
        result->NotImplemented();
      });
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
