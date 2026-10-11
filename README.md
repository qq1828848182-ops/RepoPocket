# RepoPocket

RepoPocket 是一款适用于 iOS 16+、TrollStore 的 GitHub 文件管理工具。

部分功能根据个人使用需求开发，本项目由 AI 辅助编写、编译和整理。

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

### 本地工作区使用

导入会复制文件。请编辑 RepoPocket → Repositories 中的实际副本，而不是原下载目录。返回前台不会自动扫描或检查远端；编辑或删除文件后，点“刷新变更”或下拉刷新。首次打开和实际导入、下载、关联、提交、拉取、删除工作区之后仍会更新结果。

“刷新变更”只检测本地变更，不会建立远端关联。本地新增、修改、删除均可先勾选；提交需要可靠关联的基线。验证原始导入快照及历史 commit 可保留当前编辑，不要求当前本地内容等于远端。已关联工作区里的文件删除可在手动刷新后勾选提交；提交仍检查本地扫描快照及远端分支，拒绝过期数据和强推。

## 相关仓库

[TrollFools LSP 修改版插件源](https://github.com/wm0104/trollfools-repo)

## 下载

[下载 RepoPocket 1.0.1（build 7）](https://github.com/wm0104/RepoPocket/releases/download/v1.0.1/RepoPocket.ipa) · [SHA256 校验文件](https://github.com/wm0104/RepoPocket/releases/download/v1.0.1/RepoPocket.ipa.sha256) · [历史版本](https://github.com/wm0104/RepoPocket/releases)

系统要求：iOS 16 或更高版本。低于 iOS 16 的系统未测试，请自行测试。