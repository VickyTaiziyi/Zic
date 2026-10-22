import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:zic/state/device_session.dart';
import 'package:zic/ui/chat/mention_sheet.dart';

class _FakeGateway implements ChatGateway {
  List<Map<String, dynamic>> files = const [];
  List<Map<String, dynamic>> subagents = const [];
  List<({String id, String title})> sessions = const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  Future<List<Map<String, dynamic>>> mentionFiles() async => files;

  @override
  Future<List<Map<String, dynamic>>> mentionSubagents() async => subagents;

  @override
  List<({String id, String title})> mentionSessions() => sessions;
}

void main() {
  testWidgets('files category lists workspace files and returns the pick',
      (tester) async {
    final gateway = _FakeGateway()
      ..files = [
        {
          'name': 'chat_page.dart',
          'relativePath': 'lib/ui/chat/chat_page.dart',
          'type': 'file',
        },
      ];
    MentionEntry? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (buttonCtx) => FilledButton(
              onPressed: () async {
                picked = await showMentionSheet(buttonCtx, gateway);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    // fixed pumps: the sheet's autofocus caret never settles
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.text('文件'), findsOneWidget);
    await tester.tap(find.text('文件'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(find.byType(TextField), findsOneWidget,
        reason: 'entered the files category');
    expect(find.text('chat_page.dart'), findsOneWidget);
    await tester.tap(find.text('chat_page.dart'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    expect(picked?.insert, 'lib/ui/chat/chat_page.dart');
  });

  test('applyMentionInsert replaces the @ trigger and appends a space', () {
    // triggerEnd is the CURSOR offset (just after the typed @)
    expect(applyMentionInsert('看一下 @', 5, 'lib/a.dart'),
        '看一下 @lib/a.dart ');
    expect(applyMentionInsert('a @', 3, 'skill-name'), 'a @skill-name ');
    expect(applyMentionInsert('x\n@', 3, 'f.dart'), 'x\n@f.dart ');
  });
}
