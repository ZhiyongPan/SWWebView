import Foundation
import ServiceWorker
import ServiceWorkerContainer

@objc public protocol SWWebViewContainerDelegate {
    @objc func container(_: SWWebView, getContainerFor: URL) -> ServiceWorkerContainer?
    @objc func container(_: SWWebView, createContainerFor: URL) throws -> ServiceWorkerContainer
    @objc func container(_: SWWebView, freeContainer: ServiceWorkerContainer)
}
