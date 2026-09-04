import SwiftData
import XCTest
@testable import BudgetApp

final class CaptureInboxServiceTests: ServiceTestCase {
    func testEnqueuePersistsParsedSMS() throws {
        let text = "【招商银行】您尾号1234的储蓄卡8月29日12:30支付宝支付100.00元，余额9,999.99元。"
        let service = CaptureInboxService(context: context)

        let result = try service.enqueue(text: text)
        guard case .insertedRecognized(_) = result else {
            return XCTFail("应写入一条待确认记录")
        }

        let items = try context.fetch(FetchDescriptor<CaptureInboxItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].amountCents, 10000)
        XCTAssertEqual(items[0].cardLastFour, "1234")
        XCTAssertEqual(items[0].state, .pending)
        XCTAssertEqual(items[0].rawText, text)
    }

    func testDuplicateSMSIsIgnoredAcrossServiceInstances() throws {
        let text = "【工商银行】尾号5678信用卡8月30日09:01消费52.30元。"

        _ = try CaptureInboxService(context: context).enqueue(text: text)
        let second = try CaptureInboxService(context: context).enqueue(text: "  \(text)\n")

        XCTAssertEqual(second, .duplicate)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureInboxItem>()), 1)
    }

    func testDiscardClearsSensitiveRawTextButKeepsFingerprint() throws {
        let text = "【中国银行】尾号4321银行卡8月30日11:08支付宝退款20.00元。"
        let service = CaptureInboxService(context: context)
        _ = try service.enqueue(text: text)
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureInboxItem>()).first)
        let fingerprint = item.fingerprint

        try service.discard(item)

        XCTAssertEqual(item.state, .discarded)
        XCTAssertEqual(item.rawText, "")
        XCTAssertEqual(item.fingerprint, fingerprint)
        XCTAssertEqual(try service.enqueue(text: text), .duplicate)
    }

    func testUnrecognizedNonemptyMessageIsPersistedForDiagnosis() throws {
        let result = try CaptureInboxService(context: context).enqueue(
            text: "【银行】验证码123456，请勿泄露。"
        )

        guard case .insertedNeedsReview(_) = result else {
            return XCTFail("无法解析的非空输入也应该进入待确认列表")
        }
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureInboxItem>()).first)
        XCTAssertFalse(item.isRecognized)
        XCTAssertEqual(item.amountCents, 0)
        XCTAssertEqual(item.rawText, "【银行】验证码123456，请勿泄露。")
    }

    func testEmptyShortcutInputCreatesVisibleDiagnostic() throws {
        let result = try CaptureInboxService(context: context).enqueue(text: "  \n")

        guard case .insertedNeedsReview(_) = result else {
            return XCTFail("空输入也应该留下可见诊断")
        }
        let item = try XCTUnwrap(context.fetch(FetchDescriptor<CaptureInboxItem>()).first)
        XCTAssertFalse(item.isRecognized)
        XCTAssertTrue(item.rawText.contains("没有传入短信正文"))
    }

    func testEnqueueAllPersistsTwoRapidConsecutiveMessages() throws {
        let income = "您的借记卡/账户1833于08月30日银联入账人民币1.00元（刘子轩）,交易后余额1929.84【中国银行】"
        let expense = "您的借记卡账户1833，于08月30日网上支付支取人民币1.00元,交易后余额1928.84【中国银行】"

        let results = try CaptureInboxService(context: context).enqueueAll(text: income + expense)
        let items = try context.fetch(FetchDescriptor<CaptureInboxItem>())

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(Set(items.map(\.amountCents)), [100])
        XCTAssertEqual(Set(items.map(\.transactionKindRaw)), ["income", "expense"])
    }

    func testEnqueueAllDeduplicatesEachMessageIndependently() throws {
        let first = "【招商银行】您尾号1234的储蓄卡8月30日12:30支付宝支付10.00元，余额999.00元。"
        let second = "【招商银行】您尾号1234的储蓄卡8月30日12:31微信支付20.00元，余额979.00元。"
        _ = try CaptureInboxService(context: context).enqueue(text: first)

        let results = try CaptureInboxService(context: context).enqueueAll(text: first + "\n" + second)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0], .duplicate)
        guard case .insertedRecognized = results[1] else {
            return XCTFail("第二条不同短信不应被相似内容误判为重复")
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureInboxItem>()), 2)
    }
}
