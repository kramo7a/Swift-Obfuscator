struct Handler {
    let label: String
    init(_ label: String) {
        self.label = label
    }
    func format(_ message: String) -> String {
        "\(message)"
    }
    func evaluate(_ webView: WebView) {
        work { [weak webView] in webView?.run() }
    }
    func shadow(_ value: Int) -> Int {
        do { let value = 1; _ = value }
        return value
    }
}
