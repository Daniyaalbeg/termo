# termo

Native macOS terminal shell with:
- real Ghostty surfaces
- a web-driven sidebar host
- vertical session tabs and split panes

Quick start

```bash
git clone https://github.com/Daniyaalbeg/termo.git && cd termo && npm start
```

Requirements

- macOS
- Xcode command line tools and first-launch setup completed
- Node.js and npm

Manual setup

1. Install required tools if you want to regenerate the Xcode project:

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
npm run setup
```

4. Build the app without opening it:

```bash
npm run build
```

5. Build and run the app:

```bash
npm start
```

Notes

- `npm start` bootstraps `electrobun`, builds the web UI, builds GhosttyKit if needed, builds the macOS app into `DerivedData/`, and opens `termo.app`
- `./scripts/setup.sh` uses `zig` by default; if needed it will also use `.tooling/zig-aarch64-macos-0.15.2/zig`
- if GhosttyKit is already built at `ghostty/macos/GhosttyKit.xcframework`, setup skips rebuilding it
- to rebuild the web UI only, run `npm run build:web`
