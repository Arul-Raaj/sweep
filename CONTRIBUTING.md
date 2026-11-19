# Contributing to Sweep

Thanks for helping. Sweep deletes files, so the bar is simple: **nothing it does should
ever surprise the person using it.**

## Getting started

```bash
git clone https://github.com/Arul-Raaj/sweep.git
cd sweep
./test.sh                                  # run the tests
tools/make-demo-home.sh /tmp/sweep-demo    # a fake home to try changes on
swift build && SWEEP_HOME=/tmp/sweep-demo "$(swift build --show-bin-path)/Sweep"
```

Use `SWEEP_HOME` while developing, so the app never looks at your real files.

## Adding a cleaning rule

Rules live in `Sources/SweepCore/Rule.swift`. A new rule needs:

1. **A narrow location.** One folder or a documented pattern, never a broad sweep.
   Prefer a name filter (`Rule.Filter`) over "everything in this folder".
2. **The right level.**
   - *Recommended:* rebuilds itself and nobody would notice.
   - *Rebuildable:* comes back, but costs a download, an install or a rebuild.
   - *Review:* the user's own files. These go to the Trash, never straight to deletion.
3. **Honest copy:** `what` (what the files are), `whySafe` (why removing them can't break
   anything) and `after` (what the user will notice). Plain words, no jargon, no hype.
4. **Protection for live data.** If an app uses the files, guard the rule with
   `guardedBy:` (the app's data folder), so it's skipped while the app runs. Use an age
   gate (`days:`) wherever "recent" could mean "in use".
5. **Tests with decoys.** Add the rule's targets *and* look-alike files that must survive
   to a test, ideally the end-to-end test in `Tests/SweepCoreTests`. Check that
   `Safety.allows` rejects anything outside the rule.
6. **A source.** In the pull request, link the tool's documentation or another reliable
   source that says the files are safe to remove.

If the right way to clean something is the owner's own command (`brew cleanup`,
`pnpm store prune`, `tmutil`) or a setting, Sweep shouldn't delete the files directly.

## Code

- Swift 6 with strict concurrency, SwiftUI, no third-party dependencies.
- The engine (`SweepCore`) has no UI and is where logic and tests belong.
- Keep it small and readable. Comments explain *why*, not *what*.
- Before opening a pull request: `./test.sh` passes, and `swift build` shows no warnings.

## Reporting a problem

If Sweep listed or removed something it shouldn't have, please open an issue with the
category, the path (anonymise it if you like) and your macOS version. These reports are
the most valuable ones.
