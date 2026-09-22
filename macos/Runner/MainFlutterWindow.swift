import Cocoa
import FlutterMacOS

/// DEBUG-BISECTION: 不参与命中测试的振动视图，用来验证"点击全部失效"是否由它吃掉。
class NoHitVisualEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    enableBehindWindowVibrancy()

    super.awakeFromNib()
  }

  /// 让窗口能透出桌面内容，并在 Flutter 层正下方垫一层 behindWindow 振动视图。
  ///
  /// 侧栏的磨砂靠的就是这一层：Flutter 侧把根 Material 设成透明、内容区自己补
  /// 不透明底，透明像素才会露出下面的 NSVisualEffectView。
  ///
  /// 振动视图挂在主题框（contentView.superview）里、排在 contentView 下面，
  /// 而不是往 contentView 内部插 subview：后者的层级会和 Flutter 自己的渲染层抢，
  /// 换 container 又会和 contentViewController 冲突。
  private func enableBehindWindowVibrancy() {
    // DEBUG-BISECTION: 每个开关对应 /tmp/sw_glass/ 下的一个文件，文件存在即启用。
    // 用于一次编译后反复重启二分定位"点击全部失效"的成因，排查完删除。
    func on(_ key: String) -> Bool {
      FileManager.default.fileExists(atPath: "/tmp/sw_glass/\(key)")
    }

    if on("01_transparent") {
      isOpaque = false
      backgroundColor = .clear
      titlebarAppearsTransparent = true
      styleMask.insert(.fullSizeContentView)
    }

    if on("03_wantslayer") {
      // Flutter 的渲染层默认不透明，必须清掉底色才留得住 alpha
      contentViewController?.view.wantsLayer = true
      contentViewController?.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    guard let themeFrame = contentView?.superview else { return }

    if on("02_vibrancy") {
      let frame: NSView = on("06_nested") ? (contentView ?? themeFrame) : themeFrame
      let effectView: NSVisualEffectView = on("05_nohit")
        ? NoHitVisualEffectView(frame: frame.bounds)
        : NSVisualEffectView(frame: frame.bounds)
      effectView.autoresizingMask = [.width, .height]
      // 用 fullScreenUI 而不是语义上更贴切的 sidebar：实测（同一张桌面图、同样的
      // 采样框，玻璃 stdDev ÷ 裸桌面 stdDev 当作"透出结构比例"）sidebar 只有 0.11，
      // 背景基本被抹成一块浅板；fullScreenUI 是 0.30，且亮度均值和 sidebar 持平
      // （229 vs 229），所以透得更多却不牺牲文字对比度。
      // windowBackground / contentBackground / sheet / underPageBackground 实测完全不透。
      effectView.material = .fullScreenUI
      effectView.blendingMode = .behindWindow
      effectView.state = .followsWindowActiveState

      if on("06_nested") {
        frame.addSubview(effectView, positioned: .below, relativeTo: frame.subviews.first)
      } else {
        frame.addSubview(effectView, positioned: .below, relativeTo: contentView)
      }
    }

    if on("04_clearflutter") {
      // FlutterView 这一层自己的图层底色是不透明黑：Flutter 场景里 alpha=0 的像素
      // 不会露出振动层，而是露出这块黑，侧栏因此变成"压在黑底上的灰板"。
      // 必须在它建好之后再清一次；引擎可能晚于 awakeFromNib 才设这个底色，
      // 所以补两次延迟重设。
      clearFlutterSurfaceBackground()
      for delay in [0.5, 2.0] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
          self?.clearFlutterSurfaceBackground()
        }
      }
    }
  }

  private func clearFlutterSurfaceBackground() {
    guard let root = contentViewController?.view else { return }
    // FlutterView 没有导出到 Swift 侧，只能按 ObjC 类名匹配
    let flutterViewName = "FlutterView"
    func walk(_ view: NSView) {
      if NSStringFromClass(type(of: view)) == flutterViewName {
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
      }
      view.subviews.forEach(walk)
    }
    walk(root)
  }
}
