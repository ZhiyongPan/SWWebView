import Foundation
import SQLite3

/// A bridge between the a Foundation InputStream and the SQLite C API's blob functions.
public class SQLiteBlobReadStream: InputStreamImplementation {
    let dbPointer: SQLiteBlobStreamPointer

    init(_ db: SQLiteConnection, table: String, column: String, row: Int64) {
        self.dbPointer = SQLiteBlobStreamPointer(db, table: table, column: column, row: row, isWrite: true)

        // Don't understand why, but it forces us to call a specified initializer. So we'll do it with empty data.
        let dummyData = Data(count: 0)
        super.init(data: dummyData)
        self.streamStatus = .notOpen
    }

    override public func open() {
        do {
            self.streamStatus = Stream.Status.opening
            try self.dbPointer.open()
            self.streamStatus = Stream.Status.open
            self.emitEvent(event: .openCompleted)
            self.emitEvent(event: .hasBytesAvailable)
        } catch {
            self.throwError(error)
        }
    }

    override public var hasBytesAvailable: Bool {
        guard let state = self.dbPointer.openState else {
            // As specified in docs: https://developer.apple.com/documentation/foundation/inputstream/1409410-hasbytesavailable
            // both hasSpaceAvailable and hasBytesAvailable should return true when the actual state is unknown.
            return true
        }
        return state.currentPosition < state.blobLength
    }

    override public func close() {
        self.dbPointer.close()
        self.streamStatus = .closed
    }

    override public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        do {
            self.streamStatus = .reading
            guard let state = self.dbPointer.openState else {
                throw ErrorMessage("Trying to read a closed stream")
            }

            let bytesLeft = state.blobLength - state.currentPosition

            // We can't read more data than exists in the blob, so we make sure we're
            // not going to go over:

            let lengthToRead = min(Int32(len), bytesLeft)

            if sqlite3_blob_read(state.pointer, buffer, lengthToRead, state.currentPosition) != SQLITE_OK {
                guard let errMsg = sqlite3_errmsg(self.dbPointer.db.db) else {
                    throw ErrorMessage("SQLite failed, but can't get error")
                }
                let str = String(cString: errMsg)
                throw ErrorMessage(str)
            }

            // Now that we've read X bytes, ensure our pointer is updated to the next place we want
            // to read from.

            state.currentPosition += lengthToRead

            if state.currentPosition == state.blobLength {
                self.streamStatus = .atEnd
                self.emitEvent(event: .endEncountered)
            } else {
                self.streamStatus = .open
                self.emitEvent(event: .hasBytesAvailable)
            }

            return Int(lengthToRead)
        } catch {
            self.throwError(error)
            return -1
        }
    }
}
