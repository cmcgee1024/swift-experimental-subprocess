//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif

import Subprocess

/// A concrete `Output` type for subprocesses that collects output
/// from the subprocess as `Data`. This option must be used with
/// the `run()` method that returns a `CollectedResult`
@available(macOS 9999, *)
public final class DataOutput: ManagedOutputProtocol {
    public typealias OutputType = Data
    public let maxSize: Int
    public let pipe: Subprocess.Pipe

    public func output(from span: RawSpan) throws -> Data {
        return Data(span)
    }

    internal init(limit: Int) {
        self.maxSize = limit
        self.pipe = Subprocess.Pipe()
    }
}

@available(macOS 9999, *)
extension OutputProtocol where Self == DataOutput {
    /// Create a `Subprocess` output that collects output as `Data`
    /// up to 128kb.
    public static var data: Self {
        return .data(limit: 128 * 1024)
    }

    /// Create a `Subprocess` output that collects output as `Data`
    /// with given max number of bytes to collect.
    public static func data(limit: Int) -> Self  {
        return .init(limit: limit)
    }
}

// MARK: - Workarounds
@available(macOS 9999, *)
extension ManagedOutputProtocol {
    @_disfavoredOverload
    public func output(from data: some DataProtocol) throws -> OutputType {
        //FIXME: remove workaround for rdar://143992296
        return try self.output(from: data.bytes)
    }
}
