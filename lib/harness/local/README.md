# Local harness host

本机 harness 的发现、启动与日志读取。桌面版把 Studio 自己启动的终端会话
和历史日志会话合成一个列表，实现 `lib/harness/harness_host.dart` 契约里的
`HarnessHost`（`id` 为 `local`，`kind` 为 `local`）。

## 组成

| 文件 | 职责 |
| --- | --- |
| `harness_provider.dart` | 提供方模型、内置表、`qfli_harness_providers.json` 解析 |
| `executable_locator.dart` | 配置路径 → PATH → 平台安装目录的探测，Windows 按 PATHEXT 补全 |
| `provider_registry.dart` | 合并内置与用户提供方，暴露 `HarnessProviderInfo` |
| `pty_process.dart` | PTY 抽象与两个后端：`script`（macOS/Linux）、`pipe`（Windows） |
| `studio_mux.dart` | 会话进程、状态、滚动缓冲、显式结束 |
| `transcript_log_reader.dart` | jsonl 尾部窗口、公共解析、id 规则 |
| `claude_code_log_reader.dart` / `codex_log_reader.dart` / `pi_log_reader.dart` | 各 harness 的日志解析 |
| `live_log_follower.dart` | 直播会话按工作目录找到日志并增量推送事件 |
| `local_harness_host.dart` | `HarnessHost` 实现与会话句柄 |

## 用法

```dart
final host = LocalHarnessHost();
final providers = await host.providers();
final handle = await host.launch(
  HarnessLaunchRequest(providerId: 'claude', cwd: projectPath),
);
handle.terminal?.write(Uint8List.fromList(utf8.encode('hello\r')));
```

`open()` 对直播会话返回终端与（有日志时）结构化对话，对历史会话只返回
transcript。`detach()` 只释放视图，`stop()` 才结束进程，调用方必须先取
用户确认。

## 用户提供方配置

应用支持目录下的 `qfli_harness_providers.json`，与内置项同 schema：

```json
{
  "providers": [
    {
      "id": "aider",
      "label": "Aider",
      "executable": "aider",
      "args": ["--no-auto-commits"],
      "env": {"AIDER_CHECK_UPDATE": "false"},
      "logDirectory": "~/.aider/sessions",
      "logFormat": "claude",
      "detectPaths": ["~/.local/bin/aider"],
      "enabled": true,
      "requiresTerminal": true
    }
  ]
}
```

同 `id` 的用户项覆盖内置项；把某个内置项写成 `"enabled": false` 就是不
再提供它（例如禁用 `claude`）。`logFormat` 只接受 `claude`、`codex`、
`pi`；未知值降级为无日志并记录诊断。文件上限 64 KiB，解析失败时保留
内置项。

`requiresTerminal` 默认为 `true`：这类 harness 在管道后端下不会出现在
“新建会话”菜单里（见下一节），避免给出一个必定卡住的入口。shell 与
批处理型 harness 可显式写 `false`。

## PTY 后端

| 平台 | 策略 | 真实终端 | 运行期改尺寸 |
| --- | --- | --- | --- |
| macOS / Linux | `script`（初始 `stty` 设定行列） | 是 | 否 |
| Windows | `pipe`（`.cmd`/`.bat` 经 `cmd.exe /c`） | 否 | 否 |
| 移动端 / Web / 鸿蒙 | `unsupported` | — | — |

Windows 目前没有 ConPTY 绑定，交互式 TUI 会退化成管道模式。因此
`providers()` 在 `allocatesTerminal == false` 时把需要真实终端的 harness
（`claude`、`codex`、`pi` 等）标成 `available: false`，`launch()` 也会
明确报错；shell 不受影响。会话层已经通过 `PtyLauncher` 留出接口，补上
原生实现（或接上 Pi-B 的 `HarnessPtyFactory`）即可获得真实终端与
`ResizePseudoConsole`，无需改动 `StudioMux`。
