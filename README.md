# SkyPort

[![Build Status](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml/badge.svg)](https://github.com/StarSphere-1024/SkyPort/actions/workflows/release.yml)

一款使用 Flutter 构建的跨平台串口调试助手。

## ✨ 功能

*   **串口操作**:
    *   自动扫描和列出可用串口。
    *   连接和断开串口设备。
    *   可配置波特率、数据位、停止位和校验位。

## 🚀 使用方法

本仓库已配置 GitHub Actions，可在推送新版本标签时自动构建并发布适用于多个平台的安装包。

1.  提交你的代码更改:
    ```bash
    git commit -m "Your amazing feature"
    ```

2.  创建一个新的 Git 标签:
    ```bash
    git tag v1.0.1
    ```

3.  将标签推送到 GitHub:
    ```bash
    git push origin v1.0.1
    ```

推送标签后，GitHub Actions 将会自动开始构建，并创建一个新的 Release。

## 📥 下载

你可以从 [GitHub Releases](https://github.com/StarSphere-1024/SkyPort/releases) 页面下载最新版本的安装包。

*   **数据收发**:
    *   支持 ASCII 和 Hex 格式发送和接收数据。
    *   时间戳记录。
    *   清空接收区。
*   **跨平台**:
    *   支持 Windows、macOS 和 Linux 桌面平台。

## 🚀 开始使用

1.  **克隆仓库**
    ```bash
    git clone https://github.com/StarSphere-1024/SkyPort.git
    cd SkyPort
    ```

2.  **获取依赖**
    ```bash
    flutter pub get
    ```

3.  **运行应用**
    ```bash
    flutter run
    ```

## 📦 主要依赖

*   [flutter_riverpod](https://pub.dev/packages/flutter_riverpod): 用于状态管理。
*   [flutter_libserialport](https://pub.dev/packages/flutter_libserialport): 用于串口通信。

---

*此项目是作为学习和演示目的创建的。*
