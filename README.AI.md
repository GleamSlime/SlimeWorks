- 此项目基于FRB(Flutter 3.41.0、Dart 3.11.0、rustc 1.92.0)，Flutter只进行UI和UI相关逻辑，复杂的逻辑处理计算及数据库等需要在RUST层完成
- 项目支持 桌面端/服务端(MacOS、Windows)，客户端/移动端(IOS、Android)
- 应用包含模块管理系统，所以RUST中分为动态加载(仅桌面端)和静态链接
- 如果需求有创建新的模块参考目录如下
  - 静态链接模块参考： rust/ws_module 文件夹
  - 动态载入模块参考： rust/capture_proxy 文件夹
- 应用主要是一套Flutter兼容移动和桌面端，当RUST功能无法再移动端完全实现时，则会通过HTTP请求客户端方式让客户端执行完逻辑后返回数据,设计和选择方案时应当考虑到兼容移动端
- 完成代码调整后需 flutter run 以校验是否有编译错误，如果只有Rust调整应当cargo build
- 完成代码后不需要输出README
- 页面目录位于 lib/pages 下，如果一个页面包含多个子页面则需创建主页面名的文件夹，在里面创建子页面
- 页面组件位于 lib/pages/{pageName}/components 中，页面需要细致的拆分为组件，而不是全写在一个文件中，页面以_screen结尾，class使用Screen结尾继承BasePage类
- 在MacOS/Windows如果缩放窗口为手机比例(窄屏)则会且为移动端模式显示，修改flutter时需考虑响应式
- 状态管理(UI/页面状态 使用GetX | 业务逻辑Service、Rust FFI桥接层、配置、数据库 使用GetIt)
- 路由操作使用GoRouter TypedGoRoute
- Dart中的尺寸需参考lib\core\theme\app_theme.dart appMetrics，颜色也需考虑亮色和暗色，如果尺寸未定义则使用scaleW，禁止直接数字或者int.w
- 打日志使用Loggers class，关键流程使用中文打info/debug/error/warn log方便后续定位问题,rust使用logger::{log_error, log_info}打日志
- 注释必须使用中文

‌## Dart规则

‌### 1. 类型安全

- 始终声明变量和函数类型
- 避免使用dynamic/any
- 创建必要的类型定义
- 类名：PascalCase

‌### 2. 命名规范

- 变量/函数：camelCase
- 文件/目录：snake_case
- 常量：UPPER_SNAKE_CASE
- 单一职责（<20行）

‌### 3. 函数设计

- 使用动词命名（getUser, saveData）
- 布尔变量：isLoading, hasError, canDelete
- 避免嵌套，提前返回

‌## ‌Flutter规则

‌### 1. 组件优化

- 尽可能使用const构造函数
- 避免深度嵌套（拆分为小组件）
- 使用ConsumerWidget + Riverpod
- 或BlocBuilder + flutter_bloc

‌### 2. 性能优化

- ListView.builder用于长列表
- const修饰不可变组件
- 最小化重绘范围
- 使用compute()处理耗时操作

‌### 3. 错误处理

- 使用SelectableText.rich显示错误
- AsyncValue处理异步状态
- Either<Failure, Success>模式
- 全局异常处理

‌## 静态分析

flutter analyze

‌## MCP诊断

flutter pub global run devtools

TIPS: 修改完代码务必执行 flutter analyze 确保没有报错!
