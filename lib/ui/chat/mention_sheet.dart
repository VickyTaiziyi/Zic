import 'package:flutter/material.dart';

import '../../state/device_session.dart';
import '../theme.dart';
import '../ui_settings.dart';

/// Applies a picked mention: replaces the `@` trigger at [triggerEnd]-1
/// with `@<insert> ` and returns the new text.
String applyMentionInsert(
    String text, int triggerEnd, String insert) {
  final start = (triggerEnd - 1).clamp(0, text.length);
  return text.replaceRange(start, triggerEnd, '@$insert ');
}

/// One selectable @-mention result.
class MentionEntry {
  final String insert; // text inserted after @
  final String title;
  final String? subtitle;
  final IconData icon;

  const MentionEntry({
    required this.insert,
    required this.title,
    this.subtitle,
    required this.icon,
  });
}

/// Web chat.mention.* parity: category list → searchable results → insert
/// the reference into the composer. Categories: 文件 / 技能 / 子智能体 /
/// 会话 (whiteboards/plugins are desktop-only and omitted).
Future<MentionEntry?> showMentionSheet(
  BuildContext context,
  ChatGateway gateway,
) {
  return showModalBottomSheet<MentionEntry>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _MentionSheet(gateway: gateway),
  );
}

class _MentionSheet extends StatefulWidget {
  final ChatGateway gateway;
  const _MentionSheet({required this.gateway});

  @override
  State<_MentionSheet> createState() => _MentionSheetState();
}

class _MentionSheetState extends State<_MentionSheet> {
  static const _categories = ['files', 'skills', 'subagents', 'sessions'];
  String? _category; // null = category list
  String _query = '';
  List<Map<String, dynamic>> _files = const [];
  List<Map<String, dynamic>> _subagents = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final files = await widget.gateway.mentionFiles();
    if (mounted) {
      setState(() {
        _files = [...files]..sort(_byPathDepth);
        _loading = false;
      });
    }
  }

  static int _byPathDepth(Map<String, dynamic> a, Map<String, dynamic> b) =>
      '${a['relativePath'] ?? ''}'.compareTo('${b['relativePath'] ?? ''}');

  List<MentionEntry> get _entries {
    final q = _query.toLowerCase();
    switch (_category) {
      case 'files':
        return [
          for (final f in _files)
            if (q.isEmpty ||
                '${f['relativePath'] ?? ''}'.toLowerCase().contains(q) ||
                '${f['name'] ?? ''}'.toLowerCase().contains(q))
              MentionEntry(
                insert: '${f['relativePath'] ?? f['name'] ?? ''}',
                title: '${f['name'] ?? ''}',
                subtitle: '${f['relativePath'] ?? ''}',
                icon: f['type'] == 'directory'
                    ? Icons.folder_outlined
                    : Icons.description_outlined,
              ),
        ];
      case 'skills':
        return [
          for (final s in widget.gateway.mentionSkillsSync())
            if (q.isEmpty || '${s['name'] ?? ''}'.toLowerCase().contains(q))
              MentionEntry(
                insert: '${s['name'] ?? ''}',
                title: '${s['name'] ?? ''}',
                subtitle: '${s['description'] ?? ''}',
                icon: Icons.auto_awesome_outlined,
              ),
        ];
      case 'subagents':
        return [
          for (final a in _subagents)
            if (q.isEmpty ||
                '${a['name'] ?? ''}'.toLowerCase().contains(q))
              MentionEntry(
                insert: '${a['name'] ?? ''}',
                title: '${a['name'] ?? ''}',
                subtitle: '${a['description'] ?? ''}',
                icon: Icons.smart_toy_outlined,
              ),
        ];
      case 'sessions':
        return [
          for (final sess in widget.gateway.mentionSessions())
            if (q.isEmpty || sess.title.toLowerCase().contains(q))
              MentionEntry(
                insert: sess.title,
                title: sess.title,
                icon: Icons.chat_bubble_outline,
              ),
        ];
    }
    return const [];
  }

  Future<void> _enterCategory(String category) async {
    setState(() => _category = category);
    if (category == 'subagents' && _subagents.isEmpty) {
      setState(() => _loading = true);
      final agents = await widget.gateway.mentionSubagents();
      if (mounted) {
        setState(() {
          _subagents = agents;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  if (_category != null)
                    IconButton(
                      icon: const Icon(Icons.arrow_back, size: 18),
                      onPressed: () =>
                          setState(() {
                            _category = null;
                            _query = '';
                          }),
                    ),
                  Expanded(
                    child: Text(
                      tr(context, _category == null
                          ? 'chat.mention.title'
                          : 'chat.mention.category.$_category'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            if (_category == null)
              Expanded(
                child: ListView(
                  children: [
                    for (final c in _categories)
                      ListTile(
                        leading: Icon(_categoryIcon(c)),
                        title: Text(tr(context, 'chat.mention.category.$c'),
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(
                            tr(context, 'chat.mention.category.$c.description'),
                            style: TextStyle(
                                fontSize: 11.5,
                                color: ZInk.faint(context))),
                        onTap: () => _enterCategory(c),
                      ),
                  ],
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr(context, 'chat.mention.searchHint'),
                    prefixIcon: const Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _entries.isEmpty
                        ? Center(
                            child: Text(
                                tr(context, 'chat.mention.emptyResults'),
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: ZInk.faint(context))))
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                              for (final e in _entries.take(100))
                                ListTile(
                                  leading: Icon(e.icon,
                                      size: 18, color: ZInk.muted(context)),
                                  title: Text(e.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13.5)),
                                  subtitle: (e.subtitle ?? '').isNotEmpty
                                      ? Text(e.subtitle!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: ZInk.faint(context)))
                                      : null,
                                  dense: true,
                                  onTap: () =>
                                      Navigator.pop(context, e),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(tr(context, 'chat.mention.selectItem'),
                  style: TextStyle(fontSize: 10.5, color: ZInk.ghost(context))),
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String c) => switch (c) {
        'files' => Icons.description_outlined,
        'skills' => Icons.auto_awesome_outlined,
        'subagents' => Icons.smart_toy_outlined,
        _ => Icons.chat_bubble_outline,
      };
}
