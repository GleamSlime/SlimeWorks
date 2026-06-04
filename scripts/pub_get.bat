@echo off
REM 固定 pub 依赖源为 https://pub.dev，避免不同设备环境变量导致 lock 文件变更
set PUB_HOSTED_URL=https://pub.dev
set FLUTTER_STORAGE_BASE_URL=https://storage.googleapis.com
flutter pub get %*
