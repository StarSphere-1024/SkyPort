# SkyPort: 串口调试助手项目设计文档

**版本:** 1.0  
**日期:** 2025年11月4日

## 1. 项目概述

### 1.1 项目简介
**SkyPort** 是一款基于 Flutter 开发的现代化、跨平台串口调试助手。它旨在为嵌入式开发者、硬件工程师及电子爱好者提供一个界面美观、操作流畅、功能专注的串口通信工具。

### 1.2 设计目标
*   **现代化 UI/UX:** 严格遵循 Google 的 Material Design 3 (M3) 设计规范，提供清爽、直观且富有呼吸感的用户界面。
*   **跨平台:** 一套代码库，原生编译到 Windows, macOS, 和 Linux 桌面平台。
*   **性能可靠:** 利用 `flutter_libserialport` 通过 FFI 调用原生 C 库，确保串口通信的低延迟和高稳定性。
*   **状态可预测:** 采用 Riverpod 进行状态管理，确保应用状态的一致性和可维护性。

## 2. 技术栈与架构

### 2.1 核心技术栈
*   **UI 框架:** Flutter 3.x
*   **串口通信库:** `flutter_libserialport`
*   **状态管理:** `flutter_riverpod`
*   **设计语言:** Material Design 3

### 2.2 应用架构
应用将遵循分层架构，将 UI、状态管理和业务逻辑（服务）清晰地分离开来。

*   **UI 层 (Widgets):** 负责界面的展示和用户交互的响应。UI 组件将是“哑”的，仅负责监听状态变化并渲染，以及将用户事件转发给状态管理层。
*   **状态管理层 (Riverpod Providers):** 作为 UI 和服务层之间的桥梁。它负责管理和组合应用状态，例如串口配置、连接状态、收发数据日志等。
*   **服务层 (Services):** 封装核心的业务逻辑。例如，创建一个 `SerialPortService` 来封装所有与 `flutter_libserialport` 库的直接交互。

### 2.3 主要 Riverpod Providers 规划

* **`availablePortsProvider` (FutureProvider<List<String>>):** 异步获取并缓存当前可用的串口列表。
* **`serialConfigProvider` (StateNotifierProvider<SerialConfig?>):** 管理串口参数配置（端口名、波特率、数据位、校验位、停止位）。
* **`serialConnectionProvider` (StateNotifierProvider<SerialConnection>):** 管理连接生命周期（连接/断开/进程中）与端口对象、读写监听、字节统计。
* **`dataLogProvider` (StateNotifierProvider<List<LogEntry>>):** 存储所有收/发数据条目，驱动右侧数据显示列表，支持接收端节流合并。
* **`uiSettingsProvider` (StateNotifierProvider<UiSettings>):** 管理界面偏好，如十六进制显示（hexDisplay）与十六进制发送（hexSend）。
* **`errorProvider` (StateNotifierProvider<String?>):** 暴露最近的错误消息（端口占用、打开超时、发送异常等），UI 层通过 SnackBar 或状态栏展示。

## 3. UI/UX 设计规范

### 3.1 布局 (Layout)
*   **主结构:** 采用固定的两栏式响应式布局。
    *   **左侧控制面板:** 固定宽度 `350dp`，包含所有配置项。
    *   **右侧主区域:** 占据所有剩余空间，用于数据显示和输入。
*   **间距 (Spacing):** 严格遵循 8dp 栅格系统。
    *   主 Panel 之间、Card 之间的标准间距为 `16dp`。
    *   Card 内部的内边距 (`Padding`) 统一为 `16dp`。
    *   元素之间的标准间距为 `8dp` 或 `12dp`。

### 3.2 颜色与主题 (Color & Theming)
*   **主题生成:** 采用 `ColorScheme.fromSeed()` 动态生成完整的 M3 颜色主题。
    *   **种子颜色 (Seed Color):** 选取一个品牌主色（例如: `Colors.blue` 或 `Colors.deepPurple`）。
    *   **亮/暗模式:** 自动支持并适配系统的亮/暗模式。
*   **组件颜色:** 所有组件（按钮、卡片、背景等）的颜色均直接取自 `Theme.of(context).colorScheme`，禁止硬编码颜色值。

### 3.3 字体 (Typography)
*   使用 `Theme.of(context).textTheme` 中预定义的字体样式来建立视觉层级。
    *   **`titleLarge`:** 用于 Card 的标题。
    *   **`bodyMedium`:** 用于表单标签和普通文本。
    *   **`labelLarge`:** 用于按钮文本。
    *   **`monospace` (自定义):** 用于数据显示区，确保字节对齐。

## 4. 组件详细设计

### 4.1 左侧控制面板 (Control Panel)

| 区域         | 组件         | 类型                           | 样式/行为                                                                                   |
| :----------- | :----------- | :----------------------------- | :------------------------------------------------------------------------------------------ |
| **串口设置** | 容器         | `FilledCard` 或 `OutlinedCard` | 内边距 `16dp`。                                                                             |
|              | 端口名       | `DropdownMenu`                 | 数据源: `availablePortsProvider`。禁用: 串口连接后。                                        |
|              | 波特率等     | `DropdownMenu`                 | 预设值列表。禁用: 串口连接后。                                                              |
|              | 打开/关闭    | `FilledButton`                 | **未连接时:** 文本 "打开"。 **连接时:** 文本 "关闭", `backgroundColor: colorScheme.error`。 |
| **接收设置** | 容器         | `FilledCard` 或 `OutlinedCard` | 内边距 `16dp`。                                                                             |
|              | 十六进制显示 | `SwitchListTile`               | 标题 "十六进制显示"。                                                                       |
|              | 清空接收区   | `OutlinedButton`               | 文本 "清空"。                                                                               |
| **发送设置** | 容器         | `FilledCard` 或 `OutlinedCard` | 内边距 `16dp`。                                                                             |
|              | 十六进制发送 | `SwitchListTile`               | 标题 "十六进制发送"。                                                                       |

### 4.2 右侧主区域 (Main Area)

| 区域           | 组件     | 类型               | 样式/行为                                                                                     |
| :------------- | :------- | :----------------- | :-------------------------------------------------------------------------------------------- |
| **数据显示区** | 容器     | `Card`             | 填充父容器，内边距 `0`。                                                                      |
|                | 滚动条   | `Scrollbar`        | 包裹 `ListView`。                                                                             |
|                | 数据列表 | `ListView.builder` | 数据源: `dataLogProvider`。使用 `monospace` 字体。收/发数据条目使用不同背景色或对齐方式区分。 |
| **数据输入区** | 容器     | `Padding`          | `padding: EdgeInsets.all(16.0)`。                                                             |
|                | 输入框   | `TextField`        | `decoration`: 带有 `labelText: '输入发送内容...'`。                                           |
|                | 发送按钮 | `FilledButton`     | 文本 "发送"，`icon: Icons.send`。禁用: 串口未连接时。                                         |

### 4.3 底部状态栏 (Status Bar)

| 区域         | 组件        | 类型                                                                                   | 样式/行为                                                                                                                                               |
| :----------- | :---------- | :------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **容器**     | `Container` | `height: 32dp`，`border: Border(top: BorderSide(color: colorScheme.outlineVariant))`。 |
| **状态信息** | `Row`       | `padding: EdgeInsets.symmetric(horizontal: 16.0)`。                                    |
|              | 连接状态    | `Row` (含 `Icon` 和 `Text`)                                                            | **未连接:** `Icon(Icons.circle, color: Colors.grey)` + `Text("未连接")`。 **连接时:** `Icon(Icons.circle, color: Colors.green)` + `Text("COM3@9600")`。 |
|              | 字节统计    | `Text`                                                                                 | `Spacer()` 将其推到最右侧。格式: `Rx: 1024                                                                                                              | Tx: 512`。 |

## 5. 数据流与错误处理

### 5.1 核心数据流
1.  **打开串口:**
    *   UI 调用 `ref.read(serialConnectionProvider.notifier).connect(settings)`。
    *   `Notifier` 从 `serialConfigProvider` 获取配置。
    *   `Notifier` 调用 `SerialPortService` 的 `open()` 方法。
    *   成功后，更新自身状态为 "connected"，并启动数据监听。
    *   失败后，抛出异常。
2.  **接收数据:**
    *   `SerialPortService` 的 `SerialPortReader` 监听到数据流。
    *   `Service` 将 `Uint8List` 数据通知给 `serialConnectionProvider`。
    *   `serialConnectionProvider` 更新 Rx 字节数，并将数据（原始及格式化后的字符串）传递给 `dataLogProvider`。
    *   `dataLogProvider` 将新数据条目添加到列表中，UI 自动刷新。
3.  **发送数据:**
    *   UI 调用 `ref.read(serialConnectionProvider.notifier).send(data)`。
    *   `Notifier` 根据 `uiSettingsProvider` 的 "hexSend" 状态，对数据进行预处理（字符串转 Hex 字节等）。
    *   `Notifier` 调用 `SerialPortService` 的 `write()` 方法，并更新 Tx 字节数。
    *   `Notifier` 将已发送的数据添加到 `dataLogProvider` 中。

### 5.2 错误处理
*   **串口打开失败:** (如端口被占用) `SerialPortService` 捕获 `SerialPortError`，`Notifier` 将错误状态暴露给 UI。UI 层通过 `SnackBar` 或 `AlertDialog` 显示友好的错误信息。
*   **读写错误/设备断开:** 在数据读写循环中进行 `try-catch`。一旦发生错误，立即更新连接状态为 "disconnected"，并弹出 `SnackBar` 提示用户 "设备已断开或读写错误"。

## 6. 未来规划 (Roadmap)
*   **V1.1:** 增加数据日志保存到文件的功能。
*   **V1.2:** 支持自定义波特率和其他高级串口参数（流控等）。
*   **V1.3:** 增加简单的图表绘制功能，可视化接收到的数据。
*   **V2.0:** 引入脚本支持（如 Lua 或 JavaScript），实现自动化测试和发送。

---