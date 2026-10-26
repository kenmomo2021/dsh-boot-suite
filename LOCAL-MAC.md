# macOS 本地适配（非官方个人 fork）

> ⚠️ **这不是官方版本，和原作者没有隶属或背书关系。**
>
> 原项目：[**dsh-boot-suite**](https://github.com/LeeRolling/dsh-boot-suite) · 作者：**沈宏宏 · [LeeRolling](https://github.com/LeeRolling)** · MIT License
>
> 本仓库是 macOS 用户的个人自用适配：只补 mac 上跑不通的地方 + 本地安装/同步脚本。
> **Windows 代码路径一行未改**；Windows 用户请直接使用原仓库和作者的 Release。
> 原作者没有审核过这份改动；如果作者认为不合适，本 fork 会停止公开。

基线：上游 `v2.13.0`（commit `147fec0`）· DSH 0.2.1-rc.3 · macOS 26.3.1

## 适合谁 / 不适合谁

| | |
|---|---|
| **适合** | 会用终端、能接受 `link:` 方式安装的 macOS 用户；想自己改代码/换模板的人 |
| **不适合** | 想要图形安装包或一键更新的用户（mac 上更新 = `git` 同步 + 重开 DSH） |
| **另有官方版本** | Windows 用户请用[原作者仓库](https://github.com/LeeRolling/dsh-boot-suite)，功能、发布包、更新都由作者维护 |
| **支持承诺** | 没有。可以提 issue，但这是个人 fork，不保证响应；和原作者无关 |

## 分支模型

| 分支 | 作用 | 规则 |
|---|---|---|
| `main` | 作者仓库镜像 | 只 fast-forward，永不提交 |
| `mac` | `main` + 本地适配（**默认检出**） | 只放小改动，方便 rebase；DSH 的 `link:` 安装指向这份工作区 |

```
upstream/main ──► main（镜像分支）
        └──────► mac（= main + 本地提交）──► origin/mac（自己的 fork）
```

## 改了什么（全部在 mac 分支）

| 文件 | 改动 | 原因 |
|---|---|---|
| `lib/host-wallpaper.js` | `/video`、`/videos/delete` 不再把 `/` 换成 `\` | POSIX 上必挂：视频播放 404、删除报 `outside root`（mac 上 `npm test` 17 项红） |
| `lib/host-wallpaper.js` | 新增 `openFolder()`：darwin `open` / win `explorer.exe` / linux `xdg-open` | 「打开文件夹」「打开视频目录」原来只认 `explorer.exe`，mac 上静默失败 |
| `lib/host-startup.js` | 5 条更新路由在 macOS 上直接返回提示 | 内建更新器是 PowerShell + `.cmd`，mac 上跑不了；提前拦掉，避免报错或崩宿主 |
| `tools/mac-profile.mjs` | profile 的 dependencies / bundles / link 助手 | 对应作者 `install.ps1` 里改 profile 的那部分 |
| `tools/install-mac.sh`、`tools/uninstall-mac.sh` | macOS 安装 / 卸载 | 作者的一键安装是 `.cmd` + PowerShell |
| `tools/sync-upstream.sh`、`tools/install-sync-agent.sh` | 同步上游 / launchd 定时任务 | 「时刻同步」 |
| `安装-mac.command`、`卸载-mac.command`、`同步上游-mac.command` | 双击入口 | 不用记命令 |
| `LOCAL-MAC.md` | 本文档 | — |

原则：**Windows 代码路径一行不改**，只在前面加 `process.platform` 判断 —— 这样 rebase 到上游时冲突最小。

## 安装（一次性）

1. ⌘Q **完全退出** DeepSeek Harness（菜单栏图标也要退）
2. 双击 `安装-mac.command`；或终端执行：

   ```bash
   ./tools/install-mac.sh --check   # 先看计划，不改任何东西
   ./tools/install-mac.sh           # 真正安装（会备份 profile 配置）
   ```

3. 手动打开 DSH，确认三件事：
   - 设置页多出「启动动画」和「聊天背景」两项
   - 冷启动会播开机动画（第一幕 → 第二幕）
   - 动画结束后落在聊天底图上（大字横幅可选）

装的是 `link:` 依赖 —— 以后改代码、同步上游，**重开 DSH 即可生效**，不用重新安装。

## 卸载

⌘Q 退出 DSH → 双击 `卸载-mac.command`。用户配置默认保留，脚本最后会列出需要手动删的路径。

## 跟作者仓库同步

```bash
./tools/sync-upstream.sh            # 只检查：落后几个提交、上游改了什么（默认）
./tools/sync-upstream.sh --apply    # 同步：rebase + npm test（失败自动回滚）
```

流程：`git fetch upstream` → `git rebase upstream/main` → `npm test` → `git branch -f main upstream/main`。

- 冲突：自动 `git rebase --abort`，保持同步前状态
- 测试失败：自动回滚到同步前，失败现场存到 `mac-sync-failed` 分支
  （`git diff mac mac-sync-failed` 查看；确认不要了就 `git branch -D mac-sync-failed`）
- 已开 `git rerere`，同一处冲突下次会复用上次解法
- 同步后**重开 DSH** 生效

### 时刻同步（可选）

```bash
./tools/install-sync-agent.sh                  # 每小时自动同步一次
./tools/install-sync-agent.sh --interval=1800  # 每 30 分钟
./tools/install-sync-agent.sh --uninstall      # 卸掉
```

launchd 任务的行为（= `sync-upstream.sh --auto`）：

- DSH 正在运行 → **跳过**（下次再试）
- 工作区有未提交改动 → 跳过
- 同步失败 / 测试失败 → 自动回滚 + macOS 通知

日志：`~/.dsh/boot-suite-mac-sync.log`

> 为什么 DSH 运行时跳过：插件是 `link:` 安装，DSH 直接读工作区文件。边用边换文件，刷新页面时可能出现「新客户端 + 旧宿主」的版本错配。

## 自己的 fork

> 如果你要复用这套东西：先把 `origin` 换成你自己的账号（下面命令），否则 `--push` 会推到本仓库。

```bash
git remote set-url origin git@github.com:<你的账号>/dsh-boot-suite.git
git push -u origin main
git push -u origin mac
```

之后同步时加 `--push`（`mac` 会被 rebase，用 `--force-with-lease` 推送属正常）：

```bash
./tools/sync-upstream.sh --apply --push
```

### 本机网络的坑：SSH 必须走 443

这台机器的代理（TUN 模式）会掐掉 `github.com:22`，直连 SSH 22 会被 `198.18.0.88` 关闭。
已在本仓库里配好：

```bash
git config core.sshCommand "ssh -o Hostname=ssh.github.com -p 443 -o StrictHostKeyChecking=accept-new"
```

所以在本仓库 `git push` 直接能用。想全局生效，在 `~/.ssh/config` 里加：

```
Host github.com
  HostName ssh.github.com
  Port 443
  User git
```

## 署名与许可

- 原项目、模板、素材、文档的版权与署名归原作者 **沈宏宏 · LeeRolling**；`LICENSE` 和 `package.json` 的 `author` 保持原样未改。
- 本 fork 新增的脚本与文档（`tools/*-mac*`、`tools/mac-profile.mjs`、`tools/sync-upstream.sh`、`LOCAL-MAC.md`、`*.command`）同样按 **MIT** 授权，可自由取用、修改、甚至整理成 PR 提回上游。
- 转载/再分发请保留原作者署名和本声明，不要把它说成官方版本。

## 已知限制

- **插件内建更新在 macOS 上不可用**：设置页仍会提示「有新版本」，点更新会提示改用 git 同步（代码里已拦截）。mac 上的更新 = `sync-upstream.sh --apply` + 重开 DSH。
- `README.md` 顶部加了一段非官方声明（方便从 fork 进来的人认出来），其余内容保持作者原样；`INSTALL.md` / `DESKTOP.md` 仍是作者的 Windows 口径，刻意不改（减少和上游的冲突）。
- `tools/build-release.mjs`、`tools/*.ps1`、`*.cmd` 是 Windows 发布/安装用的，mac 上用不到，没动。
- 上游如果自己修了这两个路径 bug，rebase 可能冲突：确认后 `git rebase --skip` 丢掉我们的补丁即可（补丁只有几行，删起来很快）。
- 本分支是个人维护，没跑过 Windows 侧；Windows 行为依赖「原代码不动」这个约定来保证。
