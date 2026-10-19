//
//  SignInControls.swift
//  My Videos
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Picker + live status for how My Videos signs in. Choosing a method does the obvious
/// next step right away, and the status says whether it works and what to do if not.
struct SignInControls: View {
    @Bindable var model: AppModel
    /// Compact rows for the Download page; full sections in Settings.
    var compact = false
    @Environment(\.openWindow) private var openWindow

    private var prefs: Preferences { model.prefs }

    var body: some View {
        Group {
            if compact {
                FormRow(title: "Sign-In", systemImage: "person.crop.circle.badge.checkmark", color: .green) {
                    sourcePicker
                }
                if prefs.cookieSource == .browser {
                    FormRow(title: "Browser", systemImage: "safari.fill", color: .teal) { browserPicker }
                    if !model.signIn.profiles.isEmpty {
                        FormRow(title: "Profile", systemImage: "person.2.fill", color: .blue) { profilePicker }
                    }
                }
                if prefs.cookieSource != .none {
                    statusRow.padding(.horizontal, 12).padding(.vertical, 10)
                }
            } else {
                Section {
                    LabeledContent("Sign in using") { sourcePicker }
                    if prefs.cookieSource == .browser {
                        LabeledContent("Browser") { browserPicker }
                        if !model.signIn.profiles.isEmpty {
                            LabeledContent("Profile") { profilePicker }
                        }
                    }
                    if prefs.cookieSource != .none { statusRow }
                } footer: {
                    Text(footer).foregroundStyle(.secondary)
                }
            }
        }
        .task { await model.signIn.check(prefs: prefs, toolchain: model.toolchain) }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Coming back from the sign-in window or System Settings: refresh what's shown.
            Task { await model.signIn.check(prefs: prefs, toolchain: model.toolchain) }
        }
    }

    private var sourcePicker: some View {
        Picker("Sign in using", selection: Binding(
            get: { prefs.cookieSource },
            set: { choose($0) })) {
            ForEach(CookieSource.allCases) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    private var browserPicker: some View {
        Picker("Browser", selection: Binding(
            get: { prefs.cookieBrowser },
            set: { browser in
                prefs.cookieBrowser = browser
                prefs.cookieBrowserProfile = ""
                recheck()
            })) {
            ForEach(CookieBrowser.allCases) { Text($0.displayName).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// Browsers with several people/profiles: pick the one signed in to the site.
    private var profilePicker: some View {
        Picker("Profile", selection: Binding(
            get: { prefs.cookieBrowserProfile },
            set: { profile in
                prefs.cookieBrowserProfile = profile
                recheck()
            })) {
            Text("Most Recently Used").tag("")
            Divider()
            ForEach(model.signIn.profiles) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .fixedSize()
    }

    /// Selecting a method immediately does what it needs.
    private func choose(_ source: CookieSource) {
        prefs.cookieSource = source
        Task {
            await model.signIn.check(prefs: prefs, toolchain: model.toolchain, readBrowser: source == .browser)
            switch (source, model.signIn.state) {
            case (.builtIn, .problem): openWindow(id: "signin")
            case (.file, .problem): chooseFile()
            default: break
            }
        }
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(alignment: .top, spacing: 10) {
            switch model.signIn.state {
            case .notNeeded:
                EmptyView()
            case .checking:
                ProgressView().controlSize(.small)
                Text(prefs.cookieSource == .browser
                     ? "Reading \(prefs.cookieBrowser.displayName)’s sign-ins…"
                     : "Checking…")
                    .foregroundStyle(.secondary)
                Spacer()
            case .ready(let sites):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Signed in to \(Self.list(sites))")
                    if prefs.cookieSource == .file {
                        Text((prefs.cookieFilePath as NSString).lastPathComponent)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer()
                actionButton(for: .none)
            case .problem(let message, let fix):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                actionButton(for: fix)
            }
        }
        .font(.callout)
        .animation(.smooth(duration: 0.2), value: model.signIn.state)
    }

    @ViewBuilder
    private func actionButton(for fix: SignInStatus.Fix) -> some View {
        switch (fix, prefs.cookieSource) {
        case (.signIn, _), (.none, .builtIn):
            Button(fix == .signIn ? "Sign In…" : "Add a Site…") { openWindow(id: "signin") }
        case (.chooseFile, _), (.none, .file):
            Button(fix == .chooseFile ? "Choose File…" : "Change…", action: chooseFile)
        case (.fullDiskAccess, _):
            VStack(alignment: .trailing, spacing: 6) {
                Button("Open Full Disk Access") { SignInStatus.openFullDiskAccess() }
                Button("Reopen My Videos") { SignInStatus.relaunch() }
                    .help("macOS applies Full Disk Access after the app reopens")
            }
        case (.useBuiltIn, _):
            Button("Use My Videos Sign-In") { choose(.builtIn) }
        case (.retry, _), (.none, .browser):
            Button(fix == .retry ? "Check Again" : "Refresh") { recheck() }
        default:
            EmptyView()
        }
    }

    private func recheck() {
        Task { await model.signIn.check(prefs: prefs, toolchain: model.toolchain, readBrowser: true) }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a cookies.txt File"
        panel.message = "Export it from a browser where you’re signed in (Netscape format)."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text, .plainText, .item]
        panel.prompt = "Use File"
        if panel.runModal() == .OK, let url = panel.url {
            prefs.cookieFilePath = url.path
        }
        Task { await model.signIn.check(prefs: prefs, toolchain: model.toolchain) }
    }

    private var footer: String {
        switch prefs.cookieSource {
        case .none:
            return "Public videos never need a sign-in. Use one for private, members-only or age-restricted videos."
        case .builtIn:
            return "Sign in once in My Videos’ own browser window. Your sign-ins stay private on this Mac."
        case .browser:
            return "Uses the sites you’re signed in to in another browser. They’re read once and refreshed twice a day, so you won’t be asked for your password on every download."
        case .file:
            return "A Netscape-format cookies.txt exported from a browser where you’re signed in (for example with the “Get cookies.txt LOCALLY” extension)."
        }
    }

    static func list(_ sites: [String]) -> String {
        switch sites.count {
        case 0: return "no sites"
        case 1...3: return sites.joined(separator: ", ")
        default: return sites.prefix(3).joined(separator: ", ") + " and \(sites.count - 3) more"
        }
    }
}

// MARK: - Sign-in menu

/// How downloads sign in, switchable right where you download: a browser's sign-ins,
/// My Videos Sign-In, or a cookies.txt file.
struct SignInMenu: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    private var prefs: Preferences { model.prefs }

    private var needsAttention: Bool {
        if prefs.cookieSource == .none { return false }
        if case .problem = model.signIn.state { return true }
        return false
    }

    private var title: String {
        if needsAttention { return "Sign-In Needs Attention" }
        switch prefs.cookieSource {
        case .none: return "Not Signed In"
        case .browser: return "Signed In with \(prefs.cookieBrowser.displayName)"
        case .builtIn: return "My Videos Sign-In"
        case .file: return "Signed In with cookies.txt"
        }
    }

    var body: some View {
        Menu {
            Toggle("Don’t Sign In", isOn: binding { prefs.cookieSource == .none } set: { use(.none) })
            Section("Use Your Sign-Ins From") {
                ForEach(CookieBrowser.allCases) { browser in
                    Toggle(browser.displayName, isOn: binding {
                        prefs.cookieSource == .browser && prefs.cookieBrowser == browser
                    } set: {
                        if prefs.cookieBrowser != browser { prefs.cookieBrowserProfile = "" }
                        prefs.cookieBrowser = browser
                        use(.browser)
                    })
                }
            }
            Divider()
            Toggle("My Videos Sign-In…", isOn: binding { prefs.cookieSource == .builtIn } set: {
                use(.builtIn)
                openWindow(id: "signin")
            })
            Toggle("cookies.txt File…", isOn: binding { prefs.cookieSource == .file } set: { chooseFile() })
            Divider()
            Button("Accounts Settings…") { Self.openAccounts(openSettings) }
        } label: {
            Label(title, systemImage: needsAttention ? "exclamationmark.triangle.fill"
                  : prefs.cookieSource == .none ? "person.crop.circle" : "person.crop.circle.badge.checkmark")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .foregroundStyle(needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        .font(.callout)
        .help("Choose how downloads sign in to sites, for private and members-only videos")
    }

    /// Opens Settings on the Accounts tab.
    static func openAccounts(_ openSettings: OpenSettingsAction) {
        // SwiftUI remembers the Settings tab here; Accounts is the fourth tab.
        UserDefaults.standard.set(3, forKey: "com_apple_SwiftUI_Settings_selectedTabIndex")
        NSApp.activate()
        openSettings()
    }

    private func binding(_ get: @escaping () -> Bool, set: @escaping () -> Void) -> Binding<Bool> {
        Binding(get: get, set: { if $0 { set() } })
    }

    private func use(_ source: CookieSource) {
        prefs.cookieSource = source
        Task { await model.signIn.check(prefs: prefs, toolchain: model.toolchain, readBrowser: source == .browser) }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose a cookies.txt File"
        panel.message = "Export it from a browser where you’re signed in (Netscape format)."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.text, .plainText, .item]
        panel.prompt = "Use File"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        prefs.cookieFilePath = url.path
        use(.file)
    }
}
