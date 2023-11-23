//
//  CookieBaker.swift
//
//
//  Created by MJ.Lee on 11/23/22.
//

import WebKit

@objcMembers
class CookieBaker: NSObject {
    // MARK: - Add Cookie

    static func addCookies(to request: URLRequest, userAgent: String? = nil) -> URLRequest {
        var request = request
        var cookiesArray: [HTTPCookie] = []
        if let url = request.url {
            if let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                cookiesArray.append(contentsOf: cookies)
            }
        } else {
            if let cookies = HTTPCookieStorage.shared.cookies {
                cookiesArray.append(contentsOf: cookies)
            }
        }
        let cookieDict = HTTPCookie.requestHeaderFields(with: cookiesArray)
        if let cookieStr = cookieDict["Cookie"] {
            request.setValue(cookieStr, forHTTPHeaderField: "Cookie")
        }

        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        
        return request
    }

    // MARK: - Set Cookie

    static func setLocalCookie(from webCookies: [HTTPCookie]) {
        for cookie in webCookies {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func setLocalCookie(with properties: [HTTPCookiePropertyKey: Any]) {
        if let cookie = HTTPCookie(properties: properties) {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    static func setLocalCookies(from navigationResponse: WKNavigationResponse, webView: WKWebView, completion: (() -> Void)?) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           let headerFields = response.allHeaderFields as? [String: String],
           let url = response.url {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)
            CookieBaker.setLocalCookie(from: cookies)
        }
        
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            CookieBaker.setLocalCookie(from: cookies)
        }
        completion?()
    }

    static func setWebCookie(from localCookie: HTTPCookie?) {
        if let cookie = localCookie {
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie, completionHandler: {})
            }
        }
    }

    static func setWebCookie(from localCookies: [HTTPCookie]?, webView: WKWebView, completion: (() -> Void)?) {
        guard let localCookies else {
            completion?()
            return
        }

        func addCookieScript() {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "EEE, d MMM yyyy HH:mm:ss zzz"
            formatter.locale = Locale(identifier: "en_US")

            localCookies.forEach { cookie in
                var cookieString = "\(cookie.name)=\(cookie.value);path=\(cookie.path);"
                cookieString += "domain=\(cookie.domain);"
                if let expireDate = cookie.expiresDate {
                    let expiresString = formatter.string(from: expireDate)
                    cookieString += "expires=\(expiresString);"
                }
                if cookie.isSecure {
                    cookieString += "Secure;"
                }
                if cookie.isHTTPOnly {
                    cookieString += "HttpOnly"
                }
                let cookieSource = "document.cookie='\(cookieString)';"
                let cookieScript = WKUserScript(source: cookieSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
                webView.configuration.userContentController.addUserScript(cookieScript)
            }
        }

        addCookieScript()
        let group = DispatchGroup()
        for cookie in localCookies {
            group.enter()
            DispatchQueue.main.async {
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    group.leave()
                }
            }
        }
        group.notify(queue: DispatchQueue.main) {
            completion?()
        }
    }

    // MARK: - Delete Cookie

    static func deleteWebCookie(cookie: HTTPCookie, webView: WKWebView? = nil, completion: (() -> Void)?) {
        DispatchQueue.main.async {
            if let w = webView {
                w.configuration.websiteDataStore.httpCookieStore.delete(cookie, completionHandler: completion)
            } else {
                WKWebsiteDataStore.default().httpCookieStore.delete(cookie, completionHandler: completion)
            }
        }
    }

    static func deleteAllWebCacheData(from webView: WKWebView? = nil, completion: @escaping (() -> Void)) {
        //        let websiteDataTypes: Set<String> = [WKWebsiteDataTypeCookies,
        //                                             WKWebsiteDataTypeDiskCache,
        //                                             WKWebsiteDataTypeOfflineWebApplicationCache,
        //                                             WKWebsiteDataTypeMemoryCache,
        //                                             WKWebsiteDataTypeLocalStorage,
        //                                             WKWebsiteDataTypeSessionStorage,
        //                                             WKWebsiteDataTypeIndexedDBDatabases,
        //                                             WKWebsiteDataTypeWebSQLDatabases]
        let websiteDataTypes: Set<String> = [WKWebsiteDataTypeCookies,
                                             WKWebsiteDataTypeDiskCache,
                                             WKWebsiteDataTypeOfflineWebApplicationCache,
                                             WKWebsiteDataTypeMemoryCache]

        let date = Date(timeIntervalSince1970: 0)
        if let w = webView {
            w.configuration.websiteDataStore.removeData(ofTypes: websiteDataTypes, modifiedSince: date, completionHandler: completion)
        } else {
            WKWebsiteDataStore.default().removeData(ofTypes: websiteDataTypes, modifiedSince: date, completionHandler: completion)
        }
    }
}
