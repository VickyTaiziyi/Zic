import 'package:flutter/material.dart';

import 'legal_copy.dart';
import 'theme.dart';

/// Scrollable in-app document. No network, so it works offline.
class DocumentPage extends StatelessWidget {
  final String title;
  final List<LegalBlock> blocks;
  const DocumentPage({super.key, required this.title, required this.blocks});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          for (final block in blocks) ...[
            if (block.heading != null) ...[
              const SizedBox(height: 16),
              Text(
                block.heading!,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ZInk.solid(context),
                ),
              ),
              const SizedBox(height: 6),
            ],
            SelectableText(
              block.body,
              style: TextStyle(
                fontSize: 14,
                height: 1.55,
                color: ZInk.solid(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
