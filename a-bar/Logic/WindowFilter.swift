import Foundation

/// The exclusion rules a user types once and five widgets apply.
///
/// `exclusions`, `titleExclusions` and `exclusionsAsRegex` are three fields in one settings
/// panel, but yabai's spaces row, yabai's opened-apps row, AeroSpace's workspaces row and
/// AeroSpace's opened-apps row each read and interpreted them on their own, in five copies that
/// were not identical. The disagreements were invisible from the settings panel: the same
/// pattern hid an app under one window manager and left it on screen under the other.
///
/// Filtering is shared; each widget chooses its own ordering separately.
///
/// Generic over key paths rather than a protocol: `YabaiWindow` and `AerospaceWindow` spell the
/// same two fields `app`/`appName` and `title`/`windowTitle`, and neither is worth a conformance
/// - nor is the two-field struct a test wants to pass in.
enum WindowFilter {

  /// How a pattern is compared when the user has *not* asked for regular expressions.
  enum LiteralMatch {
    /// The value must equal the pattern. How app names and space labels are compared, so that
    /// excluding `1` does not also hide space `12`.
    case whole

    /// The pattern need only appear somewhere in the value. How window titles are compared,
    /// because a title is a sentence and nobody types one out in full.
    case anywhere
  }

  // MARK: - Reading the field

  /// Split one of the comma-separated exclusion fields into patterns.
  ///
  /// Empty entries are dropped. `split` already discards the empty piece a bare trailing comma
  /// leaves behind, but `"Finder, "` splits into `["Finder", " "]` and that second entry trims
  /// to `""`. An empty regular expression matches every string, so with regex mode on, a
  /// trailing comma and a space - what the field looks like for as long as it takes to type the
  /// next name - hid every space and every app in the bar.
  static func patterns(from field: String) -> [String] {
    field
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
  }

  /// Does `value` match any of these patterns?
  ///
  /// A regular expression that does not parse matches nothing rather than throwing: the field is
  /// being typed into live, so it spends most of its time half-written.
  static func isExcluded(
    _ value: String, by patterns: [String], asRegex: Bool, literal: LiteralMatch
  ) -> Bool {
    patterns.contains { pattern in
      if asRegex {
        return value.matches(pattern: pattern)
      }
      switch literal {
      case .whole: return value == pattern
      case .anywhere: return value.contains(pattern)
      }
    }
  }

  // MARK: - Filtering

  /// Keep the spaces or workspaces whose label the user has not excluded.
  ///
  /// The same `exclusions` field also names apps, in `excludingWindows` below. That is one field
  /// doing two jobs, which is how the settings panel has always presented it.
  static func excludingLabels<Item>(
    _ items: [Item], excluding field: String, asRegex: Bool, label: KeyPath<Item, String>
  ) -> [Item] {
    let labelPatterns = patterns(from: field)
    guard !labelPatterns.isEmpty else { return items }
    return items.filter {
      !isExcluded($0[keyPath: label], by: labelPatterns, asRegex: asRegex, literal: .whole)
    }
  }

  /// Keep the windows whose app name and title the user has not excluded.
  ///
  /// App names are compared whole and titles by substring. The asymmetry is deliberate and both
  /// window managers have always had it - an app name is a short fixed string the user can type
  /// exactly, a window title is not.
  static func excludingWindows<Window>(
    _ windows: [Window],
    excludingApps appField: String,
    excludingTitles titleField: String,
    asRegex: Bool,
    appName: KeyPath<Window, String>,
    title: KeyPath<Window, String>
  ) -> [Window] {
    let appPatterns = patterns(from: appField)
    let titlePatterns = patterns(from: titleField)
    guard !appPatterns.isEmpty || !titlePatterns.isEmpty else { return windows }

    return windows.filter { window in
      let appExcluded = isExcluded(
        window[keyPath: appName], by: appPatterns, asRegex: asRegex, literal: .whole)
      let titleExcluded = isExcluded(
        window[keyPath: title], by: titlePatterns, asRegex: asRegex, literal: .anywhere)
      return !appExcluded && !titleExcluded
    }
  }

  /// Keep the first window of each app and drop the rest.
  ///
  /// First, not last: the icon row is already in the order the user is about to read it, and the
  /// window that opened the app is the one they expect the icon to focus.
  static func deduplicatedByApp<Window>(
    _ windows: [Window], appName: KeyPath<Window, String>
  ) -> [Window] {
    var seen = Set<String>()
    return windows.filter { seen.insert($0[keyPath: appName]).inserted }
  }

  // MARK: - Ordering

  /// Order windows the way they sit on screen: down a stack first, then left to right.
  ///
  /// A window with no reported stack index is treated as index 0, which is what yabai itself
  /// reports for a window that is not in a stack - the badge in the process widget hides on
  /// exactly that value. The comparator this replaces instead fell back to comparing x whenever
  /// *either* window lacked an index, and that is not an ordering: given A(stack 1, x 10),
  /// B(stack 2, x 5) and C(no stack, x 7) it claims A < B, B < C and C < A at once, leaving
  /// `sort` free to return any arrangement at all.
  ///
  /// Ties are broken by the order the windows arrived in. `sort` is not stable, and two windows
  /// sharing a stack position and an x - overlapping floating windows - would otherwise swap
  /// places between refreshes for no reason the user can see.
  static func orderedByStackThenPosition<Window>(
    _ windows: [Window], stackIndex: KeyPath<Window, Int?>, x: KeyPath<Window, Double>
  ) -> [Window] {
    windows.enumerated()
      .sorted { lhs, rhs in
        let lhsStack = lhs.element[keyPath: stackIndex] ?? 0
        let rhsStack = rhs.element[keyPath: stackIndex] ?? 0
        if lhsStack != rhsStack { return lhsStack < rhsStack }

        let lhsX = lhs.element[keyPath: x]
        let rhsX = rhs.element[keyPath: x]
        if lhsX != rhsX { return lhsX < rhsX }

        return lhs.offset < rhs.offset
      }
      .map { $0.element }
  }
}
