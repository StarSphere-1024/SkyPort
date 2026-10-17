# SkyPort

[![Build Status](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml/badge.svg)](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml)
[![License: AGPL v3](https://img.shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

一款基于 Rust + Flutter 的跨平台串口调试助手，专注桌面平台的高性能串口收发与调试体验，支持 ANSI 转义序列渲染和灵活的数据处理模式。

**v2.0.0 已重构为 Rust + Flutter 全新实现**：Rust 核心负责串口生命周期、数据收发、配置持久化、日志、统计与调度；Flutter 负责桌面界面和交互，通过 `flutter_rust_bridge` 与 Rust 核心通信。

## 📸 界面预览

<img src="static/images/main_interface.png" alt="SkyPort 主界面" width="75%">

## ✨ 功能特性

*   **串口操作**
    *   自动扫描和列出可用串口。
    *   连接和断开串口设备，连接状态与收发统计显示在底部状态栏。
    *   可配置波特率、数据位、停止位和校验位，常用参数会被记忆并自动恢复。
    *   支持智能重连，当设备意外断开时自动尝试重新连接。

*   **数据收发**
    *   支持 ASCII 和 Hex 两种格式发送和接收数据。
    *   支持 ANSI 转义序列的解析和渲染，用于彩色日志输出。
    *   采用**统一流式缓冲架构**，自动处理数据包边界：
    *   每条记录可选显示时间戳，并区分显示"发送"和"接收"记录。
    *   可配置日志缓冲区大小（16-512MB，默认128MB）来控制内存使用。

*   **发送配置**
    *   支持 Hex 发送和文本发送模式切换。
    *   文本发送可选择是否自动追加换行，以及换行风格（LF / CR / CRLF）。
    *   支持自动发送和历史发送数据记忆。

*   **界面与体验**
    *   基于 Material Design 3，左右双栏布局：左侧为配置与发送控制，右侧为数据日志与输入区。
    *   支持浅色/深色/跟随系统主题切换。
    *   多种预设主题色可选。
    *   支持串口自动重连。
    *   可启用/禁用 ANSI 转义序列渲染。
    *   窗口尺寸、位置和串口偏好会被记忆，提升日常使用效率。

*   **跨平台**
    *   当前支持 Windows 和 Linux 桌面平台；macOS 项目文件存在，但暂不视为已支持平台。

## 📥 下载安装

当前源码版本为 **v2.0.0**，应用版本由 `app/pubspec.yaml` 统一管理。

你可以从 [GitHub Releases](https://github.com/StarSphere-1024/SkyPort/releases) 页面下载最新版本的安装包。

## 🚀 如何构建

### 环境准备
安装满足 `app/pubspec.yaml` 的 Flutter/Dart SDK、Rust stable 和对应桌面平台编译工具链。Linux 需要 GTK3、`pkg-config` 和 libudev 开发包（Debian/Ubuntu：`libgtk-3-dev libudev-dev`）。核心可单独构建，不需要 Flutter SDK。

### 构建步骤

1.  **克隆仓库**
    ```bash
    git clone https://github.com/StarSphere-1024/SkyPort.git
    cd SkyPort
    ```

2.  **验证核心并获取 Flutter 依赖**
    从仓库根目录执行：
    ```bash
    cargo test --locked -p skyport_core
    cd app
    flutter pub get
    ```

3.  **运行应用（桌面）**
    在 `app/` 目录执行：
    ```bash
    flutter run -d windows  # Windows
    flutter run -d linux    # Linux
    ```

4.  **构建发布版本**
    在 `app/` 目录、对应宿主机及其平台工具链上执行：
    ```bash
    flutter build windows --release  # Windows host
    flutter build linux --release    # Linux host
    ```
    macOS 项目文件保留，但未接入本次 native 打包和验收，不在当前正式支持范围内。

Flutter 的 Linux/Windows CMake 构建会调用 Cargo，并将 bridge 动态库放入最终 bundle。不要只复制可执行文件；Linux 库位于 `lib/libskyport_flutter_bridge.so`，Windows 库与 `.exe` 相邻。

从仓库根目录运行检查：

```bash
tool/test_quiet.sh
python3 scripts/pty_ui_smoke.py                  # Linux，真实 bridge + UI + 伪终端
python3 scripts/package_smoke.py <bundle或发行包> # 验证打包后的真实加载与生命周期
```

有显示环境时可直接运行 smoke；无显示的 Linux CI 使用 `xvfb-run -a`。支持检查目录、deb、rpm、AppImage 和 Windows portable zip。Windows 安装程序须先安装到隔离目录，再检查该目录；物理串口和不同架构仍需各自验收。

CI 的 Rust 核心测试覆盖 Linux x64、Linux ARM64 和 Windows；Linux PTY 测试的 C 字符缓冲区使用 `libc::c_char`，避免不同架构的字符符号类型差异。Flutter 检查先运行 `flutter analyze`，通过后才执行测试、PTY UI smoke 和覆盖率门禁。

修改 bridge API 后，从仓库根目录安装生成器，再进入 `app/` 生成绑定：

```bash
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cd app
flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml
```

架构与队列、日志、迁移合同见 [Rust 核心设计](docs/rust-serial-kernel-design.md)。核心保存版本化 `config.json`；Flutter 只保存主题、显示等前端偏好，并在 Rust 成功写入新配置后标记旧串口偏好迁移完成。

## 📦 主要依赖

*   [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) (v3.0.3): 用于状态管理。
*   [serialport](https://docs.rs/serialport) (Cargo 锁定 4.10.1): 独立 Rust 核心的串口通信。
*   [flutter_rust_bridge](https://pub.dev/packages/flutter_rust_bridge) (v2.13.0): Flutter 的类型化 native 接入，核心不依赖它。
*   [shared_preferences](https://pub.dev/packages/shared_preferences) (v2.5.3): 前端显示偏好及旧配置的一次性读取。
*   [ansi_escape_codes](https://pub.dev/packages/ansi_escape_codes) (v4.0.1): 用于 ANSI 转义序列解析和渲染。
*   [flutter_localizations](https://api.flutter.dev/flutter/flutter_localizations/flutter_localizations-library.html) + [intl](https://pub.dev/packages/intl) (v0.20.2): 用于国际化支持。

## 🤝 贡献

欢迎贡献！请遵循以下步骤：

1. Fork 本仓库
2. 创建你的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交你的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

### 开发环境设置
- 安装满足 `app/pubspec.yaml` 要求的 Flutter SDK（Dart SDK `>=3.10.0`）。
- 从仓库根目录执行 `cargo test --locked -p skyport_core`；从 `app/` 执行 `flutter pub get`。
- 从 `app/` 使用 `flutter run -d linux` 或在 Windows 宿主机上使用 `flutter run -d windows`。

## 🐛 问题报告

如果你发现 bug 或有功能建议，请在 [Issues](https://github.com/StarSphere-1024/SkyPort/issues) 页面提交。

## 📄 许可证

本项目采用 [GNU Affero General Public License v3.0](LICENSE) 许可证。

## 👤 作者

**StarSphere-1024** - [GitHub](https://github.com/StarSphere-1024)

---

*如果这个项目对你有帮助，请给它一个 ⭐！*
