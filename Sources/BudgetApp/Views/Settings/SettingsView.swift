import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 「我的」Tab：账户管理、自定义规则、数据导出导入。
struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @Query(filter: #Predicate<CaptureInboxItem> { $0.stateRaw == "pending" })
    private var pendingCaptures: [CaptureInboxItem]

    @State private var exportDocument: BudgetBackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImportData: Data?
    @State private var infoMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AccountListView()
                    } label: {
                        Label("资金账户管理", systemImage: "creditcard")
                    }
                } header: {
                    Text("账户")
                } footer: {
                    Text("实际的钱（微信、支付宝、银行卡…）与预算分开管理，支持计入总资产。")
                }

                Section {
                    NavigationLink {
                        AutomationSetupView()
                    } label: {
                        Label("设置银行短信自动化", systemImage: "bolt.badge.clock")
                    }
                    NavigationLink {
                        CaptureInboxView()
                    } label: {
                        HStack {
                            Label("银行短信待确认", systemImage: "text.badge.checkmark")
                            Spacer()
                            if !pendingCaptures.isEmpty {
                                Text("\(pendingCaptures.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(.red, in: Capsule())
                            }
                        }
                    }
                    NavigationLink {
                        RulesListView()
                    } label: {
                        Label("自定义分类规则", systemImage: "person.badge.shield.checkmark")
                    }
                    LabeledContent("内置词库") {
                        Text("\(BuiltinClassificationRules.rules.count) 条关键词")
                    }
                    if let shortcutsURL = URL(string: "shortcuts://") {
                        Link(destination: shortcutsURL) {
                            Label("打开「快捷指令」App", systemImage: "arrow.up.forward.app")
                        }
                    }
                    comingSoonRow("AI 智能识别（后续批次）", systemImage: "sparkles")
                } header: {
                    Text("自动记账")
                } footer: {
                    Text("在快捷指令 App 新建个人自动化：触发条件选“信息”并填写银行号码 → 选择“立即运行” → 添加“接收银行短信正文”操作。该操作会优先连接上一步收到的信息，识别结果进入待确认列表。")
                }

                Section {
                    Button {
                        exportData()
                    } label: {
                        Label("导出全部数据（JSON）", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        showingImporter = true
                    } label: {
                        Label("从备份文件导入", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("数据")
                } footer: {
                    Text("数据全部保存在本机。建议定期导出 JSON 备份；导入会覆盖当前全部数据。")
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
            .navigationBarTitleDisplayMode(.large)
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "分区预算备份-\(dateStamp)"
            ) { result in
                if case .success = result {
                    infoMessage = "备份已导出"
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    importFrom(url: url)
                case .failure(let error):
                    infoMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                "确认导入备份？",
                isPresented: Binding(
                    get: { pendingImportData != nil },
                    set: { if !$0 { pendingImportData = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("覆盖导入（当前数据将被替换）", role: .destructive) {
                    performImport()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("导入会清空当前全部数据，用备份文件的内容替换。此操作不可撤销。")
            }
            .alert(
                "提示",
                isPresented: Binding(
                    get: { infoMessage != nil },
                    set: { if !$0 { infoMessage = nil } }
                )
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(infoMessage ?? "")
            }
        }
    }

    // MARK: - 导出 / 导入

    private var dateStamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter.string(from: Date())
    }

    private func exportData() {
        do {
            let data = try BackupService.export(context: context)
            exportDocument = BudgetBackupDocument(data: data)
            showingExporter = true
        } catch {
            infoMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func importFrom(url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer {
            if secured { url.stopAccessingSecurityScopedResource() }
        }
        do {
            pendingImportData = try Data(contentsOf: url)
        } catch {
            infoMessage = "读取文件失败：\(error.localizedDescription)"
        }
    }

    private func performImport() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        do {
            try BackupService.importReplace(data: data, context: context)
            infoMessage = "导入完成，数据已恢复"
        } catch {
            infoMessage = error.localizedDescription
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version ?? "0.2.0"
    }

    private func comingSoonRow(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .foregroundStyle(.secondary)
            .opacity(0.55)
    }
}
