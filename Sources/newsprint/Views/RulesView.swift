import SwiftData
import SwiftUI
import newsprintCore

struct RulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.newsprintTheme) private var theme
    @Query(sort: \FilterRule.priority) private var rules: [FilterRule]
    @State private var name = ""
    @State private var target: RuleTarget = .title
    @State private var matchMode: RuleMatchMode = .contains
    @State private var pattern = ""
    @State private var action: RuleAction = .tag
    @State private var actionValue = ""
    @State private var priority = 0
    @State private var errorMessage: String?

    var body: some View {
        AdminPageShell("Rules") {
            HStack(alignment: .top) {
                AdminSectionHeader(
                    "Rules",
                    caption: "Filter, tag, hide, and score incoming articles as they are saved."
                )

                Spacer()

                Button("Add Rule", systemImage: "plus") {
                    addRule()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAddRule)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            AdminSurface {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        ruleTextColumn
                        Divider()
                        ruleConfigColumn
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        ruleTextColumn
                        Divider()
                        ruleConfigColumn
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                AdminSectionHeader("Existing Rules", caption: "\(rules.count) configured")

                if rules.isEmpty {
                    ContentUnavailableView("No Rules", systemImage: "line.3.horizontal.decrease.circle", description: Text("Add a rule to shape your feed automatically."))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(rules) { rule in
                            RuleRow(rule: rule, saveRule: saveRule, delete: deleteRule)
                        }
                    }
                }
            }
        }
    }

    private var ruleTextColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $name)
                .font(.headline)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 6) {
                Text("Pattern")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.metadata)
                CodePatternField(placeholder: "regex|keyword|domain", text: $pattern)
            }

            if action == .boost || action == .tag {
                TextField(action == .boost ? "Score Delta" : "Tag", text: $actionValue)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var ruleConfigColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Target", selection: $target) {
                ForEach(RuleTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }

            Picker("Match", selection: $matchMode) {
                ForEach(RuleMatchMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Action", selection: $action) {
                ForEach(RuleAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }

            Stepper("Priority \(priority)", value: $priority, in: -100...100)
        }
        .pickerStyle(.menu)
        .frame(width: 260, alignment: .leading)
    }

    private var canAddRule: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addRule() {
        let rule = FilterRule(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            target: target,
            matchMode: matchMode,
            pattern: pattern.trimmingCharacters(in: .whitespacesAndNewlines),
            action: action,
            actionValue: normalizedActionValue,
            priority: priority
        )
        modelContext.insert(rule)
        saveRule()
        name = ""
        pattern = ""
        actionValue = ""
        priority = 0
    }

    private var normalizedActionValue: String? {
        actionValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func saveRule() {
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRule(_ rule: FilterRule) {
        do {
            try SwiftDataRuleRepository(context: modelContext).delete(rule)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RuleRow: View {
    @Environment(\.newsprintTheme) private var theme
    let rule: FilterRule
    let saveRule: () -> Void
    let delete: (FilterRule) -> Void

    var body: some View {
        AdminSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    TextField("Name", text: binding(\.name))
                        .font(.headline)
                        .textFieldStyle(.plain)

                    Toggle("Enabled", isOn: binding(\.enabled))
                        .toggleStyle(.switch)
                        .labelsHidden()

                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete(rule)
                    }
                    .buttonStyle(.borderless)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        configRow
                        CodePatternField(placeholder: "Pattern", text: binding(\.pattern))
                            .frame(minWidth: 260)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        configRow
                        CodePatternField(placeholder: "Pattern", text: binding(\.pattern))
                    }
                }

                HStack(spacing: 12) {
                    TextField("Action Value", text: optionalBinding(\.actionValue))
                        .textFieldStyle(.roundedBorder)
                    Stepper("Priority \(rule.priority)", value: binding(\.priority), in: -100...100)
                        .frame(width: 170)
                }
            }
        }
    }

    private var configRow: some View {
        HStack(spacing: 10) {
            Picker("Target", selection: Binding(
                get: { rule.target },
                set: { value in
                    rule.target = value
                    rule.updatedAt = Date()
                    saveRule()
                }
            )) {
                ForEach(RuleTarget.allCases) { target in
                    Text(target.displayName).tag(target)
                }
            }

            Picker("Match", selection: Binding(
                get: { rule.matchMode },
                set: { value in
                    rule.matchMode = value
                    rule.updatedAt = Date()
                    saveRule()
                }
            )) {
                ForEach(RuleMatchMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Action", selection: Binding(
                get: { rule.action },
                set: { value in
                    rule.action = value
                    rule.updatedAt = Date()
                    saveRule()
                }
            )) {
                ForEach(RuleAction.allCases) { action in
                    Text(action.displayName).tag(action)
                }
            }
        }
        .pickerStyle(.menu)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<FilterRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                rule[keyPath: keyPath] = value
                rule.updatedAt = Date()
                saveRule()
            }
        )
    }

    private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<FilterRule, String?>) -> Binding<String> {
        Binding(
            get: { rule[keyPath: keyPath] ?? "" },
            set: { value in
                rule[keyPath: keyPath] = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                rule.updatedAt = Date()
                saveRule()
            }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
