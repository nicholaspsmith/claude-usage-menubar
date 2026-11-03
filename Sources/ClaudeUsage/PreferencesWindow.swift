// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import ClaudeUsageCore
import StatusItemKit
import SwiftUI

/// Claude Usage's Preferences window (menu ▸ Preferences…, ⌘,), on
/// StatusItemKit's shared `PreferencesPane`. It replaced the Settings, Icon
/// and Color submenus: Start at Login and Show Sessions, the icon's shape and
/// One Eye per Window, the colour pair, and the app's own sign-in.
///
/// Every choice writes the defaults key the menus wrote (`MeterStyle`,
/// `WindowColors`, `ShowSessions`, `OwlEyePerWindow`), so nothing set before
/// is lost.
final class PreferencesModel: ObservableObject {
    /// The tile id of the usage ramp, which has no `ColorPair`.
    static let usageRampID = "usage"

    @Published var style: MeterStyle {
        didSet { if style != oldValue { appearance.style = style; onChange() } }
    }
    @Published var colorID: String {
        didSet {
            guard colorID != oldValue else { return }
            ColorPair.save(ColorPair.presets.first(where: { $0.id == colorID }))
            onChange()
        }
    }
    @Published var showSessions = MenuPreferences.showSessions() {
        didSet { if showSessions != oldValue { MenuPreferences.setShowSessions(showSessions) } }
    }
    @Published var eyePerWindow = MenuPreferences.eyePerWindow() {
        didSet { if eyePerWindow != oldValue { MenuPreferences.setEyePerWindow(eyePerWindow); onChange() } }
    }
    /// Whether the app holds a login of its own (only that one can be signed out).
    @Published var ownLogin = false
    /// A sign-in is waiting for the browser.
    @Published var signingIn = false

    let styles: [MeterStyle] = MeterStyle.proportional + [.character]
    private let appearance: MeterAppearance
    /// Redraws the menu-bar icon after a change to how it looks.
    private let onChange: () -> Void
    /// The icon as the bar would draw it in `style` with `colors`.
    let preview: (MeterStyle, ColorPair?) -> NSImage
    let signIn: () -> Void
    let signOut: () -> Void
    /// Whether a sign-in is in progress, from the app.
    private let isSigningIn: () -> Bool

    init(appearance: MeterAppearance,
         preview: @escaping (MeterStyle, ColorPair?) -> NSImage,
         isSigningIn: @escaping () -> Bool,
         signIn: @escaping () -> Void,
         signOut: @escaping () -> Void,
         onChange: @escaping () -> Void) {
        self.appearance = appearance
        self.preview = preview
        self.isSigningIn = isSigningIn
        self.signIn = signIn
        self.signOut = signOut
        self.onChange = onChange
        style = appearance.style
        colorID = ColorPair.stored()?.id ?? Self.usageRampID
    }

    /// Re-reads everything something else may have changed: the account
    /// (a sign-in finishing, a sign-out) and the stored choices.
    func refresh() {
        style = appearance.style
        colorID = ColorPair.stored()?.id ?? Self.usageRampID
        showSessions = MenuPreferences.showSessions()
        eyePerWindow = MenuPreferences.eyePerWindow()
        ownLogin = OwnLogin.exists
        signingIn = isSigningIn()
    }

    var selectedPair: ColorPair? { ColorPair.presets.first(where: { $0.id == colorID }) }

    func title(_ style: MeterStyle) -> String { style == .character ? "Owl" : style.title }
}

struct PreferencesView: View {
    @ObservedObject var model: PreferencesModel

    var body: some View {
        PreferencesForm {
            Section("General") {
                StartAtLoginToggle()
                Toggle("Show Sessions", isOn: $model.showSessions)
            }
            Section {
                IconTilePicker(model.styles.map { style in
                    .init(id: style, title: model.title(style), image: model.preview(style, model.selectedPair))
                }, selection: $model.style)
                .tileRow()
                Toggle("One Eye per Window", isOn: $model.eyePerWindow)
                    .disabled(model.style != .character)
            } header: {
                Text("Icon")
            } footer: {
                PreferencesNote("The meters show the 5-hour session. The owl shows both windows: his lids follow the session and his eyes the week, or, with One Eye per Window, the left eye is the session and the right the week.")
            }
            Section {
                IconTilePicker(colorChoices, selection: $model.colorID).tileRow()
            } header: {
                Text("Color")
            } footer: {
                PreferencesNote("Usage runs green to red with each window's use. A pair gives the session bar its first colour and the weekly bar its second, and so the owl's pupils.")
            }
            Section {
                if model.signingIn {
                    Text("Waiting for claude.ai in the browser…").foregroundStyle(.secondary)
                } else {
                    LabeledContent(model.ownLogin ? "Own login" : "Login") {
                        HStack {
                            Button(model.ownLogin ? "Sign In Again…" : "Sign In with Claude…") { model.signIn() }
                            if model.ownLogin {
                                Button("Sign Out") { model.signOut() }
                            }
                        }
                    }
                }
            } header: {
                Text("Account")
            } footer: {
                PreferencesNote("Without a login of its own the app reads Claude Code's. Signing in gives it one, kept in its own Keychain item, so it stays signed in without the CLI. Signing out forgets only that one; Claude Code's stays.")
            }
        }
    }

    private var colorChoices: [IconTilePicker<String>.Choice] {
        [.init(id: PreferencesModel.usageRampID, title: "Usage",
               image: ColorSwatch.image([MeterColor.health(0), MeterColor.health(1)]))]
            + ColorPair.presets.map { pair in
                .init(id: pair.id, title: pair.name,
                      image: ColorSwatch.image([ColorSwatch.color(pair.sessionHex), ColorSwatch.color(pair.weeklyHex)]))
            }
    }
}

private extension View {
    /// A floor under a row of tiles' height. Without it the grouped form
    /// measured the Icon row short and clipped the tops of its tiles
    /// (rendering the window offscreen, macOS 27); padding did not help.
    func tileRow() -> some View { frame(minHeight: 70) }
}

/// Two dots side by side, session left and week right.
enum ColorSwatch {
    static func color(_ hex: String) -> NSColor { MeterColor.color(fromHex: hex) ?? .systemGray }

    static func image(_ colors: [NSColor], diameter: CGFloat = 14) -> NSImage {
        let gap: CGFloat = 4
        let image = NSImage(size: NSSize(width: diameter * 2 + gap, height: diameter), flipped: false) { _ in
            for (i, color) in colors.enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: CGFloat(i) * (diameter + gap), y: 0, width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}

func makePreferences(model: PreferencesModel) -> PreferencesPane {
    let pane = PreferencesPane(appName: "Claude Usage") { PreferencesView(model: model) }
    pane.onShow = { [weak model] in model?.refresh() }
    return pane
}
