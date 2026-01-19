# 史莱姆工坊 - 安装包构建

## 📁 项目结构

```
SlimeWorks/
├── installer/               # 安装包构建目录
│   ├── build.bat           # 构建脚本
│   ├── installer.nsi        # NSIS安装脚本
│   ├── launcher.bat        # 应用启动器
│   └── output/             # 输出目录
│       └── SlimeWorks_Setup.exe  # 生成的安装包
├── lib/                    # Flutter源代码
├── windows/                # Windows平台代码
└── ...
```

## 🚀 构建安装包

```bash
cd installer
.\build.bat
```

生成的安装包位置：`installer\output\SlimeWorks_Setup.exe`
