# RepoPocket

RepoPocket 是一款适用于 iOS 16+、TrollStore 的 GitHub 文件管理工具。

部分功能根据个人使用需求开发，本项目由 AI 辅助编写、编译和整理。

![累计下载次数](https://img.shields.io/github/downloads/wm0104/RepoPocket/total?label=Downloads&color=007AFF)
![最新版本](https://img.shields.io/github/v/release/wm0104/RepoPocket?label=Release&color=007AFF)

## 功能

- 管理多个 GitHub 账号
- 浏览仓库、分支和文件
- 新建、编辑、上传和删除文件
- 提交文件修改并查看提交记录
- 创建和切换分支
- Fork 仓库和创建新仓库
- 编辑并上传 `.deb` 插件文件
- 管理 `.dylib` 插件的版本、名称、作者等元信息，目前适配 LSP 版 TrollFools 插件源格式，不涉及插件二进制代码修改
- 管理本地工作区文件
- 管理你的 `发行版`
- 阅读 README 和 Markdown（表格、图片、任务列表、链接等）
- 查看 Issue / PR、讨论评论、审查记录、行内评论及 PR 文件差异
- 代码阅读高亮、仓库搜索语言筛选和排序
- 用户资料、公开活动、关注动态、贡献者和语言字节统计
- 发现近期新建的热门仓库和活跃开发者，原生浏览资料与仓库
- 浏览器设备授权登录（需自行配置 OAuth App Client ID 并启用 Device Flow）
- 跟随系统 / 浅色 / 深色外观

## 1.1.1 预览版说明

仓库首页按简介、协作入口、分支与代码、底部 README 排列；长 README 可展开或收起。
列表使用缩进分隔线，沿用 1.0.4 的 22 点分组圆角；中间行不再重复显示顶部圆角。
原有文件提交、本地工作区、插件编辑和发行版管理继续保留。

Issue / PR、评论、审查记录和文件差异在 App 内阅读；支持新建议题、回复、关闭或重新打开，以及有权限时确认合并 PR。
Actions 支持运行列表、任务步骤、文本日志、产物下载，以及有权限时确认重跑或取消；这些操作由 GitHub 最终校验权限。
文件历史、贡献者、语言字节统计、Star 时间分布和公开活动图均有原生页面。
README 的仓库、议题、PR、提交和 Actions 链接可进入原生页面；暂未支持的网页在 App 内浏览器打开。
OAuth 仍需通过 GitHub 授权页面完成登录。

协作和 Actions 列表每页 30 条，最多加载 300 条；失败可重试当前页。
README 排版上限 256 KiB；代码高亮预览上限 128 KiB，原始文本及编辑器保留原来的 1 MiB 加载限制。
日志仅预览前 256 KiB。图片不附带 GitHub Token，私有图片可能无法加载。
发现页按近期新建仓库的累计 Star 排序，不等于 GitHub Trending 增长榜。
Star 图按最近最多 1,000 位当前加星用户的时间汇总，不含已取消的 Star；公开活动图也不是完整贡献日历。
代码行数按固定提交扫描最多 40 个源文件、每文件 128 KiB、总计 2 MiB；包括空行和注释，并明确显示跳过文件与不完整结果。

### 浏览器授权

在 GitHub Settings → Developer settings → OAuth Apps 创建自己的应用，并勾选 Enable Device Flow。
在 RepoPocket 的账号管理 → 使用 GitHub 浏览器授权中填写 Client ID；不需要 Client Secret 或自己的服务器。
默认只请求 `read:user public_repo`，可主动开启 `repo` 以访问私有仓库。
Token 登录和原有权限检查继续保留；设备授权不会自动申请删除仓库等额外权限。
取消、离开授权页面或切换账号会停止轮询，授权码不落盘；成功后凭据保存到原有钥匙串。

## 下载

[下载 RepoPocket](https://github.com/wm0104/RepoPocket/releases/latest)

系统要求：iOS 16 或更高版本。低于 iOS 16 的系统未测试，请自行测试。

## 相关仓库

[TrollFools LSP 修改版插件源](https://github.com/wm0104/trollfools-repo)
