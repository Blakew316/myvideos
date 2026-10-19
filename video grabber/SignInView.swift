//
//  SignInView.swift
//  My Videos
//

import SwiftUI
import WebKit
import Combine

/// A small, private browser for signing in to video sites. Its sign-ins are exported
/// to yt-dlp so members-only, private and age-restricted videos can be downloaded.
struct SignInView: View {
    @State private var browser = BrowserModel()
    @Environment(\.dismissWindow) private var dismissWindow

    private static let sites: [(name: String, url: String)] = [
        ("YouTube", "https://accounts.google.com/ServiceLogin?service=youtube&continue=https%3A%2F%2Fwww.youtube.com%2F"),
        ("Vimeo", "https://vimeo.com/log_in"),
        ("Instagram", "https://www.instagram.com/accounts/login/"),
        ("Facebook", "https://www.facebook.com/login"),
        ("X", "https://x.com/i/flow/login"),
        ("TikTok", "https://www.tiktok.com/login"),
        ("Twitch", "https://www.twitch.tv/login"),
        ("Patreon", "https://www.patreon.com/login"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Sign in to the sites you download from. Your sign-ins stay on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.bar)
            Divider()
            WebView(model: browser)
                .overlay(alignment: .top) {
                    if browser.isLoading {
                        ProgressView(value: browser.progress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 560)
        .navigationTitle(browser.title.isEmpty ? "Sign In" : browser.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { browser.webView.goBack() } label: { Label("Back", systemImage: "chevron.backward") }
                    .disabled(!browser.canGoBack)
                Button { browser.webView.goForward() } label: { Label("Forward", systemImage: "chevron.forward") }
                    .disabled(!browser.canGoForward)
            }
            ToolbarItem(placement: .principal) {
                Menu {
                    ForEach(Self.sites, id: \.name) { site in
                        Button(site.name) { browser.load(site.url) }
                    }
                } label: {
                    Label(browser.host.isEmpty ? "Choose a Site" : browser.host, systemImage: "globe")
                }
                .menuIndicator(.visible)
                .fixedSize()
                .help("Choose a site to sign in to")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { browser.webView.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    Task {
                        _ = await SignInSession.exportCookies()
                        await AppModel.shared.signIn.check(prefs: AppModel.shared.prefs, toolchain: AppModel.shared.toolchain)
                        dismissWindow(id: "signin")
                    }
                }
                .buttonStyle(.glassProminent)
            }
        }
        .onAppear {
            if browser.webView.url == nil { browser.load(Self.sites[0].url) }
            AppModel.shared.prefs.cookieSource = .builtIn
        }
    }
}

@Observable
final class BrowserModel: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    var title = ""
    var host = ""
    var isLoading = false
    var progress = 0.0
    var canGoBack = false
    var canGoForward = false
    private var observations: [AnyCancellable] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = SignInSession.dataStore
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = SignInSession.userAgent
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        // Publishers delivered on the main queue — never a background-thread KVO callback.
        observations = [
            webView.publisher(for: \.title).receive(on: DispatchQueue.main).sink { [weak self] in self?.title = $0 ?? "" },
            webView.publisher(for: \.url).receive(on: DispatchQueue.main).sink { [weak self] in self?.host = $0?.host() ?? "" },
            webView.publisher(for: \.isLoading).receive(on: DispatchQueue.main).sink { [weak self] in self?.isLoading = $0 },
            webView.publisher(for: \.estimatedProgress).receive(on: DispatchQueue.main).sink { [weak self] in self?.progress = $0 },
            webView.publisher(for: \.canGoBack).receive(on: DispatchQueue.main).sink { [weak self] in self?.canGoBack = $0 },
            webView.publisher(for: \.canGoForward).receive(on: DispatchQueue.main).sink { [weak self] in self?.canGoForward = $0 },
        ]
    }

    func load(_ string: String) {
        guard let url = URL(string: string) else { return }
        webView.load(URLRequest(url: url))
    }
}

private struct WebView: NSViewRepresentable {
    let model: BrowserModel
    func makeNSView(context: Context) -> WKWebView { model.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
