import SwiftUI
import SwiftData

/// 资金账户管理（规格第十二节）。
struct AccountListView: View {
    @Environment(\.modelContext) private var context

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.createdAt)])
    private var accounts: [Account]

    @Query(sort: [SortDescriptor(\Transaction.date, order: .reverse)])
    private var allTransactions: [Transaction]

    @State private var editing: Account?
    @State private var showingForm = false
    @State private var errorMessage: String?

    private var balances: [UUID: Int64] {
        var result: [UUID: Int64] = [:]
        for account in accounts {
            let id = account.accountID
            let delta = allTransactions
                .filter { $0.accountID == id }
                .reduce(Int64(0)) { $0 + ($1.type == .income ? $1.cents : -$1.cents) }
            result[id] = account.openingBalanceCents + delta
        }
        return result
    }

    private var netWorthCents: Int64 {
        accounts.filter(\.includeInNetWorth)
            .reduce(Int64(0)) { $0 + (balances[$1.accountID] ?? 0) }
    }

    var body: some View {
        List {
            if !accounts.isEmpty {
                Section {
                    LabeledContent("总资产（计入部分）") {
                        Text(Money(cents: netWorthCents).displayText)
                            .fontWeight(.semibold)
                    }
                } footer: {
                    Text("余额 = 期初余额 + 关联交易（收入加、支出减）。预算是规划，账户是实际的钱，两者分开统计。")
                        .listRowBackground(Color.clear)
                }
                .dsGlassRowCard()
            }
            Section {
                ForEach(accounts) { account in
                    Button {
                        editing = account
                    } label: {
                        accountRow(account)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            delete(account)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text("删除账户只会解绑交易，消费记录会完整保留。")
                    .listRowBackground(Color.clear)
            }
            .dsGlassRowCard()
        }
        .dsGlassListSurface()
        .navigationTitle("资金账户")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingForm = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingForm) {
            AccountFormSheet()
        }
        .sheet(item: $editing) { account in
            AccountFormSheet(editingAccount: account)
        }
        .alert(
            "出错了",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                Image(systemName: account.icon)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text("\(account.type.title)\(account.includeInNetWorth ? " · 计入总资产" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Money(cents: balances[account.accountID] ?? 0).displayText)
                .fontWeight(.semibold)
                .foregroundStyle((balances[account.accountID] ?? 0) < 0 ? Color.red : Color.primary)
        }
    }

    private func delete(_ account: Account) {
        do {
            try AccountService(context: context).delete(account)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 新建 / 编辑资金账户。
struct AccountFormSheet: View {
    var editingAccount: Account? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: AccountType = .bank
    @State private var openingBalanceString = ""
    @State private var includeInNetWorth = true
    @State private var errorMessage: String?

    private let icons = ["building.columns", "creditcard", "banknote", "iphone", "wallet.pass", "giftcard"]

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("如：招商银行卡、微信零钱", text: $name)
                }
                Section {
                    Picker("类型", selection: $type) {
                        ForEach(AccountType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    Picker("图标", selection: $icon) {
                        ForEach(icons, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                } header: {
                    Text("类型")
                }
                Section {
                    TextField("期初余额（元）", text: $openingBalanceString)
                        .keyboardType(.decimalPad)
                    Toggle("计入总资产", isOn: $includeInNetWorth)
                } header: {
                    Text("余额")
                } footer: {
                    Text("期初余额是开始记录时这个账户实际有的钱；之后的余额会随绑定的收支自动变化。储蓄、公积金等不想计入总资产的账户可以关掉开关。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingAccount == nil ? "新建账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") { save() }
                }
            }
            .onAppear { loadIfNeeded() }
        }
    }

    @State private var icon = "creditcard"

    private func loadIfNeeded() {
        guard let account = editingAccount, name.isEmpty else { return }
        name = account.name
        type = account.type
        icon = account.icon
        openingBalanceString = account.openingBalanceCents == 0
            ? ""
            : Money(cents: account.openingBalanceCents).inputText
        includeInNetWorth = account.includeInNetWorth
    }

    private func save() {
        do {
            let cents = Money(string: openingBalanceString)?.cents ?? 0
            let service = AccountService(context: context)
            if let account = editingAccount {
                try service.update(
                    account,
                    name: name,
                    type: type,
                    icon: icon,
                    openingBalanceCents: cents,
                    includeInNetWorth: includeInNetWorth
                )
            } else {
                try service.create(
                    name: name,
                    type: type,
                    icon: icon,
                    openingBalanceCents: cents,
                    includeInNetWorth: includeInNetWorth
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
