#include "window_backdrop.h"

#include <cstring>

#include <dwmapi.h>

namespace {

// 下面这几个值在较旧的 Windows SDK 头文件里没有定义，按官方文档的取值补上。
// 用自己的常量名，不去覆盖系统头里的同名宏，避免和不同 SDK 版本打架。
constexpr int kSystemBackdropTypeAttribute = 38;  // DWMWA_SYSTEMBACKDROP_TYPE
constexpr int kMicaEffectAttribute = 1029;        // 22000~22620 的过渡属性
constexpr int kBackdropNone = 0;                  // DWMSBT_NONE
constexpr int kBackdropMainWindow = 2;            // DWMSBT_MAINWINDOW = Mica
constexpr int kBackdropTransientWindow = 3;       // DWMSBT_TRANSIENTWINDOW = 压克力

// Mica 是 Windows 11（build 22000）才有的系统材质；22621（22H2）起才有公开属性。
constexpr DWORD kBuildWithMica = 22000;
constexpr DWORD kBuildWithPublicBackdropAttribute = 22621;

// 取真实系统版本。GetVersionEx 会被应用清单里的兼容性声明改写，
// 只有 ntdll 导出的 RtlGetVersion 给的是内核的真实版本号。
bool GetSystemBuild(DWORD* major, DWORD* build) {
  HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
  if (ntdll == nullptr) {
    return false;
  }
  typedef LONG(WINAPI* RtlGetVersionFunc)(OSVERSIONINFOEXW*);
  RtlGetVersionFunc rtl_get_version = reinterpret_cast<RtlGetVersionFunc>(
      ::GetProcAddress(ntdll, "RtlGetVersion"));
  if (rtl_get_version == nullptr) {
    return false;
  }

  OSVERSIONINFOEXW info = {};
  info.dwOSVersionInfoSize = sizeof(info);
  if (rtl_get_version(&info) != 0) {
    return false;
  }
  *major = info.dwMajorVersion;
  *build = info.dwBuildNumber;
  return true;
}

// 用户可以在「设置 → 个性化 → 颜色 → 透明效果」里把系统材质整个关掉。
// 关掉之后再去申请只会拿到一块纯色底，不如直接按“不支持”处理。
//
// 值名是 EnableTransparency：Win10 时代叫 EnableMIPThreshold，后来又叫过
// EnableTransparencyEffects，但 Win11（至少到 26xxx）实际写回的是
// EnableTransparency。之前只读 Effects 那个名字，永远读不到、永远按“开启”
// 处理，用户真关掉时材质其实没画，界面却把窗口底留成了透明——穿透但不模糊。
// 这里按新旧名字依次读，取第一个读得到的。
bool AreTransparencyEffectsEnabled() {
  const wchar_t* key_path =
      L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
  HKEY key = nullptr;
  if (::RegOpenKeyExW(HKEY_CURRENT_USER, key_path, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    // 读不到就按系统默认（开启）处理，不要因为这个把材质关掉。
    return true;
  }

  const wchar_t* value_names[] = {L"EnableTransparency",
                                  L"EnableTransparencyEffects"};
  bool enabled = true;
  bool found = false;
  for (const wchar_t* value_name : value_names) {
    DWORD value = 1;
    DWORD value_size = sizeof(value);
    DWORD value_type = 0;
    LSTATUS status =
        ::RegQueryValueExW(key, value_name, nullptr, &value_type,
                           reinterpret_cast<LPBYTE>(&value), &value_size);
    if (status == ERROR_SUCCESS && value_type == REG_DWORD) {
      enabled = value != 0;
      found = true;
      break;
    }
  }
  ::RegCloseKey(key);
  // 一个名字都没读到就按系统默认（开启）处理。
  return found ? enabled : true;
}

// 把想要的材质写进 DWM 并回读确认。
//
// 回读是必要的：用户在「设置」里关掉透明效果时，DwmSetWindowAttribute 一样会
// 返回成功，只是系统压根不画——那种情况下界面必须退回实心底。
bool SetBackdropAttribute(HWND hwnd, int backdrop) {
  if (FAILED(::DwmSetWindowAttribute(hwnd, kSystemBackdropTypeAttribute,
                                     &backdrop, sizeof(backdrop)))) {
    return false;
  }
  int actual = kBackdropNone;
  if (SUCCEEDED(::DwmGetWindowAttribute(hwnd, kSystemBackdropTypeAttribute,
                                        &actual, sizeof(actual)))) {
    return actual == backdrop;
  }
  // 读不回来就当作设置成功，不要把能力误判成没有。
  return true;
}

// —— 老 Accent 策略与 DWM 背景材质互斥 ——
//
// window_manager 落透明底色时用的是 Win10 时代的 SetWindowCompositionAttribute
// （Accent / TRANSPARENTGRADIENT）。只要 Accent 策略还挂在窗口上，Win11 的
// DWMWA_SYSTEMBACKDROP_TYPE 材质就不会被绘制——症状是窗口「穿透但不模糊」。
// 挂材质前必须先把 Accent 置为 DISABLED，这一步抄的是 flutter_acrylic 的做法
// （https://github.com/alexmercerind/flutter_acrylic，windows 插件源文件）。
// SetWindowCompositionAttribute 是未导出文档的 API，按惯例从 user32 动态取。

constexpr int kWindowCompositionAttributeAccentPolicy = 19;
constexpr int kAccentDisabled = 0;
constexpr int kAccentTransientWindowForCompatibility = 2;

struct AccentPolicy {
  int accent_state;
  int flags;
  DWORD color;
  int animation_id;
};

struct WindowCompositionAttribData {
  int attribute;
  void* data;
  unsigned long size;
};

typedef BOOL(WINAPI* SetWindowCompositionAttribFunc)(
    HWND, WindowCompositionAttribData*);

bool DisableAccentPolicy(HWND hwnd) {
  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) {
    return false;
  }
  SetWindowCompositionAttribFunc set_attribute =
      reinterpret_cast<SetWindowCompositionAttribFunc>(
          ::GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_attribute == nullptr) {
    return false;
  }
  AccentPolicy accent = {kAccentDisabled,
                         kAccentTransientWindowForCompatibility, 0, 0};
  WindowCompositionAttribData data = {
      kWindowCompositionAttributeAccentPolicy, &accent, sizeof(accent)};
  return set_attribute(hwnd, &data) != FALSE;
}

}  // namespace

WindowsBackdropCapability QueryWindowsBackdropCapability() {
  WindowsBackdropCapability capability;
  capability.transparent_effects_enabled = AreTransparencyEffectsEnabled();

  DWORD major = 0;
  DWORD build = 0;
  if (GetSystemBuild(&major, &build)) {
    capability.build_number = build;
    if (major >= 10 && build >= kBuildWithMica) {
      capability.public_backdrop_supported =
          build >= kBuildWithPublicBackdropAttribute;
      capability.legacy_mica_supported = true;
    }
  }
  return capability;
}

WindowsBackdropKind ApplyWindowsBackdrop(HWND hwnd, WindowsBackdropKind kind) {
  if (hwnd == nullptr || kind == WindowsBackdropKind::None) {
    return WindowsBackdropKind::None;
  }

  const WindowsBackdropCapability capability = QueryWindowsBackdropCapability();
  if (!capability.transparent_effects_enabled) {
    return WindowsBackdropKind::None;
  }

  // 先清掉可能存在的 Accent 策略，材质才可能被绘制（原因见 DisableAccentPolicy）。
  DisableAccentPolicy(hwnd);
  // 标题栏底色置为「透明」哨兵值（DWMWA_CAPTION_COLOR = 35, RGB(0,0,0) 的
  // 特殊值 0xFFFFFFFE），让标题栏区域也让材质透出来，flutter_acrylic 同款处理。
  DWORD caption_color_none = 0xFFFFFFFE;
  ::DwmSetWindowAttribute(hwnd, 35, &caption_color_none,
                          sizeof(caption_color_none));

  bool applied = false;
  if (capability.public_backdrop_supported) {
    applied =
        SetBackdropAttribute(hwnd, kind == WindowsBackdropKind::Acrylic
                                       ? kBackdropTransientWindow
                                       : kBackdropMainWindow);
  } else if (capability.legacy_mica_supported &&
             kind == WindowsBackdropKind::Mica) {
    // 22000~22620 只认这个当时的内部属性，而且只有 Mica 一种可选。
    BOOL enable_mica = TRUE;
    applied = SUCCEEDED(::DwmSetWindowAttribute(hwnd, kMicaEffectAttribute,
                                                &enable_mica,
                                                sizeof(enable_mica)));
  }

  if (!applied) {
    return WindowsBackdropKind::None;
  }

  // 把窗口边框扩展到整个客户区。不扩展的话材质只画在标题栏那一圈，
  // 客户区仍然是不透明纯色，界面里的半透明区域透不出任何东西。
  MARGINS extend_into_client_area = {-1, -1, -1, -1};
  ::DwmExtendFrameIntoClientArea(hwnd, &extend_into_client_area);

  return kind;
}

void ClearWindowsBackdrop(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  if (QueryWindowsBackdropCapability().public_backdrop_supported) {
    SetBackdropAttribute(hwnd, kBackdropNone);
  }
  MARGINS client_area_only = {0, 0, 0, 0};
  ::DwmExtendFrameIntoClientArea(hwnd, &client_area_only);
}

const char* WindowsBackdropKindName(WindowsBackdropKind kind) {
  switch (kind) {
    case WindowsBackdropKind::Mica:
      return "mica";
    case WindowsBackdropKind::Acrylic:
      return "acrylic";
    case WindowsBackdropKind::None:
      return "none";
  }
  return "none";
}

WindowsBackdropKind WindowsBackdropKindFromName(const char* name) {
  if (name == nullptr) {
    return WindowsBackdropKind::None;
  }
  if (std::strcmp(name, "mica") == 0) {
    return WindowsBackdropKind::Mica;
  }
  if (std::strcmp(name, "acrylic") == 0) {
    return WindowsBackdropKind::Acrylic;
  }
  return WindowsBackdropKind::None;
}
