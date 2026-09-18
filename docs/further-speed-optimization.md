# 深入优化路线：把 agent shell 从 ~80ms 压向 ~10ms

> 前置阅读：`docs/one-shot-fastpath.md`（已完成的改造与基线数据）。
> 本文是**下一阶段路线图**，按收益/风险比排序，含每项的前置条件与验收方式。

## 0. 基线与预算

`niu -c "echo hello"` 端到端（安静时机），2024-09 本机复测：

```
~50ms  进程创建 + Rust runtime + main() 前置检查      ← 硬地板，进程内无法突破
  ~1ms  winuxcmd 选择 + shell root
 ~7-9ms Executor::new                                  ← 进程内最大单项（rubash 内部）
  ~1.9ms env + host handler + aliases + packs
  ~0.6ms history provider → ✅ §1 懒加载后 ~0.05ms
  ~0.5ms framework env 探测 → ✅ §3a 削减后 ~0.15ms
  ~0.1ms completion state + bundle keybindings（one-shot 已归零）
  ~0.9ms execute_script（echo hello 本体）
  ~0.4ms exit trap（one-shot 已短路探测）
```

**结论**：§1 + §3a 合计再砍 ~1ms（进程内 ~12ms → ~11ms）；同窗口交错 e2e 对拍中
低于 ±5ms 调度抖动，只能靠 trace 段数据归因。进程内剩余大头是 `Executor::new`
（rubash 上游）与别名注册（§2 上游 setter）。要突破进程创建地板只有一条路——
**常驻进程**（第 4 节），那才能到 ~10-20ms。
对拍原生 Git Bash（`perf/bench-vs-bash.sh`）：本机 `niu -c` 全命令面已快于
Git Bash 5.3（`true` 22 vs 50ms、`echo|grep -c` 43 vs 93ms，同窗口 min）。

## 1. 历史文件懒加载（✅ 已完成，~0.6ms）

`RubashHistoryProvider::with_file` 原本在启动时打开历史文件。现在只记录参数，
首次被 `history`/`fc` 相关 builtin 触达时才真正打开（`Option<LiveFileBackedHistory>`
+ `opened()` 按需初始化）；构造不再可能失败，坏历史文件从"启动失败"降级为
"builtin 报错"，对一次性命令更友好。REPL 的 `LiveFileBackedHistory`（repl.rs）
不受影响，仍是交互侧的 history 拥有者。

- 实测：启动 trace history provider 段 0.6-0.75ms → **0.03-0.07ms**。
- 契约：host_contract 的 history/fc 用例全绿（只是延迟打开）。
- 注意：该段 tick 之间还夹着 host env 默认值写入，故新增了 `host env defaults`
  / `framework env` 两个细分 tick（见 §3a）。

## 3a. 框架目录探测削减（✅ 已完成，~0.5ms）

`set_default_niubash_framework_env`（trace `framework env` 段）原本在无 bundle
机器上走最坏路径：exe 侧 2 候选 × 3 次 `is_file` stat + home 侧 4 候选 × 3 stat
+ 2 次 `read_dir` ≈ 18 次系统调用，实测 0.29-0.9ms。三处结构性削减：

- `app_bundled_niubash_framework_dir`：先用 1 次 stat 判 `<exe_dir>/bundles`
  目录，不存在直接返回（1 次 miss 代替 6 次）；
- `first_valid_niubash_framework_dir`：`~/.niubash/bundles` 根目录一次 stat
  通过后才执行 2 次 `read_dir` 版本枚举；
- `is_niubash_framework_dir`：`is_dir` 前置，单次 stat 否决代替 3 次 `is_file`。

- 实测：`framework env` 段 0.29-0.9ms → **0.13-0.27ms**（无 bundle 机器）。
- 契约：有 bundle 的机器探测结果与原逻辑逐字节一致（只是减少否定路径的
  stat 次数）；`plugin_inventory` 别名契约（bundle 清单优先）仍绿。
- 残余：4 次 home 候选 stat；可再做磁盘负缓存（记录"本机无 bundle"），
  预期再省 ~0.15ms，状态文件失效语义复杂度不划算，暂缓。

## 3b. 静态 CRT（实测不采纳）

`RUSTFLAGS="-C target-feature=+crt-static"` 全量重建后 100 轮交错 `niu -c true`：
min 17.2 vs 20.1ms（略优）、avg 37.3 vs 36.2ms（略差）——信号混杂无法归因，
且二进制 +1.1MB、偏离默认配置。不采纳；机器安静窗口可复测。

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
| 1 | history 懒加载 | ~0.6ms | ✅ 已完成 | — |
| 3a | 框架探测削减 | ~0.5ms | ✅ 已完成 | — |
| 3b | 静态 CRT | 0（信号混杂） | 已实测 | 不采纳 |
| 2 | `Executor::set_alias` 上游 PR | ~1.3ms + 解锁 one-shot 砍别名 | 1-2 天跨仓库 | 做 |
| 3 | `Executor::new` 剖析 | 0~7ms（未知） | 1-3 天 | 先 profile 再定 |
| 4 | DSH 直连 | -100ms（宿主侧） | DSH 侧小改 | 做 |
| 5 | `niu-agentd` | 81ms → 10-20ms | 1-2 周 + 长期维护 | 视调用量 |
