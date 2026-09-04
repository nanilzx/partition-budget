import XCTest
@testable import BudgetApp

/// 银行扣款短信解析测试。
final class CaptureParserTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_788_264_000) // 2026-09-01 前后，确保「08月30日」是过去日期

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

    func testParseBankOfChinaUnionPayIncomeTemplate() throws {
        let text = "您的借记卡/账户1833于08月30日银联入账人民币1.00元（刘子轩）,交易后余额1929.84【中国银行】"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))

        XCTAssertEqual(parsed.amountCents, 100)
        XCTAssertEqual(parsed.transactionKind, .income)
        XCTAssertEqual(parsed.bankName, "中国银行")
        XCTAssertEqual(parsed.channel, "银联")
        XCTAssertEqual(parsed.cardLastFour, "1833")
        XCTAssertEqual(parsed.merchant, "中国银行·刘子轩")
        XCTAssertNotNil(parsed.date)
    }

    func testParseBankOfChinaOnlinePaymentTemplate() throws {
        let text = "您的借记卡账户1833，于08月30日网上支付支取人民币1.00元,交易后余额1928.84【中国银行】"
        let parsed = try XCTUnwrap(CaptureParser.parseBankSMS(text, now: now))

        XCTAssertEqual(parsed.amountCents, 100)
        XCTAssertEqual(parsed.transactionKind, .expense)
        XCTAssertEqual(parsed.bankName, "中国银行")
        XCTAssertEqual(parsed.cardLastFour, "1833")
        XCTAssertEqual(parsed.merchant, "中国银行")
        XCTAssertNotNil(parsed.date)
    }

    func testSplitTwoConsecutiveBankOfChinaMessagesWithoutNewline() throws {
        let income = "您的借记卡/账户1833于08月30日银联入账人民币1.00元（刘子轩）,交易后余额1929.84【中国银行】"
        let expense = "您的借记卡账户1833，于08月30日网上支付支取人民币1.00元,交易后余额1928.84【中国银行】"

        let messages = CaptureParser.splitBankSMSPayload(income + expense)

        XCTAssertEqual(messages, [income, expense])
        XCTAssertEqual(messages.compactMap { CaptureParser.parseBankSMS($0, now: now) }.count, 2)
    }

    func testSplitTwoLeadingBankSignatureMessagesOnSeparateLines() {
        let first = "【招商银行】您尾号1234的储蓄卡8月30日12:30支付宝支付10.00元，余额999.00元。"
        let second = "【招商银行】您尾号1234的储蓄卡8月30日12:31微信支付20.00元，余额979.00元。"

        XCTAssertEqual(CaptureParser.splitBankSMSPayload(first + "\n" + second), [first, second])
    }

    func testAdditionalDebitAndCreditWording() throws {
        let debit = try XCTUnwrap(CaptureParser.parseBankSMS("【中国银行】账户1833于9月4日支取人民币8.00元。", now: now))
        let credit = try XCTUnwrap(CaptureParser.parseBankSMS("【中国银行】账户1833于9月4日到账人民币18.00元。", now: now))

        XCTAssertEqual(debit.transactionKind, .expense)
        XCTAssertEqual(credit.transactionKind, .income)
    }
}
