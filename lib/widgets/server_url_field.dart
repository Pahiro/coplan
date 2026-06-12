import 'package:flutter/material.dart';

/// Collapsible "Server URL" section shared by the login and register screens.
/// Renders the toggle row plus (when expanded) the URL form field.
class ServerUrlField extends StatefulWidget {
  final TextEditingController controller;

  const ServerUrlField({super.key, required this.controller});

  @override
  State<ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends State<ServerUrlField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _show = !_show),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.dns_outlined, size: 14, color: muted),
              const SizedBox(width: 4),
              Text(
                _show ? 'Hide server URL' : 'Server URL',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              Icon(
                _show ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: muted,
              ),
            ],
          ),
        ),
        if (_show) ...[
          const SizedBox(height: 8),
          TextFormField(
            controller: widget.controller,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'PocketBase URL',
              hintText: 'http://192.168.1.100:8090',
              prefixIcon: Icon(Icons.link),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Server URL required';
              final uri = Uri.tryParse(v);
              if (uri == null || !uri.hasScheme) return 'Enter a valid URL';
              return null;
            },
          ),
        ],
      ],
    );
  }
}
