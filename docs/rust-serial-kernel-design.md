# 独立 Rust 应用核心与可替换前端设计

> 状态：核心与 Flutter 接入已落地。本机 Linux x64 已通过 21 项 Rust 检查、无 Flutter SDK 路径的普通 Rust 调用方 smoke、真实 Flutter/FRB 伪终端收发及订阅溢出恢复、release bundle 加载/关闭 smoke，并已观察正常桌面窗口渲染与原生关闭请求。Windows、Linux arm64、真实串口电气行为与正式发行包仍需对应环境验收，不能由本机结果推断成功。

## 1. 结论先行

本项目按“完整重构”设计，而不是把 `flutter_libserialport` 替换成另一个 transport：

- Rust 核心作为普通 library crate 独立编译、运行和测试，负责串口领域状态、数据处理、配置、日志模型和任务调度；
- Rust 核心使用 `serialport` crate，通过 worker thread 处理阻塞式串口 I/O，不依赖 Flutter、Dart 或 GUI 框架；
- Flutter 是第一个前端，只负责 UI、交互和渲染；
- 独立的 Flutter bridge crate 编译为 `cdylib`，使用 `flutter_rust_bridge` 接入核心；其底层仍通过 FFI，但不手工维护 C ABI；
- CLI 和纯 Rust GUI（例如 GPUI-kit 方案）直接依赖核心 Rust API，不绕行 Flutter bridge；
- 所有前端通过 command、snapshot 和 event 使用同一套业务行为，不在各自的事件循环中复制连接状态机；
- 现有 Dart manager、service、串口模型和旧 FFI 依赖只作为行为基线，不作为最终架构。

核心负责状态和规则，前端负责交互和表现。“完全解耦”指核心可以脱离任何前端运行，不代表前端不能理解连接状态或串口配置。替换前端不应改写串口行为；未来 CLI、GPUI 前端是接入方向，不要求本次同时实现或承诺其平台支持。

## 2. 重构前的行为基线

### 2.1 调用链

迁移前链路如下；本节用于对照用户行为，不是新实现的调用合同：

```text
UI widgets
  -> SerialPortManager (Riverpod Notifier)
    -> SerialPortServiceInterface
      -> SerialPortService
        -> flutter_libserialport / C libserialport
```

关键位置：
- 以下文件名属于目录迁移前的历史行为基线，`SkyPort/` 是旧应用目录，不代表当前仓库路径：
  - `SkyPort/lib/services/serial_port_service.dart`：历史 serial service；接口、定时轮询和 native port 生命周期如上所述。
  - `SkyPort/lib/providers/serial/serial_port_manager.dart`：历史 manager；负责连接状态、配置调和、端口扫描、自动重连和收发统计，并用生命周期队列及 token/generation 忽略过期操作与事件。
  - `SkyPort/lib/models/serial_config.dart`：历史 serial config；直接使用 `flutter_libserialport` 常量，UI 支持范围如上所述。
  - `SkyPort/lib/providers/serial/data_log_provider.dart`：历史数据日志 provider；按字节流收取，换行只影响日志记录边界。
  - `SkyPort/test/helpers/mock_classes.dart`：历史测试替身；通过 service/session 接口隔离 FFI。

### 2.2 迁移前的平台与构建事实

- 迁移前的 README 声明正式支持 Windows 和 Linux；macOS 工程存在但不属于当时的正式支持范围。
- 迁移前 `pubspec.yaml` 直接依赖 `flutter_libserialport: ^0.6.0`。
- 当时 Flutter 生成的 Linux、Windows、macOS 插件注册文件仍然注册 `flutter_libserialport`。
- 当时 Linux CI 构建 x64 和 arm64；Windows/macOS 也有独立工作流。
- 当时 CI 没有 Rust toolchain、Cargo 缓存或 Rust native library 打包步骤。

### 2.3 当前 UI/内核解耦度评估

结论：**transport 解耦度中等，UI 与串口领域内核的解耦度较低。**

已经解耦的部分：

- widget 没有直接 import `flutter_libserialport`；
- native I/O 集中在 `SerialPortService`；
- `SerialPortServiceInterface` 和 `SerialPortSessionInterface` 允许纯 Dart fake；
- manager 不负责构建 widget，测试可以隔离真实 FFI。

仍然紧耦合的部分：

- widget 直接依赖具体的 `serialPortManagerProvider` 和 `SerialPortState`；
- widget 直接调用 `connect`、`disconnect`、`send`、`setParity`、`setAutoReconnect` 等业务方法；
- UI 绑定旧 manager 的具体状态类型及 `isBusy/isReconciling` 等字段；理解连接状态本身不是耦合问题，依赖旧实现类型和自行推导业务行为才是；
- `SerialPortManager` 同时拥有连接状态机、重连、配置持久化、日志写入、错误 provider 和 UI 状态；
- `SerialConfig` 仍直接 import `flutter_libserialport`；
- UI 操作“清空接收区”时分别调用 data log provider 和 manager 的 stats reset，单个用户意图被拆成两个 provider 操作；
- 发送 widget 在发命令前自行判断 connected，部分业务规则因此泄漏到 UI。

因此当前结构更准确地描述为：

```text
UI -> Riverpod 业务状态机 -> service abstraction -> native transport
```

不是：

```text
UI -> 纯 UI projection -> 独立应用内核
```

如果目标是完整重构，现有 interface 只能作为测试和过渡接缝，不能作为最终的内核边界。

## 3. 目标边界

### 3.1 Rust 应负责

Rust 作为唯一的应用后端，负责：

1. 端口枚举、打开、配置、关闭；
2. 连接状态、拔线检测、自动重连和配置调和；
3. 读写 worker、队列、背压和资源生命周期；
4. 文本、Hex、换行和发送任务的处理；
5. 原始接收流、日志记录事实、容量和清空操作；
6. 收发统计、历史记录和后台任务；
7. 配置校验和持久化；
8. 统一的错误分类、状态快照和事件顺序。

这里的“负责”指状态和规则的唯一所有者。任何前端都不应再复制一份连接状态机、重连计时器、权威日志缓冲区或发送格式化逻辑。记录边界、清空时是否重置统计、导出编码和文件内容属于核心合同，不能由不同前端各自定义。

### 3.2 前端应负责

Flutter、CLI 和纯 Rust GUI 分别负责自己的交互与显示：

1. widget、终端输出或 GUI 控件，以及布局、主题和可访问性；
2. 收集用户输入并发送核心 command；
3. 订阅核心 event/state snapshot；
4. 将原始日志记录或终端显示数据渲染为界面，并在需要时运行 ANSI parser/terminal emulator；
5. 本地化文案、错误展示，以及文件选择等平台交互。

前端可以禁用当前不可用的按钮，但核心仍须独立校验连接状态和命令参数；CLI 或其他调用方不能绕过规则。Flutter 的 Riverpod 可以保留，但仅负责 UI 生命周期、订阅和渲染投影；GPUI 的视图状态和 CLI 的输出循环承担同类职责。

### 3.3 不属于应用核心的内容

- Flutter widget、GPUI 控件和平台窗口管理；
- 本地化文案和框架特有的颜色、样式或文本类型；
- 纯 UI 动画、焦点和滚动位置；
- 尚未提交的临时输入框内容；
- 日志的最终视觉布局及终端屏幕状态。

### 3.4 ANSI 解析与终端渲染边界

ANSI 解析和终端模拟不是同一件事：

- **流式解析器**处理转义序列、分包和 SGR 样式状态；
- **终端模拟器**维护光标、屏幕 buffer、清屏、滚动、替代屏幕等状态；
- **渲染器**把文本或终端屏幕绘制成具体前端的输出。

SkyPort 当前是按日志行显示数据，不是完整终端模拟器。`LogEntry` 在 Flutter 侧按行调用 `ansi.Parser`，再把样式映射为 Flutter `TextSpan`；`enableAnsi` 也是 UI 设置。保留这一方式可作为首个前端实现，但“ANSI 必须在 Flutter 解析”不是核心架构约束。

核心提供原始字节批次、时间、收发方向、日志记录边界和容量事实。Flutter、CLI、GPUI 自行选择显示方式；若使用终端组件，原始接收流可交给该前端的终端控制器。核心不维护虚拟终端屏幕，不生成 `TextSpan` 或 GUI 节点。

点击清空时，前端发送核心清空命令；核心清空日志并发布结果，前端据此清空自己的显示缓存或终端控制器。显示缓存不是第二份业务日志，不能决定导出内容或业务统计。

若多个前端确实需要一致的 ANSI 增量解析，再提取不依赖 UI 框架的 Rust 解析模块；屏幕 buffer 和渲染仍属于前端。当前不预先建设该模块，日志导出语义也不能依赖某个前端的 parser。

### 3.5 为什么不是只迁移 transport

当前 `SerialPortManager` 已经包含连接调和、自动重连、生命周期队列、operation token 和 session generation。只替换底层 transport 会留下两套时序边界：Dart 管状态，Rust 管线程和端口。这样只能降低 C 依赖，不能消除原有生命周期复杂度。

完整重构的收益是让 Rust 成为串口行为的单一所有者。迁移过程中可以暂时读取旧实现作为行为基线，但不保留旧 manager、旧 service interface 或双后端作为最终设计。

### 3.6 为什么不让前端执行串口逻辑

`serialport` 提供 blocking I/O。串口读写、拔线、重连和关闭都涉及跨线程时序，放在 Flutter isolate 或 GPUI 的界面线程中会把硬件时序和 UI 生命周期绑定在一起。核心自行维护 worker 和状态机，前端事件循环只消费快照和事件；CLI 也使用同一套核心行为。

## 4. 推荐架构

```text
Flutter widgets -> Dart projection -> skyport_flutter_bridge (cdylib)
                                      |
CLI ----------------------------------+--> skyport_core (Rust library)
GPUI frontend ------------------------+      - command dispatcher
                                             - connection state machine
                                             - serial worker threads
                                             - data/text/hex/log processing
                                             - config store
                                             - auto-send scheduler
                                             - bounded event subscription
                                             - serialport crate
```

依赖方向只能从消费者指向核心：Flutter bridge、CLI 和 GPUI 前端依赖 `skyport_core`，核心不依赖这些消费者。CLI、GPUI 直接调用 Rust API，不需要 Flutter bridge 动态库、跨语言 FFI 或 Flutter 环境。

Rust 暴露的是应用级 API，不是让前端自己组装 session 的底层句柄集合。前端发送 command，核心更新内部状态并产生 event；前端不根据 native 细节自行推导连接状态。当前按单进程、单应用宿主设计，不为未来前端预先引入 HTTP/RPC、插件系统、通用 C ABI 或多客户端服务。

### 4.1 `flutter_rust_bridge` 只属于 Flutter 适配层

Flutter 接入仍选择 `flutter_rust_bridge`，而不是手写 C ABI：

- 核心 command、event、snapshot、配置和错误使用普通 Rust struct/enum；
- bridge 通过受控的 `api.rs` 入口进行必要的类型转换、异步调用和 stream 转发；
- 自动生成 Dart/Rust glue，减少手写内存分配、UTF-8、buffer 和 Result 映射；
- 生成代码、FRB 属性、`StreamSink` 和 Dart 对象只存在于 bridge crate；
- 核心能在不编译 bridge、不安装 Flutter SDK 的环境中使用和测试。

未来消费者已明确包含 CLI 和纯 Rust GUI，但它们消费 Rust API，不构成维护通用跨语言 ABI 的理由。FRB 是 Flutter 的接入方式，不是核心协议；生成入口不得导出核心内部 session、线程或 `serialport` crate 的类型。

### 4.2 核心订阅与前端事件流

Rust worker 将事件交给 AppCore，由核心提供框架无关、有界且有顺序的订阅。Flutter bridge 将该订阅转发为 FRB typed stream；CLI、GPUI 直接消费核心订阅。不手工实现 Rust -> Dart callback。

核心负责事件顺序、容量、溢出和订阅结束语义；适配层负责前端事件循环、Dart isolate 和 stream dispose。FRB stream 不替代核心背压，也不能在转发层引入无界缓冲或静默丢失。

取消某个订阅只释放该订阅及转发任务，不关闭串口应用核心。最终关闭由应用宿主显式发起；组件重建、窗口视图销毁或输出消费者结束不能隐式销毁 AppCore。

### 4.3 迁移期如何避免双后端

完整重构不等于一次提交完成。施工期间可以让旧 Flutter 页面作为临时 UI，读取新 Rust AppCore 的 event；但不要同时运行旧 manager 和新状态机。

旧实现的用途只有两个：

1. 作为行为基线；
2. 在硬件测试中作为对照。

新 Rust backend 验收后，旧 Dart 串口代码整体删除。

## 5. 建议的 Rust API 合同

以下是框架无关的应用级设计合同，不是可直接编译的实现代码。核心使用普通 Rust 类型；Flutter bridge 为生成 Dart glue 定义受控入口。Rust 内部的 session、线程和 `serialport` 类型不跨应用 API 边界，FRB 类型也不进入核心。

### 5.1 应用级 API

```rust
let app = skyport_core::AppCore::create(options)?;
let (snapshot, subscription) = app.subscribe()?;
let request_id = app.dispatch(command)?;
let event = subscription.recv_timeout(std::time::Duration::from_millis(100))?;
subscription.cancel(); // 不关闭应用核心
app.close()?;          // 阻塞等待同一次清理；Flutter bridge 异步调用
```

`AppOptions` 接收配置和数据目录等宿主参数，不接收 widget、Dart 回调或 GUI context。宿主负责选择路径，核心负责文件格式、校验和读写。具体订阅读取 API 与异步执行方式在原型中确定，不要求消费者运行某个 UI 框架。

CLI、GPUI 直接调用该 API；实际生成到 Dart 的 API 名称由 bridge 的 FRB 配置决定。任何前端都不持有串口 session handle；端口 session 是 AppCore 的内部对象。

### 5.2 命令

初始命令集合：

- `list_ports`；
- `set_config`；
- `connect`；
- `disconnect`；
- `send_text`；
- `send_hex`；
- `clear_log`；
- `set_auto_reconnect`；
- `set_auto_send`。

读取当前状态使用 `snapshot`，初始化显示使用 `subscribe`，不再另设重复的 `get_snapshot` 命令。日志读取、文件导出和历史记录等能力应在相应垂直切片中定义应用 API，不能转移到前端业务实现中。文件导入功能已移除，不再暴露对应命令或桥接接口。

命令只表达用户意图。核心负责校验、排队、执行和产生最终结果，不要求前端先自行修改“预期状态”。返回 request id 只代表命令已接受，不代表操作已完成；每个已接受请求必须有可关联的最终成功或失败结果，拒绝接受则直接返回结构化错误。

### 5.3 事件和状态

事件至少包含：

- `state_changed`：连接状态、应用配置、错误和统计；
- `ports_changed`：端口名称列表；
- `data_received`：原始字节批次或日志记录，不生成前端样式对象；
- `data_sent`：实际写入完成的发送记录；
- `write_failed`；
- `disconnected`；
- `reconnecting`；
- `queue_overflow`；
- `task_failed`；
- `command_completed` / `command_failed`：其他命令的最终结果，携带 request id；发送请求以 `data_sent` / `write_failed` 为最终结果，不重复确认。

AppCore 为状态变化和事件分配单调递增的 sequence，snapshot 标明其覆盖的 sequence。`subscribe` 必须在同一一致性边界内建立订阅并取得初始 snapshot：snapshot 包含该边界的状态和保留日志，订阅从其后的事件开始。禁止先调用 `snapshot` 再单独注册监听，否则中间发生的事件可能遗漏。

`AppSnapshot` / `AppState` 暴露累计 `rx_bytes`、累计 `tx_bytes`、最近一次接收批次的 `last_rx_bytes`，以及仅接收方向吞吐率 `rx_bytes_per_second`。核心约每秒采样累计 RX，并按单调时钟实际经过时间计算；仅在速率变化时发布 `state_changed`。空闲速率为零。连接状态变化或计数器重置时速率归零并建立新基线；首次采样从该基线计算，不计入历史字节。

高吞吐数据必须使用批量事件和容量上限，snapshot 不复制无界历史。命令、接收和订阅队列的满载行为须分别定义；溢出通知或订阅终止原因不能依赖向已经满载的数据队列再塞入普通事件。消费者必须获知数据缺口，不能把不完整记录当作完整日志。FRB stream 不替代背压设计。

### 5.4 写入和数据语义

完整后端必须先定义：

1. `send_text` 的编码和换行由 Rust 处理；
2. `send_hex` 的非法输入返回 command error，不得静默修改；
3. `data_sent` 表示请求的全部字节已写入串口驱动，不表示设备已接收或处理；部分写入失败须报告已写字节数；
4. 接收数据按字节流处理，不假设一次 read 就是一条消息；
5. 日志记录边界、容量、清空与统计的关系，以及导出编码和内容由核心统一定义；
6. 队列满时明确拒绝、报告 `queue_overflow` 或结束订阅，不得静默丢数据。

发送命令返回 request id，由核心产生 `data_sent` 或 `write_failed` 最终结果，前端不等待物理写入。文本和 Hex 输入不得在 bridge 中预处理，避免不同前端产生不同的实际发送字节。

### 5.5 AppCore 内部生命周期

应用宿主拥有 AppCore，订阅和界面组件不拥有其关闭权。前端适配层可持有安全共享引用，但不能绕过核心生命周期状态；释放订阅只停止消费，不停止自动发送、重连或串口 worker。

`close` 首先进入 closing 状态并拒绝新命令，再停止自动任务和重连、结束待执行请求、关闭 session、唤醒并等待 worker 退出，最后结束订阅。已接受但未执行完的请求必须得到失败结果，或由明确的关闭终止原因告知消费者；不能永久悬挂。

关闭操作幂等，并发关闭等待同一次清理。关闭完成后 command、snapshot 和新 subscribe 返回 closed，已有订阅结束；AppCore 在最后一个安全引用释放后销毁。Rust 宿主等待 `close` 完成再退出，Flutter bridge 同样提供可等待的关闭入口，不以 widget dispose 或 Dart GC 代替关闭。

## 6. 配置和错误设计

### 6.1 Rust 领域模型独立于旧依赖

`SerialConfig.parity` 当前与 `flutter_libserialport` 的整数常量绑定。完整重构时应移除该 Dart 模型及其旧依赖，Rust 定义自己的版本化配置模型。

旧 SharedPreferences 中的 `serial_parity`、波特率等值通过 Flutter 适配层一次性读取，作为中立迁移数据交给核心转换和校验；核心不依赖 Dart SharedPreferences。新配置写入成功后才能记录迁移完成，失败不能静默使用默认值或破坏旧配置。之后所有前端共用核心的配置格式和持久化规则，旧底层库常量不再成为新协议。

### 6.2 Rust 是配置验证的唯一所有者

Flutter 下拉选项、CLI 参数检查和 GUI 输入限制都不是信任边界。核心必须验证：

- 端口名非空；
- 波特率大于 0；
- 数据位为支持值；
- 校验位为定义值；
- 停止位为支持值；
- command 参数、数据长度和容量限制；bridge 额外负责跨语言边界的对象与内存安全。

无效输入返回结构化 command error，不能静默回退。

### 6.3 错误和日志边界

核心负责错误分类、错误上下文、状态转换和后台日志；前端负责将结构化错误映射为本地化文案或 CLI 输出。核心不携带前端文案、颜色或控件类型。

错误类型至少区分：

- invalid argument；
- port not found / open failed：仅明确的路径不存在错误返回前者；`serialport::NoDevice` 还包含 Unix 占用、Windows 拒绝访问，因此打开时返回后者，不通过系统错误文案猜测原因；
- permission denied；
- unsupported configuration；
- read failed / disconnected；
- write failed；
- timeout；
- closed；
- queue overflow；
- task failed；
- internal error。

`SerialPortOpenTimeoutException` 这类旧 Dart exception 不应原样保留。核心返回真实的 timeout/error 类型；各前端只做显示层映射，不通过字符串匹配推断业务状态。

## 7. serialport crate 的平台注意事项

官方 crate 提供 POSIX 和 Windows 的 blocking I/O 及端口枚举；异步场景由上层自行组织。其 `SerialPort` trait 支持波特率、数据位、校验位、停止位、流控、超时和 buffer 查询等能力。

需要在原型阶段确认：

1. `flow_control::None` 是否完全覆盖当前 `xonXoff disabled / RTS off / CTS ignore / DSR ignore / DTR off` 的行为；
2. DTR/RTS 在 Windows、Linux、macOS 上的打开初始电平；
3. 拔出设备时 `read` 的实际错误类型和返回时机；
4. COM10 以上端口名、Linux `/dev/tty*`、macOS `/dev/cu.*` 和 `/dev/tty.*` 的枚举结果；
5. 非标准波特率和不支持的数据位/停止位的错误行为；
6. Linux 打包时是否启用默认 `libudev` feature。

当前应用只消费端口名称。如果产品不需要 USB VID/PID、制造商等元数据，可以评估 `default-features = false` 以减少 Linux 的 `libudev` 依赖；但这会牺牲部分枚举信息，必须用实际发行包测试后再决定，不能仅因能编译就默认关闭。

crate 使用 MPL-2.0。项目本身使用 AGPLv3，合并前应完成许可证、动态链接和发行包义务的正式审查；本文不替代法律结论。


## 8. 完整重构步骤

### 阶段 0：冻结现状行为

- 记录端口枚举、配置、打开、收发、日志、拔线、重连、关闭和退出行为；
- 现有 Dart 测试作为行为基线，不作为新架构的长期测试边界；
- Linux 用 pseudo-terminal 建立收发基线；
- 确认正式支持平台和发布产物。

目标是记录“必须保留的用户行为”，不是保留旧代码结构。

### 阶段 1：先建立 UI 边界

- 新建稳定的 UI-facing state 和 user-intent API；
- 让 widget 只依赖 UI state/controller，不再依赖旧 `SerialPortManager`、`SerialPortState` 或 native 库常量；理解中立的领域状态并不违反解耦；
- 将当前 `SerialPortManager` 包装为临时 `LegacyUiBackend`，作为唯一旧实现；
- controller 只做状态映射和命令转发，不复制连接、重连或日志状态；
- 保证现有 UI 行为和测试继续通过。

目标结构：

```text
Widgets
  -> UiController / UiState
    -> LegacyUiBackend
      -> current SerialPortManager
```

这一步先切断 UI 与当前实现的依赖，但不改变串口行为。临时 wrapper 只用于迁移，不建设可插拔 backend 框架；接入核心时按最终协议调整 projection，不承诺 widget 完全无需修改。

### 阶段 2：定义 Rust AppCore 协议

- 定义框架无关的 command、event、snapshot、错误类型和文件格式版本；
- 定义请求最终结果、接收 chunk、日志记录边界、导出、容量和各队列溢出语义；
- 定义原子订阅与 snapshot、sequence、取消订阅和宿主显式关闭规则；
- 定义配置文件格式和中立的旧配置迁移输入；
- 单独定义 Flutter bridge 的类型映射、线程、跨语言生命周期和 panic 安全规则，不让这些规则侵入核心 API。

核心合同先于 Rust 实现和新 UI bridge。UI 边界先行只是切断旧实现依赖，不代表先设计一套由 Flutter 生成器决定的核心协议。

### 阶段 3：实现独立 Rust AppCore 并验证无 UI 运行

建议使用 Cargo workspace，将核心和 bridge 分开：

```text
Cargo.toml                    # workspace
crates/
  skyport_core/               # 普通 Rust library
    Cargo.toml
    src/
      lib.rs                 # 公共 Rust API 和领域类型
      app.rs                 # 命令、状态、订阅、生命周期
      serial/
      config/
      logging/
      scheduler/
    tests/
  skyport_flutter_bridge/    # 阶段 4 接入时创建，cdylib
    Cargo.toml
    src/
      lib.rs
      api.rs                 # FRB 生成入口、转换和转发
```

核心的 `serial` 管理 worker 和串口，`app` 管理命令与状态，`config` 管理校验、持久化和中立迁移数据，`logging` 管理字节流、记录、导出和容量，`scheduler` 管理自动发送。公共类型先放在 `lib.rs`，按实际规模拆分，不为规划中的功能预建空模块。

核心 manifest 不依赖 FRB、Flutter、Dart 或 GPUI；这些依赖也不能由核心默认 feature 间接引入。CI 必须能单独执行 `cargo test -p skyport_core`，无需 Flutter SDK 或 bridge 构建。

使用临时 Rust 命令行 smoke 程序直接依赖核心，在无 Flutter 环境中完成创建、列端口、打开、收发、订阅取消和关闭退出。Linux 可用 pseudo-terminal；这一证明必须先于 Flutter 接入，不能用 Cargo 编译通过替代。不要求此时开发完整 CLI 产品或 GPUI 页面；验证完成后移除临时程序，保留有行为价值的回归检查。

### 阶段 4：实现 Flutter bridge 和最薄 Dart projection

- 创建独立 `skyport_flutter_bridge` crate，依赖核心和 FRB，负责生成入口、类型转换、订阅转发及跨语言生命周期；
- Dart 只保留生成的 binding、typed event stream 和 UI projection，不重复实现串口业务模型；
- 以原子订阅返回的 snapshot 初始化显示，再按 sequence 应用事件；处理显式溢出或订阅结束；
- Riverpod provider 只管理 UI 订阅和 widget 生命周期，应用宿主单独负责核心创建和可等待的关闭；
- 不在 Dart 复制核心的连接、重连、日志、发送格式化和调度状态；
- Flutter 接入失败不能阻止核心被 CLI 或纯 Rust GUI 独立使用。

### 阶段 5：按垂直切片重建 UI

按一条可运行链路推进，而不是先重写所有 widget：

1. 端口列表；
2. 打开/关闭；
3. 文本和 Hex 发送；
4. 接收数据显示；
5. 配置修改；
6. 日志和统计；
7. 自动发送；
8. 拔线和自动重连；
9. 设置持久化。

每完成一条切片，同时验证核心无 UI 路径和 Rust event -> bridge -> Dart projection -> UI 的完整路径。CLI、GPUI 的后续接入复用同一合同，不重写业务；本次不创建其产品级工程。

### 阶段 6：删除旧实现

仅在新 AppCore 通过行为验收后：

- 删除 `flutter_libserialport` 依赖；
- 删除旧 service、manager、Dart 串口模型和旧 exception；
- 删除旧测试替身中对应的 interface；
- 重新生成并检查 Flutter 平台插件注册文件；
- 从 CMake/Xcode/MSBuild 和发布配置中移除旧插件；
- 删除不再使用的 Dart 串口相关常量和 provider。

不保留运行时 backend selector，不保留旧 interface 兼容层，不保留双写或双状态。

### 阶段 7：平台发布验收

- CI 安装并缓存 Rust stable，单独验证核心，再构建 Flutter bridge 和应用；
- 正式验收 Linux x64/arm64 和 Windows；macOS 只有明确纳入支持范围并完成平台检查后才进入验收；
- 检查 Flutter 最终 bundle 中 bridge 动态库路径和依赖；
- 用真实串口或平台对应虚拟串口完成收发、拔线和重连；
- 解包正式发布的 deb/rpm/AppImage/Windows 产物后再做一次 bridge 加载和核心生命周期 smoke test；
- 将来发布 CLI、GPUI 时分别验证其发行包和目标平台，不能由 Flutter 发布检查推断成功。

## 9. 测试矩阵

### Rust 单元测试

覆盖：

- 配置校验、文件格式版本和中立的旧配置迁移；
- 无前端预校验时的非法命令和状态拒绝；
- 端口打开错误分类；
- 读取超时不误报断开；
- 多次 read 的事件顺序；
- 二进制零字节、非 UTF-8 和任意字节值；
- 文本/Hex/换行处理；
- 日志聚合、容量限制和清空；
- 自动重连和自动发送调度；
- 写入 request id、成功事件和失败事件；
- worker 错误只产生一次终止事件；
- app close 幂等、并发关闭、未完成请求结束和关闭后操作拒绝；
- 原子订阅期间的 snapshot/event 连续性、sequence 和有界队列溢出；
- 取消订阅后核心仍可接受命令，新订阅能获得一致的当前状态。

### Rust 集成测试

Linux 优先使用 pseudo-terminal 验证端到端打开、配置、收发、拔线和重连；不依赖真实 USB 设备。Windows 需要真实设备或虚拟 COM 对，不能把 Linux 行为推断为 Windows 行为。

### 无前端 smoke 验收

在不安装 Flutter SDK、不构建 FRB bridge 的环境中，由 Rust 调用方直接创建核心，列端口、打开虚拟或真实串口、发送文本/Hex、接收包含零字节和非 UTF-8 的数据、观察结果并关闭退出。取消后重新订阅必须不影响连接和后台任务，初始 snapshot 与后续事件不得遗漏或重复应用业务变化。

该验收证明核心可独立运行，不代表完整 CLI 或 GPUI 产品已实现；硬件及不同操作系统的行为仍按各自矩阵验证。

### Flutter 适配与 UI 测试

- 用真实 bridge smoke 验证生成类型映射、订阅结束、错误传递和可等待关闭；
- 测试 UI projection 在正常更新、数据缺口和关闭状态下的可见行为；
- 在端到端收发检查中确认 bridge 不改变用户输入和实际字节，不新增只验证转发或复制的单元测试；
- widget 测试不加载真实动态库；
- 不再测试 Dart 版连接状态机、重连计时器或日志业务逻辑，因为这些已经属于核心。

### 发布 smoke test

每个正式支持平台至少验证：Flutter bridge 能加载、AppCore 能创建、端口能列出、能打开真实串口、能收发、拔线后能重连、能关闭并退出。仅 `flutter analyze` 或 Cargo 编译通过不能证明 native library 已被正确打包。未来 CLI、GPUI 的发行包直接验证核心使用和退出，不要求加载 Flutter 动态库。

## 10. 主要风险和处理

| 风险 | 处理 |
| --- | --- |
| 核心被 Flutter bridge 污染 | 独立 crate、单向依赖、无 Flutter 环境的核心构建和 smoke |
| 跨语言对象生命周期错误 | FRB 生成 glue、安全引用、宿主显式 close 并等待、真实 bridge smoke |
| 界面事件循环被阻塞 | 核心 worker；适配层非阻塞调用及事件转发 |
| 接收或转发队列无界增长 | 各层有界；满载行为和可观察的数据缺口明确，不静默丢数据 |
| 核心与前端状态不一致 | 核心是唯一事实源；原子 snapshot + 订阅及 sequence |
| 视图销毁意外停止串口 | 订阅生命周期与核心生命周期分离，宿主拥有关闭权 |
| 完整重构范围失控 | 先锁定核心合同，按垂直切片验收，不同时开发 CLI/GPUI 产品 |
| 平台配置差异 | Windows/Linux 真实设备矩阵；不要只跑 Linux CI |
| Rust panic 穿过 FFI | 验证 FRB 入口的 panic 处理和内部 worker 失败通知，禁止 unwind 穿过语言边界；不承诺 panic 后可继续运行 |
| 动态库未进入 Flutter 安装包 | CI 中解包正式支持平台的最终 artifact 并检查 bridge 库及实际加载 |
| Linux 运行时缺少 libudev | 原型分别测试默认 feature 和关闭 feature 的发行包 |
| 许可证义务误判 | 合并前做 AGPLv3 + MPL-2.0 的正式审查 |

## 11. 已确认决策与实现细化项

用户已确认全部采用推荐默认方案。以下产品边界已锁定，不再作为实施前待确认问题：

| 决策 | 已确认方案 |
| --- | --- |
| 本次交付 | 独立核心并接入 Flutter；命令行仅用于无 UI 验收，不同时交付 CLI 或 GPUI 产品 |
| 正式平台 | Windows、Linux x64/arm64；macOS 不纳入本次正式验收 |
| 日志保留 | 有限容量的最近日志；裁剪必须可见，导出仅包含当前保留内容，不承诺完整会话留存 |
| 发送队列满载 | 明确拒绝新发送，不静默丢弃或隐式重试 |
| 显示订阅溢出 | 明确报告数据缺口并重新建立原子 snapshot + 订阅；恢复当前保留状态不代表找回已裁剪的数据 |
| 接收保证 | 不承诺无限持续接收绝不丢数据；接收队列溢出必须可观察，不能把不完整日志标记为完整 |
| USB 信息 | 保留按端口名称使用的能力，不新增 USB 元数据显示或按设备身份重连；拔插匹配规则保持现有行为 |
| 显示一致性 | 核心统一字节、日志记录和导出语义；各前端自行处理 ANSI 与显示，暂不建设共享 ANSI 解析模块 |

技术与迁移方案同样按以下默认值执行：

- 普通 Rust library 核心 + 独立 FRB `cdylib`，未来 CLI、GPUI 直接使用核心；不引入 RPC、插件或通用 C ABI；
- 类型化 Rust API，持久化格式显式版本化；Rust API 在同一 workspace 内协同更新，不预先承诺稳定二进制 ABI；
- 发送通过 request id 和最终 event 返回结果；成功表示全部字节写入驱动，不表示设备确认，部分失败报告已写字节数；
- 原子 snapshot + 有序有界订阅，取消订阅不关闭核心，宿主显式关闭并等待；
- 核心统一校验和持久化；Flutter 读取旧配置，核心转换并成功写入后才标记迁移完成；
- 日志记录边界、清空与统计关系保持现有行为，不借重构改变产品语义；
- Linux 先保留 `libudev` feature，完成默认与关闭 feature 的发行包对比后再决定是否移除，不仅凭端口名称需求推断可关闭；
- CI 现场构建并缓存 Cargo 依赖，核心检查不依赖 Flutter，Flutter 发行包单独验证 bridge。

以下属于实施细化，不阻塞上述产品决策：具体 Rust 类型与错误变体、配置和日志文件格式、容量数值、接收队列满载处置、订阅读取方式、FRB 生成配置及平台构建脚本。容量须有明确上限，接收满载须明确数据缺口或终止原因；这些细节按现有行为基线和原型结果确定，不改变已确认边界。

## 12. 参考资料

- serialport-rs README：<https://github.com/serialport/serialport-rs/blob/main/README.md>
- serialport-rs `Cargo.toml`（features、平台依赖和许可证）：<https://github.com/serialport/serialport-rs/blob/main/Cargo.toml>
- `serialport::SerialPort` trait：<https://docs.rs/serialport/latest/serialport/trait.SerialPort.html>
- SkyPort 核心入口：`crates/skyport_core/src/lib.rs`
- SkyPort 核心生命周期：`crates/skyport_core/src/app.rs`
- SkyPort 配置与中立迁移：`crates/skyport_core/src/config.rs`

## 13. 已落地的核心合同与验证入口

- `skyport_core` 不依赖 Flutter、Dart 或 FRB；`skyport_flutter_bridge` 单向依赖核心，生成器与运行库版本锁定为 FRB 2.13.0。
- 核心使用单个 I/O worker；应用命令队列默认 128 项，队列容量只接受 1–4096。接收直接进入有界日志，不另建接收转发队列；读取批次为 8 KiB，读取超时最多 5 ms，并让出自动发送截止时间。较短的读取等待减少命令排队，但增加空闲唤醒，不提供端到端硬实时保证。POSIX descriptor 使用 nonblocking syscall 配合 serialport 的 readiness polling，避免大缓冲区阻塞写入；发送请求总超时 1 秒，保留部分写入计数。
- 每个订阅默认最多 256 个事件，逻辑负载上限 8 MiB；满载通过队列外的 `QueueOverflow` 终止原因通知，前端重新原子订阅。超时读取返回 `None`，取消和最终关闭返回 `Closed`。
- Flutter 的数据缺口提示在恢复 snapshot 后仍保留；只有当前清空请求确认成功才移除提示。已连接 session 丢失即标记日志不完整，不能因最后一行恰好完整而掩盖后续缺口。
- 原子初始 snapshot 包含保留日志；后续状态事件只带元数据，日志事件带 `LogDelta`。delta 包含 upsert、显式删除 ID、最早保留 ID、裁剪计数和不完整标记，不反复复制全部历史。
- 普通日志记录 ID 按完成顺序分配；唯一 pending RX 行使用保留 ID `u64::MAX`、总在末尾，完成时删除该 ID 并新增正式行，保留 RX 分包期间插入 TX 的顺序。
- Dart 利用记录 ID 的有序性二分定位，不保留或复制整表 ID 索引。每批日志增量按事件顺序合并 upsert、删除及最终保留边界，只复制和裁剪一次留存列表；清空、pending 重建及裁剪不能恢复已删除的旧行。
- 日志容量为 16–512 MiB，默认 128 MiB；最多 65,536 条记录，pending 超过 256 KiB 强制固化。裁剪计数可观察；清空同时清空日志、裁剪事实和收发统计。
- 已接受的发送（含文件发送）使用相同的 `DataSent`/`WriteFailed` 最终结果；文件读取或 Hex 解析失败也返回关联的 `WriteFailed`，已写入计数为 0，不让调用方等待另一种完成事件。
- 文本使用 UTF-8，换行由核心追加；Hex 只接受完整字节对和空白，不接受 `_` 或隐式修复。发送数据最多 1 MiB；Hex 原始输入（含空白）及自动发送草稿另有 2 MiB 输入上限，超限返回 `SendInputTooLarge`，与数据超限区分。成功表示全部字节写入驱动，失败携带已写入字节数。自动发送事件的 request ID 为保留值 0；用户请求 ID 从 1 开始。
- 配置为数据目录内 `config.json`，显式版本 1，原子替换；旧偏好作为原始可选 `LegacyConfig` 字段交给 Rust。只对缺失字段补默认值，非法值拒绝；已存在的新配置优先于旧偏好。历史最多 100 项且合计不超过 1 MiB。
- 前端通过字段级 `ConfigPatch` 提交设置，不用可能过期的 UI snapshot 覆盖整个配置或历史；手动 `SendInput` 使用 worker 当前设置。换行类型与 `append_newline` 分开保存，关闭再启用追加不会丢失用户选择。
- 自动发送内容只在输入或编码变化时重新编码，周期内复用缓存；提交非法 Hex 后暂停并报告 `auto_send_error`，不继续发送旧内容；后续输入更新不能意外重新启用已经关闭的任务。
- Flutter 仅保留显示设置和未提交草稿。Hex/文本草稿切换只转换可无损表示的 UTF-8；非法或非 UTF-8 内容保持可见，不补零或插入替换字节。文件选择使用 path-only `file_selector`，不提前创建或截断导出目的文件。
- 控件按渲染字段订阅状态；日志列表按旧到新的顺序显示，日志行使用稳定 ID 保留元素身份。自动跟随最多每帧定位一次，并在可变行高布局修正滚动范围后继续校正到底部；点击回到底部恢复跟随，布局校正不视为用户上滚。用户向上滚动或选择文字时不强制追赶日志尾部。
- Linux 高频长跑仍观察到 GLib `Too many GWeakRef registered` 告警。本机 Flutter engine 的 `fl_view_accessible.cc` 将语义节点按 ID 缓存至 view 销毁，疑似与该缓存的长期增长有关，尚未通过 engine 级跟踪确认因果；不能以关闭无障碍或吞掉告警代替 SDK 层回收验证。
- bridge 内的订阅 receiver 由 Mutex 保护；`next_events` 在 FRB 普通工作线程上等待第一条事件，随后非阻塞排空已就绪事件，每批最多 32 条，不为凑批增加等待。Dart 逐条检查序号并处理命令终态，再合并投影视图，保留原有队列边界与溢出恢复。宿主通过原生窗口关闭请求等待 `close`，widget/provider 销毁只取消订阅。
- 端口扫描由核心初始执行并每秒刷新。手动首次打开失败不启动隐式重试；已连接端口意外丢失时，按用户配置进入可见重连。Linux 通过文件系统类型确认 devpts 后才跳过不支持的 modem ioctl；物理端口显式关闭 DTR/RTS，初始电平与电气时序仍需各平台硬件验收。
- 自动重连间隔保持 1 秒，重试开始不清除最近失败诊断。Flutter 将状态诊断与一次性通知分开：意外断开仅提示一次，后续重试失败只更新底栏可查看的诊断；恢复后清除错误，不额外弹窗。主动操作失败、部分写入和数据缺口仍提示，用户主动断开取消重连。`scripts/pty_ui_smoke.py` 覆盖真实 PTY 拔出、多轮静默重试、同名设备替换恢复、主动停止及手动连接失败。
- 将配置端口清空是合法的取消目标操作：关闭已有 session、取消重连并保留空配置；后续显式连接仍校验非空目标，不尝试打开空名称。
- 导出内容和原子文件替换属于核心；Flutter 只选择目的路径及显示选项。核心统一 UTF-8 替换解码、Hex、时间、方向与 ANSI 去除；导出预览每条记录最多 4096 原始字节。Flutter 文字预览最多 4096 原始字节，Hex 视图最多 4096 显示字符（含软换行），显示裁剪不修改核心保留数据。

从仓库根目录执行：

```bash
cargo test --locked -p skyport_core
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
(cd app && flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml)
tool/test_quiet.sh
python3 scripts/pty_ui_smoke.py                 # Linux，需要可用显示
python3 scripts/package_smoke.py <bundle或发行包> # 真实加载已打包 bridge
```

无前端 smoke 使用临时普通 Rust 调用方完成创建、枚举、打开、文本/Hex 实际写入、零字节与非 UTF-8 接收、取消并重新订阅、清空和幂等关闭；旧 C `libserialport` 在本机拒绝 `/dev/pts/*`（构造端口时 errno 2），因此新核心 PTY 路径直接验证，不宣称旧 native 路径已有成功对照。

真实 Flutter PTY smoke 通过 UI 连接、文本发送、Hex 模式切换及文本恢复，验证 TX 精确为 `5054590d0a00ffa50a414241420d0a`、RX 为 `00fffe0d0a`；同时验证 UI 销毁后核心仍连接、重新订阅保留历史。向未消费的真实订阅提交 50 个 512 KiB 输入更新，确认有限订阅报告缺口并恢复 snapshot；随后清空同时重置日志、统计和 UI 缺口提示。Release bundle smoke 实际加载邻接 bridge、创建核心、枚举端口、取消/恢复订阅、幂等关闭并检查关闭后的类型化拒绝；不把该无硬件 smoke 描述为真实设备发行验收。

普通 release 应用已在隔离的数据目录启动并观察到实际 Flutter 桌面界面；发送原生 `WM_DELETE_WINDOW` 请求后进程正常退出。仅加载 bundle 内的 bridge，缺失时明确报错，不从工作目录回退加载其他构建。桌面集成测试和 release 构建须串行执行，避免共用 `linux/flutter/ephemeral` 时混入不同 engine 或入口产物。

最终本机检查：Rust 21 项、Flutter 单元/widget 73 项、真实 Linux UI 集成 3 项通过；`flutter analyze` 无问题，保留原有 70% 覆盖率门槛（501/713 行）。最终 release bundle 及其真实 ZIP 解包后均输出 `SKYPORT_KERNEL_SMOKE_OK`；移除复制 bundle 中的 bridge 后，宿主明确报缺库并以 1 退出。额外的普通 Rust 调用方在不含 Flutter SDK 的 PATH 下验证了文件发送失败的关联结果、零写入计数和幂等关闭；临时调用方与打包 smoke 产物已清理。

发布前仍需 Windows、Linux arm64 和真实 USB/虚拟 COM 矩阵，以及 AGPLv3 与 MPL-2.0 发行义务的正式审查；构建或本机 smoke 不替代这些检查。
