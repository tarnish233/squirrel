//
//  SquirrelPanel.swift
//  Squirrel
//
//  Created by Leo Liu on 5/10/24.
//

import AppKit

final class SquirrelPanel: NSPanel {
  private let view: SquirrelView
  private let back: NSView
  var inputController: SquirrelInputController?

  var position: NSRect
  private var screenRect: NSRect = .zero
  private var maxHeight: CGFloat = 0

  private var statusMessage: String = ""
  private var statusTimer: Timer?

  private var preedit: String = ""
  private var selRange: NSRange = .empty
  private var caretPos: Int = 0
  private var candidates: [String] = .init()
  private var comments: [String] = .init()
  private var labels: [String] = .init()
  private var index: Int = 0
  private var cursorIndex: Int = 0
  private var scrollDirection: CGVector = .zero
  private var scrollTime: Date = .distantPast
  private var page: Int = 0
  private var lastPage: Bool = true
  private var pagingUp: Bool?
  // Scroll mode: layout of the expanded grid, and column widths remembered for one expansion.
  private var scrollLayout: SquirrelScrollLayout?
  private var scrollColumnWidths: [CGFloat] = []
  private var scrollGeneration: Int?
  private var minimumTextWidth: CGFloat = 0
  private var minimumContentWidth: CGFloat = 0
  // Motion: whether the shown panel is an expanded grid, and the running frame transition.
  private var shownExpanded = false
  private var frameMotion: FrameMotion?
  private var liquidGlassRadius: CGFloat = 0
  /// Slows frame transitions down, for tests.
  static var motionTimeScale = 1.0
  /// Overrides the screen-based limit of a scroll-mode row's width, for tests.
  static var rowWidthLimit: CGFloat?

  init(position: NSRect) {
    self.position = position
    self.view = SquirrelView(frame: position)
    self.back = Self.makeBackgroundView()
    super.init(contentRect: position, styleMask: .nonactivatingPanel, backing: .buffered, defer: true)
    self.level = .init(Int(CGShieldingWindowLevel()))
    self.hasShadow = true
    self.isOpaque = false
    self.backgroundColor = .clear
    back.wantsLayer = true
    back.layer?.mask = view.shape
    let contentView = NSView()
    contentView.addSubview(back)
    contentView.addSubview(view)
    contentView.addSubview(view.textView)
    self.contentView = contentView
  }

  var linear: Bool {
    view.currentTheme.linear
  }
  var vertical: Bool {
    view.currentTheme.vertical
  }
  var inlinePreedit: Bool {
    view.currentTheme.inlinePreedit
  }
  var inlineCandidate: Bool {
    view.currentTheme.inlineCandidate
  }
  var scrollSettings: SquirrelScrollSettings {
    view.currentTheme.scrollSettings
  }
  /// Scroll mode applies to the horizontal linear layout only.
  var scrollModeActive: Bool {
    scrollSettings.enabled && linear && !vertical
  }

  // swiftlint:disable:next cyclomatic_complexity
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      let (index, _, pagingUp) =  view.click(at: mousePosition())
      if let pagingUp {
        self.pagingUp = pagingUp
      } else {
        self.pagingUp = nil
      }
      if let index, index >= 0 && index < candidates.count {
        self.index = index
      }
    case .leftMouseUp:
      let (index, preeditIndex, pagingUp) = view.click(at: mousePosition())

      if let pagingUp, pagingUp == self.pagingUp {
        _ = inputController?.page(up: pagingUp)
      } else {
        self.pagingUp = nil
      }
      if let preeditIndex, preeditIndex >= 0 && preeditIndex < preedit.utf16.count {
        if preeditIndex < caretPos {
          _ = inputController?.moveCaret(forward: true)
        } else if preeditIndex > caretPos {
          _ = inputController?.moveCaret(forward: false)
        }
      }
      if let index, index == self.index && index >= 0 && index < candidates.count {
        _ = inputController?.selectCandidate(index)
      }
    case .mouseEntered:
      acceptsMouseMovedEvents = true
    case .mouseExited:
      acceptsMouseMovedEvents = false
      if cursorIndex != index {
        update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels, highlighted: index, page: page, lastPage: lastPage,
               scroll: scrollLayout, update: false)
      }
      pagingUp = nil
    case .mouseMoved:
      let (index, _, _) = view.click(at: mousePosition())
      if let index = index, cursorIndex != index && index >= 0 && index < candidates.count {
        update(preedit: preedit, selRange: selRange, caretPos: caretPos, candidates: candidates, comments: comments, labels: labels, highlighted: index, page: page, lastPage: lastPage,
               scroll: scrollLayout, update: false)
      }
    case .scrollWheel:
      if event.phase == .began {
        scrollDirection = .zero
      } else if event.phase == .ended || (event.phase == .init(rawValue: 0) && event.momentumPhase != .init(rawValue: 0)) {
        if abs(scrollDirection.dx) > abs(scrollDirection.dy) && abs(scrollDirection.dx) > 10 {
          _ = inputController?.page(up: (scrollDirection.dx < 0) == vertical)
        } else if abs(scrollDirection.dx) < abs(scrollDirection.dy) && abs(scrollDirection.dy) > 10 {
          _ = inputController?.page(up: scrollDirection.dy > 0)
        }
        scrollDirection = .zero
      } else if event.phase == .init(rawValue: 0) && event.momentumPhase == .init(rawValue: 0) {
        if scrollTime.timeIntervalSinceNow < -1 {
          scrollDirection = .zero
        }
        scrollTime = .now
        if (scrollDirection.dy >= 0 && event.scrollingDeltaY > 0) || (scrollDirection.dy <= 0 && event.scrollingDeltaY < 0) {
          scrollDirection.dy += event.scrollingDeltaY
        } else {
          scrollDirection = .zero
        }
        if abs(scrollDirection.dy) > 10 {
          _ = inputController?.page(up: scrollDirection.dy > 0)
          scrollDirection = .zero
        }
      } else {
        scrollDirection.dx += event.scrollingDeltaX
        scrollDirection.dy += event.scrollingDeltaY
      }
    default:
      break
    }
    super.sendEvent(event)
  }

  func hide() {
    statusTimer?.invalidate()
    statusTimer = nil
    stopFrameMotion()
    shownExpanded = false
    orderOut(nil)
    maxHeight = 0
  }

  // swiftlint:disable:next cyclomatic_complexity function_parameter_count
  func update(preedit: String, selRange: NSRange, caretPos: Int, candidates: [String], comments: [String], labels: [String], highlighted index: Int, page: Int, lastPage: Bool,
              scroll: SquirrelScrollLayout? = nil, update: Bool) {
    if update {
      self.scrollLayout = scroll
      self.preedit = preedit
      self.selRange = selRange
      self.caretPos = caretPos
      self.candidates = candidates
      self.comments = comments
      self.labels = labels
      self.index = index
      self.page = page
      self.lastPage = lastPage
    }
    cursorIndex = index

    if !candidates.isEmpty || !preedit.isEmpty {
      statusMessage = ""
      statusTimer?.invalidate()
      statusTimer = nil
    } else {
      if !statusMessage.isEmpty {
        show(status: statusMessage)
        statusMessage = ""
      } else if statusTimer == nil {
        hide()
      }
      return
    }

    let theme = view.currentTheme
    currentScreen()

    let text = NSMutableAttributedString()
    let preeditRange: NSRange
    let highlightedPreeditRange: NSRange

    if !preedit.isEmpty {
      preeditRange = NSRange(location: 0, length: preedit.utf16.count)
      highlightedPreeditRange = selRange

      let line = NSMutableAttributedString(string: preedit)
      line.addAttributes(theme.preeditAttrs, range: preeditRange)
      line.addAttributes(theme.preeditHighlightedAttrs, range: selRange)
      text.append(line)

      text.addAttribute(.paragraphStyle, value: theme.preeditParagraphStyle, range: NSRange(location: 0, length: text.length))
      if !candidates.isEmpty {
        text.append(NSAttributedString(string: "\n", attributes: theme.preeditAttrs))
      }
    } else {
      preeditRange = .empty
      highlightedPreeditRange = .empty
    }

    var candidateRanges = [NSRange]()
    // Where each candidate's text starts in its line, after the label.
    var labelLengths = [Int]()
    for i in 0..<candidates.count {
      // In an expanded grid every row is one page: labels restart in each row, and only the
      // highlighted row (librime's current page) shows them, since digit keys select from it.
      let column = scroll.map { i % $0.rowSize } ?? i
      let pageIndex: Int? = if let scroll { i / scroll.rowSize == scroll.highlightedRow ? column : nil } else { i }
      let attrs = i == index ? theme.highlightedAttrs : theme.attrs
      var labelAttrs = i == index ? theme.labelHighlightedAttrs : theme.labelAttrs
      if pageIndex == nil {
        // Keep the label's width so columns stay aligned.
        labelAttrs[.foregroundColor] = NSColor.clear
      }
      let commentAttrs = i == index ? theme.commentHighlightedAttrs : theme.commentAttrs

      let label = if theme.candidateFormat.contains(/\[label\]/) {
        if labels.count > 1 && column < labels.count {
          labels[column]
        } else if labels.count == 1 && column < labels.first!.count {
          String(labels.first![labels.first!.index(labels.first!.startIndex, offsetBy: column)])
        } else {
          "\(column+1)"
        }
      } else {
        ""
      }

      let candidate = candidates[i].precomposedStringWithCanonicalMapping
      let comment = comments[i].precomposedStringWithCanonicalMapping

      let line = NSMutableAttributedString(string: theme.candidateFormat, attributes: labelAttrs)
      for range in line.string.ranges(of: /\[candidate\]/) {
        let convertedRange = convert(range: range, in: line.string)
        line.addAttributes(attrs, range: convertedRange)
        if candidate.count <= 5 {
          line.addAttribute(.noBreak, value: true, range: NSRange(location: convertedRange.location+1, length: convertedRange.length-1))
        }
      }
      for range in line.string.ranges(of: /\[comment\]/) {
        let convertedRange = convert(range: range, in: line.string)
        // Apply semantic accent/warning colors only for non-highlighted rows
        if let inputController, let pageIndex, !inputController.specialCommentIndices.isEmpty && i != index {
          var newCommentAttrs = commentAttrs
          if let accent = inputController.specialCommentIndices[.commentHighlight], accent.contains(pageIndex) {
            newCommentAttrs[.foregroundColor] = theme.accentCommentTextColor
          } else if let warning = inputController.specialCommentIndices[.commentWarning], warning.contains(pageIndex) {
            newCommentAttrs[.foregroundColor] = theme.warningCommentTextColor
          }
          line.addAttributes(newCommentAttrs, range: convertedRange)
        } else {
          line.addAttributes(commentAttrs, range: convertedRange)
        }
      }
      line.mutableString.replaceOccurrences(of: "[label]", with: label, range: NSRange(location: 0, length: line.length))
      let labeledLine = line.copy() as! NSAttributedString
      line.mutableString.replaceOccurrences(of: "[candidate]", with: candidate, range: NSRange(location: 0, length: line.length))
      line.mutableString.replaceOccurrences(of: "[comment]", with: comment, range: NSRange(location: 0, length: line.length))
      preferColorEmoji(in: line)
      let labelLength = labeledLine.string.firstMatch(of: /\[(candidate|comment)\]/).map { $0.range.lowerBound.utf16Offset(in: labeledLine.string) } ?? 0
      labelLengths.append(labelLength)
      if theme.liquidGlass && !vertical && labelLength > 0 {
        // Labels take a fixed width, so that every candidate starts at the same offset.
        let width = line.attributedSubstring(from: NSRange(location: 0, length: labelLength)).size().width
        if width < theme.labelColumnWidth {
          line.addAttribute(.kern, value: theme.labelColumnWidth - width, range: NSRange(location: labelLength - 1, length: 1))
        }
      }

      if line.length <= 10 {
        line.addAttribute(.noBreak, value: true, range: NSRange(location: 1, length: line.length-1))
      }

      let lineSeparator = if linear, let spacing = theme.candidateSpacing {
        // One space stretched to the configured width (the highlight takes half of it on each side).
        NSAttributedString(string: " ", attributes: attrs.merging([.kern: spacing - (" " as NSString).size(withAttributes: attrs).width]) { $1 })
      } else {
        NSAttributedString(string: linear ? "  " : "\n", attributes: attrs)
      }
      if i > 0 {
        if scroll != nil {
          // Rows break with a line separator, staying in one paragraph like wrapped linear text;
          // candidates in a row are aligned to columns with tab stops (see alignGrid).
          text.append(NSAttributedString(string: column == 0 ? "\u{2028}" : "\t", attributes: attrs))
        } else {
          text.append(lineSeparator)
        }
      }
      let str = lineSeparator.mutableCopy() as! NSMutableAttributedString
      if vertical {
        str.addAttribute(.verticalGlyphForm, value: 1, range: NSRange(location: 0, length: str.length))
      }
      view.separatorWidth = str.boundingRect(with: .zero).width

      let paragraphStyleCandidate = (i == 0 ? theme.firstParagraphStyle : theme.paragraphStyle).mutableCopy() as! NSMutableParagraphStyle
      if linear {
        paragraphStyleCandidate.paragraphSpacingBefore -= theme.linespace
        paragraphStyleCandidate.lineSpacing = theme.linespace
      }
      if theme.liquidGlass {
        // Even rows: emoji and fallback fonts must not make their line taller.
        let lineHeight = theme.font.ascender - theme.font.descender + theme.font.leading
        paragraphStyleCandidate.minimumLineHeight = lineHeight
        paragraphStyleCandidate.maximumLineHeight = lineHeight
      }
      if !linear, let labelEnd = labeledLine.string.firstMatch(of: /\[(candidate|comment)\]/)?.range.lowerBound {
        let labelString = labeledLine.attributedSubstring(from: NSRange(location: 0, length: labelEnd.utf16Offset(in: labeledLine.string)))
        let labelWidth = labelString.boundingRect(with: .zero, options: [.usesLineFragmentOrigin]).width
        paragraphStyleCandidate.headIndent = labelWidth
      }
      line.addAttribute(.paragraphStyle, value: paragraphStyleCandidate, range: NSRange(location: 0, length: line.length))

      candidateRanges.append(NSRange(location: text.length, length: line.length))
      text.append(line)
    }

    view.textView.textContentStorage?.attributedString = text
    view.textView.setLayoutOrientation(vertical ? .vertical : .horizontal)

    let maxTextHeight = vertical ? screenRect.width - theme.edgeInset.width * 2 : screenRect.height - theme.edgeInset.height * 2
    if scroll != nil || scrollModeActive {
      layOutRows(scroll, text: text, candidateRanges: &candidateRanges, labelLengths: labelLengths, maxTextHeight: maxTextHeight)
    } else {
      minimumTextWidth = 0
      minimumContentWidth = 0
      view.gridColumnWidths = []
    }

    // Force TextKit 2 layout before measuring wrapped text and highlight bounds.
    let textWidth = max(maxTextWidth(), minimumTextWidth)
    view.textContainer.size = NSSize(width: textWidth, height: maxTextHeight)
    view.textLayoutManager.ensureLayout(for: view.textLayoutManager.documentRange)

    // Keep very tall wrapped text from auto-scrolling past the first line.
    view.textView.scrollToBeginningOfDocument(nil)

    view.drawView(candidateRanges: candidateRanges, hilightedIndex: index, preeditRange: preeditRange, highlightedPreeditRange: highlightedPreeditRange, canPageUp: page > 0, canPageDown: !lastPage)
    show()
  }

  func updateStatus(long longMessage: String, short shortMessage: String) {
    let theme = view.currentTheme
    switch theme.statusMessageType {
    case .mix:
      statusMessage = shortMessage.isEmpty ? longMessage : shortMessage
    case .long:
      statusMessage = longMessage
    case .short:
      if !shortMessage.isEmpty {
        statusMessage = shortMessage
      } else if let initial = longMessage.first {
        statusMessage = String(initial)
      } else {
        statusMessage = ""
      }
    }
  }

  func load(config: SquirrelConfig, forDarkMode isDark: Bool) {
    if isDark {
      view.darkTheme = SquirrelTheme()
      view.darkTheme.load(config: config, dark: true)
    } else {
      view.lightTheme = SquirrelTheme()
      view.lightTheme.load(config: config, dark: isDark)
    }
  }
}

private extension SquirrelPanel {
  func mousePosition() -> NSPoint {
    var point = NSEvent.mouseLocation
    point = self.convertPoint(fromScreen: point)
    return view.convert(point, from: nil)
  }

  func currentScreen() {
    if let screen = NSScreen.main {
      screenRect = screen.frame
    }
    for screen in NSScreen.screens where screen.frame.contains(position.origin) {
      screenRect = screen.frame
      break
    }
  }

  func maxTextWidth() -> CGFloat {
    let theme = view.currentTheme
    let font: NSFont = theme.font
    let fontScale = font.pointSize / 12
    let textWidthRatio = min(1, 1 / (vertical ? 4 : 3) + fontScale / 12)
    let maxWidth = if vertical {
      screenRect.height * textWidthRatio - theme.edgeInset.height * 2
    } else {
      screenRect.width * textWidthRatio - theme.edgeInset.width * 2
    }
    return maxWidth
  }

  // swiftlint:disable:next cyclomatic_complexity
  func show() {
    currentScreen()
    let theme = view.currentTheme
    if theme.native || view.darkTheme.available {
      self.appearance = NSApp.effectiveAppearance
    } else {
      // user configured only a light theme, set window appearance to light.
      self.appearance = NSAppearance(named: .aqua)
    }

    view.textView.textContainerInset = theme.edgeInset

    var textWidth = max(maxTextWidth(), minimumTextWidth)
    // Measure natural text height before constraining the panel.
    view.textContainer.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)

    // Do not let NSTextView shrink the container to the current view width; it can loop or hide text.
    view.textContainer.widthTracksTextView = false
    view.textContainer.heightTracksTextView = false

    view.textLayoutManager.ensureLayout(for: view.textLayoutManager.documentRange)
    view.textView.bounds.origin = .zero

    var contentRect = view.contentRect
    // An expanded grid keeps the width of its widest columns while scrolling.
    contentRect.size.width = max(contentRect.width, minimumContentWidth)

    // Compute the largest size possible for a giant panel
    var naturalPanelSize = NSSize.zero
    if vertical {
      naturalPanelSize.width = contentRect.height + theme.edgeInset.height * 2
      naturalPanelSize.height = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
    } else {
      naturalPanelSize.width = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
      naturalPanelSize.height = contentRect.height + theme.edgeInset.height * 2
    }

    let maxAllowedWidth = screenRect.width * 0.95
    let maxAllowedHeight = screenRect.height * 0.95

    let requiresFullScreen = naturalPanelSize.width > maxAllowedWidth || naturalPanelSize.height > maxAllowedHeight

    if requiresFullScreen {
      // Expand line length before fullscreen scaling to avoid wasting screen space on narrow text.
      let area = contentRect.width * contentRect.height
      let screenRatio = maxAllowedWidth / maxAllowedHeight

      let optimalTextWidth: CGFloat
      if vertical {
        // Width = screen height in vertical mode
        optimalTextWidth = sqrt(area / screenRatio)
      } else {
        optimalTextWidth = sqrt(area * screenRatio)
      }

      // If there's extra room for text, tighten the layout
      if optimalTextWidth > textWidth {
        textWidth = optimalTextWidth
        view.textContainer.size = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
        view.textLayoutManager.ensureLayout(for: view.textLayoutManager.documentRange)

        contentRect = view.contentRect

        if vertical {
          naturalPanelSize.width = contentRect.height + theme.edgeInset.height * 2
          naturalPanelSize.height = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
        } else {
          naturalPanelSize.width = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
          naturalPanelSize.height = contentRect.height + theme.edgeInset.height * 2
        }
      }
    }

    var panelRect = NSRect.zero

    if requiresFullScreen {
      let scaleX = maxAllowedWidth / naturalPanelSize.width
      let scaleY = maxAllowedHeight / naturalPanelSize.height
      let scale = min(scaleX, scaleY)

      panelRect.size = NSSize(width: naturalPanelSize.width * scale, height: naturalPanelSize.height * scale)

      panelRect.origin = NSPoint(
        x: screenRect.minX + (screenRect.width - panelRect.width) / 2,
        y: screenRect.minY + (screenRect.height - panelRect.height) / 2
      )

      maxHeight = 0
    } else {
      if theme.memorizeSize && (vertical && position.midY / screenRect.height < 0.5) ||
          (vertical && position.minX + max(contentRect.width, maxHeight) + theme.edgeInset.width * 2 > screenRect.maxX) {
        if contentRect.width >= maxHeight {
          maxHeight = contentRect.width
        } else {
          contentRect.size.width = maxHeight
          if vertical {
            naturalPanelSize.height = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
          } else {
            naturalPanelSize.width = contentRect.width + theme.edgeInset.width * 2 + theme.pagingOffset
          }
        }
      }

      panelRect.size = naturalPanelSize

      if vertical {
        // Anchor vertical panels on one side of the cursor to avoid jumping while typing.
        if position.midY / screenRect.height >= 0.5 {
          panelRect.origin.y = position.minY - SquirrelTheme.offsetHeight - panelRect.height + theme.pagingOffset
        } else {
          panelRect.origin.y = position.maxY + SquirrelTheme.offsetHeight
        }
        panelRect.origin.x = position.minX - panelRect.width - SquirrelTheme.offsetHeight
        if view.preeditRange.length > 0, let preeditTextRange = view.convert(range: view.preeditRange) {
          let preeditRect = view.contentRect(range: preeditTextRange)
          panelRect.origin.x += preeditRect.height + theme.edgeInset.width
        }
      } else {
        panelRect.origin = NSPoint(x: position.minX - theme.pagingOffset, y: position.minY - SquirrelTheme.offsetHeight - panelRect.height)
      }

      if panelRect.maxX > screenRect.maxX { panelRect.origin.x = screenRect.maxX - panelRect.width }
      if panelRect.minX < screenRect.minX { panelRect.origin.x = screenRect.minX }
      if panelRect.minY < screenRect.minY {
        if vertical { panelRect.origin.y = screenRect.minY } else { panelRect.origin.y = position.maxY + SquirrelTheme.offsetHeight }
      }
      if panelRect.maxY > screenRect.maxY { panelRect.origin.y = screenRect.maxY - panelRect.height }
      if panelRect.minY < screenRect.minY { panelRect.origin.y = screenRect.minY }
    }

    // Motion: expanding or collapsing the grid moves the window frame like a drawer, as in WeType.
    let expanded = scrollLayout != nil
    let transition = expanded != shownExpanded
    shownExpanded = expanded
    let canAnimate = theme.motion && !vertical && !requiresFullScreen && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    if canAnimate && transition && isVisible {
      startFrameMotion(to: panelRect, expanding: expanded)
    } else if canAnimate, let motion = frameMotion {
      // A new layout during the transition: keep moving, towards it.
      motion.target = panelRect
    } else {
      stopFrameMotion()
      self.setFrame(panelRect, display: true)
    }
    let animating = frameMotion != nil

    if animating {
      // The window is in between: draw at the final size, pinned to its top, and let the window clip.
      contentView!.bounds = NSRect(origin: .zero, size: contentView!.frame.size)
      contentView!.boundsRotation = 0
      contentView!.setBoundsOrigin(.zero)
    } else {
      // Keep the window frame at the scaled physical size while drawing in natural coordinates through bounds.
      contentView!.frame = NSRect(origin: .zero, size: panelRect.size)
      contentView!.bounds = NSRect(origin: .zero, size: naturalPanelSize)

      if vertical {
        contentView!.boundsRotation = -90
        contentView!.setBoundsOrigin(NSPoint(x: 0, y: naturalPanelSize.width))
      } else {
        contentView!.boundsRotation = 0
        contentView!.setBoundsOrigin(.zero)
      }
    }

    view.textView.boundsRotation = 0
    view.textView.setBoundsOrigin(.zero)

    // Subviews must read the post-rotation bounds; Cocoa adjusts the origin and swaps dimensions in vertical mode.
    let subviewFrame = if animating {
      NSRect(x: 0, y: contentView!.bounds.height - naturalPanelSize.height, width: naturalPanelSize.width, height: naturalPanelSize.height)
    } else {
      contentView!.bounds
    }
    view.frame = subviewFrame

    var textFrame = subviewFrame
    textFrame.size.width -= theme.pagingOffset
    textFrame.origin.x += theme.pagingOffset
    if theme.liquidGlass && !vertical {
      // Optical alignment: the highlight stays centered on the line, the glyphs move.
      textFrame.origin.y += theme.baseOffset
    }
    view.textView.frame = textFrame
    // While the window frame moves, the content stays at the top and the background follows.
    view.autoresizingMask = animating ? [.minYMargin] : []
    view.textView.autoresizingMask = animating ? [.minYMargin] : []
    back.autoresizingMask = animating ? [.width, .height] : []

    if theme.translucency {
      var backFrame = animating ? contentView!.bounds : subviewFrame
      backFrame.size.width += animating ? 0 : theme.pagingOffset
      back.frame = backFrame
      back.appearance = NSApp.effectiveAppearance
      if theme.liquidGlass {
        liquidGlassRadius = view.liquidGlassRadius(height: naturalPanelSize.height)
        configureLiquidGlass(radius: min(liquidGlassRadius, backFrame.height / 2))
        // With reduced transparency the view draws an opaque background instead.
        back.isHidden = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
      } else {
        back.layer?.mask = view.shape
        if #available(macOS 26.0, *), let glass = back as? NSGlassEffectView {
          glass.style = theme.glassStyle == .regular ? .regular : .clear
          // Let the glass edge follow the panel's rounded corners (the shape mask clips the rest).
          glass.cornerRadius = theme.cornerRadius
          glass.contentView = nil
        }
        back.isHidden = false
      }
    } else {
      back.isHidden = true
    }

    alphaValue = theme.alpha
    invalidateShadow()
    orderFront(nil)
    // voila!
  }

  func show(status message: String) {
    minimumTextWidth = 0
    minimumContentWidth = 0
    scrollLayout = nil
    view.gridColumnWidths = []
    let theme = view.currentTheme
    let text = NSMutableAttributedString(string: message, attributes: theme.attrs)
    text.addAttribute(.paragraphStyle, value: theme.paragraphStyle, range: NSRange(location: 0, length: text.length))
    view.textContentStorage.attributedString = text
    view.textView.setLayoutOrientation(vertical ? .vertical : .horizontal)
    view.drawView(candidateRanges: [NSRange(location: 0, length: text.length)], hilightedIndex: -1,
                  preeditRange: .empty, highlightedPreeditRange: .empty, canPageUp: false, canPageDown: false)
    show()

    statusTimer?.invalidate()
    statusTimer = Timer.scheduledTimer(withTimeInterval: SquirrelTheme.showStatusDuration, repeats: false) { _ in
      self.hide()
    }
  }

  /// Lays the candidates out the way scroll mode shows them, in rows of one line: the collapsed
  /// row, or the rows of an expanded grid, aligned into columns with tab stops. A row grows as
  /// wide as the screen allows instead of wrapping; past that, the widest cells are cut short with
  /// an ellipsis. Cells are measured with an unbounded line length; grid columns only grow during
  /// one expansion, so the panel keeps its size while scrolling.
  func layOutRows(_ scroll: SquirrelScrollLayout?, text: NSMutableAttributedString, candidateRanges: inout [NSRange], labelLengths: [Int], maxTextHeight: CGFloat) {
    let rowSize = scroll?.rowSize ?? candidateRanges.count
    guard !candidateRanges.isEmpty, rowSize > 0 else {
      minimumTextWidth = 0
      minimumContentWidth = 0
      view.gridColumnWidths = []
      return
    }
    if let scroll, scrollGeneration != scroll.generation || scrollColumnWidths.count != rowSize {
      scrollGeneration = scroll.generation
      scrollColumnWidths = .init(repeating: 0, count: rowSize)
    }
    func measureCells() -> [CGFloat] {
      view.textContainer.size = NSSize(width: 100_000, height: maxTextHeight)
      view.textLayoutManager.ensureLayout(for: view.textLayoutManager.documentRange)
      return candidateRanges.map { range in
        view.convert(range: range).map { ceil(view.contentRect(range: $0).width) } ?? 0
      }
    }
    func widestInColumns(_ cells: [CGFloat]) -> [CGFloat] {
      var columns = [CGFloat](repeating: 0, count: rowSize)
      for (i, width) in cells.enumerated() {
        columns[i % rowSize] = max(columns[i % rowSize], width)
      }
      return columns
    }

    var cells = measureCells()
    var columns = widestInColumns(cells)
    if scroll != nil {
      for column in 0..<rowSize {
        scrollColumnWidths[column] = max(scrollColumnWidths[column], columns[column], scrollSettings.columnWidth)
      }
      columns = scrollColumnWidths
    }
    let gap = view.separatorWidth
    let gaps = gap * CGFloat(rowSize - 1)
    let maxWidth = maxRowWidth()
    if columns.reduce(0, +) + gaps > maxWidth {
      // Too wide even for the screen: cap the cells at the width that fits, the widest first.
      let cellLimit = max(Self.waterLevel(columns, total: maxWidth - gaps), view.currentTheme.font.pointSize * 4)
      for i in candidateRanges.indices.reversed() where cells[i] > cellLimit {
        let change = truncate(text, range: candidateRanges[i], labelLength: labelLengths[i], to: cellLimit)
        candidateRanges[i].length += change
        for later in candidateRanges.indices where later > i {
          candidateRanges[later].location += change
        }
      }
      view.textView.textContentStorage?.attributedString = text
      cells = measureCells()
      let truncatedColumns = widestInColumns(cells)
      columns = if scroll != nil {
        // Columns keep their width, capped, so that the grid does not jump while scrolling.
        zip(scrollColumnWidths, truncatedColumns).map { max(min($0, cellLimit), $1) }
      } else {
        truncatedColumns
      }
    }
    let rowWidth = columns.reduce(0, +) + gaps

    if scroll != nil, let firstRange = candidateRanges.first {
      view.gridColumnWidths = columns
      var tabStops = [NSTextTab]()
      var location: CGFloat = 0
      for width in columns.dropLast() {
        location += width + gap
        tabStops.append(NSTextTab(textAlignment: .left, location: location))
      }
      let blockRange = NSRange(location: firstRange.location, length: text.length - firstRange.location)
      let baseStyle = text.attribute(.paragraphStyle, at: firstRange.location, effectiveRange: nil) as? NSParagraphStyle ?? view.currentTheme.paragraphStyle
      let style = baseStyle.mutableCopy() as! NSMutableParagraphStyle
      style.tabStops = tabStops
      style.defaultTabInterval = max(1, gap)
      text.addAttribute(.paragraphStyle, value: style, range: blockRange)
      view.textView.textContentStorage?.attributedString = text
      minimumContentWidth = rowWidth
    } else {
      view.gridColumnWidths = []
      minimumContentWidth = 0
    }
    // The line is a little longer than the row, so that the row never wraps.
    minimumTextWidth = ceil(rowWidth + gap)
  }

  /// The widest a scroll-mode row may grow: most of the screen width.
  func maxRowWidth() -> CGFloat {
    if let limit = Self.rowWidthLimit {
      return limit
    }
    let theme = view.currentTheme
    return floor(screenRect.width * 0.9) - theme.edgeInset.width * 2 - theme.pagingOffset
  }

  /// The largest width for which the widths, each capped at it, add up to no more than total.
  static func waterLevel(_ widths: [CGFloat], total: CGFloat) -> CGFloat {
    var remaining = total
    let sorted = widths.sorted()
    for (i, width) in sorted.enumerated() {
      let rest = CGFloat(sorted.count - i)
      if width * rest > remaining {
        return remaining / rest
      }
      remaining -= width
    }
    return sorted.last ?? total
  }

  /// Cuts the candidate (and its comment) at `range` in `text` short to fit `width`, keeping its
  /// label: drops whole characters from the end and adds an ellipsis. Returns the change in length.
  func truncate(_ text: NSMutableAttributedString, range: NSRange, labelLength: Int, to width: CGFloat) -> Int {
    let line = text.attributedSubstring(from: range)
    let string = line.string as NSString
    // Trailing spaces (the format's space before an empty comment) stay after the ellipsis.
    var end = string.length
    while end > labelLength && string.character(at: end - 1) == 0x20 {
      end -= 1
    }
    guard labelLength < end else { return 0 }
    // Where each character after the label starts: keeping n characters ends at starts[n].
    var starts = [Int]()
    string.enumerateSubstrings(in: NSRange(location: labelLength, length: end - labelLength), options: .byComposedCharacterSequences) { _, characterRange, _, _ in
      starts.append(characterRange.location)
    }
    guard starts.count > 1 else { return 0 }
    let tail = line.attributedSubstring(from: NSRange(location: end, length: string.length - end))
    func shortened(keeping count: Int) -> NSAttributedString {
      var keep = starts[count]
      while keep > labelLength && string.character(at: keep - 1) == 0x20 {
        keep -= 1
      }
      let result = NSMutableAttributedString(attributedString: line.attributedSubstring(from: NSRange(location: 0, length: keep)))
      var attrs = line.attributes(at: keep > labelLength ? keep - 1 : labelLength, effectiveRange: nil)
      attrs[.kern] = nil
      result.append(NSAttributedString(string: "…", attributes: attrs))
      result.append(tail)
      return result
    }
    // The most characters that fit, at least one.
    var low = 1, high = starts.count - 1
    while low < high {
      let middle = (low + high + 1) / 2
      if shortened(keeping: middle).size().width <= width {
        low = middle
      } else {
        high = middle - 1
      }
    }
    let result = shortened(keeping: low)
    text.replaceCharacters(in: range, with: result)
    return result.length - range.length
  }

  func convert(range: Range<String.Index>, in string: String) -> NSRange {
    let startPos = range.lowerBound.utf16Offset(in: string)
    let endPos = range.upperBound.utf16Offset(in: string)
    return NSRange(location: startPos, length: endPos - startPos)
  }

  /// A window frame transition: expanding takes 0.20 s, collapsing 0.16 s, with WeType's curves.
  final class FrameMotion {
    let start: NSRect
    var target: NSRect
    let startTime = CACurrentMediaTime()
    let duration: Double
    let curve: (Double, Double, Double, Double)
    var timer: Timer?

    init(from start: NSRect, to target: NSRect, expanding: Bool) {
      self.start = start
      self.target = target
      duration = (expanding ? 0.20 : 0.16) * SquirrelPanel.motionTimeScale
      curve = expanding ? (0.18, 0.82, 0.24, 1) : (0.25, 0.10, 0.25, 1)
    }

    /// The frame at a time, on the cubic Bézier timing curve.
    func frame(at time: CFTimeInterval) -> (NSRect, done: Bool) {
      let elapsed = min(1, max(0, (time - startTime) / duration))
      let progress = CGFloat(Self.bezier(elapsed, curve))
      func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
      let frame = NSRect(x: mix(start.minX, target.minX), y: mix(start.minY, target.minY),
                         width: mix(start.width, target.width), height: mix(start.height, target.height))
      return (elapsed >= 1 ? target : frame, elapsed >= 1)
    }

    /// y of the timing curve through (0, 0), (x1, y1), (x2, y2), (1, 1) at x.
    static func bezier(_ x: Double, _ curve: (Double, Double, Double, Double)) -> Double {
      func sample(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t
      }
      var low = 0.0, high = 1.0, t = x
      for _ in 0..<24 {
        if sample(t, curve.0, curve.2) < x { low = t } else { high = t }
        t = (low + high) / 2
      }
      return sample(t, curve.1, curve.3)
    }
  }

  func startFrameMotion(to target: NSRect, expanding: Bool) {
    stopFrameMotion()
    let motion = FrameMotion(from: frame, to: target, expanding: expanding)
    frameMotion = motion
    let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
      self?.stepFrameMotion()
    }
    RunLoop.main.add(timer, forMode: .common)
    motion.timer = timer
    // The text fades in (and drops into place when expanding), as WeType's candidates do.
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0.3
    fade.toValue = 1
    let slide = CABasicAnimation(keyPath: "transform.translation.y")
    slide.fromValue = expanding ? 4 : 0
    slide.toValue = 0
    let reveal = CAAnimationGroup()
    reveal.animations = [fade, slide]
    reveal.duration = expanding ? 0.16 : 0.10
    reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
    view.textView.layer?.add(reveal, forKey: "reveal")
  }

  func stepFrameMotion() {
    guard let motion = frameMotion else { return }
    let (frame, done) = motion.frame(at: CACurrentMediaTime())
    setFrame(frame, display: true)
    if view.currentTheme.liquidGlass {
      configureLiquidGlass(radius: min(liquidGlassRadius, frame.height / 2))
    }
    invalidateShadow()
    if done {
      stopFrameMotion()
    }
  }

  func stopFrameMotion() {
    frameMotion?.timer?.invalidate()
    frameMotion = nil
  }

  /// The liquid glass background, as in the WeType glass theme: the glass is shaped by its own
  /// corner radius (a mask would clip its edge highlights) and veiled in dark mode so that white
  /// text stays readable over bright content.
  func configureLiquidGlass(radius: CGFloat) {
    back.layer?.mask = nil
    guard #available(macOS 26.0, *), let glass = back as? NSGlassEffectView else {
      // Blur before macOS 26.
      back.layer?.cornerRadius = radius
      back.layer?.cornerCurve = .continuous
      back.layer?.masksToBounds = true
      return
    }
    glass.style = view.currentTheme.glassStyle == .regular ? .regular : .clear
    glass.cornerRadius = radius
    if #available(macOS 27.0, *) {
      glass.effectIsInteractive = false
    }
    let veil = glass.contentView ?? NSView()
    veil.wantsLayer = true
    veil.layer?.cornerRadius = radius
    veil.layer?.cornerCurve = .continuous
    veil.layer?.masksToBounds = true
    veil.layer?.backgroundColor = (view.isDark ? NSColor(white: 0, alpha: 0.5) : NSColor.clear).cgColor
    if glass.contentView !== veil {
      glass.contentView = veil
    }
  }

  /// PingFang has monochrome glyphs for some emoji (such as 🉑 and 🉐): draw every emoji cluster
  /// with the color emoji font, keeping explicit text presentation (U+FE0E).
  func preferColorEmoji(in text: NSMutableAttributedString) {
    let string = text.string as NSString
    string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: .byComposedCharacterSequences) { cluster, range, _, _ in
      guard let scalars = cluster?.unicodeScalars, !scalars.contains("\u{FE0E}") else { return }
      let isColor = scalars.contains { $0.properties.isEmojiPresentation } ||
        ((scalars.contains("\u{FE0F}") || scalars.contains("\u{20E3}")) && scalars.contains { $0.properties.isEmoji })
      guard isColor, let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont,
            let emojiFont = NSFont(name: "AppleColorEmoji", size: font.pointSize) else { return }
      text.addAttribute(.font, value: emojiFont, range: range)
    }
  }

  static func makeBackgroundView() -> NSView {
    if #available(macOS 26.0, *) {
      let glassView = NSGlassEffectView()
      glassView.style = .clear
      return glassView
    } else {
      let visualEffectView = NSVisualEffectView()
      visualEffectView.blendingMode = .behindWindow
      visualEffectView.material = .hudWindow
      visualEffectView.state = .active
      return visualEffectView
    }
  }
}
