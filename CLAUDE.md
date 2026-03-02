# SkyPort - Claude Code 项目约定

> 本文档整合自 GEMINI.md 和项目开发实践，定义了 AI 辅助开发的操作规范和最佳实践。

## 🎨 视觉设计原则

### 美学标准

1. **现代化 UI** - 使用现代组件、视觉平衡的布局、干净的间距和 polished 样式
2. **响应式设计** - 确保应用适配不同屏幕尺寸（移动端和 Web）
3. **视觉元素** - 合理的颜色、字体、图标、动画、效果、纹理、阴影、渐变
4. **交互性** - 按钮、滑块、列表等交互元素应有视觉反馈（阴影、颜色变化）

### 视觉细节

| 元素 | 规范 |
|------|------|
| **字体** | 使用 `google_fonts` 包，层次分明（hero 文本、标题、正文） |
| **颜色** | 使用 `ColorScheme.fromSeed` 生成和谐的配色方案 |
| **阴影** | 多层级阴影创造深度感，卡片使用柔和阴影呈现"悬浮"效果 |
| **图标** | 使用 Material Icons 增强理解和导航 |
| **交互反馈** | 按钮悬停/点击状态、滑块拖动反馈 |

---

## ♿ 无障碍标准 (A11Y)

- 实现无障碍功能，确保所有用户（不同身体能力、 mental abilities、年龄、教育水平）都能使用
- 使用语义化组件
- 确保足够的颜色对比度
- 为图标和图像提供语义标签

---

## 🏗️ 应用架构

### 分层架构

```
presentation (UI、widgets、pages)
    ↓
domain (业务逻辑、模型、用例)
    ↓
data (repositories、数据源、API clients)
    ↓
core (共享工具、通用扩展)
```

### 关注点分离

- **Widgets** - 仅负责 UI 渲染
- **Providers** - 状态管理和业务逻辑
- **Services** - 外部依赖抽象（串口、文件等）
- **Models** - 数据结构定义

### 状态管理推荐

| 场景 | 推荐方案 |
|------|----------|
| 单个值状态 | `ValueNotifier` + `ValueListenableBuilder` |
| 异步事件流 | `Stream` + `StreamBuilder` |
| 单次异步操作 | `Future` + `FutureBuilder` |
| 跨组件共享状态 | `ChangeNotifier` + `Provider` |
| 应用级状态 | `Provider` 依赖注入 |

---

## 📝 代码生成与构建

### 代码生成流程

当引入需要代码生成的功能时（如 `freezed`、`json_serializable`）：

1. 确保 `build_runner` 在 `dev_dependencies` 中
2. 执行 `dart run build_runner build --delete-conflicting-outputs`

### 依赖管理

```bash
# 添加常规依赖
flutter pub add <package_name>

# 添加开发依赖
flutter pub add dev:<package_name>
```

---

## 🧪 错误检测与自动修复

### 修改后检查流程

每次代码修改后，AI 应：

1. **监控诊断** - IDE diagnostics（问题面板）和终端输出
2. **检查错误** - 编译错误、Dart 分析警告、运行时异常
3. **检查预览** - 观察预览服务器是否有视觉和运行时错误
4. **尝试修复** - 自动修复检测到的错误

### 自动修复策略

| 错误类型 | 修复方式 |
|----------|----------|
| 语法错误 | 直接修正 |
| 类型不匹配 | 添加类型转换或修正类型 |
| 空安全问题 | 添加 null 检查或使用 `?` / `!` |
| Lint 警告 | 运行 `flutter fix --apply .` |
| setState 未挂载 | 添加 `if (!mounted) return;` |
| 异步错误 | 添加 try-catch 块 |
| 导入缺失 | 自动添加 import 语句 |

### 常见 Flutter 问题修复

```dart
// ❌ 错误 - setState on unmounted widget
setState(() { _count++; });

// ✅ 正确
if (!mounted) return;
setState(() { _count++; });

// ❌ 错误 - 异步操作无错误处理
final data = await fetchData();

// ✅ 正确
try {
  final data = await fetchData();
} catch (e, s) {
  developer.log('Fetch failed', error: e, stackTrace: s);
}
```

---

## 🪵 日志规范

### 使用 `dart:developer` 结构化日志

```dart
import 'dart:developer' as developer;

// 简单日志
developer.log('这是一条日志消息');

// 结构化日志
developer.log(
  '发生错误',
  name: 'skyport.network',
  level: 900, // WARNING
  error: e,
  stackTrace: s,
);
```

### 日志级别

| 级别 | 数值 | 说明 |
|------|------|------|
| INFO | 800 | 普通信息 |
| WARNING | 900 | 警告 |
| SEVERE | 1000 | 严重错误 |

---

## ⚠️ 重要：Windows 环境操作规范

### Bash 命令执行规则

1. **禁止使用 Windows 路径格式**（如 `D:\Projects\SkyPort`）
2. **使用相对路径** - 当前工作目录已是项目根目录
3. **使用 Unix 路径格式** - 如 `SkyPort/coverage/lcov.info`
4. **切换目录使用相对路径** - `cd SkyPort` 而非 `cd D:/Projects/SkyPort/SkyPort`

### 正确的命令示例

```bash
# ✅ 正确 - 相对路径
cd SkyPort && flutter test --coverage

# ✅ 正确 - 使用 forward slashes
grep "^LF:" SkyPort/coverage/lcov.info

# ❌ 错误 - Windows 绝对路径
cd D:\Projects\SkyPort\SkyPort

# ❌ 错误 - 混合格式
cd /d/SkyPort
```

### PowerShell 命令执行

```bash
# 在 Windows 上运行 PowerShell 脚本
powershell -ExecutionPolicy Bypass -File scripts/check_coverage.ps1

# 使用 shell 参数
flutter test --coverage && powershell -c "Write-Host 'Tests passed'"
```

---

## 🎨 Material Design 主题

### 配色方案 (Material 3)

使用 `ColorScheme.fromSeed` 生成和谐的配色：

```dart
// 亮色主题
colorScheme: ColorScheme.fromSeed(
  seedColor: Colors.deepPurple,
  brightness: Brightness.light,
),

// 暗色主题
colorScheme: ColorScheme.fromSeed(
  seedColor: Colors.deepPurple,
  brightness: Brightness.dark,
),
```

### 字体

使用 `google_fonts` 包：

```dart
import 'package:google_fonts/google_fonts.dart';

final TextTheme appTextTheme = TextTheme(
  displayLarge: GoogleFonts.oswald(fontSize: 57, fontWeight: FontWeight.bold),
  titleLarge: GoogleFonts.roboto(fontSize: 22, fontWeight: FontWeight.w500),
  bodyMedium: GoogleFonts.openSans(fontSize: 14),
);
```

### 主题切换

使用 `Provider` 实现主题切换：

```dart
class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}
```

---

## 📁 项目结构

```
SkyPort/
├── lib/
│   ├── providers/          # 状态管理 Provider
│   │   ├── data_log_provider.dart    # 日志数据管理
│   │   ├── serial_connection_provider.dart  # 串口连接
│   │   ├── ui_settings_provider.dart # UI 设置
│   │   └── theme_provider.dart       # 主题管理
│   ├── services/           # 业务服务层
│   │   ├── serial_port_service.dart  # 串口服务
│   │   └── error_handler.dart        # 错误处理
│   ├── models/             # 数据模型
│   │   ├── log_model.dart           # 日志模型
│   │   └── connection_status.dart   # 连接状态
│   ├── ui/
│   │   ├── right_panel/   # 右侧面板组件
│   │   │   ├── receive_display_widget.dart  # 接收显示
│   │   │   └── send_input_widget.dart       # 发送输入
│   │   └── widgets/       # 通用组件
│   └── utils/             # 工具类
│       ├── hex_parser.dart           # Hex 解析
│       └── ansi_parser.dart          # ANSI 解析
├── test/
│   ├── widget/            # Widget 测试
│   │   └── right_panel/
│   ├── unit/              # 单元测试
│   │   ├── providers/
│   │   ├── services/
│   │   └── models/
│   └── integration/       # 集成测试
├── .github/workflows/     # CI/CD 配置
├── scripts/               # 辅助脚本
│   ├── check_coverage.sh
│   └── check_coverage.ps1
└── SkyPort/               # Flutter 项目主目录
    ├── lib/
    ├── test/
    ├── pubspec.yaml
    └── coverage/          # 覆盖率报告输出
```

---

## 🔄 迭代开发流程

### 测试驱动开发

1. **请求测试** - 当用户请求新功能时，优先编写测试
2. **自动生成测试文件** - 创建 `test/<file_name>_test.dart`
3. **自动执行测试** - 修改后运行 `flutter test`
4. **报告结果** - 向用户报告测试通过/失败状态

### 测试类型

| 类型 | 位置 | 命令 |
|------|------|------|
| 单元测试 | `test/unit/` | `flutter test test/unit/` |
| Widget 测试 | `test/widget/` | `flutter test test/widget/` |
| 集成测试 | `test/integration/` | `flutter test integration_test/` |

### 测试覆盖要求

- 新业务逻辑必须包含单元测试
- Widget 测试覆盖关键 UI 组件
- 测试应覆盖边界条件和错误场景
- 使用 mock 隔离依赖

---

## 🧪 测试规范

### 运行测试

```bash
# 运行所有测试
cd SkyPort && flutter test

# 运行测试并生成覆盖率报告
cd SkyPort && flutter test --coverage

# 运行特定测试文件
cd SkyPort && flutter test test/widget/right_panel/send_input_widget_test.dart

# 运行特定目录测试
cd SkyPort && flutter test test/widget/right_panel/

# 检查覆盖率是否达标
cd SkyPort && ../scripts/check_coverage.ps1 -Threshold 70
```

### 覆盖率阈值

| 指标 | 阈值 | 说明 |
|------|------|------|
| 整体覆盖率 | ≥70% | 第一阶段目标 |
| 关键模块 | ≥85% | Provider/Service 层 |
| 新增代码 | ≥95% | 防止质量下降 |

### 测试文件命名约定

- Widget 测试：`test/widget/<path>/<widget_name>_test.dart`
- 单元测试：`test/unit/<type>/<name>_test.dart`
- 集成测试：`test/integration/<feature>_test.dart`

---

## 🚀 CI/CD 流程

### Workflow 结构

```
ci.yml (入口)
└── build-matrix.yml (编排)
    ├── build-linux.yml (Linux 构建)
    │   └── 包含覆盖率检查
    └── build-windows.yml (Windows 构建)
        └── 包含覆盖率检查
```

### 覆盖率检查步骤

CI 中覆盖率检查位置：
1. `flutter test --coverage` 之后
2. `Upload coverage to Codecov` 之前
3. 失败则阻断后续流程

### 本地验证

```bash
# 在提交前本地验证
cd SkyPort
flutter test --coverage
../scripts/check_coverage.ps1 -Threshold 70
```

---

## 📝 开发约定

### 代码风格

- 使用 `dart format .` 格式化代码
- 遵循 `analysis_options.yaml` 规则
- 提交前运行 `flutter analyze`
- 自动修复：运行 `flutter fix --apply .` 修复常见问题

### 代码质量目标

- 干净的结构和关注点分离（UI 逻辑与业务逻辑分离）
- 有意义的命名约定
- 有效使用 `const` 构造函数和 widgets 优化性能
- 避免在 build 方法中进行昂贵计算或 I/O 操作
- 正确使用 async/await 处理异步操作
- 健壮的异常处理机制

### 提交规范

```
<type>(<scope>): <description>

Examples:
feat(send): add auto-send timer functionality
fix(serial): handle connection timeout correctly
test(widget): add send_input_widget tests
ci(workflow): add coverage threshold check
```

### Magic Numbers 处理

所有硬编码数字应提取为常量：
```dart
// ❌ 避免
if (data.length > 256 * 1024) { ... }

// ✅ 推荐
const maxBufferSize = 256 * 1024; // 256KB
if (data.length > maxBufferSize) { ... }
```

常量集中管理位置：`lib/utils/constants.dart`

---

## 🏛️ 架构模式

### 推荐模式

| 模式 | 适用场景 |
|------|----------|
| **Feature-first** | 按功能组织代码，每个功能有独立的 presentation/domain/data 子目录 |
| **分层架构** | 清晰的层次分离，适合中大型项目 |
| **Repository 模式** | 抽象数据源（API、数据库、本地存储） |

### 依赖注入

- 使用构造函数注入
- 使用 `Provider` 进行应用级依赖管理
- 避免紧耦合

---

## 🔧 常用命令速查

```bash
# 获取依赖
cd SkyPort && flutter pub get

# 运行测试
cd SkyPort && flutter test

# 测试 + 覆盖率
cd SkyPort && flutter test --coverage

# 检查覆盖率
cd SkyPort && ../scripts/check_coverage.ps1

# 代码分析
cd SkyPort && flutter analyze

# 格式化代码
cd SkyPort && dart format .

# 构建发布版
cd SkyPort && flutter build windows --release
```

---

## 🧭 路由和导航

### 基础导航 (Navigator)

简单导航栈使用内置 `Navigator`：

```dart
// 推送到新页面
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const ScreenB()),
);

// 返回
Navigator.pop(context);

// 替换当前页面
Navigator.pushReplacement(
  context,
  MaterialPageRoute(builder: (context) => const HomeScreen()),
);
```

### 声明式导航 (go_router)

复杂导航、深层链接、Web 支持使用 `go_router`：

```dart
import 'package:go_router/go_router.dart';

final GoRouter _router = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) {
        return const HomeScreen();
      },
      routes: <RouteBase>[
        GoRoute(
          path: 'details/:id',
          builder: (BuildContext context, GoRouterState state) {
            final String id = state.pathParameters['id']!;
            return DetailScreen(id: id);
          },
        ),
      ],
    ),
  ],
);

// 使用：context.go('/details/123')
```

---

## 📦 资源、图片和图标

### 资源声明

在 `pubspec.yaml` 中声明：

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/images/
    - assets/icons/my_icon.png
```

### 使用示例

```dart
// 本地图片
Image.asset('assets/images/placeholder.png', fit: BoxFit.cover)

// 网络图片
Image.network(
  'https://example.com/image.png',
  loadingBuilder: (context, child, loadingProgress) {
    if (loadingProgress == null) return child;
    return Center(child: CircularProgressIndicator(value: loadingProgress.progress));
  },
  errorBuilder: (context, error, stackTrace) => const Icon(Icons.error),
)

// Material 图标
const Icon(Icons.favorite, color: Colors.red, size: 30.0)

// 自定义图标
ImageIcon(const AssetImage('assets/icons/custom_icon.png'), size: 24)
```

---
