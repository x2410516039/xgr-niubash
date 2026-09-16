# 深入优化路线：把 agent shell 从 ~80ms 压向 ~10ms

> 前置阅读：`docs/one-shot-fastpath.md`（已完成的改造与基线数据）。
> 本文是**下一阶段路线图**，按收益/风险比排序，含每项的前置条件与验收方式。

## 0. 基线与预算

当前 `niu -c "echo hello"` 端到端 ~81ms（安静时机），构成：

```
~50ms  进程创建 + Rust runtime + main() 前置检查      ← 硬地板，进程内无法突破
  ~1ms  winuxcmd 选择 + shell root
 ~7-9ms Executor::new                                  ← 进程内最大单项
 ~1.9ms env + host handler + aliases + packs
 ~0.7ms history provider（含历史文件打开 I/O）
 ~0.1ms completion state + bundle keybindings（one-shot 已归零）
 ~0.9ms execute_script（echo hello 本体）
 ~0.4ms exit trap（one-shot 已短路探测）
```

**结论**：进程内还剩 ~12ms 可挖（收益上限：81ms → ~50ms 地板）。
要突破地板只有一条路——**常驻进程**（第 4 节），那才能到 ~10-20ms。

## 1. 历史文件懒加载（低成本，~0.7ms）

`RubashHistoryProvider::with_file` 在启动时打开历史文件。改为首次调用
`history`/`fc` 相关 builtin 时才打开（`Option<Provider>` + 按需初始化）。

- 契约：`host_contract.rs` 的 history/fc 语义不变（只是延迟打开）。
- 风险：低。验收：host_contract 全绿 + 启动 trace 中 history provider 段 <0.1ms。

## 2. `Executor::set_alias`（上游 PR，~1.3ms）

rubash 的别名表是私有 `HashMap<String, Alias>`，niubash 只能逐条
`tokenize→parse→execute_ast` 注册配置别名（本机 ~1.3ms）。

- 做法：rubash 增加公开 setter（直插 map + 标记 expand_aliases 语义），niubash 构造器改调用它。
- 顺带解锁：one-shot 模式砍掉全部别名注册（对 agent 场景别名本就无意义，见
  one-shot 文档 §2.3 的前置条件）。
- 风险：中（跨仓库）；验收：`plugin_inventory` 别名契约仍绿（setter 的语义必须与
  `alias name=value` builtin 完全一致，含引号处理）。

## 3. 剖析 `Executor::new`（上限 ~7-9ms，收益不确定）

one-shot 后进程内最大单项。需先用 `NIU_TRACE_STARTUP` 在 rubash 内部加细分 tick，
确认时间去向：

- 若是 builtin 注册表构造 → 改静态/编译期表（`lazy_static` 或 const fn）；
- 若是解析器/词法表初始化 → 同上；
- 若有隐藏 I/O（PATH 扫描、目录枚举）→ 懒加载。
- 风险：中；验收：host_contract + compat 全绿，trace 分段数据前后对比。

## 4. `niu-agentd` 常驻进程（突破地板，目标 ~10-20ms/次）

唯一能绕过 ~50ms 进程创建地板的方案。文档 `niubash优化适配.md` 第 4 步的原判断
（缓行）依然成立，此处给出设计骨架供决策：

```
DSH/ZCode Bash 工具
  → niu-client（~1ms，负责 spawn 与协议）  [或直接由宿主进程发 IPC，零 client]
  → named pipe / localhost IPC
  → niu-agentd：已初始化的 Rubash runtime 池
  → execute + 返回 stdout/stderr/exitCode
```

必须解决的隔离问题（每一个都是坑，缺一不可）：

| 问题 | 要点 |
|---|---|
| cwd | 每次调用带 cwd 参数；agentd 在执行前 `set_current_dir`，池化 runtime 需按 cwd 串行或一请求一 runtime |
| env | 调用间隔离：diff-based env 快照，或每请求重建 executor（重建 ~7-9ms，折损收益） |
| 并发 | Bash 工具可能并发；按 session 排队或按 cwd 分片 |
| Ctrl+C | Windows 无进程组信号；需 job object + GenerateConsoleCtrlEvent 路由 |
| stdin | 管道桥接（one-shot 已有 `inherit_process_stdin` 经验） |
| 后台任务/长命令 | 超时与取消：TerminateJobObject 树杀 |
| 状态污染 | cd/变量/set -e 残留：默认每请求隔离，显式 opt-in 会话粘性 |

**建议**：先做第 1-3 节（合计可到 ~50ms 地板），agentd 等 DSH 直连落地后
按真实调用量决定是否值得复杂度。

## 5. DSH 直连集成（宿主侧，非本仓库）

DSH 的 Bash 工具直接以 `niu.exe` 为 shell：省掉 ZCode hook 改写段（~80ms），
单命令即 ~80ms；叠加 agentd 后 ~10-20ms。

- DSH 侧用 `--encoded-command` 程序化拼参（无引号问题；不经 Git Bash 时 `v1:` 可省）。
- 注意 fail-open 语义由 DSH 自行实现（niu 直连后没有 hook 层兜底）。

## 6. 测量纪律

- 一切对比用**同窗口交错**（round-robin）计时，取 min 为信号、avg 为参考；
- 每次改动跑 `cargo test` 全量 + `perf/battery.sh` 行为对拍，契约护栏清单见
  one-shot 文档 §2.3；
- trace 用 `NIU_TRACE_STARTUP=1`，分阶段取 5 次 min（脚本 `perf/trace-min.sh`）。

## 7. 优先级总表

| # | 项目 | 预期收益 | 成本 | 建议 |
|---|---|---|---|---|
| 1 | history 懒加载 | ~0.7ms | 半天 | 做 |
| 2 | `Executor::set_alias` 上游 PR | ~1.3ms + 解锁 one-shot 砍别名 | 1-2 天跨仓库 | 做 |
| 3 | `Executor::new` 剖析 | 0~7ms（未知） | 1-3 天 | 先 profile 再定 |
| 4 | DSH 直连 | -100ms（宿主侧） | DSH 侧小改 | 做 |
| 5 | `niu-agentd` | 81ms → 10-20ms | 1-2 周 + 长期维护 | 视调用量 |
