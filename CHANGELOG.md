# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

_No changes yet._

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
