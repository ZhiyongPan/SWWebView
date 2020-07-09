import Foundation
import JavaScriptCore
import PromiseKit

extension ServiceWorkerExecutionEnvironment {
    class PromiseWrappedCall: NSObject {
        internal let seal: Resolver<Any?>
        internal let promise: Promise<Any?>

        override init() {
            (self.promise, self.seal) = Promise<Any?>.pending()
        }

        func resolve() -> Promise<Any?> {
            return self.promise
        }

        func resolveVoid() -> Promise<Void> {
            return self.promise.done { _ in () }
        }
    }

    @objc enum EvaluateReturnType: Int {
        case void
        case object
        case promise
    }

    @objc internal class EvaluateScriptCall: NSObject {
        let script: String
        let url: URL?
        let returnType: EvaluateReturnType
        let fulfill: (Any?) -> Void
        let reject: (Error) -> Void

        init(script: String, url: URL?, passthrough: PromisePassthrough, returnType: EvaluateReturnType = .object) {
            self.script = script
            self.url = url
            self.returnType = returnType
            self.fulfill = passthrough.fulfill
            self.reject = passthrough.reject
            super.init()
        }
    }

    typealias FuncType = (JSContext) throws -> Void

    @objc internal class WithJSContextCall: PromiseWrappedCall {
        let funcToRun: FuncType
        init(_ funcToRun: @escaping FuncType) {
            self.funcToRun = funcToRun
        }
    }

    @objc internal class DispatchEventCall: PromiseWrappedCall {
        let event: Event
        init(_ event: Event) {
            self.event = event
        }
    }
}
