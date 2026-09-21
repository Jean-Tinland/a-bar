# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

_No changes yet._

## v1.6.0 - 2026-09-21

- chore: deadcode removal
- fix: a single unrecognised value in the config no longer resets every setting - unknown widgets, themes and malformed values are now repaired one value at a time
- fix: a config file that cannot be read is preserved and quarantined instead of being overwritten with defaults, with the last known good config kept as a backup
- fix: launch at login had no effect - the toggle was wired to a local state while the app unregistered the login item on every settings change
- fix: the menu bar bar-visibility toggle and the AppleScript widget commands now persist, and are no longer reverted by the next save from Preferences
- fix: layouts saved from before the profile system are recovered instead of silently reset
- fix: selecting a profile to edit no longer marks its layout as modified, which could write it to the wrong profile
- refactor: the config file is now the single source of truth with one writer, defaults come only from the property initializers, and profile invariants are enforced on every load
- test: add a unit test target covering settings decoding, repair, migration and persistence
- feat: refactor Wi-Fi functionality into a dedicated service like the Bluetooth widget
- ci: run the test suite on every push and pull request, and fail the build when a test file is not a member of the test target
- test: cover widget layout accessors, graph history, AeroSpace decoding and theme colour handling
- fix: a custom widget script that prints more than 64KB no longer hangs until its timeout and comes back cut off - its output is now read while the script runs
- fix: an unreadable colour value is no longer rendered fully transparent, which made the widget disappear instead of showing a colour that could be corrected
- fix: colour values no longer lose a step per channel each time they are saved, which made a customised theme drift darker over repeated edits
- test: cover yabai state filtering, the formatting and colour helpers, and shell command execution
- fix: a custom widget script whose output uses Windows line endings now shows its dropdown instead of printing the whole script into the bar with stray characters
- test: cover xbar-style script output parsing, and split the parser from its menu building
- fix: a new profile name that differs from an existing one only by surrounding spaces is now recognised as a duplicate instead of being accepted
- fix: update button style to bordered for Bluetooth and Wi-Fi widgets
- refactor: the layout builder's drag payload, reordering and custom-widget index handling moved out of the views into tested logic
- test: cover layout drag and drop, widget reordering, custom-widget index remapping and profile name validation
- fix: a critically low battery now shows red - the warning was unreachable, so a battery at 2% looked the same as one at 45%
- fix: an AeroSpace space that is visible but not focused no longer draws a stray dark rectangle behind its background
- fix: a long single-word keyboard layout name is now shortened instead of pushing the rest of the bar along
- refactor: widget colours, labels, weather presentation and graph geometry moved out of the views into tested logic, removing several branches that could never be reached
- test: cover widget threshold colours, volume handling, bar labels, weather presentation, graph points and bar placement

## v1.5.2 - 2026-09-20

- fix: update color handling in Bluetooth widget for better visibility and consistency

## v1.5.1 - 2026-09-20

- fix: declare NSBluetoothAlwaysUsageDescription so the app no longer crashes at launch on macOS

## v1.5.0 - 2026-09-19

- feat: add bluetooth widget with paired devices popover, battery levels and power toggle

## v1.4.3 - 2026-06-14

- refactor: duplicated code cleanup and utilities centralization in widgets, settings and services

## v1.4.2 - 2026-06-12

- feat: enhance widget refresh and cycle duration handling with minimum constraints + update app signing in release script

## v1.4.1 - 2026-04-10

- feat: implement timed signal action for yabai commands to prevent hangs

## v1.4.0 - 2026-04-10

- feat: revamp custom widget system with a XBar inspired API

## v1.3.8 - 2026-03-12

- fix: handle monitor ID mapping by screen name for Aerospace widgets

## v1.3.7 - 2026-02-17

- feat: add several new color themes
- refactor: remove unused highlight color from theme
- fix: update font settings in MicWidget and SoundWidget to use global settings

## v1.3.6 - 2026-02-16

- fix: make caffeinate toggle work again
- fix: ensure github widget keeps refreshing when hidden in absence of notification
- fix: ensure custom user widgets keeps polling for notifications even when hidden

## v1.3.5 - 2026-02-14

- refactor: update AppLogo assets and improve calendar access description

## v1.3.4 - 2026-02-13

- feat: add a scale effect while clicking on interactive widgets
- feat: add bar element background opacity setting and apply it across widgets
- feat: enable border display in global settings by default
- feat: add showElementsBorder setting and apply it across widgets
- feat: add NSCalendarsUsageDescription for calendar access in widgets

## v1.3.3 - 2026-02-13

- fix: add missing onSave method when creating a new custom widget

## v1.3.2 - 2026-02-12

- feat: add audio device names to MicWidget and SoundWidget
- feat: enhance bar layout and settings with global configurations for padding, corner radius, and background options
- refactor: improve BarEditorSheet layout with scrollable sections and fixed available widgets area
- refactor: remove redundant background color from GraphView
- refactor: adjust padding and add divider in CustomWidgetEditorView header
- refactor: update CreateSpaceButton styling for improved visibility
- fix: add horizontal padding to window elements in ProcessWidget for better spacing

## v1.3.1 - 2026-02-11

- feat: implement termination of existing a-bar instances to prevent multiple processes
- refactor: optimize refresh method to improve layout handling and reduce memory pressure
- refactor: enhance volume refresh method to run asynchronously for improved performance
- refactor: update refreshMemory method to run asynchronously for improved responsiveness
- refactor: improve caffeinate killing function for better performance
- refactor: enhance icon lookup method for improved performance and responsiveness
- refactor: enhance shell command execution with timeout handling for improved reliability
- refactor: improve DateWidget timer management for better resource handling
- refactor: improve timer management in TimeWidget for better resource handling
- refactor: enhance WifiWidget to refresh SSID asynchronously for improved performance
- refactor: update menu bar icon size and replace SVG with new design
- refactor: enhance BatteryIconView with background color and shadow effects

## v1.3.0 - 2026-02-10

- feat: integrate Aerospace window manager support
- feat: update Sound, Mic & HackerNews widgets positioning to support dynamic bar position adjustments
- fix: show layout mode indicator even if space is empty
- refactor: improve widget reordering widgets in the bar editor
- refactor: update bar separator color to use foreground opacity for improved visibility
- refactor: update dayShift theme colors for improved contrast and consistency
- refactor: add extra light borders to BaseWidgetView, ProcessWidget and SpaceView
- refactor: adjust space background opacity for improved visibility
- refactor: enhance chevron button with hover effects and tooltip in HackerNewWidget

## v1.2.0 - 2026-02-09

- fix: enhance YabaiService with JSON cleanup and filtering for spaces, windows, and displays
- feat: add Hacker News widget with customizable settings and integration
- refactor: enhance signal handling in YabaiService
- feat: add microphone control functionality in SystemInfoService
- feat: enhance MicWidget with popover functionality for microphone control
- fix: prevent layout vanishing when saving other settings

## v1.1.1 - 2026-02-06

- fix: remove unnecessary WidgetSeparator from SpacesWidget when displaying sticky windows
- refactor: remove unused WidgetIcon and WidgetSeparator structs from WidgetContainer
- refactor: add detailed comments in multiple files
- refactor: remove debug print statements from various services and widgets
- refactor: increase signal timer interval from 5 to 20 seconds for improved performance
- fix: enhance `caffeinate` management by checking system-wide processes
- fix: cache host port to prevent Mach port leaks and improve system stability
- refactor: remove unused variable assignments in SystemInfoService and CustomWidgetEditorView

## v1.1.0 - 2026-02-04

- feat: add profile system for multiple layout configurations
- chore: update logo
- fix: correct padding direction in NetstatsWidget for better layout

## v1.0.6 - 2026-02-04

- feat: add Disk Activity widget

## v1.0.5 - 2026-02-04

- fix: update signal handling in YabaiService

## v1.0.4 - 2026-02-04

- refactor: remove AccessibilityHelper and WindowAXObserver, update YabaiSettingsView to eliminate accessibility prompts
- feat: add commands for toggling, hiding, and showing custom widgets; update refresh command description

## v1.0.3 - 2026-02-03

- refactor: integrate AccessibilityHelper into YabaiSettingsView and remove AccessibilityPromptView

## v1.0.2 - 2026-02-03

- refactor: remove Sparkle integration and updater service from the project

## v1.0.1 - 2026-02-03

- fix: enhance AccessibilityHelper with continuous monitoring

## v1.0.0 - 2026-02-03

- Initial release of the project.
