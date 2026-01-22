# FFmpeg 库使用说明

## 📦 自动构建（推荐）

`ffmpeg-sys-next` 的 `build` 特性会**自动下载并编译 FFmpeg**，无需手动安装！

首次编译时间较长（约5-10分钟），但只需编译一次。

### ⚠️ 如果遇到网络问题

首次编译需要从 GitHub 下载 FFmpeg 源码，如果网络不稳定可以配置代理：

```bash
# macOS/Linux
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890

# 然后执行编译
cd rust/ffmpeg_lib
cargo build --lib
```

### ✅ 编译成功

```bash
cd rust/ffmpeg_lib
cargo build --lib  # 只编译库
cargo build        # 编译库和CLI工具
```

## 功能说明

```bash
cd rust/ffmpeg_lib
cargo build --release
```

## 测试

### 提取视频封面
```bash
cargo run --bin ffmpeg_lib thumbnail input.mp4 --quality 90 --width 1920 --height 1080
```

### 压缩视频
```bash
cargo run --bin ffmpeg_lib compress input.mp4 --codec h264 --crf 23 --preset medium
```

### 录制视频
```bash
cargo run --bin ffmpeg_lib record https://example.com/stream.m3u8 --format mp4 --duration 3600
```

## Flutter集成

在 Flutter 中通过 FFI 调用：

```dart
import 'package:slime_works/src/rust/api/ffmpeg.dart';

// 提取封面
final result = await extractVideoThumbnail(
  config: VideoThumbnailConfig(
    inputUrl: 'path/to/video.mp4',
    outputDir: '/tmp',
    format: 'jpg',
    quality: 90,
    width: 1920,
    height: 1080,
  ),
);

// 压缩视频
final output = await compressVideo(
  config: VideoCompressConfig(
    inputPath: 'input.mp4',
    outputDir: '/tmp',
    codec: 'h264',
    useHardwareAccel: true,
    crf: 23,
    preset: 'medium',
  ),
);
```

## 硬件加速

- **macOS**: VideoToolbox (h264_videotoolbox, hevc_videotoolbox)
- **Windows**: NVENC (h264_nvenc, hevc_nvenc)  
- **Linux**: VAAPI, NVENC

确保 FFmpeg 编译时启用了相应的硬件加速支持。
