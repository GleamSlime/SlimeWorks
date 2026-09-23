#ifndef WINDOW_BACKDROP_H_
#define WINDOW_BACKDROP_H_

#include <windows.h>

// 系统给了哪种背景材质。None 表示没挂/已摘掉。
enum class WindowsBackdropKind { None, Mica, Acrylic };

// 这台机器的材质能力，纯静态信息，不改变窗口状态。
struct WindowsBackdropCapability {
  // 用户在「设置 → 个性化 → 颜色 → 透明效果」里的开关。关掉时系统会拒绝所有材质。
  bool transparent_effects_enabled = false;
  // build >= 22621：有公开的 DWMWA_SYSTEMBACKDROP_TYPE，Mica/压克力都能申请。
  bool public_backdrop_supported = false;
  // build 22000~22620：只有当时的内部 Mica 属性，也就是只有 Mica 一种能申请。
  bool legacy_mica_supported = false;
  DWORD build_number = 0;
};

// 查询材质能力。
WindowsBackdropCapability QueryWindowsBackdropCapability();

// 给顶层窗口挂上指定材质，并让材质铺满整个客户区。
// 返回真正生效的材质；系统没接受时返回 None，调用方据此把界面退回不透明底色。
WindowsBackdropKind ApplyWindowsBackdrop(HWND hwnd, WindowsBackdropKind kind);

// 摘掉材质，窗口退回普通的不透明底。
void ClearWindowsBackdrop(HWND hwnd);

// 用于跨语言传参的材质名。
const char* WindowsBackdropKindName(WindowsBackdropKind kind);

// 解析 Dart 侧传来的材质名；无法识别时返回 None。
WindowsBackdropKind WindowsBackdropKindFromName(const char* name);

#endif  // WINDOW_BACKDROP_H_
