import Foundation
import JavaScriptCore
import PromiseKit

@objc protocol WebSQLDatabaseExports: JSExport {
    func transaction(_: JSValue, _: JSValue, _: JSValue)
    func readTransaction(_: JSValue, _: JSValue, _: JSValue)
}

/// This is a partial-ish implementation of the WebSQL API. The only reason it exists is to be used
/// by the IndexedDB shim, that's been my measure of success - if the shim works, we're done. So
/// I have no idea what's missing here, really.
@objc class WebSQLDatabase: NSObject, WebSQLDatabaseExports {
    let connection: SQLiteConnection
    weak var environment: ServiceWorkerExecutionEnvironment?
    var transactionQueue: [WebSQLTransaction] = []

    init(at path: URL, in environment: ServiceWorkerExecutionEnvironment) throws {
        self.connection = try SQLiteConnection(path)
        self.environment = environment
    }

    func transaction(_ withCallback: JSValue, _ errorCallback: JSValue, _ completeCallback: JSValue) {
        let trans = WebSQLTransaction(in: self, isReadOnly: false, withCallback: withCallback, errorCallback: errorCallback, completeCallback: completeCallback)
        self.transactionQueue.append(trans)
        self.runTransactionQueue()
    }

    func readTransaction(_ withCallback: JSValue, _ errorCallback: JSValue, _ completeCallback: JSValue) {
        let trans = WebSQLTransaction(in: self, isReadOnly: true, withCallback: withCallback, errorCallback: errorCallback, completeCallback: completeCallback)
        self.transactionQueue.append(trans)
        self.runTransactionQueue()
    }

    var transactionQueueIsRunning = false

    var onTransactionsDrained: (() -> Void)?

    func runTransactionQueue() {
        if self.transactionQueueIsRunning == true {
            return
        }

        guard let nextTransaction = self.transactionQueue.first else {
            if let drained = self.onTransactionsDrained {
                drained()
            }
            return
        }

        self.transactionQueueIsRunning = true

        nextTransaction.run {
            self.transactionQueue.removeFirst()
            self.transactionQueueIsRunning = false
            self.runTransactionQueue()
        }
    }

    deinit {
        self.forceClose()
    }

    func forceClose() {
        do {
            if self.connection.open == true {
                try self.connection.close()
            }
        } catch {
            Log.error?("Could not close WebSQL connection")
        }
    }

    func close() -> Promise<Void> {
        // If we still have transactions pending we want them to execute before
        // we close up connections.

        if self.transactionQueue.count > 0 {
            Log.info?("\(self.transactionQueue.count) transactions pending on close...")
            return Promise { seal in
                self.onTransactionsDrained = {
                    Log.info?("Transactions complete, closing...")
                    self.forceClose()
                    seal.fulfill(())
                }
            }
        } else {
            Log.info?("No pending transactions, closing immediately")
            self.forceClose()
            return Promise.value(())
        }
    }

    static func openDatabase(for worker: ServiceWorker, in environment: ServiceWorkerExecutionEnvironment, name: String) throws -> WebSQLDatabase {
        // We defer to the delegate to get the path where we should be storing our WebSQL data files.

        guard let storagePath = try worker.delegate?.serviceWorkerGetDomainStoragePath(worker) else {
            throw ErrorMessage("ServiceWorker has no delegate")
        }

        guard let escapedName = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else {
            throw ErrorMessage("Could not escape SQLite database filename")
        }

        let dbDirectory = storagePath
            .appendingPathComponent("websql", isDirectory: true)

        let dbURL = dbDirectory
            .appendingPathComponent(escapedName)
            .appendingPathExtension("sqlite")

        // If the domain-specific directory hasn't been created yet, make it

        if FileManager.default.fileExists(atPath: dbDirectory.path) == false {
            try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true, attributes: nil)
        }

        let db = try WebSQLDatabase(at: dbURL, in: environment)
        return db
    }
}
