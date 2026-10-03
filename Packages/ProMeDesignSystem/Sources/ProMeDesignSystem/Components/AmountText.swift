import ProMeDomain
import SwiftUI

/// Renders a monetary amount with an explicit sign, so meaning never
/// depends on color alone.
public struct AmountText: View {
    private let money: Money
    private let colored: Bool

    public init(_ money: Money, colored: Bool = false) {
        self.money = money
        self.colored = colored
    }

    public var body: some View {
        let sign = money.isNegative ? "−" : "+"
        Text("\(sign)\(money.formatted())")
            .monospacedDigit()
            .foregroundStyle(colored ? signColor : Color.primary)
    }

    private var signColor: Color {
        money.isNegative ? ProMeColor.expense : ProMeColor.income
    }
}
