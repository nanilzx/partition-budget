import SwiftUI
import SwiftData

/// 「我的」Tab。本批交付核心闭环，以下功能按路线图分批启用。
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("存储位置") {
                        Text("仅本机")
                    }
                    comingSoonRow("数据导出 / 导入（第二批）", systemImage: "square.and.arrow.up")
                    comingSoonRow("iCloud 备份（后续）", systemImage: "icloud")
                } header: {
                    Text("数据")
                } footer: {
                    Text("核心财务数据全部保存在本机（SwiftData 本地数据库），离线可用，不上传任何服务器。")
                }
                Section {
                    LabeledContent("内置词库") {
                        Text("\(BuiltinClassificationRules.rules.count) 条关键词")
                    }
                    comingSoonRow("自定义分类规则（第二批）", systemImage: "person.badge.shield.checkmark")
                    comingSoonRow("AI 设置（第二批）", systemImage: "sparkles")
                } header: {
                    Text("智能分类")
                }
                Section {
                    comingSoonRow("资金账户管理（第二批）", systemImage: "creditcard")
                } header: {
                    Text("账户")
                }
                Section {
                    comingSoonRow("Face ID 解锁（第二批）", systemImage: "faceid")
                } header: {
                    Text("安全")
                }
                Section {
                    LabeledContent("版本") {
                        Text(versionText)
                    }
                    LabeledContent("核心原则") {
                        Text("离线优先 · 数据本地")
                    }
                } header: {
                    Text("关于")
                }
            }
            .navigationTitle("我的")
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.1.0"
    }

    private func comingSoonRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .opacity(0.55)
    }
}
