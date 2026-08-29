# 项目任务书：xbar 插件迁移成原生 SwiftUI 菜单栏 App

## 核心思路：只换展示层，数据层原封不动

现有的两个数据抓取脚本（`fetch_claude_usage.py`、`fetch_antigravity_usage.py`）和 launchd 定时任务，**已经跑通、经过实战验证过所有的坑**（Keychain 存凭证、SSL 证书、时区转换、CSRF token 提取、`lsof -a` 那个隐蔽 bug……），这些全部保留不变，继续按原来的方式定时跑、写入这两个缓存文件：

```
~/.claude/rate_limits_cache.json
~/.antigravity/quota_cache.json
```

**只把"读这两个文件、渲染成界面"这一层，从 xbar 插件换成真正的原生 macOS App**，用苹果官方给菜单栏小工具设计的 API：SwiftUI 的 `MenuBarExtra`。

这样做的好处：数据获取这边最难、最容易踩坑的部分完全不用重新折腾一遍；只需要写界面渲染，而且换成真原生 UI 之后，之前被 xbar 卡住的那几个限制（标题栏没法分段上色、SF Symbols 支不支持还得现测、白色文字在浅色背景看不清）全都不存在了。

---

## 你需要自己动手的部分（没法完全交给 Agent）

### 1. 在 Xcode 里建一个新工程

Xcode 工程文件本身格式复杂，让 Agent 从零手写容易出错，这一步自己在 GUI 里点几下最快最稳：

1. 打开 Xcode → File → New → Project
2. 选 **macOS** → **App**
3. Interface 选 **SwiftUI**，Language 选 **Swift**
4. 项目名随便取（比如 `QuotaMenuBar`），存到你喜欢的位置（不要存进 Antigravity 的 scratch 目录，参考之前的教训）

### 2. 把它设置成"只在菜单栏出现"的纯 Agent 应用

建好工程后：
1. 点左侧导航栏的项目名（最顶层，蓝色图标）
2. 选中 Target → **Info** 标签页
3. 找到（没有就新建一个）key 叫 `Application is agent (UIElement)`，值设成 **YES**

这样运行起来这个 App 不会在 Dock 里出现图标、也不会弹出普通窗口，纯粹是个菜单栏小工具——这是原生实现"只活在菜单栏"的正规做法，效果上等价于现在 xbar 插件的角色。

### 3. 把工程路径交给 Claude Code / Antigravity

告诉 Agent 这个已经建好的工程在哪，让它在这个**已有工程里**添加/修改 Swift 文件，不要自己另建工程结构。

---

## 交给 Agent 写的部分

### 数据读取
写一个 Swift 结构体/函数，读取上面那两个 JSON 缓存文件，解析出跟现在 xbar 插件读的内容一样的字段（剩余百分比、重置时间、更新时间）。这部分逻辑照抄 `claude-quota.30s.py` 里对应的解析逻辑就行，字段名和结构完全不变。

### 界面
用 `MenuBarExtra` 场景 + SwiftUI 视图渲染，设计语言延续 `UI_REDESIGN_BRIEF_v2.md` 那份任务书，但因为现在是真原生界面了，明确告诉 Agent 这几个限制不用再迁就：
- 可以任意元素独立上色，不用担心"一行只能一个颜色"
- 用真正的 SF Symbols：`Image(systemName: "cloud")`、`Image(systemName: "sparkles")`，不用再猜支不支持
- 深浅色模式用系统语义色（`Color(.systemGreen)`、`Color(.labelColor)` 这类），SwiftUI 会自动适配，不用手动处理"浅色背景白字看不清"这种问题
- 进度条可以用 SwiftUI 原生的 `ProgressView`，不用再拼 `████░░░░` 这种字符画

### 刷新机制
`MenuBarExtra` 本身不会自动感知文件变化，需要一个定时器（比如每 30 秒）重新读一次那两个缓存文件、刷新界面——跟 xbar 插件文件名里 `.30s.` 那个约定是一回事，只是现在要在 Swift 里自己实现这个定时刷新。

---

## 跟之前不一样的地方：这次没法完全靠命令行验证效果

Agent 能用 `xcodebuild` 在命令行编译，抓到语法错误、编译报错，**但看不到编译出来的菜单栏实际长什么样**。跟你这几天一直在做的事情本质上是一样的——图形界面这块，还是需要你自己在 Xcode 里按 `Cmd + R` 跑起来、截图发给 Agent 看,它才能根据实际效果继续调整。这个"人工看效果、反馈截图"的环节省不掉，是图形界面开发本身的特点，不是这次流程有什么问题。

---

## 关于签名，纯自用不用花钱

在自己这台 Mac 上开发、运行、调试，Xcode 用你自己的 Apple ID 免费签名就够了，不需要付费的 Apple Developer Program（$99/年那个）。第一次运行如果被 Gatekeeper 拦一下，去 系统设置 → 隐私与安全性 里允许一次就行。只有想把这个 App 分发给别人、装到别的 Mac 上，才需要考虑付费账号和公证（notarization）——纯自己用完全不需要。

## 验收标准
- 运行起来后，Dock 里没有图标，只在菜单栏出现
- 显示内容跟现有 xbar 版本一致：Claude 5h/7d、Gemini 额度，各自剩余百分比、倒计时、更新时间
- 深浅色菜单栏背景下都清晰可读
- 数据每 30 秒左右自动刷新一次（读缓存文件，不重新发请求，请求频率还是由现有 launchd 定时任务控制）
