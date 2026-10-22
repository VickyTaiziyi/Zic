import 'package:zic/protocol/conversation.dart';
import 'package:zic/state/device_session.dart';

/// DeviceSession subclass answering from local tables (never connects).
///
/// [channelHandler] intercepts every channel RPC (automation/off-peak ports
/// route through [DeviceSession.callChannel]): answer locally and assert on
/// [channelCalls] in tests.
class FakeDeviceSession extends DeviceSession {
  @override
  DeviceStatus status;
  @override
  final SessionsIndexState sessions;

  FakeDeviceSession({
    required super.deviceId,
    required super.params,
    List<Map<String, dynamic>> entries = const [],
    List<Map<String, dynamic>> workspaces = const [],
    this.relayTasks = const [],
    this.chatRows = const [],
    this.snapshotExtra = const {},
    this.channelHandler,
  }) : status = DeviceStatus.connected,
       sessions = SessionsIndexState(),
       super() {
    sessions.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {'workspaceId': 'ws-1', 'sessions': entries},
      },
    }, onGap: () {});
    _workspaces = workspaces;
    _active = workspaces.isEmpty ? null : workspaces.first;
  }

  late List<Map<String, dynamic>> _workspaces;

  /// Seeded relay overview tasks (`Dg`).
  @override
  List<Map<String, dynamic>> relayTasks;
  Map<String, dynamic>? _active;
  final List<Map<String, dynamic>> chatRows;

  /// Extra snapshot fields (queue / pendingInteractions) merged into the
  /// seeded chat feed.
  final Map<String, dynamic> snapshotExtra;

  /// Optional local answers for channel RPCs; every call is recorded in
  /// [channelCalls] regardless.
  final Future<dynamic> Function(
    String channel,
    String method,
    List<Object?> args,
  )?
  channelHandler;
  final List<(String, String, List<Object?>)> channelCalls = [];

  @override
  Future<dynamic> callChannel(
    String channel,
    String method, [
    List<Object?> args = const [],
  ]) async {
    channelCalls.add((channel, method, args));
    final handler = channelHandler;
    if (handler != null) return handler(channel, method, args);
    return null;
  }

  @override
  List<Map<String, dynamic>> get workspaces => _workspaces;
  @override
  Map<String, dynamic>? get activeWorkspace => _active;

  /// Seeded failure reason (app-error / close-code mapping).
  @override
  String? failureReason;

  @override
  Map<String, dynamic> get offPeakScope {
    final ws = _active ?? const <String, dynamic>{};
    return {
      'workspacePath': ws['workspacePath'],
      if (ws['workspaceIdentity'] != null)
        'workspaceIdentity': ws['workspaceIdentity'],
    };
  }

  @override
  Future<void> reloadTasks() async {}

  @override
  Future<void> openWorkspace(
    Map<String, dynamic> workspace, {
    String? taskId,
  }) async {
    _active = workspace;
    notifyListeners();
  }

  @override
  Future<ChatHandle> subscribe(String sessionId) async {
    final state = ConversationState();
    if (chatRows.isNotEmpty) {
      state.applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            'sessionId': sessionId,
            'logEpoch': 'e1',
            'revision': 1,
            'rows': {'window': chatRows, 'totalCount': chatRows.length},
            ...snapshotExtra,
          },
        },
      }, onGap: () {});
    }
    return ChatHandle(state: state, close: () async {});
  }

  @override
  Future<WorkspacePrep> prepareWorkspace() async => WorkspacePrep.fromMap({
    'configOptions': [
      {
        'id': 'model',
        'name': '模型',
        'currentValue': 'builtin/glm-5.2',
        'options': [
          {
            'value': 'builtin/glm-5.2',
            'name': 'GLM-5.2',
            'modelProviderName': 'BigModel',
          },
          {
            'value': 'kimi/moonshot-v2',
            'name': 'Moonshot V2',
            'modelProviderName': 'kimi_zz',
          },
        ],
      },
      {
        'id': 'thought_level',
        'name': '思考等级',
        'currentValue': 'max',
        'options': [
          {'value': 'max', 'name': '最高'},
          {'value': 'high', 'name': '高'},
          {'value': 'nothink', 'name': '关闭'},
        ],
      },
    ],
    'slashCommands': [
      {'name': 'compact', 'description': '压缩上下文', 'source': 'builtin'},
    ],
  });

  @override
  Future<List<SkillEntry>> skills() async => const [];

  @override
  String? get chatWorkspaceId => 'ws-1';
}
