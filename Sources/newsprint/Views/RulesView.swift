import SwiftData
import SwiftUI
import newsprintCore

struct RulesView: View {
    @Environment(\.modelContext) private var modelContext
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
        VStack(spacing: 0) {
            Form {
                Section("Add Rule") {
                    TextField("Name", text: $name)
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
                    TextField("Pattern", text: $pattern)
                    Picker("Action", selection: $action) {
                        ForEach(RuleAction.allCases) { action in
                            Text(action.displayName).tag(action)
                        }
                    }
                    if action == .boost || action == .tag {
                        TextField(action == .boost ? "Score Delta" : "Tag", text: $actionValue)
                    }
                    Stepper("Priority \(priority)", value: $priority, in: -100...100)

                    HStack {
                        Button("Add Rule", systemImage: "plus") {
                            addRule()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Reapply Rules", systemImage: "arrow.triangle.2.circlepath") {
                            reapplyRules()
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 360)

            Divider()

            List {
                ForEach(rules) { rule in
                    RuleRow(rule: rule, saveAndReapply: saveAndReapply, delete: deleteRule)
                }
            }
        }
        .navigationTitle("Rules")
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
        saveAndReapply()
        name = ""
        pattern = ""
        actionValue = ""
        priority = 0
    }

    private var normalizedActionValue: String? {
        actionValue.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func saveAndReapply() {
        do {
            try modelContext.save()
            try SwiftDataRuleRepository(context: modelContext).reapplyEnabledRules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reapplyRules() {
        do {
            try SwiftDataRuleRepository(context: modelContext).reapplyEnabledRules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteRule(_ rule: FilterRule) {
        do {
            try SwiftDataRuleRepository(context: modelContext).delete(rule)
            try SwiftDataRuleRepository(context: modelContext).reapplyEnabledRules()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RuleRow: View {
    let rule: FilterRule
    let saveAndReapply: () -> Void
    let delete: (FilterRule) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: binding(\.name))
                    .font(.headline)

                Toggle("Enabled", isOn: binding(\.enabled))
                    .labelsHidden()

                Button("Delete", systemImage: "trash", role: .destructive) {
                    delete(rule)
                }
            }

            HStack {
                Picker("Target", selection: Binding(
                    get: { rule.target },
                    set: { value in
                        rule.target = value
                        rule.updatedAt = Date()
                        saveAndReapply()
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
                        saveAndReapply()
                    }
                )) {
                    ForEach(RuleMatchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                TextField("Pattern", text: binding(\.pattern))

                Picker("Action", selection: Binding(
                    get: { rule.action },
                    set: { value in
                        rule.action = value
                        rule.updatedAt = Date()
                        saveAndReapply()
                    }
                )) {
                    ForEach(RuleAction.allCases) { action in
                        Text(action.displayName).tag(action)
                    }
                }
            }

            HStack {
                TextField("Action Value", text: optionalBinding(\.actionValue))
                Stepper("Priority \(rule.priority)", value: binding(\.priority), in: -100...100)
            }
        }
        .padding(.vertical, 4)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<FilterRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { value in
                rule[keyPath: keyPath] = value
                rule.updatedAt = Date()
                saveAndReapply()
            }
        )
    }

    private func optionalBinding(_ keyPath: ReferenceWritableKeyPath<FilterRule, String?>) -> Binding<String> {
        Binding(
            get: { rule[keyPath: keyPath] ?? "" },
            set: { value in
                rule[keyPath: keyPath] = value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                rule.updatedAt = Date()
                saveAndReapply()
            }
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
