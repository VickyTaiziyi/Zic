import 'package:flutter_test/flutter_test.dart';
import 'package:zic/state/project_tree.dart';

void main() {
  test('parseProjectTree ignores a payload that is not a tree', () {
    expect(parseProjectTree(null), isNull);
    expect(parseProjectTree({'workspaces': []}), isNull);
    final empty = parseProjectTree({'projects': [], 'tasks': []});
    expect(empty, isNotNull);
    expect(empty!.projects, isEmpty);
    expect(empty.tasks, isEmpty);
  });

  test('parseProjectTree keeps projects in sidebar order and skips deleted', () {
    final catalog = parseProjectTree({
      'projects': [
        {
          'id': 'old',
          'name': 'Zic',
          'position': 3,
          'roots': [
            {'rootPath': r'D:\Code\projects\Zic', 'isPrimary': true},
          ],
        },
        {'id': 'gone', 'name': 'gone', 'deleted': true, 'position': -5},
        {
          'id': 'ops',
          'name': '  operations  ',
          'position': -1,
          'roots': [r'D:/AI/draft-8dd'],
        },
        {
          'id': 'noname',
          'position': 1,
          'primaryRoot': r'D:\Code\projects\fresh',
        },
      ],
      'tasks': [
        {
          'taskId': 't1',
          'title': '巡检',
          'status': 'interrupted',
          'projectId': 'ops',
          'workspacePath': r'D:\AI\draft-8dd',
          'pinned': false,
        },
        {'title': 'no id'},
      ],
    });
    expect(catalog, isNotNull);
    expect(catalog!.projects.map((p) => p.name).toList(), [
      'operations',
      'fresh',
      'Zic',
    ]);
    expect(catalog.projects[1].id, 'noname');
    expect(catalog.projects[1].primaryRoot, r'D:\Code\projects\fresh');
    expect(catalog.projects[2].roots, [r'D:\Code\projects\Zic']);
    expect(catalog.tasks, hasLength(1));
    expect(catalog.tasks.single['displayStatus'], 'completed');
    expect(catalog.tasks.single['projectId'], 'ops');
  });

  test('merge names a matching tab and appends projects that are not open', () {
    final tabs = [
      {
        'workspacePath': r'D:\Code\projects\Zic',
        'workspaceIdentity': 'zic-id',
        'label': 'draft-name',
        'kind': 'local',
      },
      {
        'workspacePath': r'D:\AI\draft-8dd',
        'label': 'draft-8dd',
      },
      {
        'workspacePath': r'D:\AI\default',
        'label': 'default',
      },
    ];
    final merged = mergeWorkspaceCatalog(
      tabs: tabs,
      projects: [
        CatalogProject(
          id: 'p-zic',
          name: 'Zic',
          position: 2,
          roots: [r'd:/code/projects/zic'],
          primaryRoot: r'd:/code/projects/zic',
        ),
        CatalogProject(
          id: 'p-ops',
          name: 'operations',
          position: -1,
          roots: [r'D:/AI/draft-8dd'],
          primaryRoot: r'D:/AI/draft-8dd',
        ),
        CatalogProject(
          id: 'p-new',
          name: 'fresh',
          position: 9,
          roots: [r'D:\Code\projects\fresh'],
          primaryRoot: r'D:\Code\projects\fresh',
        ),
      ],
    );
    expect(merged.map((w) => w['label']).toList(), [
      'operations',
      'Zic',
      'fresh',
      'default',
    ]);
    expect(merged[0]['projectId'], 'p-ops');
    expect(merged[1]['workspaceIdentity'], 'zic-id');
    expect(merged[1]['kind'], 'local');
    expect(merged[2]['kind'], 'local');
    expect(merged[2]['projectId'], 'p-new');
    expect(
      merged.where((w) => '${w['workspacePath']}'.contains('draft-8dd')).length,
      1,
    );
    final same = [
      {'workspacePath': '/only'},
    ];
    expect(
      identical(mergeWorkspaceCatalog(tabs: same, projects: const []), same),
      isTrue,
    );
  });

  test('a task matches its project, any root, or the workspace key', () {
    final project = {
      'projectId': 'p-ops',
      'workspacePath': r'D:\AI\draft-8dd',
      'rootPaths': [r'D:\AI\draft-8dd', r'D:\Code\extra'],
      'workspaceIdentity': 'ops-id',
    };
    expect(
      relayTaskOnWorkspace({
        'projectId': 'p-ops',
        'workspacePath': r'C:\somewhere\else',
      }, project),
      isTrue,
    );
    expect(
      relayTaskOnWorkspace({
        'workspacePath': r'd:/code/extra/',
      }, project),
      isTrue,
    );
    expect(
      relayTaskOnWorkspace({
        'workspaceIdentity': 'ops-id',
      }, project),
      isTrue,
    );
    expect(
      relayTaskOnWorkspace({
        'workspaceIdentity': 'other',
        'workspacePath': r'D:\AI\default',
      }, project),
      isFalse,
    );
    expect(pathsEqual(r'D:\Code\Zic\', 'd:/code/zic'), isTrue);
    expect(workspaceKeysEqual('ops-id', 'ops-id'), isTrue);
    expect(workspaceKeysEqual('ops-id', 'other'), isFalse);
    expect(workspaceKeysEqual(r'D:\Code\Zic', 'd:/code/zic'), isTrue);
  });

  test('listTaskList items keep the kind the query asked for', () {
    final rows = tasksFromListResult(
      {
        'items': [
          {'taskId': 'a', 'title': '置顶', 'status': 'running'},
          {'sessionId': '', 'title': 'drop'},
        ],
      },
      pinned: true,
      archived: false,
    );
    expect(rows, hasLength(1));
    expect(rows.single['pinned'], isTrue);
    expect(rows.single['archived'], isFalse);
    expect(rows.single['displayStatus'], 'running');
    expect(displayStatusOf('nope'), 'idle');
  });
}
