import Foundation
import LocalAuthentication
import Observation
import SwiftUI

/// Face ID / Touch ID 锁（规格第二十二节）。
/// 使用 Apple 官方 LocalAuthentication：.deviceOwnerAuthentication
/// （生物识别不可用时自动回退锁屏密码）。
@MainActor
@Observable
final class BiometricLock {
    static let shared = BiometricLock()
    private init() {}

    private static let storageKey = "biometricLockEnabled"

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Self.storageKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.storageKey) }
    }

    var isLocked = false
    var isUnlocking = false

    /// 设备是否配置了可用的解锁方式（生物识别或锁屏密码）。
    var canAuthenticate: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func handleSceneChange(_ phase: ScenePhase) {
        if phase == .background, isEnabled {
            isLocked = true
        }
    }

    /// App 回前台/启动时的解锁尝试；设备未配置任何解锁方式时直接放行（如部分模拟器）。
    func unlockIfNeeded() async {
        guard isEnabled, isLocked, !isUnlocking else { return }
        isUnlocking = true
        defer { isUnlocking = false }

        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "解锁查看你的预算数据"
            )
            if success {
                isLocked = false
            }
        } catch {
            // 用户取消或失败：保持锁定，等手动点「解锁」再试
        }
    }
}
