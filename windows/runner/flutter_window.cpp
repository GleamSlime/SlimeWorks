#include "flutter_window.h"

#include <optional>
#include <vector>

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
  backdrop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "slime_works/desktop_backdrop",
      &flutter::StandardMethodCodec::GetInstance());

  backdrop_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        const std::string& method = call.method_name();
        if (method == "getCapability") {
          const WindowsBackdropCapability capability =
              QueryWindowsBackdropCapability();
          // MethodResult::Success 收的是值而非指针；这里先落一个具名值只是为了
          // 让 map 的初始化列表可读，move 出去避免再拷一份。
          flutter::EncodableValue payload(flutter::EncodableMap{
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
          result->Success(std::move(payload));
          return;
        }
        if (method == "setBackdrop") {
          const flutter::EncodableValue* argument = call.arguments();
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
          flutter::EncodableValue applied_name(WindowsBackdropKindName(kind));
          result->Success(std::move(applied_name));
          return;
        }
        if (method == "setWindowBehindVisible") {
          bool on = false;
          const flutter::EncodableValue* argument = call.arguments();
          if (argument != nullptr) {
            if (const bool* direct = std::get_if<bool>(argument)) {
              on = *direct;
            } else if (const auto* map =
                           std::get_if<flutter::EncodableMap>(argument)) {
              const auto it = map->find(flutter::EncodableValue("on"));
              if (it != map->end()) {
                if (const bool* v = std::get_if<bool>(&it->second)) {
                  on = *v;
                }
              }
            }
          }
          const int rc = SetWindowBehindVisible(GetHandle(), on);
          result->Success(flutter::EncodableValue(rc));
          return;
        }
        if (method == "setWindowCaptureExcluded") {
          bool on = false;
          const flutter::EncodableValue* argument = call.arguments();
          if (argument != nullptr) {
            if (const bool* direct = std::get_if<bool>(argument)) {
              on = *direct;
            } else if (const auto* map =
                           std::get_if<flutter::EncodableMap>(argument)) {
              const auto it = map->find(flutter::EncodableValue("on"));
              if (it != map->end()) {
                if (const bool* v = std::get_if<bool>(&it->second)) {
                  on = *v;
                }
              }
            }
          }
          const int rc = SetWindowCaptureExcluded(GetHandle(), on);
          result->Success(flutter::EncodableValue(rc));
          return;
        }
        if (method == "captureBehindWindow") {
          // 抓的是本窗口矩形：物理像素直接问 Win32，省掉 Dart 侧换算 DPI。
          RECT rect = {};
          ::GetWindowRect(GetHandle(), &rect);
          const flutter::EncodableMap* args =
              call.arguments() == nullptr
                  ? nullptr
                  : std::get_if<flutter::EncodableMap>(call.arguments());
          auto read_int = [&](const char* key, int fallback) -> int {
            if (args == nullptr) {
              return fallback;
            }
            const auto it = args->find(flutter::EncodableValue(key));
            if (it == args->end()) {
              return fallback;
            }
            if (const int* v = std::get_if<int>(&it->second)) {
              return *v;
            }
            if (const int64_t* v64 = std::get_if<int64_t>(&it->second)) {
              return static_cast<int>(*v64);
            }
            return fallback;
          };
          const int downscale = read_int("downscale", 4);
          const int margin = read_int("margin", 0);

          // 向外扩一圈再抓：高斯模糊会采样到贴图边缘之外，边缘像素没有邻域
          // 数据就会淡成白/半透明。多抓一圈真实桌面，Dart 侧再把这一圈裁掉，
          // 窗口边缘就落在「有邻域数据」的内区上，白边消失。
          const int vs_left = ::GetSystemMetrics(SM_XVIRTUALSCREEN);
          const int vs_top = ::GetSystemMetrics(SM_YVIRTUALSCREEN);
          const int vs_right =
              vs_left + ::GetSystemMetrics(SM_CXVIRTUALSCREEN);
          const int vs_bottom =
              vs_top + ::GetSystemMetrics(SM_CYVIRTUALSCREEN);
          const int cap_l = rect.left - margin < vs_left
                                ? vs_left
                                : rect.left - margin;
          const int cap_t = rect.top - margin < vs_top
                                ? vs_top
                                : rect.top - margin;
          const int cap_r = rect.right + margin > vs_right
                                ? vs_right
                                : rect.right + margin;
          const int cap_b = rect.bottom + margin > vs_bottom
                                ? vs_bottom
                                : rect.bottom + margin;

          int out_w = 0;
          int out_h = 0;
          std::vector<uint8_t> pixels =
              CaptureScreenRect(cap_l, cap_t, cap_r - cap_l, cap_b - cap_t,
                                downscale, &out_w, &out_h);
          // 四边实际外扩量（可能被屏幕边界夹小），回传给 Dart 精确裁剪。
          flutter::EncodableValue payload(flutter::EncodableMap{
              {flutter::EncodableValue("width"),
               flutter::EncodableValue(out_w)},
              {flutter::EncodableValue("height"),
               flutter::EncodableValue(out_h)},
              {flutter::EncodableValue("pixels"),
               flutter::EncodableValue(std::move(pixels))},
              {flutter::EncodableValue("padLeft"),
               flutter::EncodableValue(rect.left - cap_l)},
              {flutter::EncodableValue("padTop"),
               flutter::EncodableValue(rect.top - cap_t)},
              {flutter::EncodableValue("padRight"),
               flutter::EncodableValue(cap_r - rect.right)},
              {flutter::EncodableValue("padBottom"),
               flutter::EncodableValue(cap_b - rect.bottom)},
              {flutter::EncodableValue("winX"),
               flutter::EncodableValue(static_cast<int>(rect.left))},
              {flutter::EncodableValue("winY"),
               flutter::EncodableValue(static_cast<int>(rect.top))},
              {flutter::EncodableValue("winW"),
               flutter::EncodableValue(static_cast<int>(rect.right - rect.left))},
              {flutter::EncodableValue("winH"),
               flutter::EncodableValue(static_cast<int>(rect.bottom - rect.top))},
          });
          result->Success(std::move(payload));
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
