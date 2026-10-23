import 'dart:convert';
import 'dart:typed_data';

/// A workspace document the phone can show. Text comes from
/// `file.readTextFile`. Images come from `file.readMediaPreview`.
/// Anything else stays closed: the phone does not pretend to open it.
class WorkspaceFilePreview {
  final String path;
  final String? text;
  final Uint8List? bytes;
  final String? mediaType;
  final bool truncated;
  final bool binary;
  final String? error;

  const WorkspaceFilePreview({
    required this.path,
    this.text,
    this.bytes,
    this.mediaType,
    this.truncated = false,
    this.binary = false,
    this.error,
  });

  bool get isImage =>
      bytes != null && (mediaType ?? '').startsWith('image/');
}

/// `http`, `https`, and `mailto` stay links. A file href, including
/// `file:`, is a workspace document.
String? workspaceFileHref(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value.startsWith('#')) return null;
  final lower = value.toLowerCase();
  if (lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('mailto:')) {
    return null;
  }
  if (lower.startsWith('file:')) {
    final uri = Uri.tryParse(value);
    if (uri != null && uri.scheme == 'file') {
      try {
        final path = uri.toFilePath();
        if (path.isNotEmpty) return path;
      } catch (_) {}
    }
    return value.replaceFirst(RegExp(r'^file:/*'), '');
  }
  return value;
}

/// Absolute paths stay as written. A relative path is joined to the
/// workspace root the bridge is open on.
String resolveWorkspaceFilePath(String href, String? root) {
  var value = href.trim();
  if (value.startsWith('./')) value = value.substring(2);
  final absolute = value.startsWith('/') ||
      value.startsWith('\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  if (absolute || root == null || root.isEmpty) return value;
  final sep = root.contains('\\') ? '\\' : '/';
  final rel = value.replaceAll('\\', sep).replaceAll('/', sep);
  if (root.endsWith('/') || root.endsWith('\\')) return '$root$rel';
  return '$root$sep$rel';
}

/// Path carried by a chat attachment, when the desktop wrote one.
String? attachmentWorkspacePath(Map<String, dynamic> attachment) {
  for (final key in const ['path', 'filePath', 'relativePath']) {
    final value = attachment[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Turns attachment bytes into a preview. Null bytes and binary payloads
/// do not become text.
WorkspaceFilePreview previewFromBytes(
  String name,
  Uint8List bytes,
  String? mediaType,
) {
  final media = mediaType ?? '';
  if (media.startsWith('image/')) {
    return WorkspaceFilePreview(path: name, bytes: bytes, mediaType: media);
  }
  if (_looksBinary(bytes)) {
    return WorkspaceFilePreview(path: name, binary: true);
  }
  return WorkspaceFilePreview(
    path: name,
    text: utf8.decode(bytes, allowMalformed: true),
  );
}

bool _looksBinary(Uint8List bytes) {
  if (bytes.length > 1500000) return true;
  final sample = bytes.length < 4096 ? bytes.length : 4096;
  if (sample == 0) return false;
  var odd = 0;
  for (var i = 0; i < sample; i++) {
    final b = bytes[i];
    if (b == 0) return true;
    if (b < 9 || (b > 13 && b < 32)) odd++;
  }
  return odd / sample > 0.1;
}
