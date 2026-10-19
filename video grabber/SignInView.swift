//
//  SignInView.swift
//  My Videos
//

import SwiftUI
import WebKit

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
    private var observations: [NSKeyValueObservation] = []

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = SignInSession.dataStore
        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = SignInSession.userAgent
        webView.allowsBackForwardNavigationGestures = true
        super.init()
        webView.navigationDelegate = self
        observations = [
            webView.observe(\.title) { [weak self] web, _ in MainActor.assumeIsolated { self?.title = web.title ?? "" } },
            webView.observe(\.url) { [weak self] web, _ in MainActor.assumeIsolated { self?.host = web.url?.host() ?? "" } },
            webView.observe(\.isLoading) { [weak self] web, _ in MainActor.assumeIsolated { self?.isLoading = web.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] web, _ in MainActor.assumeIsolated { self?.progress = web.estimatedProgress } },
            webView.observe(\.canGoBack) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoBack = web.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] web, _ in MainActor.assumeIsolated { self?.canGoForward = web.canGoForward } },
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
