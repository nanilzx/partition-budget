import XCTest
@testable import BudgetApp

/// 截图 OCR 文本与银行短信的解析测试。
final class CaptureParserTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_787_900_000) // 2026-08-25 前后即可

    // MARK: - 截图（微信支付风格：金额独立一行，商家在“收款方”下一行）

    func testParseWeChatStyleScreenshot() throws {
        let lines = [
            "微信支付", "支付成功", "¥98.00", "付款时间", "2026-08-29 12:30",
            "付款方式", "零钱", "收款方", "瑞幸咖啡（科创园区店）", "交易单号", "4200001820260829",
        ]
        let parsed = try XCTUnwrap(CaptureParser.parsePaymentScreen(lines: lines, now: now))
        XCTAssertEqual(parsed.amountCents, 9800)
        XCTAssertEqual(parsed.merchant, "瑞幸咖啡（科创园区店）")
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: try XCTUnwrap(parsed.date))
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 8)
        XCTAssertEqual(comps.day, 29)
        XCTAssertEqual(comps.hour, 12)
        XCTAssertEqual(comps.minute, 30)
    }

    // MARK: - 截图（支付宝风格：收款方同行、千分位金额）

    func testParseAlipayStyleScreenshot() throws {
        let lines = [
            "支付宝", "付款成功", "付款金额", "¥1,234.56", "收款方：盒马鲜生",
            "付款时间：2026年8月29日 12:30", "交易说明",
        ]
        let parsed = try XCTUnwrap(CaptureParser.parsePaymentScreen(lines: lines, now: now))
        XCTAssertEqual(parsed.amountCents, 123456)
        XCTAssertEqual(parsed.merchant, "盒马鲜生")
    }

    // MARK: - 截图：无关键词时多个金额取最大（付款页主体金额最大）

    func testAmountFallbackPicksLargest() throws {
        let lines = ["会员余额 ¥100.00", "支付成功", "¥313.00", "收款方", "饿了么"]
        let parsed = try XCTUnwrap(CaptureParser.parsePaymentScreen(lines: lines, now: now))
        XCTAssertEqual(parsed.amountCents, 31300)
        XCTAssertEqual(parsed.merchant, "饿了么")
    }

    // MARK: - 截图：「向某某付款」形式

    func testParseMerchantFromXiangSentence() throws {
        let lines = ["支付成功", "¥45.90", "向猫眼电影付款", "2026-08-28 15:02"]
        let parsed = try XCTUnwrap(CaptureParser.parsePaymentScreen(lines: lines, now: now))
        XCTAssertEqual(parsed.amountCents, 4590)
        XCTAssertEqual(parsed.merchant, "猫眼电影")
    }

    func testUnparseableScreenReturnsNil() {
        XCTAssertNil(CaptureParser.parsePaymentScreen(lines: ["今天天气不错"], now: now))
        XCTAssertNil(CaptureParser.parsePaymentScreen(lines: [], now: now))
    }

    // MARK: - 银行短信

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
