import AVFoundation
import AVKit
import Flutter
import MediaPlayer
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 激活音频会话以支持后台播放
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ── 媒体会话 MethodChannel ────────────────────────────────────────────────
    let messenger = engineBridge.pluginRegistry.registrar(forPlugin: "SlimeWorksMediaSession")!.messenger()
    let channel = FlutterMethodChannel(name: "slime_works/media_session", binaryMessenger: messenger)

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setNowPlaying":
        let args = call.arguments as? [String: Any]
        let title = args?["title"] as? String ?? ""
        let artist = args?["artist"] as? String ?? ""
        let artworkBytes = args?["artwork"] as? FlutterStandardTypedData

        var info: [String: Any] = [
          MPMediaItemPropertyTitle: title,
          MPMediaItemPropertyArtist: artist,
          MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let bytes = artworkBytes, let image = UIImage(data: bytes.data) {
          info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // 注册远程控制命令（锁屏播放/暂停）
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        result(nil as AnyObject?)

      case "isPipSupported":
        if #available(iOS 14.0, *) {
          result(AVPictureInPictureController.isPictureInPictureSupported())
        } else {
          result(false)
        }

      case "enterPip":
        // media_kit 的视频通过原生 AVPlayerLayer 渲染；PiP 需由原生层控制。
        // 此处返回 false 表示需通过其他途径实现（如 media_kit_video 1.3+ 的内置 PiP）。
        result(FlutterError(code: "UNSUPPORTED",
                            message: "PiP 需要 media_kit_video 1.3+ 的内置支持",
                            details: nil))

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
