//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===---------------------------------------------------------------------s-===//

#if canImport(WinSDK)

import WinSDK
import Foundation
import Testing

#if canImport(System)
import System
#else
@preconcurrency import SystemPackage
#endif

import TestResources
@testable import Subprocess

@Suite(.serialized)
struct SubprocessWindowsTests {
    private let cmdExe: Subprocess.Executable = .path("C:\\Windows\\System32\\cmd.exe")
}

// MARK: - Executable Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testExecutableNamed() async throws {
        // Simple test to make sure we can run a common utility
        let message = "Hello, world from Swift!"

        let result = try await Subprocess.run(
            .name("cmd.exe"),
            arguments: ["/c", "echo", message],
            output: .string,
            error: .discarded
        )

        #expect(result.terminationStatus.isSuccess)
        #expect(
            result.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines) ==
            "\"\(message)\""
        )
    }

    @available(macOS 9999, *)
    @Test func testExecutableNamedCannotResolve() async throws {
        do {
            _ = try await Subprocess.run(.name("do-not-exist"))
            Issue.record("Expected to throw")
        } catch {
            guard let subprocessError = error as? SubprocessError else {
                Issue.record("Expected CocoaError, got \(error)")
                return
            }
            // executable not found
            #expect(subprocessError.code.value == 1)
        }
    }

    @available(macOS 9999, *)
    @Test func testExecutableAtPath() async throws {
        let expected = FileManager.default.currentDirectoryPath
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "cd"],
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        #expect(
            result.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines) ==
            expected
        )
    }

    @available(macOS 9999, *)
    @Test func testExecutableAtPathCannotResolve() async {
        do {
            // Since we are using the path directly,
            // we expect the error to be thrown by the underlying
            // CreateProcssW
            _ = try await Subprocess.run(.path("X:\\do-not-exist"))
            Issue.record("Expected to throw POSIXError")
        } catch {
            guard let subprocessError = error as? SubprocessError,
                  let underlying = subprocessError.underlyingError else {
                Issue.record("Expected CocoaError, got \(error)")
                return
            }
            #expect(underlying.rawValue == DWORD(ERROR_FILE_NOT_FOUND))
        }
    }
}

// MARK: - Argument Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testArgumentsFromArray() async throws {
        let message = "Hello, World!"
        let args: [String] = [
            "/c",
            "echo",
            message
        ]
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: .init(args),
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        #expect(
            result.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines) ==
            "\"\(message)\""
        )
    }
}

// MARK: - Environment Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testEnvironmentInherit() async throws {
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "echo %Path%"],
            environment: .inherit,
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        // As a sanity check, make sure there's
        // `C:\Windows\system32` in PATH
        // since we inherited the environment variables
        let pathValue = try #require(result.standardOutput)
        #expect(pathValue.contains("C:\\Windows\\system32"))
    }

    @available(macOS 9999, *)
    @Test func testEnvironmentInheritOverride() async throws {
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "echo %HOMEPATH%"],
            environment: .inherit.updating([
                "HOMEPATH": "/my/new/home",
            ]),
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        #expect(
            result.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines) ==
            "/my/new/home"
        )
    }

    @available(macOS 9999, *)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SystemRoot"] != nil))
    func testEnvironmentCustom() async throws {
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: [
                "/c", "set"
            ],
            environment: .custom([
                "Path": "C:\\Windows\\system32;C:\\Windows",
                "ComSpec": "C:\\Windows\\System32\\cmd.exe"
            ]),
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        // Make sure the newly launched process does
        // NOT have `SystemRoot` in environment
        let output = result.standardOutput!
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!output.contains("SystemRoot"))
    }
}

// MARK: - Working Directory Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testWorkingDirectoryDefaultValue() async throws {
        // By default we should use the working directory of the parent process
        let workingDirectory = FileManager.default.currentDirectoryPath
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "cd"],
            workingDirectory: nil,
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        // There shouldn't be any other environment variables besides
        // `PATH` that we set
        #expect(
            result.standardOutput?
                .trimmingCharacters(in: .whitespacesAndNewlines) ==
            workingDirectory
        )
    }

    @available(macOS 9999, *)
    @Test func testWorkingDirectoryCustomValue() async throws {
        let workingDirectory = FilePath(
            FileManager.default.temporaryDirectory._fileSystemPath
        )
        let result = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "cd"],
            workingDirectory: workingDirectory,
            output: .string
        )
        #expect(result.terminationStatus.isSuccess)
        // There shouldn't be any other environment variables besides
        // `PATH` that we set
        let resultPath = result.standardOutput!
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(
            FilePath(resultPath) ==
            workingDirectory
        )
    }
}


// MARK: - Output Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testCollectedOutput() async throws {
        let expected = randomString(length: 32)
        let echoResult = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "echo \(expected)"],
            output: .string
        )
        #expect(echoResult.terminationStatus.isSuccess)
        let output = try #require(
            echoResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(output == expected)
    }

    @available(macOS 9999, *)
    @Test func testCollectedOutputWithLimit() async throws {
        let limit = 2
        let expected = randomString(length: 32)
        let echoResult = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "echo \(expected)"],
            output: .string(limit: limit, encoding: UTF8.self)
        )
        #expect(echoResult.terminationStatus.isSuccess)
        let output = try #require(
            echoResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let targetRange = expected.startIndex ..< expected.index(expected.startIndex, offsetBy: limit)
        #expect(String(expected[targetRange]) == output)
    }

    @available(macOS 9999, *)
    @Test func testCollectedOutputFileDesriptor() async throws {
        let outputFilePath = FilePath(
            FileManager.default.temporaryDirectory._fileSystemPath
        ).appending("Test.out")
        let outputFile: FileDescriptor = try .open(
            outputFilePath,
            .readWrite,
            options: .create,
            permissions: [.ownerReadWrite, .groupReadWrite]
        )
        let expected = randomString(length: 32)
        let echoResult = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "echo \(expected)"],
            output: .fileDescriptor(
                outputFile,
                closeAfterSpawningProcess: false
            )
        )
        #expect(echoResult.terminationStatus.isSuccess)
        try outputFile.close()
        let outputData: Data = try Data(
            contentsOf: URL(filePath: outputFilePath.string)
        )
        let output = try #require(
            String(data: outputData, encoding: .utf8)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(echoResult.terminationStatus.isSuccess)
        #expect(output == expected)
    }

    @available(macOS 9999, *)
    @Test func testRedirectedOutputRedirectToSequence() async throws {
        // Maeks ure we can read long text redirected to AsyncSequence
        let expected: Data = try Data(
            contentsOf: URL(filePath: theMysteriousIsland.string)
        )
        let catResult = try await Subprocess.run(
            self.cmdExe,
            arguments: ["/c", "type \(theMysteriousIsland.string)"],
            output: .sequence,
            error: .discarded
        ) { subprocess in
            var buffer = Data()
            for try await chunk in subprocess.standardOutput {
                buffer += chunk
            }
            return buffer
        }
        #expect(catResult.terminationStatus.isSuccess)
        #expect(catResult.value == expected)
    }
}

// MARK: - PlatformOption Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test(.enabled(if: SubprocessWindowsTests.hasAdminPrivileges()))
    func testPlatformOptionsRunAsUser() async throws {
        try await self.withTemporaryUser { username, password in
            // Use public directory as working directory so the newly created user
            // has access to it
            let workingDirectory = FilePath("C:\\Users\\Public")

            var platformOptions: Subprocess.PlatformOptions = .init()
            platformOptions.userCredentials = .init(
                username: username,
                password: password,
                domain: nil
            )

            let whoamiResult = try await Subprocess.run(
                .path("C:\\Windows\\System32\\whoami.exe"),
                workingDirectory: workingDirectory,
                platformOptions: platformOptions,
                output: .string
            )
            #expect(whoamiResult.terminationStatus.isSuccess)
            let result = try #require(
                whoamiResult.standardOutput
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            // whoami returns `computerName\userName`.
            let userInfo = result.split(separator: "\\")
            guard userInfo.count == 2 else {
                Issue.record("Fail to parse the restult for whoami: \(result)")
                return
            }
            #expect(
                userInfo[1].lowercased() ==
                username.lowercased()
            )
        }
    }

    @available(macOS 9999, *)
    @Test func testPlatformOptionsCreateNewConsole() async throws {
        let parentConsole = GetConsoleWindow()
        let sameConsoleResult = try await Subprocess.run(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-File", windowsTester.string,
                "-mode", "get-console-window"
            ],
            output: .string
        )
        #expect(sameConsoleResult.terminationStatus.isSuccess)
        let sameConsoleValue = try #require(
            sameConsoleResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Make sure the child console is same as parent
        #expect(
            "\(intptr_t(bitPattern: parentConsole))" ==
            sameConsoleValue
        )
        // Now launch a procss with new console
        var platformOptions: Subprocess.PlatformOptions = .init()
        platformOptions.consoleBehavior = .createNew
        let differentConsoleResult = try await Subprocess.run(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-File", windowsTester.string,
                "-mode", "get-console-window"
            ],
            platformOptions: platformOptions,
            output: .string
        )
        #expect(differentConsoleResult.terminationStatus.isSuccess)
        let differentConsoleValue = try #require(
            differentConsoleResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Make sure the child console is different from parent
        #expect(
            "\(intptr_t(bitPattern: parentConsole))" ==
            differentConsoleValue
        )
    }

    @available(macOS 9999, *)
    @Test func testPlatformOptionsDetachedProcess() async throws {
        var platformOptions: Subprocess.PlatformOptions = .init()
        platformOptions.consoleBehavior = .detatch
        let detachConsoleResult = try await Subprocess.run(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-File", windowsTester.string,
                "-mode", "get-console-window"
            ],
            platformOptions: platformOptions,
            output: .string
        )
        #expect(detachConsoleResult.terminationStatus.isSuccess)
        let detachConsoleValue = try #require(
            detachConsoleResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Detached process shoud NOT have a console
        #expect(detachConsoleValue.isEmpty)
    }

    @available(macOS 9999, *)
    @Test func testPlatformOptionsPreSpawnConfigurator() async throws {
        // Manually set the create new console flag
        var platformOptions: Subprocess.PlatformOptions = .init()
        platformOptions.preSpawnProcessConfigurator = { creationFlags, _ in
            creationFlags |= DWORD(CREATE_NEW_CONSOLE)
        }
        let parentConsole = GetConsoleWindow()
        let newConsoleResult = try await Subprocess.run(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-File", windowsTester.string,
                "-mode", "get-console-window"
            ],
            platformOptions: platformOptions,
            output: .string
        )
        #expect(newConsoleResult.terminationStatus.isSuccess)
        let newConsoleValue = try #require(
            newConsoleResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Make sure the child console is different from parent
        #expect(
            "\(intptr_t(bitPattern: parentConsole))" !=
            newConsoleValue
        )

        guard !Self.hasAdminPrivileges() else {
            return
        }
        // Change the console title
        let title = "My Awesome Process"
        platformOptions.preSpawnProcessConfigurator = { creationFlags, startupInfo in
            creationFlags |= DWORD(CREATE_NEW_CONSOLE)
            title.withCString(
                encodedAs: UTF16.self
            ) { titleW in
                startupInfo.lpTitle = UnsafeMutablePointer(mutating: titleW)
            }
        }
        let changeTitleResult = try await Subprocess.run(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-Command", "$consoleTitle = [console]::Title; Write-Host $consoleTitle",
            ],
            platformOptions: platformOptions,
            output: .string
        )
        #expect(changeTitleResult.terminationStatus.isSuccess)
        let newTitle = try #require(
            changeTitleResult.standardOutput
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        // Make sure the child console is different from parent\
        #expect(newTitle == title)
    }
}

// MARK: - Subprocess Controlling Tests
extension SubprocessWindowsTests {
    @available(macOS 9999, *)
    @Test func testTerminateProcess() async throws {
        let stuckProcess = try await Subprocess.run(
            self.cmdExe,
            // This command will intentionally hang
            arguments: ["/c", "type con"],
            output: .discarded,
            error: .discarded
        ) { subprocess in
            // Make sure we can kill the hung process
            try subprocess.terminate(withExitCode: 42)
        }
        // If we got here, the process was terminated
        guard case .exited(let exitCode) = stuckProcess.terminationStatus else {
            Issue.record("Process should have exited")
            return
        }
        #expect(exitCode == 42)
    }

    @available(macOS 9999, *)
    @Test func testSuspendResumeProcess() async throws {
        let stuckProcess = try await Subprocess.run(
            self.cmdExe,
            // This command will intentionally hang
            arguments: ["/c", "type con"],
            output: .discarded,
            error: .discarded
        ) { subprocess in
            try subprocess.suspend()
            // Now check the to make sure the procss is actually suspended
            // Why not spawn a nother process to do that?
            var checkResult = try await Subprocess.run(
                .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
                arguments: [
                    "-File", windowsTester.string,
                    "-mode", "is-process-suspended",
                    "-processID", "\(subprocess.processIdentifier.value)"
                ],
                output: .string
            )
            #expect(checkResult.terminationStatus.isSuccess)
            var isSuspended = try #require(
                checkResult.standardOutput
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(isSuspended == "true")

            // Now resume the process
            try subprocess.resume()
            checkResult = try await Subprocess.run(
                .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
                arguments: [
                    "-File", windowsTester.string,
                    "-mode", "is-process-suspended",
                    "-processID", "\(subprocess.processIdentifier.value)"
                ],
                output: .string
            )
            #expect(checkResult.terminationStatus.isSuccess)
            isSuspended = try #require(
                checkResult.standardOutput
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(isSuspended == "false")

            // Now finally kill the process since it's intentionally hung
            try subprocess.terminate(withExitCode: 0)
        }
        #expect(stuckProcess.terminationStatus.isSuccess)
    }

    @available(macOS 9999, *)
    @Test func testRunDetached() async throws {
        let (readFd, writeFd) = try FileDescriptor.pipe()
        SetHandleInformation(
            readFd.platformDescriptor,
            DWORD(HANDLE_FLAG_INHERIT),
            0
        )
        let pid = try Subprocess.runDetached(
            .path("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            arguments: [
                "-Command", "Write-Host $PID"
            ],
            output: writeFd
        )
        // Wait for procss to finish
        guard let processHandle = OpenProcess(
            DWORD(PROCESS_QUERY_INFORMATION | SYNCHRONIZE),
            false,
            pid.value
        ) else {
            Issue.record("Failed to get process handle")
            return
        }

        // Wait for the process to finish
        WaitForSingleObject(processHandle, INFINITE);

        let data = try await readFd.readUntilEOF(upToLength: 5)
        let resultPID = try #require(
            String(data: data, encoding: .utf8)
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect("\(pid.value)" == resultPID)
        try readFd.close()
        try writeFd.close()
    }
}

// MARK: - User Utils
extension SubprocessWindowsTests {
    private func withTemporaryUser(
        _ work: (String, String) async throws -> Void
    ) async throws {
        let username: String = "TestUser\(randomString(length: 5, lettersOnly: true))"
        let password: String = "Password\(randomString(length: 10))"

        func createUser(withUsername username: String, password: String) {
            username.withCString(
                encodedAs: UTF16.self
            ) { usernameW in
                password.withCString(
                    encodedAs: UTF16.self
                ) { passwordW in
                    var userInfo: USER_INFO_1 = USER_INFO_1()
                    userInfo.usri1_name = UnsafeMutablePointer<WCHAR>(mutating: usernameW)
                    userInfo.usri1_password = UnsafeMutablePointer<WCHAR>(mutating: passwordW)
                    userInfo.usri1_priv = DWORD(USER_PRIV_USER)
                    userInfo.usri1_home_dir = nil
                    userInfo.usri1_comment = nil
                    userInfo.usri1_flags = DWORD(UF_SCRIPT | UF_DONT_EXPIRE_PASSWD)
                    userInfo.usri1_script_path = nil

                    var error: DWORD = 0

                    var status = NetUserAdd(
                        nil,
                        1,
                        &userInfo,
                        &error
                    )
                    guard status == NERR_Success else {
                        Issue.record("Failed to create user with error: \(error)")
                        return
                    }
                }
            }
        }

        createUser(withUsername: username, password: password)
        defer {
            // Now delete the user
            let status = username.withCString(
                encodedAs: UTF16.self
            ) { usernameW in
                return NetUserDel(nil, usernameW)
            }
            if status != NERR_Success {
                Issue.record("Failed to delete user with error: \(status)")
            }
        }
        // Run work
        try await work(username, password)
    }

    private static func hasAdminPrivileges() -> Bool {
        var isAdmin: WindowsBool = false
        var adminGroup: PSID? = nil
        // SECURITY_NT_AUTHORITY
        var netAuthority = SID_IDENTIFIER_AUTHORITY(Value: (0, 0, 0, 0, 0, 5))
        guard AllocateAndInitializeSid(
            &netAuthority,
            2,  // nSubAuthorityCount
            DWORD(SECURITY_BUILTIN_DOMAIN_RID),
            DWORD(DOMAIN_ALIAS_RID_ADMINS),
            0, 0, 0, 0, 0, 0,
            &adminGroup
        ) else {
            return false
        }
        defer {
            FreeSid(adminGroup)
        }
        // Check if the current process's token is part of
        // the Administrators group
        guard CheckTokenMembership(
            nil,
            adminGroup,
            &isAdmin
        ) else {
            return false
        }
        // Okay the below is intentional because
        // `isAdmin` is a `WindowsBool` and we need `Bool`
        return isAdmin.boolValue
    }
}

extension FileDescriptor {
    internal func readUntilEOF(upToLength maxLength: Int) async throws -> Data {
        // TODO: Figure out a better way to asynchornously read
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var totalBytesRead: Int = 0
                var lastError: DWORD? = nil
                let values = Array<UInt8>(
                    unsafeUninitializedCapacity: maxLength
                ) { buffer, initializedCount in
                    while true {
                        guard let baseAddress = buffer.baseAddress else {
                            initializedCount = 0
                            break
                        }
                        let bufferPtr = baseAddress.advanced(by: totalBytesRead)
                        var bytesRead: DWORD = 0
                        let readSucceed = ReadFile(
                            self.platformDescriptor,
                            UnsafeMutableRawPointer(mutating: bufferPtr),
                            DWORD(maxLength - totalBytesRead),
                            &bytesRead,
                            nil
                        )
                        if !readSucceed {
                            // Windows throws ERROR_BROKEN_PIPE when the pipe is closed
                            let error = GetLastError()
                            if error == ERROR_BROKEN_PIPE {
                                // We are done reading
                                initializedCount = totalBytesRead
                            } else {
                                // We got some error
                                lastError = error
                                initializedCount = 0
                            }
                            break
                        } else {
                            // We succesfully read the current round
                            totalBytesRead += Int(bytesRead)
                        }

                        if totalBytesRead >= maxLength {
                            initializedCount = min(maxLength, totalBytesRead)
                            break
                        }
                    }
                }
                if let lastError = lastError {
                    let windowsError = SubprocessError(
                        code: .init(.failedToReadFromSubprocess),
                        underlyingError: .init(rawValue: lastError)
                    )
                    continuation.resume(throwing: windowsError)
                } else {
                    continuation.resume(returning: Data(values))
                }
            }
        }
    }
}

#endif // canImport(WinSDK)
