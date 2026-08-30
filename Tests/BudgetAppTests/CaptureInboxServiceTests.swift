import SwiftData
import XCTest
@testable import BudgetApp

final class CaptureInboxServiceTests: ServiceTestCase {
    func testEnqueuePersistsParsedSMS() throws {
        let text = "【招商银行】您尾号1234的储蓄卡8月29日12:30支付宝支付100.00元，余额9,999.99元。"
        let service = CaptureInboxService(context: context)

        let result = try service.enqueue(text: text)
        guard case .inserted = result else {
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

    func testUnrecognizedMessageIsNotPersisted() throws {
        let result = try CaptureInboxService(context: context).enqueue(
            text: "【银行】验证码123456，请勿泄露。"
        )

        XCTAssertEqual(result, .unrecognized)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<CaptureInboxItem>()), 0)
    }
}
