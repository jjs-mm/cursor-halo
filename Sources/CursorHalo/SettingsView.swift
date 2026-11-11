import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @ObservedObject var loginItem: LoginItemModel
    let quit: () -> Void

    private var tint: Color { Color(nsColor: settings.color.nsColor) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Cursor Halo").font(.system(size: 19, weight: .semibold))
                        Text(settings.isEnabled ? "A little easier to follow." : "Ready when you need it.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("Highlight cursor", isOn: $settings.isEnabled)
                        .labelsHidden().toggleStyle(.switch).tint(tint)
                        .accessibilityLabel("Highlight cursor")
                }

                if let error = settings.monitoringError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .textBackgroundColor))
                    HStack(spacing: 5) {
                        ForEach(0..<15) { _ in Circle().fill(Color.primary.opacity(0.08)).frame(width: 2, height: 2) }
                    }.offset(y: 32)
                    Circle()
                        .fill(settings.style == .disc ? tint.opacity(settings.opacity * 0.24) : .clear)
                        .overlay(Circle().stroke(Color.black.opacity(settings.opacity * 0.65), lineWidth: settings.lineWidth + 2))
                        .overlay(Circle().stroke(tint.opacity(settings.opacity), lineWidth: settings.lineWidth))
                        .frame(width: settings.diameter - settings.lineWidth, height: settings.diameter - settings.lineWidth)
                    Image(systemName: "cursorarrow").font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white).shadow(color: .black, radius: 1)
                        .offset(x: 7, y: -8)
                    VStack {
                        HStack {
                            Text("PREVIEW").font(.system(size: 9, weight: .semibold)).tracking(1.2)
                            Spacer()
                            Text(settings.isEnabled ? "ON" : "PAUSED").font(.system(size: 9, weight: .semibold))
                        }.foregroundStyle(.secondary)
                        Spacer()
                    }.padding(12)
                }.frame(height: 146).accessibilityLabel("Halo appearance preview")

                Picker("Style", selection: $settings.style) {
                    ForEach(HaloStyle.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Halo style")

                HStack(spacing: 10) {
                    Text("Color").font(.system(size: 12)).frame(width: 45, alignment: .leading)
                    ForEach(HaloColor.allCases) { color in
                        Button { settings.color = color } label: {
                            Circle().fill(Color(nsColor: color.nsColor)).frame(width: 24, height: 24)
                                .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 1))
                                .overlay {
                                    if settings.color == color {
                                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black.opacity(0.8))
                                    }
                                }
                        }.buttonStyle(.plain).accessibilityLabel("\(color.title) halo")
                            .accessibilityAddTraits(settings.color == color ? .isSelected : [])
                            .help(color.title)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 11) {
                    valueSlider("Size", value: $settings.diameter, range: 28...120, label: "\(Int(settings.diameter)) pt")
                    valueSlider("Opacity", value: $settings.opacity, range: 0.2...1, label: "\(Int(settings.opacity * 100))%")
                    valueSlider("Stroke", value: $settings.lineWidth, range: 1...8, label: String(format: "%.1f pt", settings.lineWidth))
                }

                Divider()
                Toggle("Show clicks", isOn: $settings.showsClicks).toggleStyle(.switch).controlSize(.small).tint(tint)
                Text("A ripple marks each click. Right-clicks use a contrasting color.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -10)
                HStack {
                    Text("Toggle shortcut").font(.system(size: 12))
                    Spacer()
                    Picker("Toggle shortcut", selection: $settings.shortcut) {
                        ForEach(ToggleShortcut.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden().frame(width: 110)
                }
                if let error = settings.shortcutError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Launch at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                .toggleStyle(.switch).controlSize(.small).tint(tint)
                if loginItem.requiresApproval {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Allow Cursor Halo in Login Items to finish enabling automatic launch.")
                            .foregroundStyle(.secondary)
                        Button("Open Login Items") { loginItem.openLoginItemsSettings() }
                    }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                }
                if let error = loginItem.errorMessage {
                    Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Text("For recordings, share your whole display so the halo is included.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack {
                    Button("Reset appearance") { settings.resetAppearance() }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    Spacer()
                    Link("Source", destination: URL(string: "https://github.com/jjs-mm/cursor-halo")!)
                        .foregroundStyle(.secondary)
                    Button("Quit", action: quit).buttonStyle(.plain)
                }.font(.system(size: 11))
            }
            .padding(20).frame(width: 324)
        }
        .frame(width: 324, height: min(700, max(320, (NSScreen.main?.visibleFrame.height ?? 800) - 40)))
    }

    private func valueSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).frame(width: 48, alignment: .leading)
            Slider(value: value, in: range).tint(tint).accessibilityLabel(title)
            Text(label).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 45, alignment: .trailing)
        }
    }
}
