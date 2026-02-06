# Changelog

All notable changes to this project will be documented in this file.

## Unreleased

<!-- _No changes yet._ -->

- fix: remove unnecessary WidgetSeparator from SpacesWidget when displaying sticky windows
- refactor: remove unused WidgetIcon and WidgetSeparator structs from WidgetContainer
- refactor: add detailed comments in multiple files
- refactor: remove debug print statements from various services and widgets
- refactor: increase signal timer interval from 5 to 20 seconds for improved performance
- fix: enhance `caffeinate` management by checking system-wide processes

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
