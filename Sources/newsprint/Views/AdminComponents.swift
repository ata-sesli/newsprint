import SwiftUI

struct AdminPageShell<Content: View>: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(theme.paneBackground)
        .navigationTitle(title)
    }
}

struct AdminSectionHeader: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let caption: String?

    init(_ title: String, caption: String? = nil) {
        self.title = title
        self.caption = caption
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let caption {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(theme.metadata)
            }
        }
    }
}

struct AdminSurface<Content: View>: View {
    @Environment(\.newsprintTheme) private var theme
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(theme.readerSurface, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.22))
            }
    }
}

struct AdminFieldRow<Control: View>: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    let caption: String?
    @ViewBuilder let control: Control

    init(_ title: String, caption: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.caption = caption
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(theme.metadata)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            control
                .frame(width: 280, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

struct PillTag: View {
    @Environment(\.newsprintTheme) private var theme
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(theme.metadata)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.tint.opacity(0.10), in: Capsule())
    }
}

struct CodePatternField: View {
    @Environment(\.newsprintTheme) private var theme
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(theme.windowBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.24))
            }
    }
}
