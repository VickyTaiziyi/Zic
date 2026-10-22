import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zic/ui/chat/diff_view.dart';

void main() {
  group('extractDiff', () {
    test('old/new alias keys from input', () {
      final diff = extractDiff({
        'kind': 'toolCall',
        'toolName': 'Edit',
        'input': {
          'filePath': 'lib/a.dart',
          'old_string': 'a\nb\nc',
          'new_string': 'a\nB\nc',
        },
      });
      expect(diff, isNotNull);
      expect(diff!.filePath, 'lib/a.dart');
      // context kept, one removed + one added line
      expect(
        diff.lines.where((l) => l.type == DiffLineType.removed).single.text,
        '-b',
      );
      expect(
        diff.lines.where((l) => l.type == DiffLineType.added).single.text,
        '+B',
      );
      expect(diff.additions, 1);
      expect(diff.deletions, 1);
    });

    test('structuredPatch lines classify by +/- prefix', () {
      final diff = extractDiff({
        'structuredPatch': [
          {
            'filePath': 'x.py',
            'lines': [' ctx', '-del', '+add'],
          }
        ],
      });
      expect(diff, isNotNull);
      expect(diff!.filePath, 'x.py');
      expect(diff.lines, hasLength(3));
      expect(diff.lines[0].type, DiffLineType.context);
      expect(diff.lines[1].type, DiffLineType.removed);
      expect(diff.lines[2].type, DiffLineType.added);
    });

    test('structuredPatch map lines classify by type', () {
      final diff = extractDiff({
        'structuredPatch': [
          {
            'lines': [
              {'type': 'add', 'content': 'new'},
              {'type': 'remove', 'content': 'old'},
            ]
          }
        ],
      });
      expect(diff, isNotNull);
      expect(diff!.lines[0].type, DiffLineType.added);
      expect(diff.lines[0].text, 'new');
      expect(diff.lines[1].type, DiffLineType.removed);
      expect(diff.lines[1].text, 'old');
    });

    test('non-edit rows return null', () {
      expect(
        extractDiff({
          'kind': 'toolCall',
          'toolName': 'Bash',
          'input': {'command': 'ls'},
        }),
        isNull,
      );
    });

    test('long diffs collapse distant context', () {
      final old =
          [for (var i = 0; i < 50; i++) i == 25 ? 'x' : 'l$i'].join('\n');
      final neu =
          [for (var i = 0; i < 50; i++) i == 25 ? 'y' : 'l$i'].join('\n');
      final diff = extractDiff({
        'input': {'oldText': old, 'newText': neu},
      });
      expect(diff, isNotNull);
      // the long trailing context collapses to "keep + ellipsis + keep"
      expect(
        diff!.lines.any((l) => l.text.trim() == '⋯'),
        isTrue,
      );
      expect(
        diff.lines.where((l) => l.type == DiffLineType.removed).single.text,
        '-x',
      );
      expect(
        diff.lines.where((l) => l.type == DiffLineType.added).single.text,
        '+y',
      );
    });
  });

  group('DiffView widget', () {
    testWidgets('renders file path header and +/- lines', (tester) async {
      await tester.pumpWidget(_wrap(DiffView(
        diff: DiffData(
          filePath: 'lib/a.dart',
          lines: [
            DiffLine(DiffLineType.context, ' ctx'),
            DiffLine(DiffLineType.removed, '-old'),
            DiffLine(DiffLineType.added, '+new'),
          ],
        ),
      )));
      expect(find.text('lib/a.dart'), findsOneWidget);
      expect(find.text('-old'), findsOneWidget);
      expect(find.text('+new'), findsOneWidget);
    });
  });
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
