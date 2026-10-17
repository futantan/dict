// SPDX-License-Identifier: GPL-3.0-or-later

import DictCore
import SwiftUI

/// 复习 (Design/main-app/review.html): today's due words as cards asking with a sentence the
/// user met them in, rated 忘了 / 记得 with 1 / 2, revealed with Space, pronounced with P.
/// The session lives in `WindowData.review`; this view draws it.
struct ReviewPage: View {
  let data: WindowData
  let navigation: MainNavigation
  let pronounce: (String, Locale.Language, SpeechRate) -> Void

  @State private var pace = PronunciationPace()
  @State private var contentWidth: CGFloat = 0

  private var model: ReviewModel { data.review }

  var body: some View {
    // A header of its own over the scroll view, as `PageScaffold` lays it out, with the
    // progress beside the title.
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.top, WindowLayout.pageTop)
        .padding(.horizontal, WindowLayout.pageSide)
        .padding(.bottom, WindowLayout.pageSpacing - WindowLayout.shadowRoom)
      ScrollView {
        content
          .frame(maxWidth: .infinity, alignment: .top)
          .onGeometryChange(for: CGFloat.self) {
            $0.size.width
          } action: {
            contentWidth = $0
          }
          .padding(.top, WindowLayout.shadowRoom)
          .padding(.horizontal, WindowLayout.pageSide)
          .padding(.bottom, WindowLayout.pageBottom)
      }
    }
    .task(id: navigation.reviewTermRequest) {
      // Cleared only once started, so the page does not start a second session meanwhile.
      if let termID = navigation.reviewTermRequest {
        await model.start(first: termID)
        navigation.didStartReview()
      } else {
        await model.appear()
      }
    }
  }

  // MARK: Header

  private var header: some View {
    VStack(alignment: .leading, spacing: ReviewLayout.headerSpacing) {
      HStack(alignment: .bottom, spacing: Spacing.input) {
        PageHeader(title: MainSection.review.title, subtitle: subtitle)
        if case .reviewing(let session) = model.phase {
          HStack(spacing: Spacing.pill + 2) {
            (Text(session.reviewed, format: .number)
              + Text(verbatim: " / \(session.total.formatted())")
              .foregroundColor(Color(Palette.textSecondary))
              .font(ReviewType.progressTotal.font))
              .font(ReviewType.progress.font)
              .monospacedDigit()
              .foregroundStyle(Color(Palette.textPrimary))
              .accessibilityHidden(true)
            EndButton { Task { await model.end() } }
          }
        }
      }
      if case .reviewing(let session) = model.phase {
        ProgressBar(done: session.reviewed, total: session.total)
      }
    }
  }

  private var subtitle: String {
    // The session's words while reviewing, then what is still due.
    if case .reviewing(let session) = model.phase {
      return ReviewStrings.dueToday(session.total)
    }
    return ReviewStrings.dueToday(data.dueCount)
  }

  // MARK: Content

  @ViewBuilder private var content: some View {
    switch model.phase {
    case .loading:
      Color.clear.frame(height: 1)
    case .empty(let next):
      MessageCard(
        title: ReviewStrings.emptyTitle,
        message: next.map { ReviewStrings.nextReview(nextText($0)) } ?? ReviewStrings.howItWorks,
        symbol: "checkmark.circle"
      ) {
        LinkButton(title: ReviewStrings.openWordList) { navigation.section = .saved }
      }
      .frame(maxWidth: ReviewLayout.cardMaxWidth)
    case .reviewing(let session):
      columns(session) { card(session) }
    case .finished(let session, let next):
      columns(session) { finished(next: next) }
    }
  }

  /// The card's column and the summary beside it, or under it where the two do not fit.
  private func columns<Main: View>(_ session: ReviewSession, @ViewBuilder main: () -> Main)
    -> some View
  {
    let summary = Summary(session: session)
    return Group {
      if contentWidth >= ReviewLayout.cardMinWidth + WindowLayout.pageSpacing
        + ReviewLayout.summaryWidth
      {
        HStack(alignment: .top, spacing: WindowLayout.pageSpacing) {
          main().frame(maxWidth: .infinity)
          summary.frame(width: ReviewLayout.summaryWidth)
        }
      } else {
        VStack(spacing: WindowLayout.pageSpacing) {
          main().frame(maxWidth: .infinity)
          summary.frame(width: ReviewLayout.summaryMaxWidth)
        }
      }
    }
  }

  @ViewBuilder private func card(_ session: ReviewSession) -> some View {
    if let card = session.current {
      let canPronounce = session.isRevealed || card.cloze == nil
      VStack(spacing: Spacing.pill) {
        ReviewCardView(
          card: card, isRevealed: session.isRevealed, appName: appName, dayText: dayText,
          reveal: model.reveal, answer: { rating in Task { await model.answer(rating) } },
          pronounce: { say(card) }
        )
        .frame(maxWidth: ReviewLayout.cardMaxWidth)
        .id(card.id)
        if let last = card.history.lastReview {
          Text(
            ReviewStrings.lastTime(
              last.rating,
              when: ReviewDates.ago(
                last.reviewedAt, today: data.day, timeZone: data.timeZone(),
                locale: SettingsText.uiLocale))
          )
          .font(WindowType.footnote.font)
          .foregroundStyle(Color(Palette.textSecondary))
        }
        KeyHints()
      }
      .background {
        Button("") { if canPronounce { say(card) } }
          .keyboardShortcut("p", modifiers: [])
          .hidden()
      }
    }
  }

  private func finished(next: LocalDay?) -> some View {
    let remaining = data.dueCount
    let message =
      remaining > 0
      ? ReviewStrings.stillDue(remaining)
      : next.map { ReviewStrings.nextReview(nextText($0)) } ?? ReviewStrings.howItWorks
    return MessageCard(
      title: remaining > 0 ? ReviewStrings.stoppedTitle : ReviewStrings.doneTitle,
      message: message, symbol: remaining > 0 ? "pause.circle" : "checkmark.circle"
    ) {
      if remaining > 0 {
        PrimaryButton(title: ReviewStrings.continueReview) { Task { await model.start() } }
      }
      LinkButton(title: ReviewStrings.openWordList) { navigation.section = .saved }
    }
    .frame(maxWidth: ReviewLayout.cardMaxWidth)
  }

  // MARK: Helpers

  private func say(_ card: ReviewCard) {
    pronounce(
      card.lemma, Locale.Language(identifier: card.item.term.language), pace.next(at: .now))
  }

  private func appName(_ bundleID: String) -> String? {
    ActivityLine.appName(bundleID: bundleID)
  }

  private func dayText(_ day: LocalDay) -> String {
    ReviewDates.day(day, today: data.day, locale: SettingsText.uiLocale)
  }

  private func nextText(_ day: LocalDay) -> String {
    ReviewDates.next(day, today: data.day, locale: SettingsText.uiLocale)
  }
}

// MARK: - Card

/// The card: the sentence with the word as a gap, then, revealed, the word, its sense, the
/// sentence's translation and another sentence, and the rating buttons.
private struct ReviewCardView: View {
  let card: ReviewCard
  let isRevealed: Bool
  let appName: (String) -> String?
  let dayText: (LocalDay) -> String
  let reveal: () -> Void
  let answer: (Rating) -> Void
  let pronounce: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: ReviewLayout.cardSpacing) {
      front
      if isRevealed {
        CardDivider()
        answerSection
        HStack(spacing: Spacing.pill) {
          RatingButton(title: ReviewStrings.forgot, key: "1", isPrimary: false) {
            answer(.again)
          }
          .keyboardShortcut("1", modifiers: [])
          RatingButton(title: ReviewStrings.remembered, key: "2", isPrimary: true) {
            answer(.good)
          }
          .keyboardShortcut("2", modifiers: [])
        }
        .padding(.top, Spacing.tight)
      } else {
        RatingButton(title: ReviewStrings.showAnswer, key: ReviewStrings.spaceKey, isPrimary: false)
        {
          reveal()
        }
        .keyboardShortcut(.space, modifiers: [])
        .padding(.top, Spacing.tight)
      }
    }
    .padding(.top, ReviewLayout.cardTop)
    .padding(.horizontal, ReviewLayout.cardSide)
    .padding(.bottom, ReviewLayout.cardBottom)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      let shape = RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
      shape.fill(Color(Palette.cardFill))
        .overlay(shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 8)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(ReviewStrings.card)
  }

  // MARK: Front

  @ViewBuilder private var front: some View {
    VStack(alignment: .leading, spacing: Spacing.row) {
      if let encounter = card.encounter, let cloze = card.cloze {
        source(encounter)
        Text(sentence(cloze))
          .font(ReviewType.sentence.font)
          .tracking(ReviewType.sentence.tracking)
          .lineSpacing(ReviewType.sentence.lineSpacing)
          .foregroundStyle(Color(Palette.textPrimary))
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityLabel(
            isRevealed
              ? cloze.before + cloze.term + cloze.after
              : cloze.before + ReviewStrings.blank + cloze.after)
      } else {
        // No sentence to ask with: the word itself.
        HStack(alignment: .top, spacing: Spacing.pill) {
          headword
          Spacer(minLength: 0)
          speaker
        }
      }
    }
  }

  /// 「Safari · 10 月 16 日」 after a globe for a web page, else an app.
  private func source(_ encounter: Encounter) -> some View {
    HStack(spacing: 6) {
      Image(systemName: encounter.sourceURL == nil ? "app" : "globe")
        .font(.system(size: ReviewType.source.size, weight: Size.symbolWeight))
        .accessibilityHidden(true)
      Text(detail(encounter))
    }
    .font(ReviewType.source.font)
    .foregroundStyle(Color(Palette.textSecondary))
  }

  /// The gap is the word in the highlight, drawn clear until revealed, so the sentence keeps
  /// its line breaks when the word appears.
  private func sentence(_ cloze: Cloze) -> AttributedString {
    var term = AttributedString("\u{200A}\(cloze.term)\u{200A}")
    term.backgroundColor = Color(Palette.highlight)
    if isRevealed {
      term.font = ReviewType.sentenceTerm.font
    } else {
      term.foregroundColor = .clear
    }
    return AttributedString(cloze.before) + term + AttributedString(cloze.after)
  }

  // MARK: Answer

  private var answerSection: some View {
    VStack(alignment: .leading, spacing: Spacing.section) {
      if card.cloze != nil || card.phonetic != nil {
        HStack(alignment: .top, spacing: Spacing.pill) {
          VStack(alignment: .leading, spacing: Spacing.buttons) {
            if card.cloze != nil { headword }
            if let phonetic = card.phonetic {
              Text(phonetic)
                .font(Typography.secondary.font)
                .foregroundStyle(Color(Palette.textSecondary))
            }
          }
          Spacer(minLength: 0)
          if card.cloze != nil { speaker }
        }
      }
      if let sense = card.sense {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.pill) {
          if let partOfSpeech = card.partOfSpeech {
            Text(CardStrings.partOfSpeech(partOfSpeech))
              .font(ReviewType.partOfSpeech.font)
              .foregroundStyle(Tone.accent.onTint)
              .lineLimit(1)
              .padding(.horizontal, Spacing.tight)
              .frame(minWidth: WindowLayout.tagWidth, minHeight: ReviewLayout.partOfSpeechHeight)
              .background(
                Tone.accent.tint,
                in: RoundedRectangle(cornerRadius: Radius.partOfSpeech, style: .continuous)
              )
              .fixedSize()
          }
          Text(sense)
            .font(ReviewType.sense.font)
            .foregroundStyle(Color(Palette.textPrimary))
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      if let translation = card.encounter?.sentenceTranslation, !translation.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text(ReviewStrings.translation)
            .font(Typography.label.font)
            .foregroundStyle(Color(Palette.accentOnTint))
          bodyText(translation)
        }
        .padding(.vertical, Spacing.blockVertical)
        .padding(.horizontal, Spacing.blockHorizontal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          Color(Palette.accentBlock),
          in: RoundedRectangle(cornerRadius: Radius.block, style: .continuous))
      }
      if let other = card.history.otherEncounter, let sentence = other.sentence {
        VStack(alignment: .leading, spacing: 6) {
          Text(ReviewStrings.alsoMet(detail(other)))
            .font(ReviewType.source.font)
            .foregroundStyle(Color(Palette.textSecondary))
          Text(Cloze(other).map(marked) ?? AttributedString(sentence))
            .font(ReviewType.body.font)
            .lineSpacing(ReviewType.body.lineSpacing)
            .foregroundStyle(Color(Palette.textQuiet))
            .fixedSize(horizontal: false, vertical: true)
          if let translation = other.sentenceTranslation, !translation.isEmpty {
            Text(translation)
              .font(ReviewType.otherTranslation.font)
              .lineSpacing(ReviewType.otherTranslation.lineSpacing)
              .foregroundStyle(Color(Palette.textSecondary))
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }

  private var headword: some View {
    Text(card.lemma)
      .font(Typography.headword.font)
      .tracking(Typography.headword.tracking)
      .foregroundStyle(Color(Palette.textPrimary))
      .fixedSize(horizontal: false, vertical: true)
  }

  private var speaker: some View {
    IconButton(
      title: ReviewStrings.pronounce, symbol: "speaker.wave.2", shortcut: "P", action: pronounce)
  }

  private func bodyText(_ text: String) -> some View {
    Text(text)
      .font(ReviewType.body.font)
      .lineSpacing(ReviewType.body.lineSpacing)
      .foregroundStyle(Color(Palette.textQuiet))
      .fixedSize(horizontal: false, vertical: true)
  }

  /// The sentence with the word in bold.
  private func marked(_ cloze: Cloze) -> AttributedString {
    var term = AttributedString(cloze.term)
    term.font = ReviewType.bodyTerm.font
    return AttributedString(cloze.before) + term + AttributedString(cloze.after)
  }

  private func detail(_ encounter: Encounter) -> String {
    [encounter.sourceApp.flatMap(appName), dayText(encounter.day)].compactMap(\.self)
      .joined(separator: " · ")
  }
}

/// 忘了 1 / 记得 2 / 显示答案 空格: a tall capsule across its half of the card.
private struct RatingButton: View {
  let title: String
  let key: String
  let isPrimary: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Spacing.row) {
        Text(title).lineLimit(1)
        Text(key)
          .font(Typography.caption.font)
          .foregroundStyle(isPrimary ? .white : Color(Palette.textSecondary))
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background {
            let shape = RoundedRectangle(cornerRadius: Radius.keycap - 1, style: .continuous)
            if isPrimary {
              shape.fill(.white.opacity(Size.keycapOnFill))
            } else {
              shape.fill(Color(Palette.cardFill))
                .overlay(shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5))
            }
          }
          .accessibilityHidden(true)
      }
      .font(ReviewType.rating.font)
      .foregroundStyle(isPrimary ? .white : Color(Palette.textPrimary))
      .frame(maxWidth: .infinity)
      .frame(height: ReviewLayout.ratingHeight)
      .background {
        if isPrimary {
          Capsule().fill(Color(Palette.accentFill))
        } else {
          Capsule().fill(Color(Palette.neutralTint))
            .overlay(Capsule().strokeBorder(Color(Palette.separator), lineWidth: 0.5))
        }
      }
      .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
    .focusRing(Capsule())
    .accessibilityLabel(title)
  }
}

/// 空格 显示答案 · 1 忘了 · 2 记得 · P 发音.
private struct KeyHints: View {
  var body: some View {
    HStack(spacing: Spacing.pill + 2) {
      hint(ReviewStrings.spaceKey, ReviewStrings.showAnswer)
      hint("1", ReviewStrings.forgot)
      hint("2", ReviewStrings.remembered)
      hint("P", ReviewStrings.pronounce)
    }
    .font(WindowType.detail.font)
    .foregroundStyle(Color(Palette.textSecondary))
    .accessibilityElement(children: .combine)
  }

  private func hint(_ key: String, _ title: String) -> some View {
    HStack(spacing: 6) {
      KeyCap(keys: key)
      Text(title).lineLimit(1)
    }
  }
}

// MARK: - Header and summary

/// 结束.
private struct EndButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(ReviewStrings.end)
        .font(ReviewType.end.font)
        .foregroundStyle(Color(Palette.textQuiet))
        .padding(.horizontal, Spacing.blockHorizontal)
        .frame(height: Size.button)
        .background {
          Capsule().fill(Color(Palette.neutralTint))
            .overlay(Capsule().strokeBorder(Color(Palette.separator), lineWidth: 0.5))
        }
        .fixedSize()
        .contentShape(Capsule())
    }
    .buttonStyle(PressStyle())
    .focusRing(Capsule())
  }
}

/// The session's progress under the header.
private struct ProgressBar: View {
  let done: Int
  let total: Int

  var body: some View {
    GeometryReader { proxy in
      Capsule()
        .fill(Color(Palette.accentFill))
        .frame(width: proxy.size.width * CGFloat(done) / CGFloat(max(total, 1)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(height: ReviewLayout.progressHeight)
    .background(Color(Palette.rowSeparator), in: Capsule())
    .clipShape(Capsule())
    .accessibilityElement()
    .accessibilityLabel(ReviewStrings.progress)
    .accessibilityValue(ReviewStrings.progressValue(done, of: total))
  }
}

/// 今天已复习 with 记得 and 忘了.
private struct Summary: View {
  let session: ReviewSession

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.pill) {
      VStack(alignment: .leading, spacing: Spacing.tight) {
        Text(ReviewStrings.reviewedToday)
          .font(WindowType.statLabel.font)
          .foregroundStyle(Color(Palette.textSecondary))
        HStack(alignment: .firstTextBaseline, spacing: 5) {
          Text(session.reviewed, format: .number)
            .font(WindowType.statValue.font)
            .foregroundStyle(Color(Palette.textPrimary))
          Text(ReviewStrings.wordsUnit(session.reviewed))
            .font(WindowType.statUnit.font)
            .foregroundStyle(Color(Palette.textSecondary))
        }
      }
      CardDivider()
      row(ReviewStrings.remembered, session.remembered, dot: Color(Palette.accentFill))
      row(ReviewStrings.forgot, session.forgotten, dot: Color(Palette.forgottenDot))
      Text(ReviewStrings.againNote)
        .font(WindowType.detail.font)
        .lineSpacing(WindowType.footnote.lineSpacing)
        .foregroundStyle(Color(Palette.textSecondary))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, Spacing.section)
    .padding(.horizontal, ReviewLayout.summarySide)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background {
      let shape = RoundedRectangle(cornerRadius: WindowLayout.cardRadius, style: .continuous)
      shape.fill(Color(Palette.cardFill))
        .overlay(shape.strokeBorder(Color(Palette.separator), lineWidth: 0.5))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(ReviewStrings.summary)
  }

  private func row(_ title: String, _ count: Int, dot: Color) -> some View {
    HStack(spacing: Spacing.buttons) {
      Circle().fill(dot).frame(width: 8, height: 8).accessibilityHidden(true)
      Text(title)
      Spacer(minLength: Spacing.buttons)
      Text(count, format: .number).fontWeight(.semibold)
    }
    .font(ReviewType.summaryRow.font)
    .foregroundStyle(Color(Palette.textPrimary))
  }
}

/// The finished and empty states: an icon, a title, a line and the actions.
private struct MessageCard<Actions: View>: View {
  let title: String
  let message: String
  let symbol: String
  @ViewBuilder let actions: Actions

  var body: some View {
    WindowCard(padding: ReviewLayout.cardTop) {
      VStack(alignment: .leading, spacing: Spacing.row) {
        Image(systemName: symbol)
          .font(.system(size: ReviewLayout.messageSymbol, weight: Size.symbolWeight))
          .foregroundStyle(Color(Palette.accent))
          .accessibilityHidden(true)
        Text(title)
          .font(ReviewType.messageTitle.font)
          .foregroundStyle(Color(Palette.textPrimary))
          .accessibilityAddTraits(.isHeader)
        Text(message)
          .font(Typography.callout.font)
          .lineSpacing(Typography.callout.lineSpacing)
          .foregroundStyle(Color(Palette.textSecondary))
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Spacing.input) { actions }
          .padding(.top, Spacing.buttons)
      }
    }
  }
}

private struct PressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
  }
}

// MARK: - Tokens

/// The review page's type, from the mockup.
private enum ReviewType {
  static let sentence = TextStyle(size: 22, lineSpacing: 8, tracking: -0.2)
  static let sentenceTerm = TextStyle(size: 22, weight: .semibold)
  static let source = TextStyle(size: 12)
  static let sense = TextStyle(size: 15, weight: .semibold)
  static let partOfSpeech = TextStyle(size: 12, weight: .semibold)
  static let body = TextStyle(size: 14.5, lineSpacing: 4)
  static let bodyTerm = TextStyle(size: 14.5, weight: .semibold)
  static let otherTranslation = TextStyle(size: 13.5, lineSpacing: 3)
  static let rating = TextStyle(size: 15, weight: .semibold)
  static let end = TextStyle(size: 13.5, weight: .semibold)
  static let progress = TextStyle(size: 14, weight: .semibold)
  static let progressTotal = TextStyle(size: 14, weight: .medium)
  static let summaryRow = TextStyle(size: 13.5)
  static let messageTitle = TextStyle(size: 17, weight: .semibold)
}

private enum ReviewLayout {
  static let headerSpacing: CGFloat = 14
  static let progressHeight: CGFloat = 4
  static let cardMaxWidth: CGFloat = 640
  /// Narrower than this and the summary goes under the card.
  static let cardMinWidth: CGFloat = 480
  static let cardTop: CGFloat = 32
  static let cardSide: CGFloat = 36
  static let cardBottom: CGFloat = 28
  static let cardSpacing: CGFloat = 22
  static let partOfSpeechHeight: CGFloat = 18
  static let ratingHeight: CGFloat = 48
  static let summaryWidth: CGFloat = 200
  static let summaryMaxWidth: CGFloat = 240
  static let summarySide: CGFloat = 18
  static let messageSymbol: CGFloat = 26
}

extension Palette {
  /// The 忘了 dot in the review summary, quieter than the 记得 accent.
  fileprivate static let forgottenDot = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      ? NSColor(srgbRed: 0x5A / 255, green: 0x5A / 255, blue: 0x60 / 255, alpha: 1)
      : NSColor(srgbRed: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255, alpha: 1)
  }
}
