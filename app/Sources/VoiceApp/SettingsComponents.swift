import SwiftUI

// Shared building blocks for the Settings window, matching voice.pen:
// section labels, rows (title + description + trailing control), select pills,
// switches, keycaps, and model cards.

struct SettingsSection: View {
    let title: String
    var topPadding: CGFloat = 26

    var body: some View {
        Text(title)
            .font(Theme.inter(10.5, .bold))
            .kerning(1.4)
            .foregroundStyle(Theme.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: topPadding, leading: 0, bottom: 8, trailing: 0))
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var description: String = ""
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.inter(13.5, .medium))
                    .foregroundStyle(Theme.ink)
                if !description.isEmpty {
                    Text(description)
                        .font(Theme.inter(12))
                        .foregroundStyle(Theme.ink2)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.vertical, 15)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line2).frame(height: 1)
        }
    }
}

/// The design's 38×22 pill switch (accent on / warm gray off).
struct EmberToggle: View {
    @Binding var isOn: Bool
    var disabled = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Theme.accent : Color(hex: 0xD6D4CC))
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                .frame(width: 18, height: 18)
                .padding(2)
        }
        .frame(width: 38, height: 22)
        .opacity(disabled ? 0.45 : 1)
        .onTapGesture {
            guard !disabled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        }
    }
}

/// The design's bordered select pill, backed by a native menu.
struct SelectPill<T: Hashable>: View {
    @Binding var selection: T
    let options: [(value: T, label: String)]

    private var currentLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { opt in
                Button(opt.label) { selection = opt.value }
            }
        } label: {
            HStack(spacing: 7) {
                Text(currentLabel)
                    .font(Theme.inter(13, .medium))
                    .foregroundStyle(Theme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.ink3)
            }
            .padding(EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11))
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct SettingsButton: View {
    let label: String
    var destructive = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.inter(13, .semibold))
                .foregroundStyle(destructive ? Theme.accent : Theme.ink)
                .padding(EdgeInsets(top: 8, leading: 13, bottom: 8, trailing: 13))
                .background(RoundedRectangle(cornerRadius: 8)
                    .fill(destructive ? Color(hex: 0xFBEDEB) : Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(destructive ? Color(hex: 0xE5483A, alpha: 0x38) : Theme.line,
                            lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(Theme.inter(12.5, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bg))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}

struct StatusBadge: View {
    let label: String
    var ok = true

    var body: some View {
        HStack(spacing: 6) {
            if ok {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            } else {
                Circle().frame(width: 7, height: 7)
            }
            Text(label).font(Theme.inter(12, .semibold))
        }
        .foregroundStyle(ok ? Color(hex: 0x1F7A45) : Color(hex: 0xB0832A))
        .padding(EdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11))
        .background(Capsule().fill(ok ? Color(hex: 0xE7F2EA) : Color(hex: 0xF7EFDC)))
    }
}

/// Model card per the Models page design.
struct ModelCard<Trailing: View>: View {
    let icon: String
    var iconEmber = false
    let title: String
    var tag: String? = nil
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if iconEmber {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.ember)
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.pane)
                }
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconEmber ? .white : Theme.ink2)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(Theme.inter(14, .semibold))
                        .foregroundStyle(Theme.ink)
                    if let tag {
                        Text(tag)
                            .font(Theme.inter(10.5, .semibold))
                            .kerning(0.3)
                            .foregroundStyle(Theme.ink3)
                            .padding(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                            .background(Capsule().fill(Theme.pane))
                    }
                }
                Text(subtitle)
                    .font(Theme.inter(12.5))
                    .foregroundStyle(Theme.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
    }
}

/// Removable word chip for the Vocabulary page.
struct WordChip: View {
    let word: String
    var accent = false
    var onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Text(word)
                .font(Theme.inter(12.5, .medium))
                .foregroundStyle(Theme.ink)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.ink3)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 9))
        .background(Capsule().fill(accent ? Theme.sel : Theme.bg))
        .overlay(Capsule().stroke(accent ? Color(hex: 0xE5483A, alpha: 0x38) : Theme.line,
                                  lineWidth: 1))
    }
}

/// Simple left-aligned wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 600
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
