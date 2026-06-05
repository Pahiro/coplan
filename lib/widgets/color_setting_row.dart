import 'package:flutter/material.dart';

class ColorSettingRow extends StatelessWidget {
  final String label;
  final String description;
  final Color current;
  final bool isEditable;
  final ValueChanged<Color> onChanged;

  /// When provided, a delete action is shown alongside the colour control.
  final VoidCallback? onDelete;

  const ColorSettingRow({
    super.key,
    required this.label,
    required this.description,
    required this.current,
    required this.isEditable,
    required this.onChanged,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: current,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(description,
            style: const TextStyle(fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isEditable
                ? TextButton(
                    onPressed: () => _pickColor(context),
                    child: const Text('Change'),
                  )
                : Tooltip(
                    message: 'Only $label can change their own colour',
                    child: const Icon(Icons.lock_outline,
                        size: 18, color: Colors.grey),
                  ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Remove',
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }

  void _pickColor(BuildContext context) {
    // Grid of preset colours — avoids adding a colour-picker dependency.
    // Two tones per hue (deep + medium) plus neutrals for plenty of choice.
    final presets = <Color>[
      // Blues / indigos
      Colors.blue[900]!,
      Colors.blue[600]!,
      Colors.lightBlue[700]!,
      Colors.indigo[700]!,
      Colors.indigo[400]!,
      // Cyans / teals / greens
      Colors.cyan[700]!,
      Colors.teal[700]!,
      Colors.teal[400]!,
      Colors.green[700]!,
      Colors.green[500]!,
      Colors.lightGreen[700]!,
      // Yellows / ambers / oranges
      Colors.lime[800]!,
      Colors.amber[700]!,
      Colors.orange[800]!,
      Colors.deepOrange[600]!,
      // Reds / pinks / purples
      Colors.red[700]!,
      Colors.pink[600]!,
      Colors.pink[300]!,
      Colors.purple[700]!,
      Colors.purple[400]!,
      Colors.deepPurple[600]!,
      // Neutrals / browns
      Colors.brown[600]!,
      Colors.blueGrey[600]!,
      Colors.grey[700]!,
    ];

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Choose colour for $label'),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: presets.map((c) {
                final isSelected = c.value == current.value;
                return GestureDetector(
                  onTap: () {
                    onChanged(c);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(8),
                      border: isSelected
                          ? Border.all(color: Colors.black, width: 3)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
