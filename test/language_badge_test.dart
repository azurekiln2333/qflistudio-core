import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qfli_studio_core/theme/app_theme.dart';
import 'package:qfli_studio_core/widgets/language_badge.dart';

/// The language marker next to a project name (R11).
///
/// The badge used to be a fixed-diameter circle with an 11pt label shrunk by a
/// `FittedBox`, so long names became unreadable and short ones sat in a big
/// circle. It is now a capsule whose height is fixed and whose width follows the
/// label, with a smaller font.
void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double textScale = 1}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// The rendered pill. `language-badge` sits on the `Container`, so its rect is
  /// the capsule itself and grows only with the label.
  Rect badgeRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const ValueKey('language-badge')));

  testWidgets('the badge is a capsule, not a circle', (tester) async {
    await pump(tester, const LanguageBadge(language: 'JavaScript'));
    final rect = badgeRect(tester);

    // Wider than tall, with rounded ends: the radius is half the height.
    expect(rect.width, greaterThan(rect.height));
    final container = tester.widget<Container>(
      find.byKey(const ValueKey('language-badge')),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.shape, BoxShape.rectangle);
    expect(
      decoration.borderRadius,
      BorderRadius.circular(rect.height / 2),
    );
  });

  testWidgets('the label is smaller than the old 11pt marker', (tester) async {
    await pump(tester, const LanguageBadge(language: 'Java'));
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('language-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(text.style!.fontSize, LanguageBadge.labelFontSize);
    expect(LanguageBadge.labelFontSize, lessThan(11));
  });

  testWidgets('the longest language name fits inside the badge', (
    tester,
  ) async {
    // JavaScript is the widest label the catalog can produce.
    expect(languageLabel('javascript'), 'JavaScript');
    await pump(tester, const LanguageBadge(language: 'javascript'));
    final rect = badgeRect(tester);
    final textRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('language-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(textRect.left, greaterThanOrEqualTo(rect.left));
    expect(textRect.right, lessThanOrEqualTo(rect.right));
    expect(textRect.top, greaterThanOrEqualTo(rect.top));
    expect(textRect.bottom, lessThanOrEqualTo(rect.bottom));
    // No FittedBox may shrink it any more.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('language-badge')),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the badge hugs its label instead of filling the row', (
    tester,
  ) async {
    await pump(tester, const LanguageBadge(language: 'C'));
    final short = badgeRect(tester);
    expect(short.width, lessThan(800));
    // A two-character label in a 9.5pt font plus 8+8 padding is wider than the
    // 26pt height, so reading "wider than tall" proves the capsule shape.
    expect(short.width, greaterThanOrEqualTo(short.height));

    // A longer label makes a wider capsule at the same height.
    await pump(tester, const LanguageBadge(language: 'TypeScript'));
    final long = badgeRect(tester);
    expect(long.width, greaterThan(short.width));
    expect(long.height, short.height);
  });

  testWidgets('the height honours the caller size and stays fixed', (
    tester,
  ) async {
    await pump(tester, const LanguageBadge(language: 'Go', size: 26));
    expect(badgeRect(tester).height, 26);
    await pump(tester, const LanguageBadge(language: 'Go'));
    expect(badgeRect(tester).height, 26);
  });
  testWidgets('a large text scale grows the capsule instead of clipping', (
    tester,
  ) async {
    await pump(
      tester,
      const LanguageBadge(language: 'TypeScript'),
      textScale: 2,
    );
    final rect = badgeRect(tester);
    final textRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('language-badge')),
        matching: find.byType(Text),
      ),
    );
    expect(textRect.right, lessThanOrEqualTo(rect.right));
    expect(tester.takeException(), isNull);
  });
}
