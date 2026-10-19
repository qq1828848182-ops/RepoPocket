# RepoPocket 1.0.9 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完成已批准的首页分组、列表搜索、议题回复和按日活动图。
**Architecture:** 复用仓库集合页、账号隔离的GitHub读取通道和分组行。新逻辑用独立Foundation模型，界面与模型分离；议题和活动的请求由页面状态持有。
**Tech Stack:** Swift 5、SwiftUI、Foundation、XCTest、现有Python原生测试夹具。
**Spec:** ../specs/2026-10-19-home-community-design.md

## Global Constraints
- iOS16，版本1.0.9，无新依赖，README不改。
- 22点连续圆角，沿用分隔线；账号切换隔离；无滚动刷新。
- 只通过Actions交付IPA，全部通过后强制关机。

## Review Focus
- 过滤后空结果、单行、多行的分组边界和分页范围提示。
- 议题搜索排除PR，API URL中仓库解析严格，账号切换不可显示旧数据。
- 引用回复嵌套引文、删除用户、空正文、Unicode及总长度上限。
- 活动截断在同一天、无记录、非法日期、跨月跨年和北京时间日期边界。
- 页面返回、滑动和失败后保持状态，刷新取消旧请求且可显式重试。

### Task 1: 首页与四个列表搜索
Files: RepositorySections.swift, RepoPocketApp.swift, UserConnectionsView.swift, ListSearchField.swift; Tests/test_home_community.py, StyleUITests.
- [ ] 添加失败的主页导航/搜索UI契约和原生过滤测试。
- [ ] 合并首页入口；复用集合页，统一显式搜索框；添加无结果与范围提示。
- [ ] 本地契约检查、CI原生和模拟器验证。

### Task 2: 我的议题与明确引用回复
Files: HomeCommunityModels.swift, PersonalIssuesView.swift, CommunityAPI.swift, CollaborationViews.swift, CollaborationComposer.swift.
Interfaces: PersonalIssueFilter; PersonalIssueRules.repository(item), query(login,filter); CommentReplyContext.body(reply,repo,number).
- [ ] 为查询、来源、引用和空回复写原生回归夹具。
- [ ] 首页显示3条；独立分页列表和筛选；评论对应对象和实际引用内容一致。
- [ ] 验证取消不发送、发送确认和账号隔离。

### Task 3: 按日公开活动
Files: ActivityCalendar.swift, ActivityCalendarView.swift, NativeStatisticsView.swift.
Interfaces: ActivityDay; ActivityCalendar.days(events,exhausted,now); ActivityCalendarStore.load(refresh,api,login).
- [ ] 写日期、去重、部分覆盖、零与未知的回归夹具。
- [ ] 30天方格、选日活动、3页首次预算与300条总上限。
- [ ] 真实模拟器点击及截图检查。

### Task 4: 审查与交付
- [ ] 版本配置与包内校验改1.0.9；新测试加入Build IPA及所有原生检查入口。
- [ ] 完整分支独立审查；处理重要问题；同步main并运行工作流。
- [ ] 核对同一SHA的成功检查和非空产物；强制关机。
