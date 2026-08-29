# 分区预算 App — 第一阶段（核心闭环 MVP）实施计划

## 0. 先回答你的问题：没有 Mac，后面能装到 iPhone 吗？

**能，有两条路径，我都会在工程里铺好路：**

| 路径 | 成本 | 体验 |
|---|---|---|
| **A. 免费 sideload（AltStore/SideStore）** | 0 元 | GitHub Actions 在云端 Mac 上编译出**未签名 IPA** 存为构建产物，你在 Windows 上用 AltServer 装进自己的 iPhone（免费 Apple ID，App **每 7 天要重新签一次**，最多 3 个自装 App） |
| **B. 付费开发者账号 + TestFlight（长期推荐）** | 99 美元/年 | 同一条 CI 流水线可直接构建+签名+上传 TestFlight，iPhone 上装 TestFlight App 即可安装，90 天有效期自动提醒更新，**全程不需要 Mac**。正式上架也走这条路 |

所以本次交付我会：① CI 同时产出「测试报告 + 未签名 IPA」；② README 写清两条安装路径的逐步操作。写代码阶段我把 Bundle ID、签名配置留成显式占位，你拿到开发者账号后改一行配置即可走 TestFlight。

日常验证节奏：我每次改完代码 → push 到你的 GitHub 仓库 → Actions 自动编译+跑全部单元测试 → 你看绿色对勾即代表本轮改动编译通过、财务逻辑测试全过。

## 1. 本次交付范围（你已确认：核心闭环 MVP）

严格对应你的「四十一、第一版验收标准」全流程：
创建分区 → 创建本月预算 → 分配金额 → 记一笔 → 分类（内置词库+历史自动推荐，可手改）→ 自动扣减 → 首页立即刷新 → 查看历史 → 修改消费（预算重算）→ 删除消费（预算恢复）→ 预算转移 → 月度切换与结转。
外加：超支五选项处理、删除有记录分区的保护、全部核心单元测试。

**本次不做**（架构预留，下一批）：账户系统、用户规则管理页、AI API、Face ID、导入导出、储蓄目标详情、深度统计。UI 先做「干净、可用、突出剩余」。

## 2. 技术选型

- **SwiftUI + SwiftData，最低 iOS 17.0**，MVVM，**零第三方依赖**
- **金额一律以「分」存储（Int64）**，提供 `Money` 值类型负责算术与 ¥ 格式化，杜绝浮点误差（你的第二十六节）
- SwiftData 模型**全部字段带默认值**、实体间用 `UUID` 显式引用（不用 @Relationship 级联），一致性完全由 Service 层控制——既满足「删分区不破坏记录」，也为将来 CloudKit 迁移留好兼容
- 本地数据库（App Support 下的 SwiftData store），离线全功能
- 工程用 **XcodeGen**（`project.yml` 文本生成 .xcodeproj，Windows 上可维护）；**GitHub Actions**（macOS runner）编译 + XCTest + 产出未签名 IPA
- 应用名默认「分区预算」（想改名随时说），Bundle ID 占位 `com.partitionbudget.app`，UI 简体中文，支持深色模式，遵循 HIG

## 3. 目录结构

```
PartitionBudget/
├── project.yml                  # XcodeGen 工程清单（App + Tests 两个 target）
├── .github/workflows/ios.yml    # 云端编译 + 测试 + IPA 产物
├── README.md                    # 中文：本地/Mac/CI 三种验证方式 + 装机路径 + 路线图
├── Sources/BudgetApp/
│   ├── BudgetApp.swift          # @main，ModelContainer 初始化，首次启动种子数据
│   ├── Models/                  # BudgetCategory, Transaction, MonthlyBudget,
│   │                            # MonthlyBudgetItem, BudgetTransfer, BudgetAdjustment
│   ├── Services/                # 全部核心业务逻辑（不写在 View/Button 里）
│   │   ├── TransactionService   # 记/改/删消费，自动扣减与恢复
│   │   ├── BudgetService        # 转移、手动调整、台账
│   │   ├── MonthlyBudgetService # 月度创建、重置、结转、月度隔离
│   │   └── ClassificationService# 内置词库 + 历史记录推荐（预留 AI 接口）
│   ├── ViewModels/              # Home/Budget/AddTransaction/TransactionList
│   ├── Views/                   # Home/ Budget/ Transaction/ Settings/ 四个 Tab
│   └── Utilities/               # Money, 扩展, 默认种子数据(7个分区+常用商户词库)
└── Tests/BudgetAppTests/        # XCTest：你第三十七节的全部场景
```

## 4. 核心设计决策（数据正确性优先）

1. **单一事实来源**：分区「已花金额」= 该月该分区全部交易求和（派生计算，不手工加减余额）。因此新增/修改/删除消费后预算余额**不可能漂移**，自动满足你第三十七节的所有算术场景。
2. **台账**：非消费类变动（初始化/手动调整/转移/结转）每笔写入 `BudgetAdjustment`（含原因、金额、日期），「不能只存最终余额」。
3. **月度隔离**：预算按 `MonthlyBudget(year, month)` + `MonthlyBudgetItem` 组织；打开 App 自动惰性创建当月预算（普通分区 = 默认月预算；开启结转的分区额外加上月剩余）。
4. **结转规则**：结转额 = max(0, 上月剩余)（超支的负数**不**结转到下月）；储蓄类分区默认开启全额结转。
5. **超支不拦截**：余额可为负。记账时若不足，弹出五选项：仍然记录 / 从其他分区转入 / 增加本月预算 / 更换分区 / 取消。
6. **删除保护**：分区下存在消费记录时禁止删除并引导（可隐藏分区），保证历史记录永不失效；无记录才允许真删。
7. **分类推荐优先级**：内置商户词库（麦当劳/瑞幸/滴滴/Steam/中国移动…约 60 条）→ 同商户历史记录 → 手动选择。UI 显示「可能属于 X，请确认」。`ClassificationService` 暴露 protocol 接口，后续 AI 作为第四级插入，置信度 <70% 必须确认。
8. **首页只回答一个问题**：本月还剩多少可以花。顶部本月总览（预算/已用/剩余/未分配），下方分区卡片（**剩余金额大字 + 进度条 + 已用百分比**，正常/提醒/警告/超支四档状态色），底部最近消费；右下角悬浮「+ 记一笔」。

## 5. 实施步骤（每步完成即自检一次）

1. **工程骨架**：project.yml、App 入口、Assets、.gitignore、git init + 首次提交
2. **Models + Money**：6 个 SwiftData 模型 + 金额类型
3. **Services + 全部单元测试**：TransactionService（记/改/删）、BudgetService（转移/调整/台账）、MonthlyBudgetService（新月/结转/隔离）、ClassificationService；测试覆盖你第三十七节全部 8 个场景 + 金额格式化 + 月度隔离 + 删除保护
4. **四 Tab UI**：首页 Dashboard、记一笔（含超支弹窗）、预算页（分区管理/月度分配/转移）、记录页（搜索/筛选/编辑/删除）、设置页（占位+关于）
5. **CI 工作流 + README**：macos runner 执行 xcodegen → xcodebuild test → 产出未签名 IPA；README 写清 GitHub 推送步骤、两条装机路径、后续路线图（对照你的 42 节逐条打勾）

## 6. 验收方式

- 我在本机无法编译 Swift（Windows 无 Xcode），正确性靠：代码严格自查 + 单元测试设计先行；**最终「编译 + 测试通过」由 CI 云端验证**
- 你只需：创建 GitHub 私有仓库 → push（我给你逐步命令）→ 看 Actions 绿勾；想装手机时按 README 的 AltStore/TestFlight 路径操作
- 完成标准 = 你的第四十一节闭环，每一步金额变化都有测试背书