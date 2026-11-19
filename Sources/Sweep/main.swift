import Foundation

// No arguments: the app window. Otherwise: command line (used by the weekly job).
let args = Array(CommandLine.arguments.dropFirst())

if args.isEmpty || args.first?.hasPrefix("-psn") == true {
    SweepApp.main()
} else {
    exit(CLI.run(args))
}
