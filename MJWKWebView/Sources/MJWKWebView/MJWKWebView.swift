//
//  MJWKWebView.swift
//
//
//  Created by MJ.Lee on 11/23/22.
//

import WebKit

@objcMembers
public class MJWKWebView: WKWebView {
    // MARK: - Properties

    public weak var wkNavigationDelegate: WKNavigationDelegate?
    public weak var wkUIDelegate: WKUIDelegate?
    public var session: URLSession? {
        willSet {
            if newValue != nil, self.session != nil {
                self.releaseSession()
                debugPrint("mj.lee - session will be nil")
            }
        }
    }

    public var decidePolicyForNavigationHandler: ((WKWebView,
                                            WKNavigationAction,
                                            @escaping (WKNavigationActionPolicy) -> Void) -> Void)?
    public var didStartProvisionalNavigationHandler: ((WKWebView, WKNavigation?) -> Void)?
    public var didFinishNavigationHandler: ((WKWebView, WKNavigation?) -> Void)?
    public var didCommitNavigationHandler: ((WKWebView, WKNavigation?) -> Void)?
    public var decidePolicyForResponseNavigationHandler: ((WKWebView, WKNavigationResponse, @escaping (WKNavigationResponsePolicy) -> Void) -> Void)?
    public var didReceiveServerRedirectHandler: ((WKWebView, WKNavigation?) -> Void)?
    public var didFailProvisionalNavigationHandler: ((WKWebView, WKNavigation?, Error) -> Void)?
    public var runJavaScriptConfirmPanelHandler: ((WKWebView, String, WKFrameInfo, @escaping (Bool) -> Void) -> Void)?
    public var runJavaScriptAlertPanelHandler: ((WKWebView, String, WKFrameInfo, @escaping () -> Void) -> Void)?
    public var createWebViewHandler: ((WKWebView, WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?)? = { webView, _, navigationAction, _ in
        guard let targetFrame = navigationAction.targetFrame else {
            webView.load(navigationAction.request)
            return nil
        }
        guard targetFrame.isMainFrame else {
            webView.load(navigationAction.request)
            return nil
        }
        return nil
    }

    // MARK: - Init

    public init(frame: CGRect) {
        let config = WKWebViewConfiguration()
        config.processPool = MJWKProcessPool.pool
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        if #available(iOS 13.0, *) {
            config.defaultWebpagePreferences.preferredContentMode = .mobile
        }

        super.init(frame: frame, configuration: config)

        navigationDelegate = self
        uiDelegate = self
        allowsBackForwardNavigationGestures = true
        CookieBaker.setWebCookie(from: HTTPCookieStorage.shared.cookies, webView: self, completion: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        releaseSession()
        CookieBaker.deleteAllWebCacheData(from: self, completion: {})
        debugPrint("mj.lee - MJWKWebView deinit")
    }

    func releaseSession() {
        self.session?.invalidateAndCancel()
        self.session = nil
    }

    // MARK: - Load Request

    public override func load(_ request: URLRequest) -> WKNavigation? {
        let cookieReq = CookieBaker.addCookies(to: request)
        requestURLSession(cookieReq, success: { [weak self] newReq, _, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                CookieBaker.setWebCookie(from: HTTPCookieStorage.shared.cookies, webView: self, completion: {
                    let req = CookieBaker.addCookies(to: newReq)
                    _ = self.superLoad(req)
                })
            }
        }, failure: { [weak self] _ in
            DispatchQueue.main.async {
                _ = self?.superLoad(cookieReq)
            }
        })
        return nil
    }

    private func superLoad(_ request: URLRequest) -> WKNavigation? {
        return super.load(request)
    }
}

// MARK: - WKNavigationDelegate

extension MJWKWebView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let handler = self.decidePolicyForNavigationHandler {
            handler(webView, navigationAction, decisionHandler)
        } else {
            decisionHandler(.allow)
        }
    }

    public func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let handler = decidePolicyForResponseNavigationHandler {
            handler(webView, navigationResponse, decisionHandler)
        } else {
            decisionHandler(.allow)
        }

        guard
            let response = navigationResponse.response as? HTTPURLResponse,
            let _ = response.allHeaderFields as? [String: String],
            let _ = response.url
        else { return }

        CookieBaker.setLocalCookies(from: navigationResponse, webView: webView, completion: nil)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        CookieBaker.setWebCookie(from: HTTPCookieStorage.shared.cookies, webView: webView) { [weak self] in
            if let handler = self?.didStartProvisionalNavigationHandler {
                handler(webView, navigation)
            }
        }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        CookieBaker.setWebCookie(from: HTTPCookieStorage.shared.cookies, webView: webView) { [weak self] in
            if let handler = self?.didCommitNavigationHandler {
                handler(webView, navigation)
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        CookieBaker.setWebCookie(from: HTTPCookieStorage.shared.cookies, webView: webView) { [weak self] in
            if let handler = self?.didFinishNavigationHandler {
                handler(webView, navigation)
            }
        }
    }

    public func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        if let handler = didFailProvisionalNavigationHandler {
            handler(webView, navigation, error)
        }
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let handler = didReceiveServerRedirectHandler {
            handler(webView, navigation)
        }
    }
}

// MARK: - WKUIDelegate

extension MJWKWebView: WKUIDelegate {
    public func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        if let handler = runJavaScriptConfirmPanelHandler {
            handler(webView, message, frame, completionHandler)
        } else {
            completionHandler(true)
        }
    }

    public func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        if let handler = runJavaScriptAlertPanelHandler {
            handler(webView, message, frame, completionHandler)
        } else {
            completionHandler()
        }
    }

    public func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let handler = createWebViewHandler {
            return handler(webView, configuration, navigationAction, windowFeatures)
        }
        return nil
    }
}

extension MJWKWebView {
    private func requestURLSession(_ request: URLRequest,
                                   success: @escaping (URLRequest, HTTPURLResponse?, Data?) -> Void,
                                   failure: @escaping (Error?) -> Void) {
        let sessionConfig = URLSessionConfiguration.default
        self.session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        let task = self.session?.dataTask(with: request) { data, response, error in
            if let error {
                failure(error)
            } else {
                if let response = response as? HTTPURLResponse {
                    if let responseHeaderFields = response.allHeaderFields as? [String: String], let url = response.url {
                        let responseCookies = HTTPCookie.cookies(withResponseHeaderFields: responseHeaderFields, for: url)
                        CookieBaker.setLocalCookie(from: responseCookies)
                    }
                    let code = response.statusCode
                    if code >= 300, code < 400 {
                        guard
                            let location = response.allHeaderFields["Location"] as? String,
                            let redirectURL = URL(string: location)
                        else {
                            failure(nil)
                            return
                        }
                        let request = URLRequest(url: redirectURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 5)
                        success(request, nil, nil)
                    } else {
                        success(request, response, data)
                    }
                } else {
                    failure(nil)
                }
            }
        }
        task?.resume()
    }
}

extension MJWKWebView: URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let newReq = CookieBaker.addCookies(to: request)
        completionHandler(newReq)
    }
}
