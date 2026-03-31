#!/bin/bash

# 杀掉残留的史莱姆工坊 macOS 实例（防止 "Failed to foreground app; open returned 1"）
pkill -f "史莱姆工坊" 2>/dev/null && echo "史莱姆工坊残留进程已清理" || echo "无残留应用进程"

# 杀掉僵尸 DDS 进程
pkill -f "dart.*dds" 2>/dev/null && echo "DDS 已清理" || echo "无僵尸 DDS 进程"

# 清理所有 iproxy 进程（iOS USB 转发，VS Code 会自动重建活跃的）
echo "清理前 iproxy 数量: $(ps aux | grep iproxy | grep -v grep | wc -l | tr -d ' ')"
pkill -f iproxy 2>/dev/null && echo "iproxy 已清理" || echo "无 iproxy 进程"

echo "清理完成，可以重新运行 flutter run"