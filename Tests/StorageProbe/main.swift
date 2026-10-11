import Foundation
import KeydeskCore
let args = CommandLine.arguments
// Test fixture only. Writes no real keys; destination must be an explicit QA directory.
guard args.count == 3, args[1] == "write", URL(fileURLWithPath: args[2]).lastPathComponent == "atomic-fixture.bin" else { exit(2) }
do {
    try VaultFileStore.atomicWrite(Data(repeating: 0x4e, count: 32 * 1024 * 1024), to: URL(fileURLWithPath: args[2]))
} catch { fputs("fixture_write_failed\n", stderr); exit(1) }
