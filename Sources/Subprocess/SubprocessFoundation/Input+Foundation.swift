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

#if SubprocessFoundation

#if canImport(FoundationEssentials)
import FoundationEssentials
#elseif canImport(Foundation)
import Foundation
#endif

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

internal import Dispatch

/// A concrete `Input` type for subprocesses that reads input
/// from a given `Data`.
public final class DataInput: ManagedInputProtocol {
    private let data: Data
    public let pipe: Subprocess.Pipe

    public func write(into writeFileDescriptor: FileDescriptor) async throws {
        _ = try await writeFileDescriptor.write(self.data)
    }

    internal init(data: Data) {
        self.data = data
        self.pipe = Subprocess.Pipe()
    }
}

/// A concrete `Input` type for subprocesses that accepts input
/// from a specified sequence of `Data`.
public final class DataSequenceInput<
    InputSequence: Sequence & Sendable
>: ManagedInputProtocol where InputSequence.Element == Data {
    private let sequence: InputSequence
    public let pipe: Subprocess.Pipe

    public func write(into writeFileDescriptor: FileDescriptor) async throws {
        var buffer = Data()
        for chunk in self.sequence {
            buffer.append(chunk)
        }
        _ = try await writeFileDescriptor.write(buffer)
    }

    internal init(underlying: InputSequence) {
        self.sequence = underlying
        self.pipe = Subprocess.Pipe()
    }
}

/// A concrete `Input` type for subprocesses that reads input
/// from a given async sequence of `Data`.
public final class DataAsyncSequenceInput<
    InputSequence: AsyncSequence & Sendable
>: ManagedInputProtocol where InputSequence.Element == Data {
    private let sequence: InputSequence
    public let pipe: Subprocess.Pipe

    private func writeChunk(_ chunk: Data, into writeFileDescriptor: FileDescriptor) async throws {
        _ = try await writeFileDescriptor.write(chunk)
    }

    public func write(into writeFileDescriptor: FileDescriptor) async throws {
        for try await chunk in self.sequence {
            try await self.writeChunk(chunk, into: writeFileDescriptor)
        }
    }

    internal init(underlying: InputSequence) {
        self.sequence = underlying
        self.pipe = Subprocess.Pipe()
    }
}

extension InputProtocol {
    /// Create a Subprocess input from a `Data`
    public static func data(_ data: Data) -> Self where Self == DataInput {
        return DataInput(data: data)
    }

    /// Create a Subprocess input from a `Sequence` of `Data`.
    public static func sequence<InputSequence: Sequence & Sendable>(
        _ sequence: InputSequence
    ) -> Self where Self == DataSequenceInput<InputSequence> {
        return .init(underlying: sequence)
    }

    /// Create a Subprocess input from a `AsyncSequence` of `Data`.
    public static func sequence<InputSequence: AsyncSequence & Sendable>(
        _ asyncSequence: InputSequence
    ) -> Self where Self == DataAsyncSequenceInput<InputSequence> {
        return .init(underlying: asyncSequence)
    }
}

extension StandardInputWriter {
    /// Write a `Data` to the standard input of the subprocess.
    /// - Parameter data: The sequence of bytes to write.
    /// - Returns number of bytes written.
    public func write(
        _ data: Data
    ) async throws -> Int {
        guard let fd: FileDescriptor = try self.input.writeFileDescriptor() else {
            fatalError("Attempting to write to a file descriptor that's already closed")
        }
        return try await fd.write(data)
    }

    /// Write a AsyncSequence of Data to the standard input of the subprocess.
    /// - Parameter sequence: The sequence of bytes to write.
    /// - Returns number of bytes written.
    public func write<AsyncSendableSequence: AsyncSequence & Sendable>(
        _ asyncSequence: AsyncSendableSequence
    ) async throws -> Int where AsyncSendableSequence.Element == Data {
        var buffer = Data()
        for try await data in asyncSequence {
            buffer.append(data)
        }
        return try await self.write(buffer)
    }
}

extension FileDescriptor {
#if os(Windows)
    internal func write(
        _ data: Data
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            // TODO: Figure out a better way to asynchornously write
            DispatchQueue.global(qos: .userInitiated).async {
                data.withUnsafeBytes {
                    self.write($0) { writtenLength, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: writtenLength)
                        }
                    }
                }
            }
        }
    }
#else
    internal func write(
        _ data: Data
    ) async throws -> Int {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
            let dispatchData = data.withUnsafeBytes {
                return DispatchData(bytesNoCopy: $0, deallocator: .custom(nil, { /* noop */ }))
            }
            self.write(dispatchData) { writtenLength, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: writtenLength)
                }
            }
        }
    }
#endif
}

#endif // SubprocessFoundation
