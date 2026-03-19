# termo

Native macOS terminal shell with:
- real Ghostty surfaces
- a web-driven sidebar host
- vertical session tabs and split panes

Setup

1. Install required tools:

```bash
brew install xcodegen
```

2. Make sure Xcode and Metal tooling are ready:

```bash
xcodebuild -runFirstLaunch
xcrun -sdk macosx metal --version
```

3. Build the web shell, GhosttyKit, and Xcode project:

```bash
./scripts/setup.sh
```

4. Build and run the app:

```bash
open termo.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project termo.xcodeproj -scheme termo -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/termo-*/Build/Products/Debug/termo.app
```

Notes

- `./scripts/setup.sh` uses `zig` by default; if needed it will also use `.tooling/zig-aarch64-macos-0.15.2/zig`
- if GhosttyKit is already built at `ghostty/macos/GhosttyKit.xcframework`, setup skips rebuilding it
- to rebuild the web UI only, run `cd electrobun && npm run build`
