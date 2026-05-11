use anyhow::Result;
use chrono::{DateTime, Utc};
use std::fs;
use std::path::{Component, Path, PathBuf};
use walkdir::{DirEntry, WalkDir};

use crate::types::{MediaItem, MediaKind};

fn is_hidden_entry(entry: &DirEntry) -> bool {
    is_hidden_path(entry.path())
}

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

fn file_name_without_extension(path: &Path) -> String {
    path.file_stem()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| {
            path.file_name()
                .and_then(|value| value.to_str())
                .unwrap_or("未命名媒体")
                .to_string()
        })
}

const MIN_IMAGE_FILE_SIZE: u64 = 10 * 1024;
const MIN_IMAGE_DIMENSION: u32 = 100;

fn build_media_item(collection_id: &str, order: i32, path: &Path) -> Result<MediaItem> {
    let metadata = fs::metadata(path)
        .map_err(|error| anyhow::anyhow!("Cannot read metadata for {:?}: {}", path, error))?;
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| anyhow::anyhow!("No extension: {:?}", path))?;
    let kind = MediaKind::from_extension(ext)
        .ok_or_else(|| anyhow::anyhow!("Unsupported extension '{}': {:?}", ext, path))?;
    let modified_at = metadata
        .modified()
        .map(DateTime::<Utc>::from)
        .unwrap_or_else(|_| Utc::now());

    if matches!(kind, MediaKind::Image) && metadata.len() < MIN_IMAGE_FILE_SIZE {
        return Err(anyhow::anyhow!(
            "Image too small ({}B < {}B): {:?}",
            metadata.len(),
            MIN_IMAGE_FILE_SIZE,
            path
        ));
    }

    let decodable = matches!(
        ext.to_ascii_lowercase().as_str(),
        "jpg" | "jpeg" | "jfif" | "png" | "gif" | "webp" | "bmp"
    );
    let (width, height) = if matches!(kind, MediaKind::Image) && decodable {
        image::image_dimensions(path)
            .ok()
            .map(|(w, h)| (Some(w), Some(h)))
    } else {
        None
    }
    .unwrap_or((None, None));

    if matches!(kind, MediaKind::Image) {
        if let (Some(w), Some(h)) = (width, height) {
            if w < MIN_IMAGE_DIMENSION || h < MIN_IMAGE_DIMENSION {
                return Err(anyhow::anyhow!(
                    "Image resolution too low ({}x{} < {}x{}): {:?}",
                    w,
                    h,
                    MIN_IMAGE_DIMENSION,
                    MIN_IMAGE_DIMENSION,
                    path
                ));
            }
        }
    }

    let duration_ms = if matches!(kind, MediaKind::Audio | MediaKind::Video) {
        read_duration_ms(path)
    } else {
        None
    };

    Ok(MediaItem {
        id: format!("media_{}", uuid::Uuid::new_v4()),
        collection_id: collection_id.to_string(),
        title: file_name_without_extension(path),
        file_path: path.to_string_lossy().to_string(),
        kind,
        file_size: metadata.len(),
        modified_at,
        width,
        height,
        duration_ms,
        order,
    })
}

/// Use ffprobe to get the media duration in milliseconds.
fn read_duration_ms(path: &Path) -> Option<u64> {
    let out = std::process::Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-show_entries",
            "format=duration",
            "-of",
            "default=noprint_wrappers=1:nokey=1",
            &path.to_string_lossy(),
        ])
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    let s = String::from_utf8_lossy(&out.stdout);
    let secs: f64 = s.trim().parse().ok()?;
    Some((secs * 1000.0) as u64)
}

pub struct MediaFolderScanner;

impl MediaFolderScanner {
    pub fn scan_media_directories<P: AsRef<Path>>(root: P) -> Result<Vec<PathBuf>> {
        let root = root.as_ref();
        println!("[media_scan] scan_media_directories: root={:?}", root);
        if !root.exists() {
            return Err(anyhow::anyhow!("Directory does not exist: {:?}", root));
        }
        if !root.is_dir() {
            return Err(anyhow::anyhow!("Path is not a directory: {:?}", root));
        }

        let mut directories = Vec::new();
        for entry in WalkDir::new(root)
            .follow_links(true)
            .into_iter()
            .filter_entry(|entry| !is_hidden_entry(entry))
        {
            let entry = match entry {
                Ok(value) => value,
                Err(error) => {
                    println!("Failed to read directory entry: {}", error);
                    continue;
                }
            };

            if !entry.file_type().is_dir() {
                continue;
            }

            let has_media = match fs::read_dir(entry.path()) {
                Ok(read_dir) => {
                    let found = read_dir.filter_map(Result::ok).any(|child| {
                        child.path().is_file() && Self::is_supported_media_file(&child.path())
                    });
                    println!("[media_scan] dir {:?} has_media={}", entry.path(), found);
                    found
                }
                Err(error) => {
                    println!(
                        "Skipping unreadable directory {:?}: {}",
                        entry.path(),
                        error
                    );
                    false
                }
            };

            if has_media {
                directories.push(entry.path().to_path_buf());
            }
        }

        directories.sort();
        directories.dedup();
        Ok(directories)
    }

    pub fn collect_media_items<P: AsRef<Path>>(
        collection_id: &str,
        folder: P,
        recursive: bool,
    ) -> Result<Vec<MediaItem>> {
        let folder = folder.as_ref();
        if !folder.exists() || !folder.is_dir() {
            return Err(anyhow::anyhow!("Path is not a directory: {:?}", folder));
        }

        let mut media_paths = Vec::new();
        if recursive {
            for entry in WalkDir::new(folder)
                .follow_links(true)
                .into_iter()
                .filter_entry(|entry| !is_hidden_entry(entry))
            {
                let entry = match entry {
                    Ok(value) => value,
                    Err(error) => {
                        println!("Failed to read media entry: {}", error);
                        continue;
                    }
                };
                let path = entry.path();
                if path.is_file() && Self::is_supported_media_file(path) {
                    media_paths.push(path.to_path_buf());
                }
            }
        } else {
            let read_dir = match fs::read_dir(folder) {
                Ok(rd) => rd,
                Err(error) => {
                    return Err(anyhow::anyhow!(
                        "Cannot read directory {:?}: {}",
                        folder,
                        error
                    ));
                }
            };
            for entry in read_dir {
                let entry = match entry {
                    Ok(value) => value,
                    Err(error) => {
                        println!("Failed to read media entry: {}", error);
                        continue;
                    }
                };
                let path = entry.path();
                if path.is_file() && !is_hidden_path(&path) && Self::is_supported_media_file(&path)
                {
                    media_paths.push(path);
                }
            }
        }

        media_paths.sort();
        println!(
            "[media_scan] collect_media_items: found {} media files in {:?}",
            media_paths.len(),
            folder
        );
        let mut items = Vec::with_capacity(media_paths.len());
        for (index, path) in media_paths.iter().enumerate() {
            match build_media_item(collection_id, index as i32, path) {
                Ok(item) => items.push(item),
                Err(error) => println!("Skipping media file {:?}: {}", path, error),
            }
        }
        Ok(items)
    }

    pub fn is_supported_media_file(path: &Path) -> bool {
        path.extension()
            .and_then(|value| value.to_str())
            .and_then(MediaKind::from_extension)
            .is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn make_temp_dir() -> TempDir {
        tempfile::Builder::new()
            .prefix("media_test_")
            .tempdir()
            .expect("create temp dir")
    }

    // ── is_supported_media_file ────────────────────────────────────────────

    #[test]
    fn supported_media_files_are_recognised() {
        for name in &["photo.jpg", "clip.mp4", "track.flac", "img.png"] {
            let path = PathBuf::from(name);
            assert!(
                MediaFolderScanner::is_supported_media_file(&path),
                "{name} should be recognised as a media file"
            );
        }
    }

    #[test]
    fn non_media_files_are_rejected() {
        for name in &["doc.pdf", "archive.zip", "script.sh", "README.md", "no_ext"] {
            let path = PathBuf::from(name);
            assert!(
                !MediaFolderScanner::is_supported_media_file(&path),
                "{name} should not be recognised as a media file"
            );
        }
    }

    // ── is_hidden_path ─────────────────────────────────────────────────────

    #[test]
    fn hidden_dot_paths_are_detected() {
        assert!(is_hidden_path(Path::new(".hidden")));
        assert!(is_hidden_path(Path::new("/some/dir/.hidden/file.jpg")));
        assert!(is_hidden_path(Path::new("._resource_fork.jpg")));
    }

    #[test]
    fn visible_paths_are_not_hidden() {
        assert!(!is_hidden_path(Path::new("visible")));
        assert!(!is_hidden_path(Path::new("/users/photos/vacation.jpg")));
    }

    // ── scan_media_directories ─────────────────────────────────────────────

    #[test]
    fn scan_finds_directory_with_images() {
        let root = make_temp_dir();
        let photo_dir = root.path().join("photos");
        fs::create_dir(&photo_dir).unwrap();
        fs::write(photo_dir.join("img.jpg"), b"fake-jpeg").unwrap();

        let dirs = MediaFolderScanner::scan_media_directories(root.path()).unwrap();
        assert!(
            dirs.contains(&photo_dir),
            "Expected photo_dir in results: {dirs:?}"
        );
    }

    #[test]
    fn scan_skips_directory_with_only_non_media_files() {
        let root = make_temp_dir();
        let docs_dir = root.path().join("docs");
        fs::create_dir(&docs_dir).unwrap();
        fs::write(docs_dir.join("readme.txt"), b"text").unwrap();

        let dirs = MediaFolderScanner::scan_media_directories(root.path()).unwrap();
        assert!(
            !dirs.contains(&docs_dir),
            "docs dir should not appear when it has no media files"
        );
    }

    #[test]
    fn scan_skips_hidden_directories() {
        let root = make_temp_dir();
        let hidden_dir = root.path().join(".hidden_photos");
        fs::create_dir(&hidden_dir).unwrap();
        fs::write(hidden_dir.join("photo.jpg"), b"fake").unwrap();

        let dirs = MediaFolderScanner::scan_media_directories(root.path()).unwrap();
        assert!(
            !dirs.contains(&hidden_dir),
            "Hidden directories should be skipped"
        );
    }

    #[test]
    fn scan_returns_error_for_nonexistent_path() {
        let result = MediaFolderScanner::scan_media_directories("/nonexistent/path/xyz");
        assert!(result.is_err(), "Expected an error for non-existent path");
    }

    #[test]
    fn scan_returns_error_for_file_path() {
        let root = make_temp_dir();
        let file_path = root.path().join("file.txt");
        fs::write(&file_path, b"data").unwrap();

        let result = MediaFolderScanner::scan_media_directories(&file_path);
        assert!(result.is_err(), "Expected error when path is a file");
    }

    // ── collect_media_items ────────────────────────────────────────────────

    #[test]
    fn collect_non_recursive_returns_only_direct_files() {
        let root = make_temp_dir();
        fs::write(root.path().join("top.jpg"), b"fake").unwrap();
        let sub = root.path().join("sub");
        fs::create_dir(&sub).unwrap();
        fs::write(sub.join("nested.jpg"), b"fake").unwrap();

        let items = MediaFolderScanner::collect_media_items("col-1", root.path(), false).unwrap();
        // Non-recursive: only direct children of root
        assert_eq!(
            items.len(),
            1,
            "Expected only top-level file, got {items:?}"
        );
        assert!(items[0].file_path.contains("top.jpg"));
    }

    #[test]
    fn collect_recursive_includes_nested_files() {
        let root = make_temp_dir();
        fs::write(root.path().join("top.jpg"), b"fake").unwrap();
        let sub = root.path().join("sub");
        fs::create_dir(&sub).unwrap();
        fs::write(sub.join("nested.png"), b"fake").unwrap();

        let items = MediaFolderScanner::collect_media_items("col-2", root.path(), true).unwrap();
        assert_eq!(items.len(), 2);
    }

    #[test]
    fn collect_assigns_correct_collection_id() {
        let root = make_temp_dir();
        fs::write(root.path().join("img.jpg"), b"fake").unwrap();

        let items = MediaFolderScanner::collect_media_items("my-col", root.path(), false).unwrap();
        assert_eq!(items[0].collection_id, "my-col");
    }

    #[test]
    fn collect_returns_error_for_nonexistent_path() {
        let result = MediaFolderScanner::collect_media_items("c", Path::new("/no/such/dir"), false);
        assert!(result.is_err());
    }
}
