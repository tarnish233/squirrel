//
//  SquirrelScrollMode.swift
//  Squirrel
//
//  Scroll mode (卷轴模式) for the horizontal linear layout.
//
//  Paging expands the single candidate row into a grid of up to `max_rows`
//  rows. Every row is exactly one librime page, so navigation stays in
//  librime: ←/→ move by candidate, ↑/↓ and the paging keys move by row while
//  keeping the column, and digits select from the highlighted row. The
//  frontend only renders the neighbouring pages, maps Tab / Shift+Tab to
//  paging (like WeType), and collapses the grid when moving up from the
//  first row.
//

import Foundation

/// Settings under `style/scroll_mode`.
struct SquirrelScrollSettings {
  /// Only takes effect with `candidate_list_layout: linear` and `text_orientation: horizontal`.
  var enabled = false
  /// Maximum number of rows (pages) visible while expanded.
  var maxRows = 5
  /// Like WeType's "Tab / Shift+Tab to turn pages": while candidates are shown,
  /// Tab moves to the next row (expanding the grid) and Shift+Tab to the previous one.
  var tabPaging = true
  /// Minimum width of a grid column in points, so that short candidates line up in even cells;
  /// longer ones still widen their column.
  var columnWidth: CGFloat = 0

  static let rowLimit = 2...20
}

/// What the panel needs to lay out an expanded grid.
struct SquirrelScrollLayout {
  /// Candidates per row, i.e. librime's page size.
  let rowSize: Int
  /// Visible row holding the highlighted candidate; labels and digit keys apply to this row only.
  let highlightedRow: Int
  /// Whether more rows exist above or below the visible ones.
  let hasRowsAbove: Bool
  let hasRowsBelow: Bool
  /// Identifies one expansion, so the panel can keep column widths stable while scrolling.
  let generation: Int
}

/// Expansion state of one input session.
struct SquirrelScrollState {
  private(set) var expanded = false
  /// librime page shown in the first visible row.
  private(set) var topRow = 0
  private(set) var generation = 0
  /// librime page of the highlighted candidate after the last update.
  private(set) var page = 0
  /// Whether the last update showed candidates.
  private(set) var hasCandidates = false
  /// Global index of the first displayed candidate while expanded.
  private(set) var firstIndex: Int?
  /// Identifies the candidate list; a new list collapses the grid.
  private var listKey: String?

  /// Moving up from the first row collapses the grid.
  var canCollapse: Bool {
    expanded && page == 0
  }

  mutating func reset() {
    collapse()
    hasCandidates = false
    listKey = nil
    page = 0
  }

  mutating func collapse() {
    expanded = false
    topRow = 0
    firstIndex = nil
  }

  /// Records librime's current page and returns the pages to show, or nil while collapsed.
  mutating func update(listKey: String, page: Int, lastPage: Bool, maxRows: Int) -> Range<Int>? {
    if listKey != self.listKey {
      collapse()
      self.listKey = listKey
    }
    hasCandidates = true
    self.page = page
    if page > 0 && !expanded {
      expanded = true
      generation &+= 1
      topRow = 0
    }
    // A single page has nothing to expand.
    guard expanded && (page > 0 || !lastPage) else {
      collapse()
      return nil
    }
    if page < topRow {
      topRow = page
    } else if page >= topRow + maxRows {
      topRow = page - maxRows + 1
    }
    return topRow..<(topRow + maxRows)
  }

  mutating func show(from index: Int?) {
    firstIndex = index
  }
}

extension RimeApi_stdbool {
  /// Reads up to `count` candidates of the current menu, starting at the global `index`.
  func candidates(of session: RimeSessionId, from index: Int, count: Int) -> [(text: String, comment: String)] {
    var iterator = RimeCandidateListIterator()
    guard candidate_list_from_index(session, &iterator, Int32(index)) else { return [] }
    defer { candidate_list_end(&iterator) }
    var result = [(text: String, comment: String)]()
    result.reserveCapacity(count)
    while result.count < count && candidate_list_next(&iterator) {
      result.append((text: iterator.candidate.text.map { String(cString: $0) } ?? "",
                     comment: iterator.candidate.comment.map { String(cString: $0) } ?? ""))
    }
    return result
  }
}
