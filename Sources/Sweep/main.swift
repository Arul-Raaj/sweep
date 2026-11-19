import Foundation

// No arguments: the app window. Otherwise: command line (used by the weekly job).
let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.first?.hasPrefix("-psn") == true {
    SweepApp.main()
}

#if DEBUG
if args.first == "snapshot" {
    exit(Snapshot.run(Array(args.dropFirst())))
}
#endif

exit(CLI.run(args))
