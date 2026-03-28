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

fn build_media_item(collection_id: &str, order: i32, path: &Path) -> Result<MediaItem> {
    let metadata = fs::metadata(path)?;
    let ext = path
        .extension()
        .and_then(|value| value.to_str())
        .ok_or_else(|| anyhow::anyhow!("Unsupported media file: {:?}", path))?;
    let kind = MediaKind::from_extension(ext)
        .ok_or_else(|| anyhow::anyhow!("Unsupported media file: {:?}", path))?;
    let modified_at = metadata
        .modified()
        .map(DateTime::<Utc>::from)
        .unwrap_or_else(|_| Utc::now());

    let (width, height) = if matches!(kind, MediaKind::Image) {
        image::image_dimensions(path).ok().map(|(w, h)| (Some(w), Some(h)))
    } else {
        None
    }
    .unwrap_or((None, None));

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
        duration_ms: None,
        order,
    })
}

pub struct MediaFolderScanner;

impl MediaFolderScanner {
    pub fn scan_media_directories<P: AsRef<Path>>(root: P) -> Result<Vec<PathBuf>> {
        let root = root.as_ref();
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
                    log::warn!("Failed to read directory entry: {}", error);
                    continue;
                }
            };

            if !entry.file_type().is_dir() {
                continue;
            }

            let has_media = fs::read_dir(entry.path())?
                .filter_map(Result::ok)
                .any(|child| child.path().is_file() && Self::is_supported_media_file(&child.path()));

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
                        log::warn!("Failed to read media entry: {}", error);
                        continue;
                    }
                };
                let path = entry.path();
                if path.is_file() && Self::is_supported_media_file(path) {
                    media_paths.push(path.to_path_buf());
                }
            }
        } else {
            for entry in fs::read_dir(folder)? {
                let entry = match entry {
                    Ok(value) => value,
                    Err(error) => {
                        log::warn!("Failed to read media entry: {}", error);
                        continue;
                    }
                };
                let path = entry.path();
                if path.is_file() && !is_hidden_path(&path) && Self::is_supported_media_file(&path) {
                    media_paths.push(path);
                }
            }
        }

        media_paths.sort();
        let mut items = Vec::with_capacity(media_paths.len());
        for (index, path) in media_paths.iter().enumerate() {
            items.push(build_media_item(collection_id, index as i32, path)?);
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