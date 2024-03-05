//
//  WebView.swift
//
//  Created by Piotrek on 28/09/2022.
//

import WebKit
import SwiftUI

@Observable
public final class WebViewNavigator {
    
    public let webView = WKWebView()
    @ObservationIgnored
    fileprivate var previousRequest: URLRequest?

    var canGoBack: Bool = false
    var canGoForward: Bool = false

    @ObservationIgnored
    var url: URL? { webView.url }

    public init() { }
    
    func load(_ request: URLRequest) {
        webView.load(request)
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    fileprivate func canProceed(_ request: URLRequest?) -> Bool {
        guard let request = request else { return false }
        guard let previousRequest = previousRequest else {
            self.previousRequest = request
            return true
        }

        if previousRequest != request {
            self.previousRequest = request
            return true
        }

        return false
    }
}

public struct WebView: UIViewRepresentable {
    
    @Binding var request: URLRequest?

    @State var viewModel: WebViewNavigator

    private var onProgressChange: ((CGFloat) -> Void)?
    private var decisionPolicy: ((Navigation) -> Policy)?
    private var onDownload: ((Navigation, WKDownload) -> Void)?
    private var onErrorOccurred: ((WKNavigation, Error) -> Void)?
    private var loadingProgress: ((Phase, WKNavigation) -> Void)?
    private var allowDeprecatedTLS: ((URLAuthenticationChallenge) -> Bool)?
    private var didReceiveChallenge: ((URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?))?

    public init(request: Binding<URLRequest?>, navigator: WebViewNavigator = WebViewNavigator()) {
        self._request = request
        self._viewModel = State(wrappedValue: navigator)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let webView = viewModel.webView
        webView.navigationDelegate = context.coordinator
        webView.addObserver(context.coordinator, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)

        return webView
    }

    public func updateUIView(_ uiView: WKWebView, context: Context) {
        
        context.coordinator.isUpdating = true
        
        if viewModel.canProceed(request) {
            uiView.load(request!)
        }

        context.coordinator.isUpdating = false
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            viewModel: $viewModel,
            onProgressChange: { progress in
                onProgressChange?(progress)
            }, loadingProgress: { progress, navigation in
                loadingProgress?(progress, navigation)
            }, decisionPolicy: { navigation in
                decisionPolicy?(navigation) ?? .allow
            }, onDownload: { navigation, download in
                onDownload?(navigation, download)
            }, onErrorOccurred: { navigation, error in
                onErrorOccurred?(navigation, error)
            }, allowDeprecatedTLS: { challenge in
                allowDeprecatedTLS?(challenge) ?? false
            }, didReceiveChallenge: { challenge in
                didReceiveChallenge?(challenge) ?? (URLSession.AuthChallengeDisposition.performDefaultHandling, nil)
            })
    }

    final public class Coordinator: NSObject {
        
        var isUpdating: Bool = false
        
        @Binding var viewModel: WebViewNavigator

        var onProgressChange: (CGFloat) -> Void
        var decisionPolicy: (Navigation) -> Policy
        var onDownload: (Navigation, WKDownload) -> Void
        var onErrorOccurred: (WKNavigation, Error) -> Void
        var loadingProgress: (Phase, WKNavigation) -> Void
        var allowDeprecatedTLS: (URLAuthenticationChallenge) -> Bool
        var didReceiveChallenge: (URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)

        init(
            viewModel: Binding<WebViewNavigator>,
            onProgressChange: @escaping (CGFloat) -> Void,
            loadingProgress: @escaping (Phase, WKNavigation) -> Void,
            decisionPolicy: @escaping ((Navigation) -> Policy),
            onDownload: @escaping (Navigation, WKDownload) -> Void,
            onErrorOccurred: @escaping (WKNavigation, Error) -> Void,
            allowDeprecatedTLS: @escaping (URLAuthenticationChallenge) -> Bool,
            didReceiveChallenge: @escaping (URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)
        ) {
            self._viewModel = viewModel
            self.onDownload = onDownload
            self.onProgressChange = onProgressChange
            self.decisionPolicy = decisionPolicy
            self.onErrorOccurred = onErrorOccurred
            self.loadingProgress = loadingProgress
            self.allowDeprecatedTLS = allowDeprecatedTLS
            self.didReceiveChallenge = didReceiveChallenge
        }
        
        public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
            guard !isUpdating else { return }
            switch keyPath {
            case "estimatedProgress":
                onProgressChange(CGFloat(viewModel.webView.estimatedProgress))
                
            default:
                break
            }
        }
    }
}

extension WebView.Coordinator: WKNavigationDelegate {
    private func update(_ webView: WKWebView) {
        viewModel.canGoBack = webView.canGoBack
        viewModel.canGoForward = webView.canGoForward
    }

    // MARK: - Allowing or Denying Navigation Requests
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let policy = decisionPolicy(.action(action: navigationAction))
        decisionHandler(policy.action)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let policy = decisionPolicy(.response(response: navigationResponse))
        decisionHandler(policy.response)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // TODO: Support NavigationActionPolicy with WebpagePreferences
        let policy = decisionPolicy(.action(action: navigationAction))
        decisionHandler(policy.action, preferences)
    }

    // MARK: - Tracking the Load Progress of a Request
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        update(webView)
        loadingProgress(.start, navigation)
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        loadingProgress(.redirect, navigation)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        loadingProgress(.commit, navigation)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        update(webView)
        loadingProgress(.finish, navigation)
    }

    // MARK: - Responding to Authentication Challenges
    public func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, credential) = didReceiveChallenge(challenge)
        completionHandler(disposition, credential)
    }
    public func webView(_ webView: WKWebView, authenticationChallenge challenge: URLAuthenticationChallenge, shouldAllowDeprecatedTLS decisionHandler: @escaping (Bool) -> Void) {
        let decision = allowDeprecatedTLS(challenge)
        decisionHandler(decision)
    }

    // MARK: - Responding to Navigation Errors
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        update(webView)
        onErrorOccurred(navigation, error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        update(webView)
        onErrorOccurred(navigation, error)
    }

    // MARK: - Handling Download Progress
    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        onDownload(.action(action: navigationAction), download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        onDownload(.response(response: navigationResponse), download)
    }
}

public extension WebView {
    public func decisionPolicy(_ policy: @escaping ((_ for: Navigation) -> Policy)) -> WebView {
        var webView = self
        webView.decisionPolicy = policy

        return webView
    }

    public func loadingProgress(_ loadingProgress: @escaping (Phase, WKNavigation) -> Void) -> WebView {
        var webView = self
        webView.loadingProgress = loadingProgress

        return webView
    }

    public func onDownload(_ onDownload: @escaping (Navigation, WKDownload) -> Void) -> WebView {
        var webView = self
        webView.onDownload = onDownload

        return webView
    }

    public func onErrorOccurred(_ onErrorOccurred: @escaping (WKNavigation, Error) -> Void) -> WebView {
        var webView = self
        webView.onErrorOccurred = onErrorOccurred

        return webView
    }

    public func allowDeprecatedTLS(_ challenge: @escaping (URLAuthenticationChallenge) -> Bool) -> WebView {
        var webView = self
        webView.allowDeprecatedTLS = challenge

        return webView
    }

    public func didReceiveChallenge(_ challenge: @escaping (URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)) -> WebView {
        var webView = self
        webView.didReceiveChallenge = challenge

        return webView
    }
    
    public func onProgressChange(_ perform: @escaping (CGFloat) -> Void) -> WebView {
        var webView = self
        webView.onProgressChange = perform

        return webView
    }
}

public extension WebView {
    enum Phase {
        case start
        case redirect
        case commit
        case finish
    }

    enum Navigation {
        case action(action: WKNavigationAction)
        case response(response: WKNavigationResponse)
    }

    enum Policy: Int {
        case cancel = 0
        case allow = 1
        case download = 2

        var action: WKNavigationActionPolicy {
            switch self {
            case .cancel:   return .cancel
            case .allow:    return .allow
            case .download: return .download
            }
        }

        var response: WKNavigationResponsePolicy {
            switch self {
            case .cancel:   return .cancel
            case .allow:    return .allow
            case .download: return .download
            }
        }
    }
}
