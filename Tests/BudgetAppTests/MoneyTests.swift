import XCTest
@testable import BudgetApp

final class MoneyTests: XCTestCase {
    func testParseYuanInteger() {
        XCTAssertEqual(Money(string: "36")?.cents, 3600)
    }

    func testParseYuanDecimal() {
        XCTAssertEqual(Money(string: "36.5")?.cents, 3650)
        XCTAssertEqual(Money(string: "23.56")?.cents, 2356)
    }

    func testParseRoundsHalfUpToFen() {
        XCTAssertEqual(Money(string: "23.567")?.cents, 2357)
    }

    func testParseInvalidReturnsNil() {
        XCTAssertNil(Money(string: ""))
        XCTAssertNil(Money(string: "   "))
        XCTAssertNil(Money(string: "abc"))
    }

    func testDisplayWholeYuan() {
        XCTAssertEqual(Money(cents: 3600).displayText, "¥36")
    }

    func testDisplayWithFenAndGrouping() {
        XCTAssertEqual(Money(cents: 123456).displayText, "¥1,234.56")
    }

    func testDisplayNegative() {
        XCTAssertEqual(Money(cents: -4800).displayText, "-¥48")
    }

    func testDisplaySmallFen() {
        XCTAssertEqual(Money(cents: 5).displayText, "¥0.05")
    }

    func testInputTextRoundTrip() {
        for text in ["36", "36.5", "1234.56", "0.05"] {
            guard let money = Money(string: text) else {
                return XCTFail("应能解析 \(text)")
            }
            XCTAssertEqual(Money(string: money.inputText)?.cents, money.cents)
        }
    }
}
