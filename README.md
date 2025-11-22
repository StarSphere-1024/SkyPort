# SkyPort

[![Build Status](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml/badge.svg)](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml)

一款使用 Flutter 构建的跨平台串口调试助手，专注桌面平台的高性能串口收发与调试体验。

## ✨ 功能

*   **串口操作**
    *   自动扫描和列出可用串口。
    *   连接和断开串口设备，连接状态与收发统计显示在底部状态栏。
    *   可配置波特率、数据位、停止位和校验位，常用参数会被记忆并自动恢复。

*   **数据收发**
    *   支持 ASCII 和 Hex 两种格式发送和接收数据。
    *   支持“按帧”和“按行”两种接收模式：
        *   按帧模式：在短时间窗口内合并连续数据，适合二进制/高频数据流；
        *   按行模式：按换行符拆分，适合日志类文本输出。
    *   每条记录可选显示时间戳，并区分显示“发送”和“接收”记录。
    *   一键清空接收区。

*   **发送配置**
    *   支持 Hex 发送和文本发送模式切换。
    *   文本发送可选择是否自动追加换行，以及换行风格（LF / CR / CRLF）。

*   **界面与体验**
    *   基于 Material Design 3，左右双栏布局：左侧为配置与发送控制，右侧为数据日志与输入区。
    *   支持浅色/深色主题。
    *   窗口尺寸、位置和串口偏好会被记忆，提升日常使用效率。

*   **跨平台**
    *   当前支持 Windows 和 Linux 桌面平台（MacOS 与 Android 在规划中）。

## 📥 下载

你可以从 [GitHub Releases](https://github.com/StarSphere-1024/SkyPort/releases) 页面下载最新版本的安装包。

## 🚀 如何构建

1.  **克隆仓库**
    ```bash
    git clone https://github.com/StarSphere-1024/SkyPort.git
    cd SkyPort
    ```

2.  **获取依赖**
    ```bash
    flutter pub get
    ```

3.  **运行应用（桌面）**
    ```bash
    flutter run -d windows
    ```

## 📦 主要依赖

*   [flutter_riverpod](https://pub.dev/packages/flutter_riverpod): 用于状态管理。
*   [flutter_libserialport](https://pub.dev/packages/flutter_libserialport): 用于串口通信。
*   [shared_preferences](https://pub.dev/packages/shared_preferences): 用于记忆用户偏好和串口参数。
*   [window_manager](https://pub.dev/packages/window_manager): 用于桌面端窗口管理。

---

*此项目是作为学习和演示目的创建的。*
