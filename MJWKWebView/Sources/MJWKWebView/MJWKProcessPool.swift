//
//  MJWKProcessPool.swift
//
//
//  Created by MJ.Lee on 11/23/23.
//

import WebKit

@objcMembers
public class MJWKProcessPool: WKProcessPool {
    static let pool = WKProcessPool()
}
