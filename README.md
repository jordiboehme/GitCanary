# GitCanary

A native macOS menu bar app that monitors git repositories and provides AI-generated summaries of changes on remote/origin since last pulled. Early warning about what's coming from remote.

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/V7V31T6CL9)

## Features

Coming soon.

## Installation

### Homebrew (recommended)

```bash
brew tap jordiboehme/tap
brew install --cask gitcanary
```

### Download

Grab the latest DMG from [GitHub Releases](https://github.com/jordiboehme/GitCanary/releases), open it, and drag GitCanary to Applications.

### Build from Source

```bash
git clone https://github.com/jordiboehme/GitCanary.git
cd GitCanary
xcodebuild -project GitCanary/GitCanary.xcodeproj -scheme GitCanary -configuration Release build CONFIGURATION_BUILD_DIR=build
```

Then move `build/GitCanary.app` to `/Applications` and launch it.

## Requirements

- **macOS 14 Sonoma** or later

## License

MIT License — See [LICENSE](LICENSE) for details.
