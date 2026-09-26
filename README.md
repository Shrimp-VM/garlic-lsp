# Garlic LSP

## **这个文档是AI写的！！！**

Garlic 语言的 Language Server，以 EditorPlugin 子节点（`GarlicLspServer`）随 ShrimpVM 插件常驻 Godot 编辑器进程，为 `.srk` 脚本提供补全、hover 和实时诊断。

## 架构

分层设计，每层只依赖上一层：

| 模块                     | 职责                                                                            |
|--------------------------|---------------------------------------------------------------------------------|
| `lsp_framing.gd`         | LSP base protocol 传输层：Content-Length 帧的切分与编码                         |
| `lsp_json_rpc.gd`        | JSON-RPC 消息的编解码，区分 request / notification / response                   |
| `lsp_server.gd`          | 请求路由：initialize、completion、hover、diagnostic、didOpen/didChange/didClose |
| `lsp_workspace.gd`       | 文档状态管理，保存每个 URI 的最新文本                                           |
| `lsp_features.gd`        | 语言功能实现：补全、hover 的结果组装                                            |
| `lsp_analyzer.gd`        | 基于 token 的上下文状态机（不依赖 AST），驱动补全上下文判定与诊断收集           |
| `lsp_schema_registry.gd` | 从 ShrimpVM 收集节点 schema，缓存 30s TTL                                       |
| `client.gd`              | 开发自测客户端，含 `self_test()` 端到端冒烟测试                                 |

## 传输

- TCP 直连 `127.0.0.1:6009`，LSP base protocol 直接跑在 TCP 上，客户端侧（如 VSCode 桥）只需字节透传
- 端口可通过 ProjectSettings `shrimpvm/garlic/lsp_port` 配置
- 单客户端：同一时刻只接受一个连接，断开后自动重置帧状态等待重连

## 能力

```json
{
  "positionEncoding": "utf-16",
  "textDocumentSync": {"openClose": true, "change": 1},
  "completionProvider": {"triggerCharacters": ["=", "("]},
  "hoverProvider": true,
  "diagnosticProvider": {"interFileDependencies": false, "workspaceDiagnostics": false}
}
```

- **补全**：识别 6 种上下文（node_name / key / value / array_item / string / none），按上下文返回精准候选——节点名、未使用的属性键、类型匹配的值、数组槽位类型；string 与 none 上下文不返回候选
- **诊断**：`textDocument/didOpen` / `didChange` 后标记脏文档，每 0.3s 批量 flush 一次 `publishDiagnostics`，避免高频输入下的重复分析
- **位置编码**：服务器内部使用 Godot 字符索引，在边界处与 UTF-16 code unit 互转（`utf16_to_char` / `char_to_utf16`），对客户端透明

## 自测

服务器随 Godot 编辑器启动后，可运行端到端冒烟测试：

```gdscript
var client = GarlicLspClient.new()
print(client.self_test())
```

返回 initialize / completionItems / hover / shutdown 各项结果。headless 联测需要两个进程：server 宿主（`extends SceneTree`）加 client（`-s` 脚本），注意 `_initialize` 阶段 add_child 的节点要到首帧才执行 `_ready`。

## 已知限制

- document symbols 与 goto definition 需要带 span 的容错解析器，暂未实现
- 不支持 workspace 级诊断与跨文件依赖分析
