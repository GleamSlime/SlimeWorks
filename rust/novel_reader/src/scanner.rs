use anyhow::Result;
use std::path::Path;
use std::sync::{Arc, Mutex};
use walkdir::WalkDir;

use crate::parser::NovelParser;
use crate::types::{NovelFormat, NovelMetadata, ScanProgress};

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
                    log::warn!("Failed to read directory entry: {}", e);
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
                    log::info!("Found novel: {} at {:?}", metadata.title, path);

                    // 更新进度
                    {
                        let mut progress = self.progress.lock().unwrap();
                        progress.found += 1;
                    }

                    novels.push(metadata);
                }
                Err(e) => {
                    log::warn!("Failed to extract metadata from {:?}: {}", path, e);
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
                    log::warn!("Failed to read directory entry: {}", e);
                    continue;
                }
            };

            let path = entry.path();
            let file_type = entry.file_type();

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
}
