@testable import SwiftExperimentalSubprocess
import XCTest
import SystemPackage

struct Ls: Subprocess.ConfigurationBuilder {
    var options: [Option]

    var paths: [FilePath]

    public enum Option {
        case long

        public var argument: String {
            switch(self) {
            case .long:
                return "-l"
            }
        }
    }

    public init(_ options: Option..., paths: FilePath...) {
        self.options = options
        self.paths = paths
    }

    public func config() -> Subprocess.Configuration {
        return Subprocess.Configuration(
            executable: .named("ls"),
            arguments: .init(self.options.map( { $0.argument } ) + self.paths.map( { $0.description } ))
        )
    }
}

final class SubprocessConfigurationTests: XCTestCase {
    public func testCommandBuilder() async throws {
        let result = try await Subprocess.run(
            Ls(.long, paths: ".")
        )
        print(result.standardOutput)
    }
}
