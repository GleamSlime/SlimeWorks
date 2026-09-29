#ifndef WINDOW_BACKDROP_H_
#define WINDOW_BACKDROP_H_

#include <windows.h>

#include <cstdint>
#include <vector>

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

// —— 实时半透明（自绘磨砂）支撑 ——
// 这台 26200 实测不给非 WinUI3 窗口渲染任何系统材质（DWM 背景材质/老 Accent
// 全部只回读成功不绘制），磨砂只能应用自绘：抓窗口背后的屏幕帧、Flutter 里
// 模糊后当窗口底。

// 把顶层窗口临时降到「肉眼不可见但仍在合成」的程度（layered alpha=1），
// 让抓帧能拿到底下的内容；on=false 时恢复原状（撤掉 layered 样式）。
// 返回 >0 成功，<=0 为失败步骤编号（调试用）。
int SetWindowBehindVisible(HWND hwnd, bool on);

// 零闪烁抓帧路径：把窗口从屏幕捕获里排除（WDA_EXCLUDEFROMCAPTURE），屏幕上
// 完全可见、BitBlt 抓到的是它背后的桌面。Win10 2004 起支持，失败时（老系统）
// 返回 <=0，调用方应退回 SetWindowBehindVisible 的隐身路径。
// 返回 >0 成功，<=0 为失败步骤编号（调试用）。
int SetWindowCaptureExcluded(HWND hwnd, bool exclude);

// 抓取屏幕物理像素矩形 [x,y,w,h] 的 1/downscale 缩略帧，输出 RGBA 字节。
// 失败或矩形无效时返回空 vector。
std::vector<uint8_t> CaptureScreenRect(int x, int y, int w, int h,
                                       int downscale, int* out_w, int* out_h);

#endif  // WINDOW_BACKDROP_H_
