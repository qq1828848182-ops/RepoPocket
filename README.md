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
- 发现近期新建的热门仓库，打开 GitHub 官方热门仓库 / 开发者榜单
- 浏览器设备授权登录（需自行配置 OAuth App Client ID 并启用 Device Flow）
- 跟随系统 / 浅色 / 深色外观

## 1.1.0 预览版说明

新增功能不替换原有文件提交、本地工作区、插件编辑和发行版管理。
Issue / PR 首版为只读浏览，回复和管理操作打开 GitHub 网页。
活动和协作列表每页 30 条，最多显示 300 条，超出可在 GitHub 查看；失败后可重试当前页。
README 排版上限 256 KiB；代码高亮预览上限 128 KiB，原始文本及编辑器保留原来的 1 MiB 加载限制。
图片和外部工具不使用 GitHub Token，私有图片可能需要在 GitHub 网页登录后查看。
发现页原生列表按近期新建仓库的累计 Star 排序，不等于 GitHub Trending 的增长榜。
Star 历史和代码行数工具是外部网站入口，语言统计显示字节数，不冒充代码行数。

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
