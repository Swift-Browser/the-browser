import AppKit
import MedusaCore
import MedusaSync

if getenv("MEDUSA_PREWARM") != nil || getenv("MEDUSA_PREWARM") != nil { exit(0) }

LegacyMigration.moveToNewName()

if !LegacyMigration.runAtLaunch() { exit(0) }

exit(MedusaCoreHost.run(argc: CommandLine.argc, argv: CommandLine.unsafeArgv) { AppDelegate() })
