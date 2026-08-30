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
        XCTAssertEqual(parsed.transactionKind, .expense)
        XCTAssertEqual(parsed.cardLastFour, "1234")
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
        XCTAssertNil(CaptureParser.parseBankSMS("【某银行】本期应还款100.00元。", now: now))
        XCTAssertNil(CaptureParser.parseBankSMS("【某银行】账户余额100.00元。", now: now))
    }

    func testParseIncomeSMS() throws {
        let text = "【建设银行】您尾号8888的账户8月30日10:20工资入账8,500.00元，余额10,000.00元。"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))
        XCTAssertEqual(parsed.amountCents, 850000)
        XCTAssertEqual(parsed.transactionKind, .income)
        XCTAssertEqual(parsed.bankName, "建设银行")
        XCTAssertEqual(parsed.cardLastFour, "8888")
    }

    func testParseRefundSMS() throws {
        let text = "【中国银行】您尾号4321的银行卡8月30日11:08收到支付宝退款20.00元。"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))
        XCTAssertEqual(parsed.amountCents, 2000)
        XCTAssertEqual(parsed.transactionKind, .refund)
        XCTAssertLessThanOrEqual(parsed.confidence, 0.8)
    }

    func testExtractCounterparty() throws {
        let text = "【工商银行】您尾号5678的信用卡8月30日09:01在麦当劳消费52.30元。"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))
        XCTAssertEqual(parsed.merchant, "工商银行·麦当劳")
    }
}
