use anyhow::Result;
use std::path::{Component, Path};
use std::sync::{Arc, Mutex};
use walkdir::WalkDir;

use crate::parser::NovelParser;
use crate::types::{NovelFormat, NovelMetadata, ScanProgress};

fn is_hidden_path(path: &Path) -> bool {
    path.components().any(|component| {
        if let Component::Normal(name) = component {
            if let Some(name) = name.to_str() {
                return name.starts_with('.') || name.starts_with("._");
            }
        }
        false
    })
}

/// 目录扫描器
pub struct DirectoryScanner {
    table_name: String,
    progress: Arc<Mutex<ScanProgress>>,
}

impl DirectoryScanner {
    pub fn new(table_name: String) -> Self {
        Self {
            table_name,
            progress: Arc::new(Mutex::new(ScanProgress {
                scanned: 0,
                found: 0,
                current_file: None,
            })),
        }
    }

    /// 扫描指定目录，递归查找所有 txt 和 epub 文件
    pub fn scan<P: AsRef<Path>>(&self, directory: P) -> Result<Vec<NovelMetadata>> {
        let directory = directory.as_ref();

        if !directory.exists() {
            return Err(anyhow::anyhow!("Directory does not exist: {:?}", directory));
        }

        if !directory.is_dir() {
            return Err(anyhow::anyhow!("Path is not a directory: {:?}", directory));
        }

        let mut novels = Vec::new();
        let walker = WalkDir::new(directory).follow_links(true);

        for entry in walker {
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    println!("Failed to read directory entry: {}", e);
                    continue;
                }
            };

            // 更新进度
            {
                let mut progress = self.progress.lock().unwrap();
                progress.scanned += 1;
                progress.current_file = Some(entry.path().to_string_lossy().to_string());
            }

            let path = entry.path();
            let file_type = entry.file_type();

            if is_hidden_path(path) {
                continue;
            }

            // 支持 Windows 下的 .epub 文件夹（包含 mimetype 文件）
            let is_valid_epub_dir = file_type.is_dir()
                && path.extension().and_then(|s| s.to_str()) == Some("epub")
                && path.join("mimetype").exists();

            // 只处理文件或有效的 epub 文件夹
            if !file_type.is_file() && !is_valid_epub_dir {
                continue;
            }

            // 检查文件扩展名
            if !Self::is_supported_file(path) && !is_valid_epub_dir {
                continue;
            }

            // 提取元数据
            match NovelParser::extract_metadata(path) {
                Ok(metadata) => {
                    println!("Found novel: {} at {:?}", metadata.title, path);

                    // 更新进度
                    {
                        let mut progress = self.progress.lock().unwrap();
                        progress.found += 1;
                    }

                    novels.push(metadata);
                }
                Err(e) => {
                    println!("Failed to extract metadata from {:?}: {}", path, e);
                }
            }
        }

        // 返回扫描结果（不再自动保存到数据库）
        Ok(novels)
    }

    /// 异步扫描（返回进度更新通道）
    pub async fn scan_async<P: AsRef<Path> + Send + 'static>(
        &self,
        directory: P,
    ) -> Result<Vec<NovelMetadata>> {
        let table_name = self.table_name.clone();
        let progress = self.progress.clone();

        tokio::task::spawn_blocking(move || {
            let scanner = DirectoryScanner {
                table_name,
                progress,
            };
            scanner.scan(directory)
        })
        .await?
    }

    /// 获取当前扫描进度
    pub fn get_progress(&self) -> ScanProgress {
        self.progress.lock().unwrap().clone()
    }

    /// 重置扫描进度
    pub fn reset_progress(&self) {
        let mut progress = self.progress.lock().unwrap();
        progress.scanned = 0;
        progress.found = 0;
        progress.current_file = None;
    }

    /// 检查文件是否为支持的格式
    fn is_supported_file(path: &Path) -> bool {
        path.extension()
            .and_then(|ext| ext.to_str())
            .and_then(NovelFormat::from_extension)
            .is_some()
    }

    /// 快速扫描获取所有支持的文件路径（不解析内容）
    /// 用于批量扫描时先获取文件列表
    pub fn scan_paths<P: AsRef<Path>>(&self, directory: P) -> Result<Vec<String>> {
        let directory = directory.as_ref();

        if !directory.exists() {
            return Err(anyhow::anyhow!("Directory does not exist: {:?}", directory));
        }

        if !directory.is_dir() {
            return Err(anyhow::anyhow!("Path is not a directory: {:?}", directory));
        }

        let mut paths = Vec::new();
        let walker = WalkDir::new(directory).follow_links(true);

        for entry in walker {
            let entry = match entry {
                Ok(e) => e,
                Err(e) => {
                    println!("Failed to read directory entry: {}", e);
                    continue;
                }
            };

            let path = entry.path();
            let file_type = entry.file_type();

            if is_hidden_path(path) {
                continue;
            }

            // 支持 Windows 下的 .epub 文件夹（包含 mimetype 文件）
            let is_valid_epub_dir = file_type.is_dir()
                && path.extension().and_then(|s| s.to_str()) == Some("epub")
                && path.join("mimetype").exists();

            // 只处理文件或有效的 epub 文件夹
            if !file_type.is_file() && !is_valid_epub_dir {
                continue;
            }

            // 检查文件扩展名
            if Self::is_supported_file(path) || is_valid_epub_dir {
                paths.push(path.to_string_lossy().to_string());
            }
        }

        Ok(paths)
    }

    /// 扫描单个文件
    pub fn scan_file<P: AsRef<Path>>(&self, file_path: P) -> Result<NovelMetadata> {
        let file_path = file_path.as_ref();

        if !file_path.exists() {
            return Err(anyhow::anyhow!("File does not exist: {:?}", file_path));
        }

        if is_hidden_path(file_path) {
            return Err(anyhow::anyhow!("Hidden file is ignored: {:?}", file_path));
        }

        // 支持 Windows 下的 .epub 文件夹（包含 mimetype 文件）
        let is_valid_epub_dir = file_path.is_dir()
            && file_path.extension().and_then(|s| s.to_str()) == Some("epub")
            && file_path.join("mimetype").exists();

        if !file_path.is_file() && !is_valid_epub_dir {
            return Err(anyhow::anyhow!(
                "Path is not a file or valid epub directory: {:?}",
                file_path
            ));
        }

        if !Self::is_supported_file(file_path) && !is_valid_epub_dir {
            return Err(anyhow::anyhow!("Unsupported file format: {:?}", file_path));
        }

        let metadata = NovelParser::extract_metadata(file_path)?;

        Ok(metadata)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::path::PathBuf;
    use uuid::Uuid;

    #[test]
    fn test_scanner() {
        // 创建临时测试目录
        let temp_dir = std::env::temp_dir().join(format!("novel_scanner_test_{}", Uuid::new_v4()));
        std::fs::create_dir_all(&temp_dir).unwrap();

        // 创建测试文件
        let test_txt = temp_dir.join("test.txt");
        let mut file = std::fs::File::create(&test_txt).unwrap();
        file.write_all(b"Test novel content").unwrap();

        // 扫描
        let scanner = DirectoryScanner::new("novels".to_string());
        let novels = scanner.scan(&temp_dir).unwrap();

        assert_eq!(novels.len(), 1);
        assert_eq!(novels[0].title, "test");

        // 清理
        std::fs::remove_dir_all(temp_dir).ok();
    }

    /// 建一棵用例独占的临时目录树（不落 DB，无需隔离 HOME）
    fn tmp_case(tag: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("novel_scanner_{}_{}", tag, Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// 写一本两章的 txt
    fn write_two_chapter_txt(dir: &Path, name: &str) -> PathBuf {
        let path = dir.join(format!("{}.txt", name));
        let mut f = std::fs::File::create(&path).unwrap();
        f.write_all("第一章 起\n正文一。\n第二章 承\n正文二。\n".as_bytes())
            .unwrap();
        path
    }

    #[test]
    fn scan_progress_counts_and_reset() {
        let dir = tmp_case("progress");
        write_two_chapter_txt(&dir, "甲书");
        write_two_chapter_txt(&dir, "乙书");
        // 不支持的扩展名：计入 scanned 但不计入 found
        std::fs::write(dir.join("说明.pdf"), b"%PDF-1.4").unwrap();
        // 隐藏文件同样被跳过
        std::fs::write(dir.join(".隐藏.txt"), b"hidden").unwrap();

        let scanner = DirectoryScanner::new("novels".to_string());
        let initial = scanner.get_progress();
        assert_eq!((initial.scanned, initial.found), (0, 0), "新建扫描器进度应为零");
        assert!(initial.current_file.is_none());

        let novels = scanner.scan(&dir).unwrap();
        assert_eq!(novels.len(), 2);
        let after = scanner.get_progress();
        assert_eq!(after.found, 2, "found 应等于成功提取元数据的书籍数");
        assert!(
            after.scanned >= 5,
            "scanned 应覆盖根目录 + 4 个条目，实际 {}",
            after.scanned
        );
        assert!(after.current_file.is_some(), "进度里应记录最后处理的文件");

        // 已知行为：进度是累加的，同一扫描器再扫一次不会自动清零
        scanner.scan(&dir).unwrap();
        let accumulated = scanner.get_progress();
        assert_eq!(accumulated.found, 4, "found 应在上次基础上累加");
        assert!(accumulated.scanned > after.scanned);

        // reset 才是唯一的清零入口
        scanner.reset_progress();
        let reset = scanner.get_progress();
        assert_eq!((reset.scanned, reset.found), (0, 0));
        assert!(reset.current_file.is_none());

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn scan_paths_lists_supported_and_epub_directories() {
        let dir = tmp_case("paths");
        let a = write_two_chapter_txt(&dir, "路径甲");
        std::fs::create_dir_all(dir.join("子目录")).unwrap();
        let b = write_two_chapter_txt(&dir.join("子目录"), "路径乙");
        std::fs::write(dir.join("图片.png"), b"png").unwrap();
        std::fs::write(dir.join(".隐藏.txt"), b"hidden").unwrap();
        // Windows 风格：解开的 .epub 目录（含 mimetype）
        std::fs::create_dir_all(dir.join("解开.epub")).unwrap();
        std::fs::write(dir.join("解开.epub").join("mimetype"), b"application/epub+zip").unwrap();

        let scanner = DirectoryScanner::new("novels".to_string());
        let mut paths = scanner.scan_paths(&dir).unwrap();
        paths.sort();
        assert!(paths.contains(&a.to_string_lossy().to_string()));
        assert!(paths.contains(&b.to_string_lossy().to_string()));
        assert!(
            paths.iter().any(|p| p.ends_with("解开.epub")),
            "含 mimetype 的 .epub 目录应被当作候选"
        );
        assert!(!paths.iter().any(|p| p.ends_with(".隐藏.txt")), "隐藏文件应被跳过");
        assert!(!paths.iter().any(|p| p.ends_with("图片.png")), "不支持的扩展名应被过滤");

        // 错误分支：目录不存在 / 传的是文件
        assert!(scanner.scan_paths(dir.join("不存在")).is_err());
        assert!(scanner.scan_paths(&a).is_err());

        // scan() 对同一目录不会因解开的 epub 目录解析失败而整体报错
        let novels = scanner.scan(&dir).unwrap();
        assert_eq!(novels.len(), 2, "无法解析的 .epub 目录只被跳过");

        std::fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn scan_file_rejects_bad_inputs() {
        let dir = tmp_case("scan_file");
        let good = write_two_chapter_txt(&dir, "单文件");
        let hidden = dir.join(".secret.txt");
        std::fs::write(&hidden, b"x").unwrap();
        let unsupported = dir.join("book.pdf");
        std::fs::write(&unsupported, b"%PDF").unwrap();

        let scanner = DirectoryScanner::new("novels".to_string());

        // 正常路径
        let meta = scanner.scan_file(&good).expect("合法 txt 应扫描成功");
        assert_eq!(meta.title, "单文件");
        assert_eq!(meta.file_path, good.to_string_lossy().to_string());

        assert!(scanner.scan_file(dir.join("查无此书.txt")).is_err(), "不存在应报错");
        assert!(scanner.scan_file(&hidden).is_err(), "隐藏文件应被拒绝");
        assert!(scanner.scan_file(&unsupported).is_err(), "不支持格式应被拒绝");
        assert!(scanner.scan_file(&dir).is_err(), "目录不是文件应被拒绝");
        assert!(scanner.scan_file(&dir.join("不存在.epub")).is_err(), "不存在的 epub 应被拒绝");
        // 解开的 .epub 目录：结构合法但内容无法解析 → 报解析错误而非 panic
        let fake_epub = dir.join("假.epub");
        std::fs::create_dir_all(&fake_epub).unwrap();
        std::fs::write(fake_epub.join("mimetype"), b"application/epub+zip").unwrap();
        assert!(scanner.scan_file(&fake_epub).is_err());

        std::fs::remove_dir_all(&dir).ok();
    }

    /// 不依赖 tokio macros feature 的简易 block_on
    fn block_on<F: std::future::Future>(f: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .build()
            .expect("构建 tokio 运行时失败")
            .block_on(f)
    }

    #[test]
    fn scan_async_matches_sync_and_propagates_error() {
        let dir = tmp_case("async");
        write_two_chapter_txt(&dir, "异步甲");
        write_two_chapter_txt(&dir, "异步乙");

        let scanner = DirectoryScanner::new("novels".to_string());
        let sync_result = scanner.scan(&dir).unwrap();
        let async_result = block_on(scanner.scan_async(dir.clone())).expect("异步扫描应成功");
        assert_eq!(async_result.len(), sync_result.len());
        let mut async_ids: Vec<String> = async_result.iter().map(|n| n.id.clone()).collect();
        let mut sync_ids: Vec<String> = sync_result.iter().map(|n| n.id.clone()).collect();
        async_ids.sort();
        sync_ids.sort();
        assert_eq!(async_ids, sync_ids, "异步与同步结果必须一致");
        // 异步扫描走的是同一份进度状态：同步 2 本 + 异步 2 本 = 累加 4
        assert_eq!(scanner.get_progress().found, 4);

        // 目录不存在 → 异步同样返回 Err
        let missing = dir.join("根本没有这层");
        assert!(block_on(scanner.scan_async(missing)).is_err());

        std::fs::remove_dir_all(&dir).ok();
    }
}
