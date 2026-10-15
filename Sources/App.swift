import SwiftUI
import Foundation
import Network
import WebKit


// One proxy server. Fill the list in `ProxyManager.proxies` with your own.
struct ProxyEntry {
    enum Kind { case socks5, http }
    let kind: Kind
    let host: String
    let port: UInt16
    var username: String? = nil
    var password: String? = nil

    var label: String { "\(host):\(port)" }
}

final class ProxyManager {
    // ====== EDIT THIS LIST ======
    // Add proxy servers you own or have access to (a cheap VPS running
    // Dante/3proxy, or a proxy provider's endpoints).
    static let proxies: [ProxyEntry] = [
        // ProxyEntry(kind: .socks5, host: "1.2.3.4", port: 1080),
        // ProxyEntry(kind: .http, host: "5.6.7.8", port: 8080, username: "user", password: "pass"),
    ]
    // ============================

    private static let lastKey = "lastProxyIndex"

    /// Picks a random proxy, avoiding the one used last time.
    static func pickNext() -> ProxyEntry? {
        guard !proxies.isEmpty else { return nil }
        let last = UserDefaults.standard.integer(forKey: lastKey)
        var idx = Int.random(in: 0..<proxies.count)
        if proxies.count > 1 { while idx == last { idx = Int.random(in: 0..<proxies.count) } }
        UserDefaults.standard.set(idx, forKey: lastKey)
        return proxies[idx]
    }

    /// Builds a private (non-persistent) data store routed through the proxy. Requires iOS 17+.
    static func makeDataStore(using proxy: ProxyEntry?) -> WKWebsiteDataStore {
        let store = WKWebsiteDataStore.nonPersistent()
        guard let proxy, let port = NWEndpoint.Port(rawValue: proxy.port) else { return store }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(proxy.host), port: port)
        var config: ProxyConfiguration
        switch proxy.kind {
        case .socks5: config = ProxyConfiguration(socksv5Proxy: endpoint)
        case .http:   config = ProxyConfiguration(httpCONNECTProxy: endpoint)
        }
        if let u = proxy.username, let p = proxy.password {
            config.applyCredential(username: u, password: p)
        }
        store.proxyConfigurations = [config]
        return store
    }
}


final class BrowserModel: ObservableObject {
    @Published var webView: WKWebView
    @Published var currentProxy: ProxyEntry?
    @Published var address = ""

    init() {
        let proxy = ProxyManager.pickNext()      // new proxy on every app launch
        currentProxy = proxy
        webView = BrowserModel.makeWebView(proxy)
        load("https://api.ipify.org")            // shows your current IP at start
    }

    static func makeWebView(_ proxy: ProxyEntry?) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = ProxyManager.makeDataStore(using: proxy)
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.allowsBackForwardNavigationGestures = true
        return wv
    }

    /// Switch to a different proxy right now (also wipes cookies, since the store is private).
    func newIP() {
        let proxy = ProxyManager.pickNext()
        currentProxy = proxy
        webView = BrowserModel.makeWebView(proxy)
        load("https://api.ipify.org")
    }

    func load(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        var url: URL?
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            url = URL(string: text)
        } else if text.contains(".") && !text.contains(" ") {
            url = URL(string: "https://" + text)
        } else {
            var c = URLComponents(string: "https://duckduckgo.com/")!
            c.queryItems = [URLQueryItem(name: "q", value: text)]
            url = c.url
        }
        if let url { webView.load(URLRequest(url: url)) }
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ContentView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: model.currentProxy == nil ? "lock.open" : "lock.shield")
                    .foregroundColor(model.currentProxy == nil ? .red : .green)
                Text(model.currentProxy.map { "VPN/proxy: \($0.label)" } ?? "No proxy configured")
                    .font(.caption)
                Spacer()
            }
            .padding(.horizontal).padding(.vertical, 6)

            HStack {
                TextField("Search or enter address", text: $model.address)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .keyboardType(.webSearch)
                    .onSubmit { model.load(model.address) }
                Button("Go") { model.load(model.address) }
            }
            .padding(.horizontal).padding(.bottom, 6)

            WebViewHost(webView: model.webView)
                .id(ObjectIdentifier(model.webView))

            HStack(spacing: 28) {
                Button { model.webView.goBack() } label: { Image(systemName: "chevron.left") }
                Button { model.webView.goForward() } label: { Image(systemName: "chevron.right") }
                Button { model.webView.reload() } label: { Image(systemName: "arrow.clockwise") }
                Button { model.newIP() } label: { Label("New IP", systemImage: "arrow.triangle.2.circlepath") }
                Button { model.load("https://api.ipify.org") } label: { Image(systemName: "network") }
            }
            .padding(10)
        }
    }
}


@main
struct PrivateVPNBrowserApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

