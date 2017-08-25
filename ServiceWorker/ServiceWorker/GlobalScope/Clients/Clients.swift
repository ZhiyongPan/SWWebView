//
//  Clients.swift
//  ServiceWorker
//
//  Created by alastair.coote on 24/08/2017.
//  Copyright © 2017 Guardian Mobile Innovation Lab. All rights reserved.
//

import Foundation
import JavaScriptCore

@objc protocol ClientsExports: JSExport {
    func get(_: String) -> JSValue
    func matchAll(_: [String: Any]?) -> JSValue
    func openWindow(_: String) -> JSValue
    func claim() -> JSValue
}

@objc class Clients: NSObject, ClientsExports {

    unowned let worker: ServiceWorker

    init(for worker: ServiceWorker) {
        self.worker = worker
    }

    func get(_ id: String) -> JSValue {

        let jsp = JSPromise(context: JSContext.current())
        self.worker.implementations.clients.get(id: id, worker: self.worker) { err, clientProtocol in
            if let error = err {
                jsp.reject(error)
            } else if let clientExists = clientProtocol {
                jsp.fulfill(Client.getOrCreate(from: clientExists, in: JSContext.current()))
            } else {
                jsp.fulfill(nil)
            }
        }
        return jsp.jsValue
    }

    func matchAll(_ options: [String: Any]?) -> JSValue {

        let jsp = JSPromise(context: JSContext.current())

        let type = options?["type"] as? String ?? "all"
        let includeUncontrolled = options?["includeUncontrolled"] as? Bool ?? false

        let options = ClientMatchAllOptions(includeUncontrolled: includeUncontrolled, type: type)

        self.worker.implementations.clients.matchAll(options: options) { err, clientProtocols in
            if let error = err {
                jsp.reject(error)
            } else {
                let mapped = clientProtocols!.map({ Client.getOrCreate(from: $0, in: JSContext.current()) })
                jsp.fulfill(mapped)
            }
        }

        return jsp.jsValue
    }

    func openWindow(_ url: String) -> JSValue {

        let jsp = JSPromise(context: JSContext.current())

        guard let parsedURL = URL(string: url, relativeTo: self.worker.url) else {
            jsp.reject(ErrorMessage("Could not parse URL given"))
            return jsp.jsValue
        }

        self.worker.implementations.clients.openWindow(parsedURL, jsp.processCallback)

        return jsp.jsValue
    }

    func claim() -> JSValue {

        let jsp = JSPromise(context: JSContext.current())

        self.worker.implementations.clients.claim(jsp.processCallback)

        return jsp.jsValue
    }
}
