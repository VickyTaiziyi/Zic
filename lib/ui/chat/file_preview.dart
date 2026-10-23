import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../state/device_session.dart';
import '../theme.dart';
import '../ui_settings.dart';
import 'markdown_view.dart';

/// Opens an http(s) link in the browser. A file href opens the desktop
/// document. Other schemes are ignored.
Future<void> openChatLink(
  BuildContext context,
  ChatGateway gateway,
  String label,
  String? href,
) async {
  final raw = (href == null || href.trim().isEmpty) ? label : href.trim();
  final web = Uri.tryParse(raw);
  if (web != null && (web.scheme == 'https' || web.scheme == 'http')) {
    await launchUrl(web, mode: LaunchMode.externalApplication);
    return;
  }
  final file = workspaceFileHref(raw);
  if (file == null || !context.mounted) return;
  final path = resolveWorkspaceFilePath(file, gateway.workspacePath);
  await showWorkspaceFilePreview(context, gateway, path);
}

Future<void> showWorkspaceFilePreview(
  BuildContext context,
  ChatGateway gateway,
  String path,
) {
  final name = _baseName(path);
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FilePreviewPage(
        title: name,
        load: () => gateway.previewWorkspaceFile(path),
      ),
    ),
  );
}

Future<void> showBytesPreview(
  BuildContext context, {
  required String title,
  required Future<WorkspaceFilePreview> Function() load,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => FilePreviewPage(title: title, load: load),
    ),
  );
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]'));
  return parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
}

class FilePreviewPage extends StatefulWidget {
  final String title;
  final Future<WorkspaceFilePreview> Function() load;

  const FilePreviewPage({super.key, required this.title, required this.load});

  @override
  State<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends State<FilePreviewPage> {
  WorkspaceFilePreview? _preview;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    try {
      final preview = await widget.load();
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _error = preview.error;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final preview = _preview;
    if (_error != null || preview == null) {
      return _note(context, tr(context, 'chat.file.failed'));
    }
    if (preview.binary) {
      return _note(context, tr(context, 'chat.file.binary'));
    }
    if (preview.isImage && preview.bytes != null) {
      return InteractiveViewer(
        child: Center(child: Image.memory(preview.bytes!)),
      );
    }
    final text = preview.text ?? '';
    final markdown = widget.title.toLowerCase().endsWith('.md');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (markdown) ZicMarkdown(text) else SelectableText(text),
        if (preview.truncated) ...[
          const SizedBox(height: 12),
          Text(
            tr(context, 'chat.file.truncated'),
            style: TextStyle(fontSize: 12, color: ZInk.faint(context)),
          ),
        ],
      ],
    );
  }

  Widget _note(BuildContext context, String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, height: 1.5, color: ZInk.soft(context)),
        ),
      ),
    );
  }
}
