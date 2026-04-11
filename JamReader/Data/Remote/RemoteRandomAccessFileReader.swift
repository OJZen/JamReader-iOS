import Foundation

protocol RemoteRandomAccessFileReader: AnyObject {
    var fileSize: UInt64 { get async throws }
    func read(offset: UInt64, length: UInt32) async throws -> Data
    func close() async throws
}

extension FileReader: RemoteRandomAccessFileReader {}
