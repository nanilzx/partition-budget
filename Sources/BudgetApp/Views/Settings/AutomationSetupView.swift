import SwiftUI

/// iOS 不允许 App 代替用户创建个人自动化，因此在 App 内给出与当前 Intent 一致的设置步骤。
struct AutomationSetupView: View {
    var body: some View {
        List {
            Section {
                setupStep(1, title: "先打开一次分区预算", detail: "安装新版后至少启动一次，让 iOS 建立快捷指令动作索引。")
                setupStep(2, title: "新建个人自动化", detail: "打开“快捷指令”→“自动化”→“新建自动化”→ 选择“信息”。")
                setupStep(3, title: "设置银行短信条件", detail: "在“发件人”中选择银行短信号码。如果号码无法直接选择，请先把它保存为联系人。")
                setupStep(4, title: "选择立即运行", detail: "关闭运行前询问，收到匹配短信后即可在后台处理。")
                setupStep(5, title: "添加分区预算动作", detail: "添加操作 →“App”→“分区预算”→ 选择“识别消费”。")
                setupStep(6, title: "传入短信正文", detail: "点“文本内容”→ 选择“快捷指令输入”→ 将类型设为“信息正文/正文”。不要填写固定文字。")
            } header: {
                Text("设置步骤")
            } footer: {
                Text("个人自动化只保存在这台设备上。换新 iPhone 后需要重新设置。")
            }

            Section("完成后") {
                Label("识别成功的短信会进入“银行短信待确认”", systemImage: "tray.full")
                Label("相同短信不会重复添加", systemImage: "checkmark.shield")
                Label("确认或忽略后会清除完整短信正文", systemImage: "lock.shield")
            }

            Section("找不到动作时") {
                Text("确认安装的是包含自动记账功能的最新版，并先打开一次分区预算。然后彻底退出“快捷指令”再重新打开；仍未出现时重启 iPhone，让系统重建 App Intent 索引。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let url = URL(string: "shortcuts://") {
                    Link(destination: url) {
                        Label("打开“快捷指令”App", systemImage: "arrow.up.forward.app")
                    }
                }
            }
        }
        .navigationTitle("短信自动记账设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setupStep(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.tint, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}
