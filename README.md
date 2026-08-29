# 分区预算 (PartitionBudget)

一个原生 iOS 个人预算 App。核心体验只有一句话：

> 收入一笔钱 → 提前分到不同用途 → 每消费一笔快速记账 → 系统自动扣对应分区的钱 → 随时打开，一眼看到每个预算还剩多少。

**技术栈：SwiftUI + SwiftData，最低 iOS 17，零第三方依赖，数据全部保存在本机，离线完全可用。**

---

## 当前状态：第一阶段核心闭环 MVP ✅

| 能力 | 状态 |
| --- | --- |
| 预算分区管理（新增/编辑/删除保护/拖拽排序/隐藏/图标颜色/储蓄类标记） | ✅ |
| 月度预算与分配（本月收入 / 已分配 / 未分配，逐分区设置金额） | ✅ |
| 记一笔（金额+描述最少两步；按历史与内置词库自动推荐分类，可确认/修改） | ✅ |
| 自动扣减预算，首页立即刷新；支出/收入都支持 | ✅ |
| 修改/删除消费 → 预算自动重算/恢复（跨分区、跨月改动也正确） | ✅ |
| 预算转移（不能超过来源剩余，双向台账留痕） | ✅ |
| 超支处理：五选项（仍然记录/转入差额/增加预算/更换分区/取消），不强制拦截 | ✅ |
| 月度切换、历史月查看；新月自动生成；按分区设置余额结转（负数不结转） | ✅ |
| 记录页：搜索 / 类型 / 分区 / 金额范围 / 时间范围筛选，编辑与删除 | ✅ |
| 分区消费记录视图、首页储蓄分区独立展示 | ✅ |
| 核心财务逻辑单元测试（扣减/恢复/差值/跨分区/跨月/超支/结转/转移/删除保护） | ✅ |

第二批（架构已预留）：账户系统、用户自定义分类规则、AI 接入、基础统计、Face ID、数据导出导入。

---

## 如何在云端验证（没有 Mac 也能用）

本仓库自带 GitHub Actions 工作流（`.github/workflows/ios.yml`），每次 push 都会在 macOS 云端：

1. 用 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成 Xcode 工程；
2. 跑全部单元测试（财务正确性回归）；
3. 打包一个**未签名 IPA** 存到构建产物 Artifacts。

### 步骤

```bash
# 1. 在 GitHub 建一个私有仓库（例如 partition-budget），然后：
cd 本项目目录
git remote add origin https://github.com/<你的用户名>/partition-budget.git
git push -u origin main

# 2. 打开仓库的 Actions 页，等两个 job 变绿：
#    - test  → 编译 + 单元测试通过
#    - ipa   → 下载 Artifacts 里的 BudgetApp-unsigned-ipa
```

### 把 IPA 装进自己的 iPhone（免费路线）

1. Windows 电脑安装 [AltServer](https://altstore.io/)，iPhone 与电脑同一 Wi-Fi，装好 AltStore；
2. 用你的 Apple ID 在 AltStore 登录（免费 Apple ID 即可）；
3. 把下载的 IPA 拖进 AltStore → 安装到手机；
4. 注意：免费签名 **7 天过期**，连着同一 Wi-Fi 时 AltStore 会自动续签；IPA 里已含 UI 所需全部资源，无需 App Store。

### 长期推荐路线（99 美元/年）

注册 Apple Developer Program 后，同一工程可以配置自动签名 + 上传 TestFlight（第二批会把 fastlane 脚本配好），iPhone 直接装 TestFlight 版，90 天有效期、无需电脑续签。Bundle ID 目前是占位符 `com.partitionbudget.app`，届时在 `project.yml` 里改成你自己的即可。

---

## 如何在有 Mac 时本地开发

```bash
brew install xcodegen          # 一次性
xcodegen generate              # 生成 PartitionBudget.xcodeproj
open PartitionBudget.xcodeproj
# Xcode 里：Target BudgetApp → Signing & Capabilities → 选择你的 Personal Team
# 选一台 iOS 17+ 的模拟器或真机，Cmd+R 运行
```

命令行跑测试：

```bash
xcodebuild test -project PartitionBudget.xcodeproj -scheme BudgetApp \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

> `.xcodeproj` 不入库（见 `.gitignore`），任何机器上都用 `xcodegen generate` 一条命令重建，避免工程文件冲突。

---

## 目录结构

```
project.yml                     XcodeGen 工程定义（App + Tests 两个 target）
.github/workflows/ios.yml       云端编译 + 测试 + IPA 产物
Sources/BudgetApp/
  BudgetApp.swift               入口：ModelContainer 初始化
  Models/                       BudgetCategory / Transaction / MonthlyBudget /
                                MonthlyBudgetItem / BudgetTransfer / BudgetAdjustment / ServiceError
  Services/                     核心业务逻辑（不在 UI 里）
    MonthlyBudgetService        月度创建（幂等）、结转、从交易派生已花/剩余/收入
    TransactionService          记/改/删消费与收入（预算联动靠派生自动成立）
    BudgetService               分区管理、预算调整、转移、台账
    ClassificationService       分类推荐：历史记录 > 内置词库（预留用户规则与 AI 接口）
  ViewModels/                   路由、记一笔表单状态机、首页计算、筛选条件
  Views/                        Home / Budget / Transaction / Settings 四个 Tab
  Utilities/                    Money(分) / BudgetMonth / 日期格式化 / 种子数据 / 内置词库
Tests/BudgetAppTests/           财务逻辑回归测试（内存数据库，逐用例隔离）
```

---

## 数据正确性设计（本项目的第一优先级）

1. **金额一律以「分」（Int64）存储运算**，展示时才格式化为 ¥，杜绝浮点误差。
2. **单一事实来源**：「已花」永远等于当月该分区全部支出交易之和（派生），不存在手工加减的余额。
   因此新增、修改金额、修改分区、跨月改日期、删除记录，预算余额都自动正确，不可能漂移。
3. **台账（BudgetAdjustment）**：初始化、手动调整、转移转入/转出、结转，每一笔都留痕（含原因与关联单据），不保存无历史的余额。
4. **月度隔离**：预算按 (年, 月) 组织；打开 App 自动惰性生成当月预算，历史月只读展示。
5. **结转规则**：开启结转的分区，新月额度 = 默认月预算 + max(0, 上月剩余)；超支的负数不结转；结转不算「新分配」（不进未分配的减项）。
6. **删除保护**：分区下有消费记录时禁止删除（可隐藏），历史记录永不失效；无记录才允许真删，并同步清理其预算项与台账。
7. **超支不拦截**：余额可以为负；记账时提示差额并提供五种处理方式，预算是决策工具不是枷锁。
8. **离线优先**：全部功能本地可用；AI 只作为分类的增强层（本批未接入，接口已预留），删除 AI 也不影响任何核心功能。

### 与规格第二十七节的字段映射

规格中的 `id` 字段在本实现中为显式命名的 `categoryID / transactionID / monthlyBudgetID / itemID / transferID / adjustmentID`（避免与 SwiftData 持久化标识冲突）；`spentAmount/remainingAmount` 不落库，由交易派生（见第 2 点）；`MonthlyBudget.totalIncome` 由当月收入交易求和派生。其余字段一一对应。

---

## 已知简化（第二批处理）

- 负余额不结转；若提前给下月记账，下月结转额会按当时快照锁定。
- 「消费内容」同时充当描述与商户名（编辑页后续拆分）。
- 储蓄目标的「目标金额/目标日期/建议月投入」UI 属第二批（当前储蓄分区已支持逐月结转累积）。
- 首月使用时若从未记录收入，「未分配」会显示为负数——分配页有提示，先记收入即可。

## 路线图

- [x] 第一批：核心闭环 MVP（当前）
- [ ] 第二批：账户系统 / 自定义分类规则 / AI 接入 / 基础统计 / Face ID / 导出导入 / 储蓄目标详情
- [ ] 第三批：Widget、Siri 快捷指令、iCloud 同步、CSV 与账单导入、周报月报
