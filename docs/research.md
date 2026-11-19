# What fills a small Mac, and what can safely be removed

Research date: November 2026, macOS 27. Sizes are typical ranges reported by Apple, tool docs and users.

## 1. Top findings

1. **On developer Macs the biggest reclaimable space is usually project output, not system files:** `node_modules` and build folders (`.next`, `.turbo`, `dist`) across many projects and git worktrees can reach tens of gigabytes.
2. **AI coding tools are a new, large group that mainstream cleaners don't handle:** sandbox VM images (around 10 GB), transcripts and runtime caches.
3. **Apple Intelligence models take 9–15 GB, sometimes more.** They can only be removed properly through Apple's asset service (what pared and RemoveMacAI do), never by deleting files under `/System`.
4. **The widely repeated "free up space" items** (aerial videos, macOS installers, iOS update files, iPhone backups, Time Machine local snapshots, Xcode, Docker) are often empty, but huge when present.
5. **A large share of a full disk is invisible without Full Disk Access:** Messages, Mail, Photos, app containers and iCloud Drive.

## 2. How to read this report

**Safety levels**

| Level | Meaning | Sweep behaviour |
|---|---|---|
| 1 safe | Rebuilds itself, nothing to do afterwards, nobody would notice | Can be pre-selected |
| 2 rebuildable | Comes back, but costs time or an action (re-download, `npm install`, re-index, first launch is slow) | Shown, not pre-selected, with the cost stated |
| 3 review | User data or state. Only the user can judge | Shown item by item, never pre-selected |
| — | Managed by macOS. Not removable, or removal is harmful | Report the size only |

**Permission column:** `none` (user-owned, readable), `FDA` (Full Disk Access needed even to measure), `admin` (root-owned, needs the admin password), `SIP` (protected by System Integrity Protection; deleting means disabling SIP or booting Recovery, which Sweep should never ask for).

**Source tags:** [A] Apple documentation, [E] Eclectic Light Co (Howard Oakley), [S] tool source code or official tool docs, [C] community or forum report (usually one user), [V] vendor blog with a product to sell, [?] not verified.

**Limits of this research**

- Reddit could not be reached by the search tools. Only one Reddit mirror link turned up. Community evidence comes from Apple Support Communities, MacRumors, Apple Developer Forums, Hacker News-linked blogs and GitHub issues.
- Several MacRumors forum pages returned 403. Figures from them come from search snippets.
- OnyX's official option list could not be read. What is listed comes from reviews.
- Claims about macOS 27 behaviour (for example, that the Apple Intelligence switch was removed) come from MacRumors and the tool READMEs, not from Apple.
- `du` counts APFS clones at full size, so some figures overstate what deleting would free. Chrome's `code_sign_clone` is the clearest case.

## 3. Space consumers in detail

### 3.1 macOS system side

#### Apple Intelligence models

- **What:** on-device foundation, vision and code models, delivered as MobileAsset "asset sets".
- **Path:** `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*` (`…FM_GenerativeModels`, `…FM_Visual`, `…FM_CodeLM`, `Overrides`). Folder names change between macOS versions. [C] [theapplewiki](https://theapplewiki.com/wiki/Apple_Intelligence), [tejyash/delete-apple-intelligence-macos](https://github.com/tejyash/delete-apple-intelligence-macos)
- **Typical size:** 9.24 GB on macOS 26.0 ([Apple Communities](https://discussions.apple.com/thread/256150006)); "about 12GB, sometimes more", with some users over 20 GB ([MacRumors, Oct 2026](https://www.macrumors.com/2026/10/06/strip-apple-intelligence-from-macos-27/)); Apple's older published figure was 7 GB ([MacRumors, Mar 2025](https://www.macrumors.com/2025/03/17/apple-intelligence-storage-space-macos-15-4/)). RemoveMacAI's README says keeping Siri keeps "about 13 GB" of foundation models.
- **Measure:** `du -sh /System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*`. Readable without Full Disk Access. Settings > General > Storage > macOS (i) also shows it, but that figure lags.
- **Level:** 2. Features stop working (Writing Tools, Genmoji and Image Playground, Visual Intelligence, Foundation Models framework apps, Xcode predictive completion, Photos Clean Up).
- **How it comes back:** macOS re-downloads the models if the feature is on and nothing blocks the download. People who deleted the folders by hand report them returning within minutes. [C]
- **Permission:** `SIP` for the files. Not needed for the supported route below.
- **Official way:** on macOS 15 and 26, turn Apple Intelligence off in Settings; macOS then marks the models as removable and may only delete them under space pressure, so the Storage figure often does not drop. [C] On macOS 27 the switch is reported removed, and turning Siri off frees little or nothing. [C] [MacRumors](https://www.macrumors.com/2026/10/06/strip-apple-intelligence-from-macos-27/)
- **How pared and RemoveMacAI do it** (this is what freed 10–12 GB): [S]
  - pared loads the private `UnifiedAssetFramework` with `dlopen`, opens an XPC connection to `com.apple.siri.uaf.subscription.service`, and sends a `ResetAssetSets` operation with the asset sets listed explicitly. Leaving the list out would reset every set. The reset applies to all users. [how-it-works.md](https://raw.githubusercontent.com/4evy/pared/master/docs/how-it-works.md)
  - Re-download is blocked by a configuration profile that sets `DownloadServerBaseURLOverride-<assetType>` in the `com.apple.MobileAsset` domain to `https://127.0.0.1:9/pared-blocked/`. `mobileassetd` reads this from `/Library/Managed Preferences/com.apple.MobileAsset.plist`; ordinary `defaults write` is denied, which is why a profile is needed.
  - SIP stays on. Nothing under `/System` is modified by the tool itself; macOS removes the files.
  - A model shared with a feature that is still on (Siri, for example) is kept.
  - RemoveMacAI is built on the same approach, adds a journal and `removemacai revert`, and supports macOS 27, 26 and (in beta) 15.1+. Apple silicon only. [README](https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/README.md)
- **Caveats from the tools' own docs:** private API that can change in any release; Apple deprecated the Apple Intelligence and Siri restriction keys in macOS 26.4; a success reply only means no error; the profile can make a stalled macOS update retry for about two hours (RemoveMacAI issue #109: turn the block off, update, turn it on again); on macOS 27 Spotlight runs as a process named Siri, so turning Siri off can change Spotlight; dictation models are not removed.
- **Storage figures mislead:** one test saw the Storage pane drop 24.5 GB while free space rose about 14 GB. [C] Use `df` or Disk Utility's container figure.
- **Risky advice in circulation:** boot Recovery, run `csrutil disable`, delete the `UAF_FM_*` folders. It lowers security, the models come back, and the folder layout differs by version.
- **For Sweep:** detect and show the size. Either link to pared/RemoveMacAI or implement the same asset-service reset as an explicitly experimental action. Never delete under `/System`.

#### Time Machine local snapshots

- **What:** APFS snapshots Time Machine takes hourly. Deleted files keep occupying space while a snapshot still references them.
- **Measure:** `tmutil listlocalsnapshots /` (names, no sizes); Disk Utility > View > Show APFS Snapshots (sizes); `diskutil apfs listSnapshots /`.
- **Typical size:** megabytes to hundreds of GB after large deletions.
- **Level:** 1 for snapshots older than 24 hours. Keep the newest one, or the next backup may be a full one. [E] [Take control of snapshots](https://eclecticlight.co/2026/09/09/take-control-of-snapshots/)
- **How it comes back:** Time Machine makes a new one within the hour. The user loses the ability to restore from the removed points in time.
- **Permission:** `admin` (`tmutil` delete and thin run as root). Listing needs nothing.
- **Official way:** `tmutil thinlocalsnapshots / <bytes> <urgency 1–4>` lets macOS choose what to drop; `tmutil deletelocalsnapshots <date>` removes one; Disk Utility can delete them too.
- **Disputed:** "macOS frees snapshots when it needs space" is not reliable. Oakley documents cases where purging fails. [E] [Aren't snapshots purgeable?](https://eclecticlight.co/2026/08/24/arent-snapshots-purgeable/), [Why can purging snapshots fail?](https://eclecticlight.co/2026/08/27/why-can-purging-snapshots-fail/)
- **Never touch:** `com.apple.os.update-*` and snapshots made by other backup apps.

#### "System Data"

- **What:** not a real category. Storage settings adds up the categories it recognises and calls the remainder System Data: "an etcetera, a ragbag", "little more than a guesstimate". [E] [What is System Data?](https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/)
- **What ends up in it:** local snapshots, `/private/var/folders`, caches, swap, logs, the Spotlight index, Apple Intelligence models, aerial video downloads, developer files Storage does not recognise, and any library it miscounts.
- **Reported runaway causes (each a single-user report unless noted):** [C]
  - Swap leak on macOS 26: about 270 GB of `swapfile*`, fixed by a restart ([MacRumors](https://forums.macrumors.com/threads/tahoe-endlessly-consumes-all-free-space-270-gb-on-macbook-pro.2465906/)).
  - Spotlight journals: 137 GB in `~/Library/Metadata/SpotlightKnowledgeEvents`, 96 GB in `CoreSpotlight` ([Apple Developer Forums](https://developer.apple.com/forums/thread/796568), [mjtsai](https://mjtsai.com/blog/?p=48557)).
  - `mediaanalysisd` cache: 15–143 GB in `~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches` ([Apple Communities](https://discussions.apple.com/thread/255835917), [mjtsai](https://mjtsai.com/blog/?p=48375)).
  - Stuck aerial downloads: up to 221 GB of `CFNetworkDownload_*.tmp`, root-owned ([Mole issue #1253](https://github.com/tw93/Mole/issues/1253)).
  - Runaway logs: 75–85 GB single log files, some under `/private/var/root` where the user cannot see them ([Apple Communities](https://discussions.apple.com/thread/256060273)).
- **For Sweep:** do not treat it as a target. Break it down and show what Sweep can and cannot see. Use the container's free space as the true figure; Finder's "available" includes purgeable space and is often wrong. [E] [Finder figures](https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/)

#### Aerial wallpaper and screen saver videos

- **Path:** `/Library/Application Support/com.apple.idleassetsd/Customer/4KSDR240FPS/` (root-owned). On macOS 15/26 also a per-user copy at `~/Library/Application Support/com.apple.wallpaper/aerials/videos/`. Stuck downloads sit in a root-owned temp folder under `/private/var/folders/zz/…/T/com.apple.idleassetsd/`.
- **Typical size:** about 10 GB on macOS 14, 26–42 GB later; one user had 42 GB twice (system and user copy). [C] [MacRumors](https://forums.macrumors.com/threads/wallpaper-screensavers-take-up-26gb-how-to-delete.2431871), [dev.to](https://dev.to/frr149/apple-installed-84gb-of-jellyfish-on-my-mac-duplicated-nf4)
- **Measure:** `du -sh` on both paths. The system path is readable without admin rights.
- **Level:** 2.
- **How it comes back:** `idleassetsd` downloads again if an aerial is still selected as wallpaper or screen saver. Some users report it returning days later anyway.
- **Permission:** `admin` for the system copy, `none` for the user copy.
- **Official way:** System Settings > Wallpaper, Control-click a downloaded aerial > Remove Download.
- **Risky advice:** `sudo rm -rf` of the whole folder while the daemon runs, deleting its index plist, or locking the folder with `chflags`. Reports of broken wallpaper settings and re-download loops. [C]
- **For Sweep:** show the size, warn if an aerial is currently selected, and open Wallpaper settings. Mole only removes aborted `.tmp` downloads untouched for an hour.

#### macOS installers and staged updates

| Item | Path | Typical | Level | Notes |
|---|---|---|---|---|
| Full installer app | `/Applications/Install macOS *.app` | 13–15 GB | 1 if older than the running macOS, else 2 | Plain delete. Re-download with `softwareupdate --fetch-full-installer`. Mole removes only installers older than 14 days that do not match the current version. Permission: `none` or `admin`. |
| Interrupted install data | `/macOS Install Data` | several GB | — | Owned by the installer. One report of an unbootable Mac after deleting it mid-upgrade. [C] [Jamf](https://community.jamf.com/general-discussions-2/os-x-install-data-folder-in-root-folder-4013). Mole refuses. |
| Downloaded updates | `/Library/Updates` | 0.5–22 GB | — | Cleared by Software Update after install. Parts are SIP-protected. Mole refuses. |
| Staged update assets | `/System/Library/AssetsV2/com_apple_MobileAsset_MacSoftwareUpdate*` | several GB | — | `SIP`. Temporary upgrade files normally clear within about a day. [E] [Why did that upgrade take so much space?](https://eclecticlight.co/2025/10/02/why-did-that-macos-upgrade-take-so-much-space/) |

#### Swap and sleep image

- **Swap:** `/System/Volumes/VM/swapfile*`, 1 GB each, created and removed by the kernel. Not removable while running. Large swap means memory pressure or a leak; quitting the app or restarting is the fix. Old advice says set `sudo pmset -a hibernatemode 0` and delete it. With mode 0 the Mac loses the session if power fails during sleep, and the advice dates from Intel laptops (2007–2016). [C] [MacRumors](https://forums.macrumors.com/threads/dealing-with-sleepimage-and-swapfiles.1579152)
- **Level:** — for both. Sweep should show them and explain, nothing more.

#### `/private/var/folders` (per-user temp and caches)

- **What:** each user gets `…/T` (temp, `$TMPDIR`), `…/C` (caches), `…/X` (code-sign clones and similar), `…/0`. The `zz` folders belong to the system.
- **Typical size:** 1–10 GB; 9. Outliers of 85 GB and more are reported. [C]
- **Measure:** `du -sh "$(getconf DARWIN_USER_TEMP_DIR)" "$(getconf DARWIN_USER_CACHE_DIR)"`.
- **Level:** mixed. A restart clears `T` (level 1, no file deletion needed). Deleting inside it while apps run can break them, because sockets, pasteboard data and live temp files are there.
- **Risky advice:** deleting `/private/var/folders` wholesale. The script cleaner mac-cleanup-py does exactly this for one path pattern. [S]
- **What Sweep can target safely:**
  - `X/com.google.Chrome.code_sign_clone/code_sign_clone.*`: Chrome clones its app bundle at launch so the signature stays valid during an update, and leaves the clone behind when it does not quit cleanly. They are APFS clones, so the real saving is less than `du` shows, but clones of superseded Chrome versions hold real space. Level 1 when Chrome is not running. [?] The mechanism is from Chromium behaviour, not verified against Chromium source in this research.
  - `T/cdp-*`: throwaway browser profiles from automation tools, 23 folders, 2.2 GB. Level 1 when older than a day and no browser process has them open.
  - `C/<bundle id>`: per-app caches. Level 1 for apps that are not running; same rules as `~/Library/Caches`.

#### Unified log, Spotlight, other system stores

| Item | Path | Typical | Level | Notes |
|---|---|---|---|---|
| Unified log | `/private/var/db/diagnostics`, `/private/var/db/uuidtext` | 0.5–2.5 GB | — | `logd` trims it itself. `sudo log erase --all` destroys diagnostics and gains little. [E] [Log storage](https://eclecticlight.co/2025/09/29/inside-the-unified-log-3-log-storage-and-attrition/) |
| Spotlight index | `/System/Volumes/Data/.Spotlight-V100`, `~/Library/Metadata/CoreSpotlight` | a few GB; 27–137 GB when broken | 2 | `sudo mdutil -E /System/Volumes/Data` rebuilds. Hours of indexing, search degraded meanwhile. Only worth it when the index is clearly bloated. [E] [When and how to rebuild](https://eclecticlight.co/2024/11/19/when-and-how-to-rebuild-spotlight-indexes/). Needs `admin`/`FDA` to measure. |
| Photos/media analysis cache | `~/Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches` | usually small; 15–143 GB reported | 2 | Regrows while analysis runs. `FDA`. |
| Diagnostic reports | `~/Library/Logs/DiagnosticReports`, `/Library/Logs/DiagnosticReports` | MBs | 1 when old | System path needs `admin`. |
| Command Line Tools | `/Library/Developer/CommandLineTools` | 1.3 GB | 2 | Removing breaks `git` and `clang` until `xcode-select --install`. `admin`. Not worth offering. |
| Rosetta, cryptexes, Preboot | `/System/Volumes/Preboot` | about 10 GB | — | `SIP`. |
| Siri, speech and language assets | `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Siri_*`, `…_UAF_LinguisticData`, `…_Speech_*`, `…_TTSAXResourceModelAssets` | a few GB in total | — for files | `SIP`. See next item for the supported route. |

#### Voices, dictation, translation languages

- **Official way only:** Spoken Content voices in System Settings > Accessibility > Spoken Content > System Voice > Manage Voices ([Apple](https://support.apple.com/guide/mac-help/mchlp2290)); translation languages in General > Language & Region > Translation Languages ([Apple](https://support.apple.com/guide/mac-help/mchldd8b3c15)); dictation languages in Keyboard > Dictation.
- **Typical size:** enhanced and premium voices are a few hundred MB each. Apple publishes no sizes.
- **Level:** 2 (re-download from the same settings pane). Some users report voices that cannot be deleted or that return. [C]
- **For Sweep:** list sizes from `AssetsV2` and open the right settings pane. No deletion.

### 3.2 User data and Apple apps

All of these are level 3 unless stated. Sweep should show sizes and open the official tool.

| Consumer | Path | Typical | Level | How to remove, what comes back | Permission |
|---|---|---|---|---|---|
| iPhone/iPad backups | `~/Library/Application Support/MobileSync/Backup/<UDID>` | 5–100+ GB each | 3 | Finder > device > Manage Backups > Delete. "After you delete a backup, you can't recover it." [A] [Apple](https://support.apple.com/en-us/108809). Often the only backup of the device. Show device name and date from each `Info.plist`. | `FDA` |
| iOS/iPadOS update files | `~/Library/iTunes/iPhone Software Updates`, `iPad Software Updates` (`.ipsw`) | 4–10 GB each | 1 | Plain delete. Finder downloads again only if the user restores or updates a device from the Mac. | none |
| Photos library | `~/Pictures/Photos Library.photoslibrary` | 10–500 GB | 3 | Photos > Settings > iCloud > Optimize Mac Storage keeps small versions locally; macOS removes originals only when space is low, not at once. [A] [Apple](https://support.apple.com/guide/photos/phtf5e48489c). Never delete inside the package. | `FDA` |
| iCloud Drive local copies | `~/Library/Mobile Documents` | any | 2 when evicting, 3 when deleting | Finder > Control-click > Remove Download evicts a synced file; opening it downloads again. Evicted files are not in Time Machine backups. [E] [Optimise Mac Storage or not](https://eclecticlight.co/2024/03/11/icloud-drive-in-sonoma-optimise-mac-storage-or-not/). Whether `brctl evict` still works on macOS 14+ is disputed. [?] | `FDA` |
| Third-party cloud folders | `~/Library/CloudStorage/*` | any | 2 when set to streaming | Use the provider's "online only" option. Deleting syncs the deletion. | `FDA` |
| Messages attachments | `~/Library/Messages/Attachments`, `chat.db` | 1–100 GB | 3 | Settings > General > Storage > Messages (i) lists attachments by size. Messages > Settings > Keep Messages (30 days, 1 year, forever). [A] [Apple](https://support.apple.com/guide/messages/icht20001/mac). Never delete files by hand; it breaks history. | `FDA` |
| Mail downloads | `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | 0.1–5 GB | 2 | Copies of attachments the user opened. Safe when the account keeps mail on the server (IMAP, iCloud, Gmail). Files the user edited and saved there would be lost. [C] | `FDA` |
| Mail store | `~/Library/Mail/V10` | 1–50 GB | 3 | Mail > Settings > Accounts > Download Attachments: Recent or None; erase Junk and Deleted. Deleting `V10` loses mail on POP accounts. [C] | `FDA` |
| GarageBand/Logic sounds | `/Library/Application Support/GarageBand`, `/Library/Application Support/Logic`, `/Library/Audio/Apple Loops` | 2–70 GB | 2 if neither app is used, else 3 | Storage > Music Creation > Remove GarageBand Sound Library, or the app's Sound Library Manager. Shared with Logic and MainStage. Re-download from the same menu. The Storage button is reported to do nothing on some versions. [C] | admin |
| Podcasts, TV, Music downloads | `~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts`, app libraries | 1–50 GB | 2 | Remove Download in each app, or Storage > (i). Re-download is free. | `FDA` |
| Trash | `~/.Trash` | any | 3 (Sweep's 30-day rule is reasonable) | Storage > Empty Trash Automatically removes items after 30 days. | `FDA` |
| Downloads, Desktop, Documents, large files | `~/Downloads` and so on | any | 3 | User's call. Sort by size and age. | none (TCC prompt per folder) |
| VM disks | `~/Parallels/*.pvm`, `~/Library/Containers/com.utmapp.UTM/Data/Documents/*.utm`, `~/Virtual Machines.localized` | 20–100 GB | 3 | Delete in the VM app. Parallels has "Reclaim Disk Space". | none/`FDA` |
| Games | `~/Library/Application Support/Steam/steamapps/common` | 10–200 GB | 3 | Uninstall in Steam. Shader and HTML caches beside it are level 1. | none |

Apple's own Storage recommendations (Store in iCloud, Optimize Storage, Empty Trash Automatically) are settings, not deletions. Oakley calls the pane "of limited usefulness". [E] [Explainer: Storage settings](https://eclecticlight.co/2025/12/20/explainer-storage-settings/). Apple's general page: [Free up storage space on Mac](https://support.apple.com/en-us/102624).

### 3.3 Developer tools

General rule from Mole's source: use the tool's own command, ask the tool where its cache is (users relocate caches with environment variables), and skip while the tool is running. [S] [clean-dev.md](https://github.com/tw93/Mole/blob/main/.claude/rules/clean-dev.md)

#### Project folders (often the largest item on a developer Mac)

| Item | Pattern | Level | Notes |
|---|---|---|---|
| Dependencies | `node_modules`, `.venv`/`venv` (has `pyvenv.cfg`), `Pods`, `vendor`, `.build` | 2 | `npm install` and equivalents restore them. Check for open files first (a running dev server). |
| Build output | `.next`, `.nuxt`, `dist`, `build`, `.turbo`, `.parcel-cache`, `target`, `.svelte-kit`, `.astro`, `.angular`, `coverage`, `__pycache__` | 2 | Rebuilt on next build. Only inside a folder with a project marker (`package.json`, `Cargo.toml`, `.git`, …). `bin` and `vendor` need extra care. This is Mole's `mo purge` list. [S] [purge_shared.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/purge_shared.sh) |
| Git worktrees | listed by `git worktree list` | 3 | May hold uncommitted work. Official removal is `git worktree remove`, which refuses if the tree is dirty. Sweep can show each worktree's age and whether its branch is merged, and offer only the dependencies and build output as level 2. |

Git worktrees multiply this: every worktree carries its own dependencies and build output, so a handful of stale worktrees can hold tens of gigabytes.

#### Xcode

| Item | Path | Typical | Level | Official way, notes | Permission |
|---|---|---|---|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData` (relocatable) | 2–50 GB | 1 | Delete the folder with Xcode closed. Next build is a full build. | none |
| Archives | `~/Library/Developer/Xcode/Archives` | 1–50 GB | 3 | Hold dSYMs needed to symbolicate crashes of shipped builds. DevCleaner leaves them unselected. | none |
| Device support | `~/Library/Developer/Xcode/{iOS,watchOS,tvOS,visionOS,macOS} DeviceSupport` | 2–5 GB per OS version | 2 | Re-created when a device connects (minutes). Keep the newest two (Mole's default). | none |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices` | 5–30 GB | 2 for unavailable, 3 for the rest | `xcrun simctl delete unavailable`. Never `simctl delete all` or `erase all`. | none |
| Simulator runtimes | `/Library/Developer/CoreSimulator/Images`, `…/Volumes` | 5–10 GB each | 2 | `xcrun simctl runtime list`, `xcrun simctl runtime delete <id>`, or Xcode > Settings > Platforms. Deletion is reported flaky; some orphaned images under `/System/Library/AssetsV2` cannot be removed. [C] [Apple Developer Forums](https://developer.apple.com/forums/thread/812992) | admin |
| Simulator caches | `~/Library/Developer/CoreSimulator/Caches`, `/Library/Developer/CoreSimulator/Caches` | 1–10 GB | 1 | Rebuilt on next boot of a simulator. Sweep already covers the user path. | none/admin |
| SwiftUI previews | `~/Library/Developer/Xcode/UserData/Previews` | 6–110 GB reported | 2 | `xcrun simctl --set previews delete all`. Deleting subfolders by hand is reported to break previews. [C] [Apple Developer Forums](https://developer.apple.com/forums/thread/682439) | none |
| Documentation cache | `~/Library/Developer/Xcode/DocumentationCache`, `/Library/Developer/Xcode/DocumentationCache` | 1–10 GB | 1 | Keep the newest Xcode version's. | none/admin |
| XCTest devices | `~/Library/Developer/XCTestDevices` | 1–20 GB | 2 | | none |
| Device logs | `~/Library/Developer/Xcode/iOS Device Logs` | small | 1 | | none |
| SwiftPM cache | `~/Library/Caches/org.swift.swiftpm` | 0.5–5 GB | 1 | `swift package purge-cache`. Keep `~/Library/org.swift.swiftpm` (config). | none |
| Old Xcode versions | `/Applications/Xcode*.app` | 10–15 GB each | 3 | | none |

DevCleaner for Xcode covers device support, archives, DerivedData, documentation cache, device logs and old documentation. It does not touch simulators, runtimes or previews. [S] [XcodeFiles.swift](https://github.com/vashpan/xcode-dev-cleaner)

One trap: on an Xcode whose first-launch setup is incomplete, any `simctl` call raises an admin prompt. Mole checks `xcodebuild -checkFirstLaunchStatus` first. [S]

#### Containers and virtual machines

| Item | Path | Level | Notes |
|---|---|---|---|
| Docker Desktop disk | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | 3 for the file, 2 for prunable content | Sparse file: `ls` shows the maximum, `du` the real size. Measure with `docker system df`. Reclaim with `docker builder prune` and `docker image prune` (dangling only). Mole runs only those two, with `--filter until=168h`, and only if Docker is already running. `docker system prune -a --volumes` deletes databases in volumes. Lowering the disk size limit deletes all images and containers. [S] [Docker docs](https://docs.docker.com/reference/cli/docker/system/prune/), [Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/) |
| OrbStack | `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data` (`data.img`), `~/.orbstack` | 3 | Sparse; apparent size is terabytes. Prune inside with `docker`. Whether it shrinks on its own was not confirmed. [?] |
| Colima, Lima | `~/.colima/_lima`, `~/.lima`; download cache `~/Library/Caches/lima` | 3; download cache 1 | |
| Podman machine | see `podman machine inspect` | 3 | Path not verified. [?] |

#### Package manager caches

| Tool | Path | Level | Official command | Notes |
|---|---|---|---|---|
| Homebrew | `~/Library/Caches/Homebrew` (`brew --cache`), old versions in `/opt/homebrew/Cellar` | 1 | `brew cleanup -n` to preview, `brew cleanup --prune=all` | Homebrew already cleans after installs and fully every 30 days; downloads older than 120 days go by default. [S] [Manpage](https://docs.brew.sh/Manpage) |
| npm | `~/.npm/_cacache` (`npm config get cache`) | 1 | `npm cache clean --force` | Keep `_npx`: running `npx` commands read from it. [S] [npm docs](https://docs.npmjs.com/cli/v10/commands/npm-cache) |
| pnpm | `pnpm store path`, default `~/Library/pnpm/store` | 2 | `pnpm store prune` | Prune removes only unreferenced packages. Do not delete the store by hand. [S] [pnpm docs](https://pnpm.io/cli/store) |
| Yarn classic | `~/Library/Caches/Yarn` | 1 | `yarn cache clean` | |
| Yarn Berry | `~/.yarn/berry/cache` | 3 | — | Plug'n'Play projects read installed packages from it. Mole protects it. |
| Bun | `~/.bun/install/cache` | 1 | `bun pm cache rm` | Sweep already covers it. |
| Deno | `~/Library/Caches/deno` | 3 | `deno clean` | Mixes remote imports with app storage. |
| Corepack, node-gyp, TypeScript, Vite, ESLint, Prisma | `~/.cache/node/corepack`, `~/Library/Caches/node-gyp`, `~/.cache/{typescript,vite,eslint,prisma}` | 1 | — | |
| Playwright, Puppeteer, Cypress browsers | `~/Library/Caches/ms-playwright`, `~/.cache/puppeteer`, `~/Library/Caches/Cypress` | 2 | `npx playwright uninstall --all`, `cypress cache prune` | 180–280 MB per browser. Playwright removes unused versions itself. [S] [Playwright docs](https://playwright.dev/docs/browsers) |
| Node versions | `~/.nvm/versions`, `~/.volta/tools`, fnm | 3 | `nvm uninstall <v>` | |
| pip | `~/Library/Caches/pip` (`pip cache dir`) | 1 | `pip cache purge` | On a Mac with only the Command Line Tools stub, calling `pip3` can raise an install dialog. |
| uv | `~/.cache/uv` (`uv cache dir`) | 1 | `uv cache prune` (unused only) or `uv cache clean` | Docs say never to modify the cache directly. [S] [uv docs](https://docs.astral.sh/uv/concepts/cache/) |
| conda | `<prefix>/pkgs` | 1 for `pkgs`, 3 for `envs` | `conda clean --all --dry-run` | |
| Poetry | `~/Library/Caches/pypoetry/{cache,artifacts}` | 1 | `poetry cache clear --all .` | `…/pypoetry/virtualenvs` holds live environments: level 3 despite being under Caches. |
| pyenv | `~/.pyenv/cache`; `~/.pyenv/versions` | 1; 3 | | |
| Cargo | `~/.cargo/registry/cache`; `registry/src`, `git`; project `target/` | 1; 2; 2 | `cargo clean` per project | Cargo 1.88+ garbage-collects by age. [S] [Cargo Book](https://doc.rust-lang.org/cargo/guide/cargo-home.html) |
| Go | `~/Library/Caches/go-build`; `~/go/pkg/mod` | 1; 2 | `go clean -cache`; `go clean -modcache` | |
| Gradle | `~/.gradle/caches`, `wrapper/dists` | 1–2 | — | Gradle cleans itself roughly daily. Skip while the daemon runs. [S] [Gradle docs](https://docs.gradle.org/current/userguide/directory_layout.html) |
| Maven, Ivy, NuGet | `~/.m2/repository`, `~/.ivy2/cache`, `~/.nuget/packages` | 2–3 | — | Mole refuses: builds read them directly. |
| Android | `~/Library/Android/sdk`, `~/.android/avd` | 3 | SDK Manager, `avdmanager delete avd` | AVDs are 6–20 GB each. [C] |
| CocoaPods | `~/Library/Caches/CocoaPods`; `~/.cocoapods/repos` | 1; 2 | `pod cache clean --all` | |
| JetBrains | `~/Library/Caches/JetBrains/<Product><Version>` | 1 for versions no longer installed | — | Settings in `~/Library/Application Support/JetBrains` are level 3. |
| VS Code, Cursor, Windsurf | `~/Library/Application Support/{Code,Cursor,Windsurf}/{Cache,CachedData,CachedExtensionVSIXs,Code Cache,GPUCache,logs}` | 1 | — | `User/workspaceStorage` and `User/History` hold chat history and local edit history: level 3. [?] for the exact semantics. |

#### Local AI models

All level 3: multi-GB downloads the user chose. Mole refuses to auto-clean every one of them.

| Tool | Path | Official way |
|---|---|---|
| Ollama | `~/.ollama/models` (`OLLAMA_MODELS`) | `ollama list`, `ollama rm <model>` [S] [FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx) |
| LM Studio | `~/.lmstudio/models`; older versions used `~/.cache/lm-studio` for models and chats | My Models in the app |
| Hugging Face | `~/.cache/huggingface/hub` (`HF_HOME`) | `hf cache ls`, `hf cache rm`, `hf cache prune`. Do not delete snapshot folders by hand; they are symlinks to shared blobs. `~/.cache/huggingface/xet` is safe to delete. [S] [HF docs](https://huggingface.co/docs/huggingface_hub/guides/manage-cache) |
| PyTorch, TensorFlow, wandb | `~/.cache/torch`, `~/.cache/tensorflow`, `~/.cache/wandb` | — |
| llama.cpp, Buzz | `~/Library/Caches/llama.cpp`, `~/Library/Caches/Buzz` | Model weights stored under Caches. A blanket Caches rule would delete them. Sweep's `~/Library/Caches` rule must exclude these. |
| Draw Things, DiffusionBee, ComfyUI | paths not verified [?] | in-app |

#### AI coding tools

| Item | Path | Level | Notes |
|---|---|---|---|
| Claude Desktop Cowork VM | `~/Library/Application Support/Claude/vm_bundles/claudevm.bundle` | 2 | `rootfs.img` grows and is not trimmed. Rebuilt the next time Cowork is used, at the cost of a download and setup. Quit Claude first. No official cleanup procedure was found. [C] [claude-code issue #22543](https://github.com/anthropics/claude-code/issues/22543), [Mole issue #537](https://github.com/tw93/Mole/issues/537) |
| Claude Desktop Electron caches | `…/Claude/{Cache,Code Cache,GPUCache,DawnGraphiteCache,DawnWebGPUCache}`, `~/Library/Logs/Claude` | 1 | Skip while Claude runs. `Partitions` (1.3 GB) mixes cache and site storage: clean only the cache subfolders inside it. |
| Claude Desktop sessions | `…/Claude/local-agent-mode-sessions`, `scratch-workspaces`, `claude-code-sessions` | 3 | Session files and work folders. |
| Claude Code transcripts | `~/.claude/projects/<project>/*.jsonl` | 3 | Conversation history; may be the only copy. A `cleanupPeriodDays` setting (default reported as 30) removes old transcripts, yet 1. [?] [settings docs](https://code.claude.com/docs/en/settings) |
| Old Claude Code binaries | `~/.local/share/claude/versions/*` | 1 | Keep the one `~/.local/bin/claude` points to, plus one. |
| Codex | `~/.codex` (`thread_history_1.sqlite` 864 MB, `sessions` 797 MB, `plugins` 517 MB) | 3 | |
| Codex runtime cache | `~/.cache/codex-runtimes` | 2 | Mole cleans it when no Codex process runs. |
| Automation browsers | `~/.agent-browser/browsers`, `~/.cache/chrome-devtools-mcp` | 1 for old builds | |

### 3.4 Browsers and Electron apps

Rule: delete only cache folders, never the profile, and never while the app runs. Sweep already does this for Chromium apps.

| Item | Path | Typical | Level | Notes |
|---|---|---|---|---|
| Chromium cache folders | `<profile>/{Cache,Code Cache,GPUCache,DawnCache,GrShaderCache,ShaderCache,Service Worker/CacheStorage}`, `~/Library/Caches/<browser>` | 0.5–5 GB per app | 1 | Mole leaves `Service Worker/ScriptCache` alone and protects web editors whose service-worker cache holds offline state (Docs, Figma, Notion). [S] |
| Chrome on-device AI (Gemini Nano) | `~/Library/Application Support/Google/Chrome/OptGuideOnDeviceModel` (some guides say under `Default/`; check both), `OptGuideOnDeviceClassifierModel` | about 4 GB | 2 | Chrome downloads it again unless Settings > System > On-device AI is off. No Google documentation found. [C] [MacRumors](https://www.macrumors.com/how-to/stop-chrome-downloading-hidden-4gb-file/), [The Register](https://www.theregister.com/ai-and-ml/2026/05/07/chrome-silently-installs-a-4-gb-local-llm-on-your-computer/5230893). |
| Chrome code-sign clones | `/private/var/folders/…/X/com.google.Chrome.code_sign_clone` | 1.4 GB per stale clone | 1 | See 4.1. 5. Brave, Teams and other Chromium apps have the same folder. |
| Google updater cache | `~/Library/Application Support/Google/GoogleUpdater/crx_cache` | 0.5–1 GB | 1 | [?] Treated as a download cache by name; not confirmed in Chromium docs. |
| Update staging (Squirrel/Sparkle) | `~/Library/Caches/<bundle id>.ShipIt`, `~/Library/Caches/<bundle id>/org.sparkle-project.Sparkle` | 0.1–1 GB | 1 | Skip while the app is updating. |
| Safari | `~/Library/Caches/com.apple.Safari`, `com.apple.WebKit.Networking` | 0.1–2 GB | 1 | `~/Library/Safari` itself is level 3 and needs `FDA`. |
| Firefox | `~/Library/Caches/Firefox/Profiles/*/cache2` | 0.3–1 GB | 1 | [?] |
| Slack, Discord, Teams, Zoom, Notion, Figma, WhatsApp | `~/Library/Application Support/<app>/{Cache,Code Cache,GPUCache,Service Worker/CacheStorage}`, `~/Library/Caches/<bundle id>` | 0.2–5 GB each | 1 | Never IndexedDB, Local Storage or the profile. |
| Telegram media | `~/Library/Group Containers/6N38VWS5BX.ru.keepcoder.Telegram/…/postbox/media` | 1–30 GB | 2–3 | Use Telegram > Settings > Data and Storage > Storage Usage. Secret-chat media does not come back. mac-cleanup-py deletes the message database itself. `FDA`. |
| Spotify | `~/Library/Caches/com.spotify.client`, `~/Library/Application Support/Spotify/PersistentCache` | 1–10 GB | 3 | May hold offline downloads. Mole refuses. |
| Adobe media cache | `~/Library/Application Support/Adobe/Common/Media Cache Files`, `~/Library/Caches/Adobe` | 1–50 GB | 1 with Adobe apps closed | Rebuilt when projects open. |
| Final Cut, iMovie, DaVinci render files | inside the library bundle; `~/Movies/CacheClip` | 1–100 GB | 2 | Final Cut: File > Delete Generated Library Files. [?] |
| App-specific databases | e.g. an app's own database and its `backups/` folder | varies | 3 | Found by size, not by rule. A "large files in Application Support" view would surface these. |

### 3.5 Leftovers from deleted apps

- **Where:** `~/Library/{Application Support,Caches,Containers,Group Containers,Preferences,Saved Application State,HTTPStorages,WebKit,Logs,LaunchAgents,Application Scripts}` and the `/Library` counterparts, `/Library/PrivilegedHelperTools`, `/private/var/db/receipts`.
- **Typical size:** megabytes to 10+ GB per app; one report of about 20 GB of Outlook data in Group Containers. [C][V]
- **Level:** 2 at best, 3 when in doubt. A wrong match deletes a live app's data.
- **Permission:** `FDA` for Containers and Group Containers; `admin` for `/Library` items.
- **How Pearcleaner decides** [S] ([ReversePathsFetch.swift](https://raw.githubusercontent.com/alienator88/Pearcleaner/main/Pearcleaner/Logic/ReversePathsFetch.swift), [Conditions.swift](https://raw.githubusercontent.com/alienator88/Pearcleaner/main/Pearcleaner/Logic/Conditions.swift)): match on bundle ID, app name (5 characters or more), and entitlements; read each container's metadata plist for the owning bundle ID; skip anything whose name contains one of about 150 tokens (`apple`, `icloud`, `cloudkit`, `mobilesync`, `microsoft`, `google`, `homebrew`, `python`, `sparkle`, `sentry`, …). Pearcleaner is on hold since late 2025.
- **How Mole decides** [S] ([apps.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/apps.sh)): an item is an orphan only if all of these hold: not a protected ID; name does not match `*1password*`, `*keychain*`, `*bitwarden*`, `*lastpass*`, `*keepass*`, `*ssh*`, `*gpg*` and similar; bundle ID not among installed apps (including Setapp and Homebrew casks); nothing inside modified in 30 days; `mdfind kMDItemCFBundleIdentifier == '<id>'` finds no app. Any timeout or error means keep. A past bug that cached a timeout as "not installed" deleted live data.
- **Limits:** vendor-named folders with no bundle ID (`Application Support/Adobe`) are missed by ID matching. Group Containers are shared across a vendor's apps by Team ID.

## 4. Risky, disputed and outdated advice

| Advice | Verdict | Why |
|---|---|---|
| Delete everything in `~/Library/Caches` | Risky | Some "caches" are live state or user data: model weights (`llama.cpp`, `Buzz`), Poetry virtualenvs, `pnpm/dlx`, kitty's graphics cache. Removing `com.apple.FontRegistry*`, `com.apple.spotlight*` or `CloudKit*` breaks fonts, search and iCloud sync. Mole hard-protects all of these. Sweep's Caches rule should exclude them by name, not only "Apple caches". |
| Delete `/private/var/folders` | Risky | Live temp files, sockets, pasteboard data. Restart instead; target only known stale items. |
| Delete `/System/Library/Caches` or kernel caches | Harmful | Sealed system volume; can leave the Mac unbootable. [V] |
| Disable SIP to delete Apple Intelligence models | Harmful | Lowers security, models return. Use the asset-service route. |
| Delete `sleepimage`, set `hibernatemode 0`, delete swap files | Outdated, risky | Intel-era advice. Power loss during sleep loses the session; deleting live swap can panic the kernel. |
| `sudo rm -rf ~/Library/Containers/*` | Harmful | Containers hold real app data (Notes, Mail). Only `…/Data/Library/Caches` inside one is cache. |
| Delete `MobileSync/Backup` wholesale | Harmful | Often the only device backup. mac-cleanup-py does this. |
| Delete Xcode Archives | Risky | Loses dSYMs for shipped builds. |
| Delete `~/Library/Mobile Documents` or `~/Library/CloudStorage` files to "free local space" | Harmful | Deletes from the cloud on all devices. Use Remove Download. |
| Delete `~/Library/Mail/V10` | Harmful | That is the mail store, not a cache. |
| Strip unused languages or architectures from apps | Risky, small gain | Modifies signed bundles; can trigger "damaged" dialogs and break updaters. CleanMyMac and Pearcleaner offer it. Tens of MB per app. |
| `docker system prune -a --volumes`; lowering Docker's disk limit | Risky | Deletes database volumes; the limit change wipes all images and containers. |
| Delete Chrome's `weights.bin` | Ineffective alone | Re-downloads unless On-device AI is turned off. |
| Lock the aerial folder with `chflags` | Risky | Reports of broken wallpaper settings and update trouble. |
| `sudo purge` to free disk space | Wrong | It flushes the memory file cache, not disk. |
| Rebuild Spotlight to free space | Disputed | Helps when the index is broken; otherwise hours of indexing for little gain. |
| `tmutil disable`, turning snapshots off | Risky | Removes the safety net. Thin instead. |
| "Clearing caches speeds up your Mac" | Unsupported | Caches rebuild at a one-time cost. No evidence of a speed gain. |
| "Purgeable space is as good as free" | Disputed | Purging is unreliable. [E] |
| "Repair permissions" | Obsolete | Removed from Disk Utility around OS X 10.11. [?] |
| "System Data is mostly caches" | Wrong | Often snapshots, swap, Spotlight journals, AI models or stuck downloads. |
| "A restart or Safe Mode fixes System Data" | Partly true | Clears swap and temp. Recurs when the cause is a bug. |
| `log erase --all`, deleting `knowledgeC.db` | Low value | Small, self-trimming, and tools read them. No evidence of knowledgeC bloat was found. |
| Cleaner apps such as MacKeeper | Context only | Long reputation for scare tactics. [C] |

## 5. Safety rules worth copying

From Mole's design ([SECURITY_DESIGN.md](https://raw.githubusercontent.com/tw93/Mole/main/docs/SECURITY_DESIGN.md), [base.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/core/base.sh), [system.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/system.sh)), DevCleaner, Pearcleaner and pared:

1. Validate every path before deleting: absolute, no `..`, symlinks resolved on the item and all its parents.
2. Never delete inside `/System`, `/usr` (except `/usr/local`), `/bin`, `/sbin`, `/etc`, `/var/db`, or a bare root such as `/Library`, `/Applications`, `~`.
3. Skip `Containers` and `Group Containers` unless the item is a proven orphan; never `com.apple.*`.
4. Protect iCloud Drive and `CloudStorage` by default.
5. A folder named "Caches" is not proof. Keep a hard exclusion list that user settings cannot remove.
6. Check that the owning app or tool is not running before touching its cache.
7. Prefer the owner's command (`brew cleanup`, `pnpm store prune`, `uv cache prune`, `simctl`, `tmutil`) and ask the tool where its cache is.
8. Use age gates: orphans 30 days, installers 14 days, aborted downloads 1 hour.
9. On timeout or error, keep the item.
10. Leave `/Library/Updates`, `/macOS Install Data`, `/private/tmp` and `/private/var/tmp` alone.
11. Dry run first, keep an operation log, and send user-selected items to the Trash where possible. RemoveMacAI does the same and keeps an undo journal.
12. For level 3 items, show enough to decide: device name and date for backups, project and date for archives, branch state for worktrees.
13. Report free space from the APFS container (`df`, `diskutil`), not from Storage settings.

What the tools get wrong, as a warning: mac-cleanup-py mixes level 1, 2 and 3 behind the same prompt (iOS backups, Xcode Archives, Arc cookies and history, Telegram's message database). [S] [default_modules.py](https://raw.githubusercontent.com/mac-cleanup/mac-cleanup-py/main/mac_cleanup/default_modules.py). Pearcleaner's developer view lists `Xcode/UserData` and `Archives` beside caches with no grading.

## 6. Suggested new rules for Sweep

Ordered by expected payoff on Macs like this one, then on Macs in general.

| # | Rule | Level |
|---|---|---|
| 1 | Project build output (`.next`, `dist`, `.turbo`, `target`, …) in projects not opened for N days, with a shorter threshold than `node_modules` | 2 |
| 2 | Git worktree view: per worktree size, age, branch merged or not; offer dependencies and build output | 2 / 3 |
| 3 | Claude Desktop Cowork VM bundle, when Claude is not running | 2 |
| 4 | Stale Chromium `code_sign_clone` folders, when the browser is not running | 1 |
| 5 | Stale automation temp profiles (`$TMPDIR/cdp-*`, `puppeteer_dev_chrome_profile-*`, `playwright_*`) older than a day | 1 |
| 6 | AI tool history view: `~/.claude/projects`, `~/.codex` by project and age | 3 |
| 7 | Apple Intelligence models: detect `UAF_FM_*`, show size, hand off to the asset-service route | 2 |
| 8 | Chrome on-device model, with the setting to turn off | 2 |
| 9 | Time Machine local snapshots older than 24 h via `tmutil thinlocalsnapshots`, keeping the newest | 1 |
| 10 | Aerial videos: size, warning if one is selected, open Wallpaper settings | 2 |
| 11 | macOS installers older than the running system and older than 14 days | 1 |
| 12 | iOS/iPadOS `.ipsw` update files | 1 |
| 13 | iPhone/iPad backups, listed per device with date | 3 |
| 14 | Xcode: device support (keep 2), `simctl delete unavailable`, runtimes, previews, documentation cache, archives (level 3) | 1–3 |
| 15 | Docker/OrbStack: show real size, offer builder and dangling-image prune | 2 |
| 16 | Package caches by owner command: Homebrew, pnpm, uv, pip, yarn classic, Go build cache, CocoaPods, Cargo registry cache | 1–2 |
| 17 | Old versioned binaries (Claude Code, Cursor agent, JetBrains Toolbox), keep current plus one | 1 |
| 18 | Updater caches (`GoogleUpdater/crx_cache`, `*.ShipIt`, Sparkle) | 1 |
| 19 | Local AI models (Ollama, LM Studio, Hugging Face), listed per model | 3 |
| 20 | Large-file and large-folder view for `~/Library/Application Support`, Downloads, Desktop, Documents | 3 |
| 21 | Orphaned app leftovers using Mole's six checks | 2–3 |
| 22 | With Full Disk Access: Messages attachments, Mail downloads, Trash, Telegram, media analysis cache, Spotlight stores | 2–3 |
| 23 | Report-only rows: swap, sleep image, unified log, system snapshot, `/Library/Updates`, with a one-line explanation each | — |

Changes to existing rules:

- **`~/Library/Caches` (3+ days):** add name exclusions for `com.apple.FontRegistry*`, `com.apple.spotlight*`, `CloudKit*`, `llama.cpp`, `Buzz`, `pypoetry/virtualenvs`, `pnpm/dlx`, `ms-playwright`, `Cypress`, `kitty`, `org.R-project.R`.
- **npm cache:** keep `~/.npm/_npx`.
- **`node_modules` (14+ days):** check for open files, and consider "project not opened" instead of folder age.
- **Electron web caches:** leave `Service Worker/ScriptCache`; treat Spotify as level 3.

## 7. Ranked table

Ranked by what a typical 256 GB Mac can expect to reclaim. "—" in the level column means report only.

| # | Consumer | Path | Typical size | Level | How to remove | Permission |
|---|---|---|---|---|---|---|
| 1 | Project dependencies and build output | `node_modules`, `.next`, `dist`, `target`, `.venv`, … | 5–80 GB | 2 | Delete; reinstall or rebuild restores | none |
| 2 | iPhone/iPad backups | `~/Library/Application Support/MobileSync/Backup` | 5–100+ GB | 3 | Finder > Manage Backups | FDA |
| 3 | Photos library | `~/Pictures/Photos Library.photoslibrary` | 10–500 GB | 3 | Optimize Mac Storage setting | FDA |
| 4 | Docker / OrbStack disk image | `~/Library/Containers/com.docker.docker/…/Docker.raw` | 10–64 GB | 2 prune / 3 file | `docker builder prune`, `docker image prune` | none |
| 5 | Xcode simulators, runtimes, previews | `~/Library/Developer/CoreSimulator`, `/Library/Developer/CoreSimulator`, `…/UserData/Previews` | 10–110 GB | 2 | `xcrun simctl delete unavailable`, `simctl runtime delete`, `simctl --set previews delete all` | none / admin |
| 6 | Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData` | 2–50 GB | 1 | Delete (Sweep has this) | none |
| 7 | Aerial wallpaper videos | `/Library/Application Support/com.apple.idleassetsd/Customer`, `~/Library/Application Support/com.apple.wallpaper/aerials/videos` | 10–84 GB | 2 | Wallpaper settings > Remove Download | admin / none |
| 8 | Messages attachments | `~/Library/Messages/Attachments` | 1–100 GB | 3 | Storage > Messages; Keep Messages setting | FDA |
| 9 | Time Machine local snapshots | APFS snapshots | 0–100+ GB | 1 | `tmutil thinlocalsnapshots` | admin |
| 10 | Apple Intelligence models | `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_FM_*` | 9–15 GB, up to 20+ | 2 | Asset-service reset plus profile (pared, RemoveMacAI); Settings on macOS 15/26 | SIP for files; none for the supported route |
| 11 | Local AI models | `~/.ollama/models`, `~/.lmstudio/models`, `~/.cache/huggingface/hub` | 4–100 GB | 3 | `ollama rm`, `hf cache rm`, in-app | none |
| 12 | VM disks and games | `*.pvm`, `*.utm`, `steamapps/common` | 20–200 GB | 3 | In the app | none |
| 13 | Git worktrees and old repos | anywhere | varies | 3 | `git worktree remove` | none |
| 14 | macOS installer | `/Applications/Install macOS *.app` | 13–15 GB | 1–2 | Delete | none / admin |
| 15 | AI coding tool VM | `~/Library/Application Support/Claude/vm_bundles` | 10 GB+ | 2 | Delete with Claude closed | none |
| 16 | AI coding tool history | `~/.claude/projects`, `~/.codex` | 1–15 GB | 3 | Per project | none |
| 17 | Xcode device support | `~/Library/Developer/Xcode/* DeviceSupport` | 5–20 GB | 2 | Delete all but newest two | none |
| 18 | Xcode Archives | `~/Library/Developer/Xcode/Archives` | 1–50 GB | 3 | Organizer | none |
| 19 | Per-user temp area | `/private/var/folders/*/*/{T,X,C}` | 1–10 GB | 1 for known stale items | Restart; targeted rules | none |
| 20 | iOS/iPadOS update files | `~/Library/iTunes/*Software Updates` | 4–10 GB each | 1 | Delete | none |
| 21 | GarageBand/Logic sounds | `/Library/Application Support/GarageBand`, `/Library/Application Support/Logic`, `/Library/Audio/Apple Loops` | 2–70 GB | 2–3 | Storage > Music Creation; Sound Library Manager | admin |
| 22 | Mail store and downloads | `~/Library/Mail`, `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads` | 1–50 GB | 3 / 2 | Mail settings; delete downloads | FDA |
| 23 | iCloud Drive and cloud-storage local copies | `~/Library/Mobile Documents`, `~/Library/CloudStorage` | varies | 2 evict | Remove Download | FDA |
| 24 | Package manager caches | `~/.npm`, pnpm store, `~/.cache/uv`, Homebrew, pip, Yarn, Go, Cargo, CocoaPods | 2–20 GB | 1–2 | Owner commands | none |
| 25 | Chrome on-device AI model | `…/Google/Chrome/OptGuideOnDeviceModel` | about 4 GB | 2 | Turn off On-device AI, then delete | none |
| 26 | Browser and Electron caches | `<profile>/Cache`, `Code Cache`, … | 1–10 GB | 1 | Delete when app is closed (Sweep has this) | none |
| 27 | Telegram, WhatsApp media | `~/Library/Group Containers/*Telegram*`, `*whatsapp*` | 1–30 GB | 2–3 | In-app storage settings | FDA |
| 28 | Leftovers of deleted apps | `~/Library/{Application Support,Containers,Group Containers,…}` | 0.1–20 GB | 2–3 | Orphan checks, then Trash | FDA |
| 29 | Media analysis cache, Spotlight stores | `~/Library/Containers/com.apple.mediaanalysisd/…/Caches`, `~/Library/Metadata/CoreSpotlight` | small; 15–140 GB when broken | 2 | Delete cache; `mdutil -E` | FDA / admin |
| 30 | `~/Library/Caches` | `~/Library/Caches` | 1–10 GB | 1 with exclusions | Delete (Sweep has this) | none |
| 31 | Adobe media cache | `~/Library/Application Support/Adobe/Common/Media Cache Files` | 1–50 GB | 1 | Delete with Adobe apps closed | none |
| 32 | Updater caches, old tool versions | `GoogleUpdater/crx_cache`, `*.ShipIt`, `~/.local/share/claude/versions` | 0.5–3 GB | 1 | Delete | none |
| 33 | Voices, dictation, translation languages | `/System/Library/AssetsV2/…` | 0.5–5 GB | 2 | Settings panes only | SIP for files |
| 34 | Logs and diagnostic reports | `~/Library/Logs`, `/Library/Logs/DiagnosticReports` | 0.1–2 GB | 1 when old | Delete (Sweep has this) | none / admin |
| 35 | Swap | `/System/Volumes/VM/swapfile*` | 1–10 GB; 270 GB in a leak | — | Restart | — |
| 36 | Sleep image | `/private/var/vm/sleepimage` | 2 GB to RAM size | — | Leave | — |
| 37 | Unified log | `/private/var/db/diagnostics`, `uuidtext` | 0.5–2.5 GB | — | Leave | — |
| 38 | Staged updates, install data | `/Library/Updates`, `/macOS Install Data` | 0–22 GB | — | Software Update | SIP in part |
| 39 | System snapshot, Preboot, Recovery | APFS volumes | about 25 GB | — | Not removable | SIP |

## 8. Open questions

- The real saving from Chrome's `code_sign_clone` folders (APFS clones) and the reason they are left behind.
- Whether deleting the Claude Cowork VM bundle loses anything beyond the VM's own state. No official statement exists.
- `brctl evict` on macOS 27: check `man brctl`.
- `xcrun simctl runtime delete --notUsedSinceDays`: check `--help` on a Mac with Xcode.
- OrbStack's disk-reclaim behaviour, Podman machine path, Draw Things / DiffusionBee / ComfyUI paths.
- VS Code `workspaceStorage` semantics.
- How much space typically sits behind Full Disk Access (Messages, Mail, Photos, containers) on an average Mac.

## 9. Sources

**Apple**
- [Free up storage space on Mac](https://support.apple.com/en-us/102624)
- [Locate and manage iPhone/iPad backups](https://support.apple.com/en-us/108809)
- [Photos: Optimize Mac Storage](https://support.apple.com/guide/photos/phtf5e48489c)
- [Messages settings](https://support.apple.com/guide/messages/icht20001/mac)
- [Spoken Content voices](https://support.apple.com/guide/mac-help/mchlp2290), [Translation languages](https://support.apple.com/guide/mac-help/mchldd8b3c15)
- Apple Developer Forums: [simulator runtimes](https://developer.apple.com/forums/thread/812992), [simulator cleanup](https://developer.apple.com/forums/thread/773153), [previews storage](https://developer.apple.com/forums/thread/682439), [Spotlight System Data](https://developer.apple.com/forums/thread/796568), [Xcode storage](https://developer.apple.com/forums/thread/812408)
- Apple Support Communities: [Apple Intelligence 9.24 GB](https://discussions.apple.com/thread/256150006), [mediaanalysisd cache](https://discussions.apple.com/thread/255835917), [hidden root logs](https://discussions.apple.com/thread/256060273), [aerial duplicates](https://discussions.apple.com/thread/256139061), [GarageBand library](https://discussions.apple.com/thread/8197069)

**Eclectic Light Co (Howard Oakley)**
- [What is System Data in Storage settings?](https://eclecticlight.co/2025/02/11/what-is-system-data-in-storage-settings/)
- [Explainer: Storage settings](https://eclecticlight.co/2025/12/20/explainer-storage-settings/)
- [Why did that macOS upgrade take so much space?](https://eclecticlight.co/2025/10/02/why-did-that-macos-upgrade-take-so-much-space/)
- [Aren't snapshots purgeable?](https://eclecticlight.co/2026/08/24/arent-snapshots-purgeable/), [Why can purging snapshots fail?](https://eclecticlight.co/2026/08/27/why-can-purging-snapshots-fail/), [Take control of snapshots](https://eclecticlight.co/2026/09/09/take-control-of-snapshots/)
- [The Finder's inaccurate free-space figures](https://eclecticlight.co/2023/04/17/the-finder-confuses-with-wildly-inaccurate-figures-for-available-space/)
- [iCloud Drive: Optimise Mac Storage or not?](https://eclecticlight.co/2024/03/11/icloud-drive-in-sonoma-optimise-mac-storage-or-not/)
- [Inside the Unified Log 3: storage and attrition](https://eclecticlight.co/2025/09/29/inside-the-unified-log-3-log-storage-and-attrition/)
- [When and how to rebuild Spotlight indexes](https://eclecticlight.co/2024/11/19/when-and-how-to-rebuild-spotlight-indexes/)
- [AI cryptexes](https://eclecticlight.co/2025/07/09/cryptexes-ai-and-creedence-clearwater-revival/)

**Cleaner source code and docs**
- pared: [repo](https://github.com/4evy/pared), [how-it-works.md](https://raw.githubusercontent.com/4evy/pared/master/docs/how-it-works.md)
- RemoveMacAI: [repo](https://github.com/omlahore/RemoveMacAI), [README](https://raw.githubusercontent.com/omlahore/RemoveMacAI/main/README.md)
- Mole: [repo](https://github.com/tw93/Mole), [SECURITY_DESIGN.md](https://raw.githubusercontent.com/tw93/Mole/main/docs/SECURITY_DESIGN.md), [base.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/core/base.sh), [system.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/system.sh), [apps.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/apps.sh), [purge_shared.sh](https://raw.githubusercontent.com/tw93/Mole/main/lib/clean/purge_shared.sh), [clean-dev.md](https://github.com/tw93/Mole/blob/main/.claude/rules/clean-dev.md), issues [#1253](https://github.com/tw93/Mole/issues/1253), [#537](https://github.com/tw93/Mole/issues/537)
- Pearcleaner: [repo](https://github.com/alienator88/Pearcleaner), [Locations.swift](https://raw.githubusercontent.com/alienator88/Pearcleaner/main/Pearcleaner/Logic/Locations.swift), [Conditions.swift](https://raw.githubusercontent.com/alienator88/Pearcleaner/main/Pearcleaner/Logic/Conditions.swift)
- DevCleaner for Xcode: [repo](https://github.com/vashpan/xcode-dev-cleaner)
- mac-cleanup-py: [default_modules.py](https://raw.githubusercontent.com/mac-cleanup/mac-cleanup-py/main/mac_cleanup/default_modules.py)
- OnyX: [vendor page](https://www.titanium-software.fr/en/onyx.html) (option list not verified)
- CleanMyMac: [System Junk list](https://macpaw.com/support/cleanmymac/knowledgebase/system-junk-cleanup-list) (vendor)
- Manual AI model deletion with SIP off (not recommended): [tejyash/delete-apple-intelligence-macos](https://github.com/tejyash/delete-apple-intelligence-macos)

**Tool documentation**
- [Homebrew manpage](https://docs.brew.sh/Manpage), [npm cache](https://docs.npmjs.com/cli/v10/commands/npm-cache), [pnpm store](https://pnpm.io/cli/store), [uv cache](https://docs.astral.sh/uv/concepts/cache/), [Playwright browsers](https://playwright.dev/docs/browsers)
- [docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/), [Docker Desktop Mac FAQ](https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/)
- [Cargo home](https://doc.rust-lang.org/cargo/guide/cargo-home.html), [Gradle directories](https://docs.gradle.org/current/userguide/directory_layout.html), [Hugging Face cache](https://huggingface.co/docs/huggingface_hub/guides/manage-cache), [Ollama FAQ](https://raw.githubusercontent.com/ollama/ollama/main/docs/faq.mdx), [Claude Code settings](https://code.claude.com/docs/en/settings)

**Press, forums, blogs**
- MacRumors: [Strip Apple Intelligence from macOS 27](https://www.macrumors.com/2026/10/06/strip-apple-intelligence-from-macos-27/), [Apple Intelligence storage, macOS 15.4](https://www.macrumors.com/2025/03/17/apple-intelligence-storage-space-macos-15-4/), [Chrome's hidden 4 GB file](https://www.macrumors.com/how-to/stop-chrome-downloading-hidden-4gb-file/), [swap leak thread](https://forums.macrumors.com/threads/tahoe-endlessly-consumes-all-free-space-270-gb-on-macbook-pro.2465906/), [aerials 26 GB](https://forums.macrumors.com/threads/wallpaper-screensavers-take-up-26gb-how-to-delete.2431871)
- The Register: [Chrome installs a 4 GB local model](https://www.theregister.com/ai-and-ml/2026/05/07/chrome-silently-installs-a-4-gb-local-llm-on-your-computer/5230893)
- Michael Tsai: [Spotlight storage](https://mjtsai.com/blog/?p=48557), [mediaanalysisd](https://mjtsai.com/blog/?p=48375)
- dev.to: [84 GB of aerial videos, duplicated](https://dev.to/frr149/apple-installed-84gb-of-jellyfish-on-my-mac-duplicated-nf4)
- GitHub: [Claude Cowork VM size](https://github.com/anthropics/claude-code/issues/22543)
- Reddit (mirror only): [100 GB of iMessage attachments](https://redlib.hbubli.cc/r/MacOS/comments/1etid2l/imessage_attachments_taking_up_100gb_on_macos)
