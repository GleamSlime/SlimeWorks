/// 格式化文件大小
/// 例如：1024 -> 1.00 KB
/// [bytes] 文件大小，单位为字节
String formatFileSize(BigInt bytes) {
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var suffixIndex = 0;
  while (size >= 1024 && suffixIndex < suffixes.length - 1) {
    size /= 1024;
    suffixIndex++;
  }
  return '${size.toStringAsFixed(2)} ${suffixes[suffixIndex]}';
}
