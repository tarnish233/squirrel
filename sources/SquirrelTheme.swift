//
//  SquirrelTheme.swift
//  Squirrel
//
//  Created by Leo Liu on 5/9/24.
//

import AppKit

final class SquirrelTheme {
  static let offsetHeight: CGFloat = 5
  static let defaultFontSize: CGFloat = NSFont.systemFontSize
  static let showStatusDuration: Double = 1.2
  static let defaultFont = NSFont.userFont(ofSize: defaultFontSize)!

  enum StatusMessageType: String {
    case long, short, mix
  }
  /// Liquid glass look: a single line is outlined as a capsule up to this corner radius.
  static let capsuleRadiusLimit: CGFloat = 20
  /// Liquid glass look: gap between the highlight capsule and the panel edge.
  static let highlightMargin: CGFloat = 3
  /// Liquid glass look: horizontal padding of the highlighted text inside its capsule.
  static let highlightPadding: CGFloat = 6.5

  /// Liquid glass look with reduced transparency: an opaque background with a hairline border.
  static let opaqueGlassBackground = color(light: .white, dark: NSColor(srgbRed: 35 / 255, green: 33 / 255, blue: 34 / 255, alpha: 1))
  static let opaqueGlassBorder = color(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.14))

  /// Glass material of the translucent background on macOS 26 and later.
  enum GlassStyle: String {
    /// Frosted; keeps text readable over busy content.
    case regular
    /// More see-through.
    case clear
  }
  enum RimeColorSpace {
    case displayP3, sRGB
    static func from(name: String) -> Self {
      if name == "display_p3" {
        return .displayP3
      } else {
        return .sRGB
      }
    }
  }

  private(set) var available = true
  private(set) var native = true
  private(set) var memorizeSize = true
  private var colorSpace: RimeColorSpace = .sRGB

  var backgroundColor: NSColor = .windowBackgroundColor
  var highlightedPreeditColor: NSColor?
  var highlightedBackColor: NSColor? = .selectedTextBackgroundColor
  var preeditBackgroundColor: NSColor?
  var candidateBackColor: NSColor?
  var borderColor: NSColor?

  private var textColor: NSColor = .secondaryLabelColor
  private var highlightedTextColor: NSColor = .labelColor
  private var candidateTextColor: NSColor = .labelColor
  private var highlightedCandidateTextColor: NSColor = .labelColor
  private var candidateLabelColor: NSColor? = .secondaryLabelColor
  private var highlightedCandidateLabelColor: NSColor? = .secondaryLabelColor
  private var commentTextColor: NSColor? = .secondaryLabelColor
  private var highlightedCommentTextColor: NSColor? = .secondaryLabelColor
  // Semantic comment colors (proposal in rime/squirrel#1124).
  private(set) var accentCommentTextColor: NSColor?
  private(set) var warningCommentTextColor: NSColor?

  private(set) var cornerRadius: CGFloat = 0
  private(set) var hilitedCornerRadius: CGFloat = 0
  private(set) var surroundingExtraExpansion: CGFloat = 0
  private(set) var shadowSize: CGFloat = 0
  private(set) var borderWidth: CGFloat = 0
  private(set) var borderHeight: CGFloat = 0
  private(set) var linespace: CGFloat = 0
  /// Space between candidates in the linear layout; two spaces of the candidate font if not set.
  private(set) var candidateSpacing: CGFloat?
  private(set) var preeditLinespace: CGFloat = 0
  private(set) var baseOffset: CGFloat = 0
  private(set) var alpha: CGFloat = 1

  private(set) var translucency = false
  private var glassStyleSetting: GlassStyle?
  /// Regular for the liquid glass look, clear otherwise, unless `glass_style` says so.
  var glassStyle: GlassStyle { glassStyleSetting ?? (liquidGlass ? .regular : .clear) }
  /// The macOS 26 Liquid Glass look, for the native color scheme with translucency:
  /// - the glass is the background, veiled in dark mode for contrast;
  /// - the outline is a capsule around a single line and has `corner_radius` around more lines;
  /// - `border_width` / `border_height` are the padding;
  /// - the highlight is a system-blue capsule with white text.
  private(set) var liquidGlass = false
  private(set) var mutualExclusive = false
  private(set) var linear = false
  private(set) var vertical = false
  private(set) var inlinePreedit = false
  private(set) var inlineCandidate = false
  private(set) var showPaging = false
  /// Animate expanding and collapsing the scroll-mode grid (`style/motion`).
  private(set) var motion = false
  private(set) var scrollSettings = SquirrelScrollSettings()

  private var fonts = [NSFont]()
  private var labelFonts = [NSFont]()
  private var commentFonts = [NSFont]()
  private var preeditFonts = [NSFont]()
  private var hilitedFonts = [NSFont]()
  private var fontSize: CGFloat?
  private var labelFontSize: CGFloat?
  private var commentFontSize: CGFloat?
  private var preeditFontSize: CGFloat?

  private var _candidateFormat = "[label]. [candidate] [comment]"
  private(set) var statusMessageType: StatusMessageType = .mix

  private var defaultFont: NSFont {
    if let size = fontSize {
      Self.defaultFont.withSize(size)
    } else {
      Self.defaultFont
    }
  }

  private(set) lazy var font: NSFont = combineFonts(fonts, size: fontSize) ?? defaultFont
  private(set) lazy var labelFont: NSFont = {
    if let font = combineFonts(labelFonts, size: labelFontSize ?? fontSize) {
      return font
    } else if let size = labelFontSize {
      return self.font.withSize(size)
    } else {
      return self.font
    }
  }()
  private(set) lazy var commentFont: NSFont = {
    if let font = combineFonts(commentFonts, size: commentFontSize ?? fontSize) {
      return font
    } else if let size = commentFontSize {
      return self.font.withSize(size)
    } else {
      return self.font
    }
  }()
  private(set) lazy var preeditFont: NSFont = {
    if let font = combineFonts(preeditFonts, size: preeditFontSize ?? fontSize) {
      return font
    } else if let size = preeditFontSize {
      return self.font.withSize(size)
    } else {
      return self.font
    }
  }()
  /// Font of the highlighted candidate and its label (`hilited_font_face`), such as a heavier weight.
  private(set) lazy var highlightedFont: NSFont = combineFonts(hilitedFonts, size: font.pointSize) ?? font
  private(set) lazy var highlightedLabelFont: NSFont = combineFonts(hilitedFonts, size: labelFont.pointSize) ?? labelFont
  /// Liquid glass look: labels take a fixed width, so candidates start at the same offset whatever
  /// the digit (as in WeType); the widest digit and a small gap.
  private(set) lazy var labelColumnWidth: CGFloat = {
    let digits = (0...9).map(String.init)
    let widest = [labelFont, highlightedLabelFont].flatMap { font in
      digits.map { ($0 as NSString).size(withAttributes: [.font: font]).width }
    }.max() ?? 0
    return widest + labelFont.pointSize * 0.05
  }()
  /// The same baseline offset on a whole line moves nothing: TextKit lays the line out around it.
  /// So the liquid glass look moves the text view by `base_offset` instead (see SquirrelPanel.show).
  private var textBaselineOffset: CGFloat {
    liquidGlass ? 0 : baseOffset
  }
  private var labelBaselineOffset: CGFloat {
    textBaselineOffset + (!vertical ? (font.pointSize - labelFont.pointSize) / 2.5 : 0)
  }
  private var commentBaselineOffset: CGFloat {
    textBaselineOffset + (!vertical ? (font.pointSize - commentFont.pointSize) / 2.5 : 0)
  }
  private(set) lazy var attrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: candidateTextColor,
    .font: font,
    .baselineOffset: textBaselineOffset
  ]
  private(set) lazy var highlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCandidateTextColor,
    .font: highlightedFont,
    .baselineOffset: textBaselineOffset
  ]
  private(set) lazy var labelAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: candidateLabelColor ?? blendColor(foregroundColor: self.candidateTextColor, backgroundColor: self.backgroundColor),
    .font: labelFont,
    .baselineOffset: labelBaselineOffset
  ]
  private(set) lazy var labelHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCandidateLabelColor ?? blendColor(foregroundColor: highlightedCandidateTextColor, backgroundColor: highlightedBackColor),
    .font: highlightedLabelFont,
    .baselineOffset: labelBaselineOffset
  ]
  private(set) lazy var commentAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: commentTextColor ?? candidateTextColor,
    .font: commentFont,
    .baselineOffset: commentBaselineOffset
  ]
  private(set) lazy var commentHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedCommentTextColor ?? highlightedCandidateTextColor,
    .font: commentFont,
    .baselineOffset: commentBaselineOffset
  ]
  private(set) lazy var preeditAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: textColor,
    .font: preeditFont,
    .baselineOffset: textBaselineOffset
  ]
  private(set) lazy var preeditHighlightedAttrs: [NSAttributedString.Key: Any] = [
    .foregroundColor: highlightedTextColor,
    .font: preeditFont,
    .baselineOffset: textBaselineOffset
  ]

  private(set) lazy var firstParagraphStyle: NSParagraphStyle = {
    let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = linespace / 2
    style.paragraphSpacingBefore = preeditLinespace / 2 + hilitedCornerRadius / 2
    return style as NSParagraphStyle
  }()
  private(set) lazy var paragraphStyle: NSParagraphStyle = {
    let style = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = linespace / 2
    style.paragraphSpacingBefore = linespace / 2
    return style as NSParagraphStyle
  }()
  private(set) lazy var preeditParagraphStyle: NSParagraphStyle = {
    let style = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
    style.paragraphSpacing = preeditLinespace / 2 + hilitedCornerRadius / 2
    style.lineSpacing = linespace
    return style as NSParagraphStyle
  }()
  private(set) lazy var edgeInset: NSSize = {
    // The liquid glass outline adapts to the content, so its padding is just the border.
    let radius = liquidGlass ? 0 : cornerRadius
    return if vertical {
      NSSize(width: borderHeight + radius, height: borderWidth + radius)
    } else {
      NSSize(width: borderWidth + radius, height: borderHeight + radius)
    }
  }()
  private(set) lazy var borderLineWidth: CGFloat = min(borderHeight, borderWidth)
  private(set) var candidateFormat: String {
    get {
      _candidateFormat
    } set {
      var newTemplate = newValue
      if newTemplate.contains(/%@/) {
        newTemplate.replace(/%@/, with: "[candidate] [comment]")
      }
      if newTemplate.contains(/%c/) {
        newTemplate.replace(/%c/, with: "[label]")
      }
      _candidateFormat = newTemplate
    }
  }
  var pagingOffset: CGFloat {
    if showPaging {
      (labelFontSize ?? fontSize ?? Self.defaultFontSize) * 1.5
    } else {
      0
    }
  }

  func load(config: SquirrelConfig, dark: Bool) {
    linear ?= config.getString("style/candidate_list_layout").map { $0 == "linear" }
    vertical ?= config.getString("style/text_orientation").map { $0 == "vertical" }
    inlinePreedit ?= config.getBool("style/inline_preedit")
    inlineCandidate ?= config.getBool("style/inline_candidate")
    translucency ?= config.getBool("style/translucency")
    glassStyleSetting ?= config.getString("style/glass_style").flatMap(GlassStyle.init(rawValue:))
    mutualExclusive ?= config.getBool("style/mutual_exclusive")
    memorizeSize ?= config.getBool("style/memorize_size")
    showPaging ?= config.getBool("style/show_paging")
    motion ?= config.getBool("style/motion")
    scrollSettings.enabled ?= config.getBool("style/scroll_mode/enable")
    scrollSettings.maxRows ?= config.getDouble("style/scroll_mode/max_rows").map {
      min(max(Int($0), SquirrelScrollSettings.rowLimit.lowerBound), SquirrelScrollSettings.rowLimit.upperBound)
    }
    scrollSettings.tabPaging ?= config.getBool("style/scroll_mode/tab_paging")
    scrollSettings.columnWidth ?= config.getDouble("style/scroll_mode/column_width").map { max(0, $0) }

    statusMessageType ?= .init(rawValue: config.getString("style/status_message_type") ?? "")
    candidateFormat ?= config.getString("style/candidate_format")

    alpha ?= config.getDouble("style/alpha").map { min(1, max(0, $0)) }
    cornerRadius ?= config.getDouble("style/corner_radius")
    hilitedCornerRadius ?= config.getDouble("style/hilited_corner_radius")
    surroundingExtraExpansion ?= config.getDouble("style/surrounding_extra_expansion")
    borderHeight ?= config.getDouble("style/border_height")
    borderWidth ?= config.getDouble("style/border_width")
    linespace ?= config.getDouble("style/line_spacing")
    candidateSpacing ?= config.getDouble("style/candidate_spacing").map { max(0, $0) }
    preeditLinespace ?= config.getDouble("style/spacing")
    baseOffset ?= config.getDouble("style/base_offset")
    shadowSize ?= config.getDouble("style/shadow_size").map { max(0, $0) }

    var fontName = config.getString("style/font_face")
    var fontSize = config.getDouble("style/font_point")
    var labelFontName = config.getString("style/label_font_face")
    var labelFontSize = config.getDouble("style/label_font_point")
    var commentFontName = config.getString("style/comment_font_face")
    var commentFontSize = config.getDouble("style/comment_font_point")
    var preeditFontName = config.getString("style/preedit_font_face")
    var preeditFontSize = config.getDouble("style/preedit_font_point")
    var hilitedFontName = config.getString("style/hilited_font_face")

    let colorSchemeOption = dark ? "style/color_scheme_dark" : "style/color_scheme"
    if let colorScheme = config.getString(colorSchemeOption) {
      if colorScheme != "native" {
        native = false
        let prefix = "preset_color_schemes/\(colorScheme)"
        colorSpace = .from(name: config.getString("\(prefix)/color_space") ?? "")
        backgroundColor ?= config.getColor("\(prefix)/back_color", inSpace: colorSpace)
        highlightedPreeditColor = config.getColor("\(prefix)/hilited_back_color", inSpace: colorSpace)
        highlightedBackColor = config.getColor("\(prefix)/hilited_candidate_back_color", inSpace: colorSpace) ?? highlightedPreeditColor
        preeditBackgroundColor = config.getColor("\(prefix)/preedit_back_color", inSpace: colorSpace)
        candidateBackColor = config.getColor("\(prefix)/candidate_back_color", inSpace: colorSpace)
        borderColor = config.getColor("\(prefix)/border_color", inSpace: colorSpace)

        textColor ?= config.getColor("\(prefix)/text_color", inSpace: colorSpace)
        highlightedTextColor = config.getColor("\(prefix)/hilited_text_color", inSpace: colorSpace) ?? textColor
        candidateTextColor = config.getColor("\(prefix)/candidate_text_color", inSpace: colorSpace) ?? textColor
        highlightedCandidateTextColor = config.getColor("\(prefix)/hilited_candidate_text_color", inSpace: colorSpace) ?? highlightedTextColor
        candidateLabelColor = config.getColor("\(prefix)/label_color", inSpace: colorSpace)
        highlightedCandidateLabelColor = config.getColor("\(prefix)/hilited_candidate_label_color", inSpace: colorSpace)
        commentTextColor = config.getColor("\(prefix)/comment_text_color", inSpace: colorSpace)
        highlightedCommentTextColor = config.getColor("\(prefix)/hilited_comment_text_color", inSpace: colorSpace)
        accentCommentTextColor = config.getColor("\(prefix)/accent_text_color", inSpace: colorSpace)
        warningCommentTextColor = config.getColor("\(prefix)/warning_text_color", inSpace: colorSpace)

        // Per-color-scheme settings override global style settings.
        linear ?= config.getString("\(prefix)/candidate_list_layout").map { $0 == "linear" }
        vertical ?= config.getString("\(prefix)/text_orientation").map { $0 == "vertical" }
        inlinePreedit ?= config.getBool("\(prefix)/inline_preedit")
        inlineCandidate ?= config.getBool("\(prefix)/inline_candidate")
        translucency ?= config.getBool("\(prefix)/translucency")
        glassStyleSetting ?= config.getString("\(prefix)/glass_style").flatMap(GlassStyle.init(rawValue:))
        mutualExclusive ?= config.getBool("\(prefix)/mutual_exclusive")
        showPaging ?= config.getBool("\(prefix)/show_paging")
        motion ?= config.getBool("\(prefix)/motion")
        candidateFormat ?= config.getString("\(prefix)/candidate_format")
        fontName ?= config.getString("\(prefix)/font_face")
        fontSize ?= config.getDouble("\(prefix)/font_point")
        labelFontName ?= config.getString("\(prefix)/label_font_face")
        labelFontSize ?= config.getDouble("\(prefix)/label_font_point")
        commentFontName ?= config.getString("\(prefix)/comment_font_face")
        commentFontSize ?= config.getDouble("\(prefix)/comment_font_point")
        preeditFontName ?= config.getString("\(prefix)/preedit_font_face")
        preeditFontSize ?= config.getDouble("\(prefix)/preedit_font_point")
        hilitedFontName ?= config.getString("\(prefix)/hilited_font_face")

        alpha ?= config.getDouble("\(prefix)/alpha").map { max(0, min(1, $0)) }
        cornerRadius ?= config.getDouble("\(prefix)/corner_radius")
        hilitedCornerRadius ?= config.getDouble("\(prefix)/hilited_corner_radius")
        surroundingExtraExpansion ?= config.getDouble("\(prefix)/surrounding_extra_expansion")
        borderHeight ?= config.getDouble("\(prefix)/border_height")
        borderWidth ?= config.getDouble("\(prefix)/border_width")
        linespace ?= config.getDouble("\(prefix)/line_spacing")
        candidateSpacing ?= config.getDouble("\(prefix)/candidate_spacing").map { max(0, $0) }
        preeditLinespace ?= config.getDouble("\(prefix)/spacing")
        baseOffset ?= config.getDouble("\(prefix)/base_offset")
        shadowSize ?= config.getDouble("\(prefix)/shadow_size").map { max(0, $0) }
      }
    } else {
      available = false
    }
    liquidGlass = native && translucency
    if liquidGlass {
      // Colors of the WeType glass theme; the glass itself is the background.
      backgroundColor = .clear
      highlightedBackColor = .systemBlue
      candidateTextColor = Self.color(light: NSColor(white: 40 / 255, alpha: 1), dark: NSColor(white: 232 / 255, alpha: 1))
      candidateLabelColor = Self.color(light: NSColor(white: 130 / 255, alpha: 1), dark: NSColor(white: 180 / 255, alpha: 1))
      commentTextColor = candidateLabelColor
      highlightedCandidateTextColor = .white
      highlightedCandidateLabelColor = .white
      highlightedCommentTextColor = NSColor(white: 1, alpha: 0.8)
    }

    fonts = decodeFonts(from: fontName)
    self.fontSize = fontSize
    labelFonts = decodeFonts(from: labelFontName ?? fontName)
    self.labelFontSize = labelFontSize
    commentFonts = decodeFonts(from: commentFontName ?? fontName)
    self.commentFontSize = commentFontSize
    preeditFonts = decodeFonts(from: preeditFontName ?? fontName)
    self.preeditFontSize = preeditFontSize
    hilitedFonts = decodeFonts(from: hilitedFontName)
  }
}

private extension SquirrelTheme {
  func combineFonts(_ fonts: [NSFont], size: CGFloat?) -> NSFont? {
    if fonts.count == 0 { return nil }
    if fonts.count == 1 {
      if let size = size {
        return fonts[0].withSize(size)
      } else {
        return fonts[0]
      }
    }
    let attribute = [NSFontDescriptor.AttributeName.cascadeList: fonts[1...].map { $0.fontDescriptor } ]
    let fontDescriptor = fonts[0].fontDescriptor.addingAttributes(attribute)
    return NSFont.init(descriptor: fontDescriptor, size: size ?? fonts[0].pointSize)
  }

  /// A color that differs between the light and the dark appearance.
  static func color(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    }
  }

  /// `system` is the system UI font: SF, falling back to the system CJK font (PingFang SC for
  /// Simplified Chinese). `system-medium`, `system-semibold` etc. pick a weight.
  static func systemFont(named name: String) -> NSFont? {
    let parts = name.lowercased().split(separator: "-", maxSplits: 1).map(String.init)
    guard parts.first == "system" else { return nil }
    let weights: [String: NSFont.Weight] = [
      "ultralight": .ultraLight, "thin": .thin, "light": .light, "regular": .regular, "medium": .medium,
      "semibold": .semibold, "bold": .bold, "heavy": .heavy, "black": .black
    ]
    guard let weight = parts.count > 1 ? weights[parts[1]] : .regular else { return nil }
    return NSFont.systemFont(ofSize: defaultFontSize, weight: weight)
  }

  func decodeFonts(from fontString: String?) -> [NSFont] {
    guard let fontString = fontString else { return [] }
    var seenFontFamilies = Set<String>()
    let fontStrings = fontString.split(separator: ",")
    var fonts = [NSFont]()
    for string in fontStrings {
      if let font = Self.systemFont(named: string.trimmingCharacters(in: .whitespaces)) {
        if seenFontFamilies.insert("system").inserted {
          fonts.append(font)
        }
        continue
      }
      if let matchedFontName = try? /^\s*(.+)-([^-]+)\s*$/.firstMatch(in: string) {
        let family = String(matchedFontName.output.1)
        let style = String(matchedFontName.output.2)
        if seenFontFamilies.contains(family) { continue }
        let fontDescriptor = NSFontDescriptor(fontAttributes: [.family: family, .face: style])
        if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
          fonts.append(font)
          seenFontFamilies.insert(family)
          continue
        }
      }
      let fontName = string.trimmingCharacters(in: .whitespaces)
      if seenFontFamilies.contains(fontName) { continue }
      let fontDescriptor = NSFontDescriptor(fontAttributes: [.name: fontName])
      if let font = NSFont(descriptor: fontDescriptor, size: Self.defaultFontSize) {
        fonts.append(font)
        seenFontFamilies.insert(fontName)
        continue
      }
    }
    return fonts
  }

  func blendColor(foregroundColor: NSColor, backgroundColor: NSColor?) -> NSColor {
    let foregroundColor = foregroundColor.usingColorSpace(NSColorSpace.deviceRGB)!
    let backgroundColor = (backgroundColor ?? NSColor.gray).usingColorSpace(NSColorSpace.deviceRGB)!
    func blend(foreground: CGFloat, background: CGFloat) -> CGFloat {
      return (foreground * 2 + background) / 3
    }
    return NSColor(deviceRed: blend(foreground: foregroundColor.redComponent, background: backgroundColor.redComponent),
                   green: blend(foreground: foregroundColor.greenComponent, background: backgroundColor.greenComponent),
                   blue: blend(foreground: foregroundColor.blueComponent, background: backgroundColor.blueComponent),
                   alpha: blend(foreground: foregroundColor.alphaComponent, background: backgroundColor.alphaComponent))
  }
}
