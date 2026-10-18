import AppKit
import ArdiaCore
import ArdiaSync

if getenv("ARDIA_PREWARM") != nil { exit(0) }

LegacyMigration.moveToNewName()

if !LegacyMigration.runAtLaunch() { exit(0) }

exit(ArdiaCoreHost.run(argc: CommandLine.argc, argv: CommandLine.unsafeArgv) { AppDelegate() })
