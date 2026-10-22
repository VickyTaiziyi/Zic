/// Desktop project catalog (`project.readTree`) and the task rows that hang
/// off it.
///
/// The relay overview (`bootstrap` / `workspace-list-updated`) only lists
/// window tabs. It does not include tasks, and a project added in ZCode
/// does not become a tab. The phone therefore asks the desktop project
/// service for every project and every indexed task, then folds projects
/// that are not already open tabs into the list the home screen renders.
library;

/// One non-deleted project from `project.readTree`.
class CatalogProject {
  final String id;
  final String name;
  final int position;
  final List<String> roots;
  final String? primaryRoot;

  const CatalogProject({
    required this.id,
    required this.name,
    required this.position,
    required this.roots,
    required this.primaryRoot,
  });
}

/// Projects plus their task rows, already shaped for [SessionEntry.fromRelayTask].
class ProjectCatalog {
  final List<CatalogProject> projects;
  final List<Map<String, dynamic>> tasks;

  const ProjectCatalog({required this.projects, required this.tasks});
}

/// `D:\Code\Zic` and `d:/code/zic/` are the same folder.
String normalizeWorkspacePath(String path) =>
    path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '').toLowerCase();

bool pathsEqual(String a, String b) =>
    normalizeWorkspacePath(a) == normalizeWorkspacePath(b);

/// Identity keys compare literally. Paths compare after slash and case folding.
bool workspaceKeysEqual(String a, String b) {
  if (a == b) return true;
  final aPath = a.contains('\\') || a.contains('/');
  final bPath = b.contains('\\') || b.contains('/');
  if (aPath || bPath) return pathsEqual(a, b);
  return false;
}

String displayStatusOf(Object? status) {
  switch (status) {
    case 'error':
      return 'error';
    case 'running':
      return 'running';
    case 'completed':
    case 'completedSuccess':
    case 'interrupted':
      return 'completed';
    default:
      return 'idle';
  }
}

/// Maps a `readTree` task or a `listTaskList` item onto the relay task
/// shape the home list already renders.
Map<String, dynamic>? relayTaskFromIndex(
  Map<String, dynamic> raw, {
  bool? pinned,
  bool? archived,
}) {
  final id = raw['taskId'] ?? raw['sessionId'];
  if (id == null || '$id'.isEmpty) return null;
  final projectId = raw['projectId'] ?? raw['project_id'];
  return {
    'taskId': id,
    'title': raw['title'] ?? '',
    'displayStatus': displayStatusOf(raw['displayStatus'] ?? raw['status']),
    'createdAt': raw['createdAt'],
    'updatedAt': raw['updatedAt'],
    'pinned': pinned ?? raw['pinned'] == true,
    'archived': archived ?? raw['archived'] == true,
    if (raw['unreadAt'] != null) 'unreadAt': raw['unreadAt'],
    if (raw['workspacePath'] != null) 'workspacePath': raw['workspacePath'],
    if (raw['workspaceIdentity'] != null)
      'workspaceIdentity': raw['workspaceIdentity'],
    if (projectId != null) 'projectId': projectId,
  };
}

List<Map<String, dynamic>> tasksFromListResult(
  dynamic res, {
  required bool pinned,
  required bool archived,
}) {
  final items = res is Map ? res['items'] ?? res['tasks'] : res;
  if (items is! List) return const [];
  final out = <Map<String, dynamic>>[];
  for (final raw in items) {
    if (raw is! Map) continue;
    final task = relayTaskFromIndex(
      raw.cast<String, dynamic>(),
      pinned: pinned,
      archived: archived,
    );
    if (task != null) out.add(task);
  }
  return out;
}

/// `null` when [res] is not a project-tree payload. An empty tree is a
/// real answer (the desktop has no projects) and is not null.
ProjectCatalog? parseProjectTree(dynamic res) {
  if (res is! Map) return null;
  if (!res.containsKey('projects') && !res.containsKey('tasks')) return null;
  final projects = <CatalogProject>[];
  final rawProjects = res['projects'];
  if (rawProjects is List) {
    for (final raw in rawProjects) {
      if (raw is! Map) continue;
      final project = _parseProject(raw.cast<String, dynamic>());
      if (project != null) projects.add(project);
    }
  }
  final tasks = <Map<String, dynamic>>[];
  final rawTasks = res['tasks'];
  if (rawTasks is List) {
    for (final raw in rawTasks) {
      if (raw is! Map) continue;
      final task = relayTaskFromIndex(raw.cast<String, dynamic>());
      if (task != null) tasks.add(task);
    }
  }
  projects.sort((a, b) => a.position.compareTo(b.position));
  return ProjectCatalog(projects: projects, tasks: tasks);
}

CatalogProject? _parseProject(Map<String, dynamic> raw) {
  if (raw['deleted'] == true) return null;
  final id = raw['id'] ?? raw['projectId'] ?? raw['project_id'];
  if (id == null || '$id'.isEmpty) return null;
  final roots = <String>[];
  String? primary;
  final rawRoots = raw['roots'];
  if (rawRoots is List) {
    for (final root in rawRoots) {
      if (root is String && root.isNotEmpty) {
        roots.add(root);
        primary ??= root;
      } else if (root is Map) {
        final path = root['rootPath'] ?? root['path'];
        if (path is! String || path.isEmpty) continue;
        roots.add(path);
        if (root['isPrimary'] == true) primary = path;
        primary ??= path;
      }
    }
  }
  final primaryField = raw['primaryRoot'];
  if (primaryField is String && primaryField.isNotEmpty) {
    primary = primaryField;
    if (!roots.any((r) => pathsEqual(r, primaryField))) roots.insert(0, primaryField);
  }
  var name = raw['name'];
  if (name is! String || name.trim().isEmpty) {
    final path = primary;
    if (path == null || path.isEmpty) return null;
    final parts = path.split(RegExp(r'[\\/]'));
    name = parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  }
  return CatalogProject(
    id: '$id',
    name: name.trim(),
    position: (raw['position'] as num?)?.toInt() ?? 0,
    roots: roots,
    primaryRoot: primary,
  );
}

/// Project cards first (desktop sidebar order), then window tabs that are
/// not a root of any of those projects. A tab whose folder is a project
/// root keeps its connection fields and takes the project name.
List<Map<String, dynamic>> mergeWorkspaceCatalog({
  required List<Map<String, dynamic>> tabs,
  required List<CatalogProject> projects,
}) {
  if (projects.isEmpty) return tabs;
  final byPath = <String, Map<String, dynamic>>{};
  for (final tab in tabs) {
    final path = tab['workspacePath'];
    if (path is String && path.isNotEmpty) {
      byPath.putIfAbsent(normalizeWorkspacePath(path), () => tab);
    }
  }
  final consumed = <String>{};
  final out = <Map<String, dynamic>>[];
  final sorted = [...projects]..sort((a, b) => a.position.compareTo(b.position));
  for (final project in sorted) {
    Map<String, dynamic>? tab;
    final primary = project.primaryRoot;
    if (primary != null) tab = byPath[normalizeWorkspacePath(primary)];
    if (tab == null) {
      for (final root in project.roots) {
        tab = byPath[normalizeWorkspacePath(root)];
        if (tab != null) break;
      }
    }
    for (final root in project.roots) {
      consumed.add(normalizeWorkspacePath(root));
    }
    if (primary != null) consumed.add(normalizeWorkspacePath(primary));
    final path = (tab?['workspacePath'] as String?) ??
        primary ??
        (project.roots.isEmpty ? null : project.roots.first);
    if (path == null || path.isEmpty) continue;
    out.add({
      if (tab != null) ...tab,
      'workspacePath': path,
      'label': project.name,
      'projectId': project.id,
      'rootPaths': project.roots.isEmpty ? <String>[path] : project.roots,
      if (tab == null) 'kind': 'local',
    });
  }
  for (final tab in tabs) {
    final path = tab['workspacePath'];
    if (path is String &&
        path.isNotEmpty &&
        consumed.contains(normalizeWorkspacePath(path))) {
      continue;
    }
    out.add(tab);
  }
  return out;
}

/// A task belongs to a card when it shares the project, one of the project's
/// roots, the card path, or the workspace key.
bool relayTaskOnWorkspace(Map<String, dynamic> task, Map<String, dynamic> ws) {
  final projectId = ws['projectId'];
  final taskProject = task['projectId'];
  if (projectId is String &&
      projectId.isNotEmpty &&
      taskProject != null &&
      '$taskProject' == projectId) {
    return true;
  }
  final taskPath = task['workspacePath'];
  if (taskPath is String && taskPath.isNotEmpty) {
    final roots = ws['rootPaths'];
    if (roots is List) {
      for (final root in roots) {
        if (root is String && root.isNotEmpty && pathsEqual(root, taskPath)) {
          return true;
        }
      }
    }
    final cardPath = ws['workspacePath'];
    if (cardPath is String && cardPath.isNotEmpty && pathsEqual(cardPath, taskPath)) {
      return true;
    }
  }
  final cardKey = _cardKey(ws);
  final taskKey = _taskKey(task);
  if (cardKey != null && taskKey != null && workspaceKeysEqual(cardKey, taskKey)) {
    return true;
  }
  return false;
}

String? _cardKey(Map<String, dynamic> ws) {
  final identity = ws['workspaceIdentity'];
  if (identity is String && identity.trim().isNotEmpty) return identity.trim();
  final path = ws['workspacePath'];
  if (path is String && path.isNotEmpty) return path;
  return null;
}

String? _taskKey(Map<String, dynamic> task) {
  final identity = task['workspaceIdentity'];
  if (identity is String && identity.trim().isNotEmpty) return identity.trim();
  final path = task['workspacePath'];
  if (path is String && path.isNotEmpty) return path;
  return null;
}
