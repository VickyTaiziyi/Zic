import 'package:flutter_test/flutter_test.dart';

import 'package:zic/state/workspace_file.dart';

void main() {
  test('web links are not workspace files', () {
    expect(workspaceFileHref('https://vicyi.com/a.md'), isNull);
    expect(workspaceFileHref('mailto:zic@localhost'), isNull);
  });

  test('relative paths join the workspace root', () {
    expect(
      resolveWorkspaceFilePath('docs/note.md', r'D:\Code\projects\Zic'),
      r'D:\Code\projects\Zic\docs\note.md',
    );
  });

  test('absolute paths stay as written', () {
    expect(
      resolveWorkspaceFilePath(r'D:\AI\note.md', r'D:\Code\projects\Zic'),
      r'D:\AI\note.md',
    );
  });
}
