# <img src="./images/a-bar-logo.png" width="200" alt="a-bar" />

Yet **a(nother) bar** :)

A native macOS menu bar replacement inspired by [simple-bar](https://github.com/Jean-Tinland/simple-bar), built with Swift and SwiftUI. It is a standalone recreation of simple-bar with a focus on performance, stability, and extensibility.

<img width="1680" alt="a-bar-preview" src="./images/a-bar-preview.jpg">

## Features

### Window Management Integration

- **Yabai Integration**: Full support for [yabai](https://github.com/koekeishiya/yabai) window manager
  - Display workspaces and processes with app icons
  - Click to switch spaces or focus windows
  - Rename, move, and manage spaces via context menu
  - Show/hide empty spaces
  - Sticky windows support

### System Information Widgets

- **Process**: Shows currently focused application
- **Battery**: Battery percentage with charging indicator, caffeinate toggle
- **Weather**: Current conditions from Open-Meteo with auto-location
- **Time**: Digital clock with optional day progress
- **Date**: Current date with calendar app integration
- **WiFi**: Network status with toggle support
- **Sound**: Volume level indicator
- **Microphone**: Mic input level
- **Keyboard**: Current keyboard layout
- **GitHub**: Notification count (requires `gh` CLI)

### Performance Graphs

- **CPU**: Real-time CPU usage graph
- **Memory**: Memory usage with pie chart visualization
- **GPU**: GPU utilization
- **Network Stats**: Upload/download speed graphs
- **Storage usage**: Disk and external devices space usage indicator

### Customization

- **2 Built-in Themes**: Night Shift and Day Shift
- **Custom Colors**: Override any theme color
- **Layout Configurator**: Manage up to 2 bars (top and bottom) on your built-in display or external monitors thanks to a new "Layout builder"
- **Widget Ordering**: Drag-and-drop to reorder widgets
- **Per-widget Settings**: Fine-tune each widget's behavior
- **Custom Widgets**: Create shell command-based widgets

## Requirements

- macOS 13.0 or later
- [yabai](https://github.com/koekeishiya/yabai) (for window management features)
- [gh CLI](https://cli.github.com/) (optional, for GitHub notifications)

## Installation

### From Release

1. Download the latest release from the [Releases](https://github.com/Jean-Tinland/a-bar/releases) page
2. Move `a-bar.app` to `/Applications`
3. Launch a-bar
4. As the app is not notarized, after launching the app for the first time, you will need to:
   - Open `System Settings` > `Privacy & Security`
   - Click `Open Anyway` next to the a-bar warning
5. Grant necessary permissions when prompted

### Build from Source

```bash
# Clone the repository
git clone https://github.com/Jean-Tinland/a-bar.git
cd a-bar

# Open in Xcode
open a-bar.xcodeproj

# Build and run (⌘R)
```

## Configuration

There is no need to enable yabai signals in your yabai configuration as a-bar uses the available native macOS APIs to monitor space and window changes and query yabai only when necessary.

a-bar is also able to detect windows of the same app focus changes but you'll need to add a-bar to the list of trusted accessibility clients in `System Settings` > `Privacy & Security` > `Accessibility`. A message will be shown in the "yabai" section of the settings if this permission is not granted.

## Widget Configuration

### Native widgets

Configure built-in widgets via the settings panel: each widget has its own settings view accessible in the "Widgets" section.

### Custom Widgets

Create shell command-based widgets with:

- Custom label and icon (label will be used for targeting in AppleScript)
- Shell command for output
- Click action command
- Configurable refresh interval

**AppleScript Support**: Programmatically refresh custom widgets using AppleScript:

```applescript
tell application "a-bar" to refresh "My Widget"
```

From the command line, you can use:

```shell
osascript -e 'tell application "a-bar" to refresh "My Widget"'
```

## Contributing

Contributions are welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

GPL-3.0 license - see [LICENSE](LICENSE) for details.

## Credits

- Inspired by [simple-bar](https://github.com/Jean-Tinland/simple-bar)
- [yabai](https://github.com/koekeishiya/yabai) by koekeishiya
