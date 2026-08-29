import SwiftUI

/// Face ID 锁定遮罩。
struct LockScreenView: View {
    var onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text("分区预算已锁定")
                    .font(.title3.weight(.semibold))
                Text("你的财务数据已受保护")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    onUnlock()
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
