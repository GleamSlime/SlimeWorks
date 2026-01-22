/// FFmpeg库独立运行和调试入口
use ffmpeg_lib::{
    CompressConfig, ImageFormat, Preset, RecordConfig, ThumbnailConfig, VideoCodec,
    VideoCompressor, VideoFormat, VideoRecorder, VideoThumbnail,
};
use std::env;

fn print_usage() {
    println!("FFmpeg工具 - 使用方法:");
    println!();
    println!("录制视频:");
    println!("  ffmpeg_lib record <url> [options]");
    println!("    --output-dir <path>        输出目录");
    println!("    --format <ts|flv|mp4|mkv>  视频格式");
    println!("    --max-fps <number>         最大帧率");
    println!("    --max-duration <seconds>   最大录制时长");
    println!();
    println!("提取缩略图:");
    println!("  ffmpeg_lib thumbnail <url> [options]");
    println!("    --output-dir <path>        输出目录");
    println!("    --format <jpg|png|bmp>     图片格式");
    println!("    --quality <1-100>          图片质量");
    println!("    --width <pixels>           目标宽度");
    println!("    --height <pixels>          目标高度");
    println!("    --temp                     保存为临时文件");
    println!();
    println!("压缩视频:");
    println!("  ffmpeg_lib compress <path> [options]");
    println!("    --output-dir <path>        输出目录");
    println!("    --codec <h264|h265|vp9|av1> 视频编码器");
    println!("    --hw-accel                 使用硬件加速");
    println!("    --bitrate <kbps>           目标比特率");
    println!("    --crf <0-51>               CRF质量值");
    println!("    --preset <preset>          压缩预设");
    println!("    --width <pixels>           目标宽度");
    println!("    --height <pixels>          目标高度");
    println!("    --fps <number>             目标帧率");
    println!();
    println!("示例:");
    println!("  ffmpeg_lib record https://example.com/video.m3u8 --format ts --max-duration 60");
    println!("  ffmpeg_lib thumbnail video.mp4 --quality 90 --width 640");
    println!("  ffmpeg_lib compress input.mp4 --codec h264 --hw-accel --crf 23");
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        return;
    }

    let command = &args[1];

    match command.as_str() {
        "record" => {
            if args.len() < 3 {
                println!("错误: 缺少视频URL");
                return;
            }

            let url = &args[2];
            let mut config = RecordConfig {
                input_url: url.clone(),
                ..Default::default()
            };

            // 解析参数
            let mut i = 3;
            while i < args.len() {
                match args[i].as_str() {
                    "--output-dir" => {
                        if i + 1 < args.len() {
                            config.output_dir = args[i + 1].clone();
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--format" => {
                        if i + 1 < args.len() {
                            config.format = match args[i + 1].as_str() {
                                "ts" => VideoFormat::TS,
                                "flv" => VideoFormat::FLV,
                                "mp4" => VideoFormat::MP4,
                                "mkv" => VideoFormat::MKV,
                                _ => VideoFormat::MP4,
                            };
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--max-fps" => {
                        if i + 1 < args.len() {
                            config.max_fps = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--max-duration" => {
                        if i + 1 < args.len() {
                            config.max_duration = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    _ => i += 1,
                }
            }

            match VideoRecorder::new(config) {
                Ok(recorder) => match recorder.start_recording() {
                    Ok(path) => println!("成功: 录制完成，文件保存在: {}", path),
                    Err(e) => println!("错误: 录制失败: {}", e),
                },
                Err(e) => println!("错误: 创建录制器失败: {}", e),
            }
        }

        "thumbnail" => {
            if args.len() < 3 {
                println!("错误: 缺少视频路径或URL");
                return;
            }

            let url = &args[2];
            let mut config = ThumbnailConfig {
                input_url: url.clone(),
                ..Default::default()
            };

            // 解析参数
            let mut i = 3;
            while i < args.len() {
                match args[i].as_str() {
                    "--output-dir" => {
                        if i + 1 < args.len() {
                            config.output_dir = args[i + 1].clone();
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--format" => {
                        if i + 1 < args.len() {
                            config.format = match args[i + 1].as_str() {
                                "jpg" | "jpeg" => ImageFormat::JPEG,
                                "png" => ImageFormat::PNG,
                                "bmp" => ImageFormat::BMP,
                                _ => ImageFormat::JPEG,
                            };
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--quality" => {
                        if i + 1 < args.len() {
                            config.quality = args[i + 1].parse().unwrap_or(85);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--width" => {
                        if i + 1 < args.len() {
                            config.width = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--height" => {
                        if i + 1 < args.len() {
                            config.height = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--temp" => {
                        config.use_temp = true;
                        i += 1;
                    }
                    _ => i += 1,
                }
            }

            match VideoThumbnail::new(config) {
                Ok(thumbnail) => match thumbnail.extract_first_frame() {
                    Ok(path) => println!("成功: 缩略图生成完成，文件保存在: {}", path),
                    Err(e) => println!("错误: 生成缩略图失败: {}", e),
                },
                Err(e) => println!("错误: 创建缩略图提取器失败: {}", e),
            }
        }

        "compress" => {
            if args.len() < 3 {
                println!("错误: 缺少视频路径");
                return;
            }

            let path = &args[2];
            let mut config = CompressConfig {
                input_path: path.clone(),
                ..Default::default()
            };

            // 解析参数
            let mut i = 3;
            while i < args.len() {
                match args[i].as_str() {
                    "--output-dir" => {
                        if i + 1 < args.len() {
                            config.output_dir = args[i + 1].clone();
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--codec" => {
                        if i + 1 < args.len() {
                            config.codec = match args[i + 1].as_str() {
                                "h264" => VideoCodec::H264,
                                "h265" => VideoCodec::H265,
                                "vp9" => VideoCodec::VP9,
                                "av1" => VideoCodec::AV1,
                                _ => VideoCodec::H264,
                            };
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--hw-accel" => {
                        config.use_hardware_accel = true;
                        i += 1;
                    }
                    "--bitrate" => {
                        if i + 1 < args.len() {
                            config.bitrate = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--crf" => {
                        if i + 1 < args.len() {
                            config.crf = args[i + 1].parse().unwrap_or(23);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--width" => {
                        if i + 1 < args.len() {
                            config.width = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--height" => {
                        if i + 1 < args.len() {
                            config.height = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    "--fps" => {
                        if i + 1 < args.len() {
                            config.fps = args[i + 1].parse().unwrap_or(0);
                            i += 2;
                        } else {
                            i += 1;
                        }
                    }
                    _ => i += 1,
                }
            }

            match VideoCompressor::new(config) {
                Ok(compressor) => match compressor.compress() {
                    Ok(path) => println!("成功: 压缩完成，文件保存在: {}", path),
                    Err(e) => println!("错误: 压缩失败: {}", e),
                },
                Err(e) => println!("错误: 创建压缩器失败: {}", e),
            }
        }

        _ => {
            println!("错误: 未知命令 '{}'", command);
            print_usage();
        }
    }
}
