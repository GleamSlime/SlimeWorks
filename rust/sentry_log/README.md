# Sentry Log Module

Sentry 协议兼容的日志收集与展示模块，可作为自托管日志服务使用。

## 功能

- **Sentry 协议兼容**：支持 Store API 和 Envelope API，与 Sentry SDK 无缝对接
- **多项目支持**：自动管理接入的项目，每个项目独立统计
- **事件检索**：支持按级别、环境、关键词、时间范围等多维度筛选
- **事件详情**：完整的异常堆栈、面包屑、用户信息、请求信息展示
- **统计数据**：事件趋势、级别分布、项目排行
- **数据导出**：支持 JSON 格式批量导出
- **存储后端**：基于 redb 嵌入式 KV 数据库，高性能且无需额外依赖

## 协议兼容

### 支持的端点

| 端点 | 方法 | 说明 |
|------|------|------|
| `/api/{project_id}/store/` | POST | 存储单个事件（JSON） |
| `/api/{project_id}/envelope/` | POST | 存储信封格式数据（支持多事件） |

### Store API 格式

```
POST /api/my-project/store/
Content-Type: application/json
X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<key>, sentry_client=<client>

{
  "event_id": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
  "message": "Something went wrong",
  "level": "error",
  "timestamp": "2024-01-01T00:00:00Z",
  "platform": "javascript",
  "environment": "production"
}
```

### Envelope API 格式

```
POST /api/my-project/envelope/
Content-Type: application/x-sentry-envelope
X-Sentry-Auth: Sentry sentry_version=7, sentry_key=<key>, sentry_client=<client>

{"event_id":"a1b2c3d4e5f6a7b8c9","sent_at":"2024-01-01T00:00:00Z"}
{"type":"event","length":280}
{"event_id":"a1b2c3d4e5f6a7b8c9","message":"Test message","level":"warning",...}
```

## 接入方式

其他项目如果已对接 Sentry，切换到本项目只需修改 DSN 地址。

### JavaScript/前端项目

```javascript
import * as Sentry from '@sentry/browser';

Sentry.init({
  dsn: 'http://localhost:17888/api/my-project',
  // 其他配置保持不变
});
```

### Python/后端项目

```python
import sentry_sdk

sentry_sdk.init(
    dsn='http://localhost:17888/api/my-project',
    # 其他配置保持不变
)
```

### curl 测试命令

**发送警告级别事件：**
```bash
curl -X POST http://localhost:17888/api/my-project/store/ \
  -H "Content-Type: application/json" \
  -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=test, sentry_client=test/1.0" \
  -d '{
    "event_id": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6",
    "message": "Envelope测试警告",
    "level": "warning",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S)'",
    "platform": "javascript",
    "environment": "staging",
    "tags": {"browser": "Chrome"},
    "extra": {"page": "/dashboard"}
  }'
```

**发送错误级别事件（带异常堆栈）：**
```bash
curl -X POST http://localhost:17888/api/my-project/store/ \
  -H "Content-Type: application/json" \
  -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=test, sentry_client=test/1.0" \
  -d '{
    "event_id": "err001aabbccdd",
    "message": "Uncaught TypeError",
    "level": "error",
    "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%S)'",
    "platform": "javascript",
    "environment": "production",
    "exception": {
      "values": [{
        "type": "TypeError",
        "value": "Cannot read properties of undefined",
        "stacktrace": {
          "frames": [
            {"filename": "app.js", "function": "renderUser", "lineno": 42, "colno": 15, "in_app": true}
          ]
        }
      }]
    }
  }'
```

**使用 Envelope 端点发送事件：**
```bash
curl -X POST http://localhost:17888/api/my-project/envelope/ \
  -H "Content-Type: application/x-sentry-envelope" \
  -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=test, sentry_client=test/1.0" \
  -d '{"event_id":"b2c3d4e5f6a7b8c9","sent_at":"'$(date -u +%Y-%m-%dT%H:%M:%S)'"}
{"type":"event","length":200}
{"event_id":"b2c3d4e5f6a7b8c9","message":"Test","level":"info","timestamp":"'$(date -u +%Y-%m-%dT%H:%M:%S)'","platform":"python","environment":"production"}'
```

## 架构

### 目录结构

```
rust/sentry_log/
├── src/
│   ├── lib.rs       # 模块入口，导出 API、Storage、Types
│   ├── api.rs       # 全局单例管理，HTTP 层入口函数
│   ├── storage.rs   # redb 数据库操作实现
│   └── types.rs     # Sentry 协议数据类型定义
└── Cargo.toml
```

### 核心组件

- **SentryLogStorage**：redb 数据库封装，负责事件的持久化存储
- **SentryEvent**：Sentry 事件数据结构，兼容 Sentry 协议
- **SentryLogFilter**：查询过滤器，支持多维度筛选

### 数据表

| 表名 | 用途 |
|------|------|
| `sentry_events` | 存储事件详情（event_id → JSON） |
| `sentry_projects` | 存储项目元数据（project_id → JSON） |
| `sentry_project_events` | 事件与项目的关联（`project_id:event_id` → timestamp） |

## API 列表

### Rust 层（内部调用）

| 函数 | 说明 |
|------|------|
| `sentry_log_init(db_path)` | 初始化存储引擎 |
| `sentry_log_store_event(project_id, event)` | 存储单个事件 |
| `sentry_log_store_raw_event(project_id, json)` | 存储原始 JSON 事件 |
| `sentry_log_store_envelope(project_id, body)` | 存储 Envelope 格式数据 |
| `sentry_log_query(filter)` | 查询事件列表 |
| `sentry_log_get_event(event_id)` | 获取单个事件 |
| `sentry_log_delete_event(event_id)` | 删除单个事件 |
| `sentry_log_delete_events(event_ids)` | 批量删除事件 |
| `sentry_log_get_projects()` | 获取项目列表 |
| `sentry_log_update_project_name(id, name)` | 更新项目名称 |
| `sentry_log_get_stats()` | 获取统计数据 |
| `sentry_log_export_json(filter)` | 导出事件为 JSON |
| `sentry_log_clear_project_events(project_id)` | 清空项目所有事件 |

## 注意事项

- 存储层使用 redb 嵌入式数据库，`Database` 本身线程安全，无需额外 Mutex 保护
- FRB 桥接函数除 `sentry_log_init` 外均为异步，避免阻塞 Flutter UI 线程
- 事件 ID 为空时自动生成 UUID
- 时间戳为空时自动填充当前时间