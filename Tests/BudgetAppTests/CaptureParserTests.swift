import XCTest
@testable import BudgetApp

/// 银行扣款短信解析测试。
final class CaptureParserTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_787_900_000) // 2026-08-25 前后即可

    func testParseBankSMS() throws {
        let text = "【招商银行】您尾号1234的储蓄卡8月29日12:30支付宝快捷支付交易100.00元，交易后余额9,999.99元。"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))
        XCTAssertEqual(parsed.amountCents, 10000)
        XCTAssertEqual(parsed.merchant, "招商银行·支付宝")
        XCTAssertEqual(parsed.source, "银行短信")
    }

    func testParseBankSMSWithoutChannel() throws {
        let text = "【工商银行】您尾号5678的信用卡8月30日09:01消费52.30元。"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))
        XCTAssertEqual(parsed.amountCents, 5230)
        XCTAssertEqual(parsed.merchant, "工商银行")
    }

    func testUnparseableSMSReturnsNil() {
        XCTAssertNil(CaptureParser.parseBankSMS("您的验证码是123456，请勿泄露。", now: now))
        XCTAssertNil(CaptureParser.parseBankSMS("", now: now))
    }
}
