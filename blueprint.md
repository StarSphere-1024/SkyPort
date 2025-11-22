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
* **主题生成:** 采用 `ColorScheme.fromSeed()` 动态生成完整的 M3 颜色主题。
    * **种子颜色 (Seed Color):** 选取一个品牌主色（例如: `Colors.blue` 或 `Colors.deepPurple`）。
    * **亮/暗模式:** 自动支持并适配系统的亮/暗模式。
* **组件颜色:** 所有组件（按钮、卡片、背景等）的颜色均直接取自 `Theme.of(context).colorScheme`，禁止硬编码颜色值（除了临时语义色，可通过扩展后期统一）。

### 3.3 卡片层级与风格 (Card Variants)
层级策略：
* **FilledCard:** 需要操作与高关注度的控制区域（串口设置 / 接收设置 / 发送设置 / 发送输入区）。
* **OutlinedCard:** 大体量、滚动型展示（日志列表）。
* **默认 Card:** 备用场景，当前未使用。

### 3.4 字体 (Typography)
* 使用 `Theme.of(context).textTheme` 建立层级：
    * `titleLarge`: 区块标题
    * `bodyMedium`: 常规正文 / 标签
    * `labelLarge`: 按钮文本
    * `code` (扩展): 等宽日志/Hex 显示（通过 `TextTheme` 扩展 `textTheme.code`，底层先用系统 `monospace`，后续可替换 `JetBrainsMono` / `SourceCodePro`）。

### 3.5 日志滚动与加载 (Log Scroll & Paging)
* **自动滚动:** 仅在用户位于底部时新数据才触发平滑滚动；用户向上浏览历史时保持位置不变。
* **增量加载:** 初始显示最近 N 条（例如 100 条），后续可根据需要扩展“加载更多”/分页能力，避免一次性构建过长列表。
* **接收合并节流:** 在“按帧模式”下，接收数据在可配置时间窗口（默认 20ms）内合并到同一条 `received` 记录，降低 UI rebuild 频次；发送数据不合并。
* **按行接收模式:** 在“文本模式”下可选择按行接收（基于 `\n`/`\r\n` 拆分），适合日志类输出，单行结束后立即落一条记录。

### 3.6 错误提示与状态分离 (Errors & Status Separation)
* 瞬时错误（打开失败 / 写入失败 / 端口断开）→ SnackBar 一次性提示，并在展示后清空错误状态。
* 状态栏仅显示持久状态（连接态 + Rx/Tx 统计）。
* 颜色语义：
    * 已连接：绿色小圆点
    * 未连接：灰色小圆点
    * 过渡（连接中/断开中）：`colorScheme.tertiary`

### 3.7 无可用端口策略 (No Ports Available)
* 无端口时串口配置保持 `null`，端口下拉呈禁用态并显示“未发现端口”。
* 不抛出异常，等待后续端口出现自动填充首个值。
* 可在后续版本加入“刷新”按钮或系统热插拔监听。

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
| **数据显示区** | 容器     | `OutlinedCard`     | 填充父容器，内边距 `0`。                                                                      |
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
    *   UI 调用 `ref.read(serialConnectionProvider.notifier).connect()`。
    *   `Notifier` 从 `serialConfigProvider` 获取配置（包括最近一次使用的端口和串口参数，如果存在）。
    *   `Notifier` 调用 `SerialPortService` 的 `open()` 方法，并在超时/失败时区分不同异常类型。
    *   成功后，更新自身状态为 `ConnectionStatus.connected`，并启动数据监听。
    *   失败后，将错误信息写入 `errorProvider`，由 UI 以 SnackBar 展示。
2.  **接收数据:**
    *   `SerialPortService` 的 `SerialPortReader` 监听到数据流。
    *   `Service` 将 `Uint8List` 数据通知给 `serialConnectionProvider`。
    *   `serialConnectionProvider` 更新 Rx 字节数，并把原始字节转交 `dataLogProvider`。
    *   `dataLogProvider` 根据当前 UI 设置选择：
        * **按帧模式（block）：** 在节流窗口内将多次接收合并为一条记录，并更新时间戳；
        * **按行模式（line）：** 以行结束符为界拆分成多条 `received` 记录。
3.  **发送数据:**
    *   UI 调用 `ref.read(serialConnectionProvider.notifier).send(data)`。
    *   `Notifier` 根据 `uiSettingsProvider` 的 "hexSend" 状态，对数据进行预处理（字符串转 Hex 字节或 UTF-8 文本，并在配置为追加换行时附加 LF/CR/CRLF）。
    *   `Notifier` 调用 `SerialPortService` 的 `write()` 方法，并更新 Tx 字节数。
    *   `Notifier` 将已发送的数据添加到 `dataLogProvider` 中。

### 5.2 错误处理
* **串口打开失败:** 捕获 `SerialPortOpenTimeoutException` / `SerialPortOpenException` 等异常后写入 `errorProvider` → 触发 SnackBar；状态栏仍保留结构并显示“未连接”。
* **读写错误/设备断开:** 流监听 `onError` 中断并调用断开逻辑，SnackBar 提示；状态栏显示“未连接”。
* **发送失败:** 捕获 `SerialPortWriteException` 并写入 `errorProvider`，不影响已显示的历史日志。
* **输入无效 Hex:** 验证失败只在输入框内提示，不进入错误 Provider。


---