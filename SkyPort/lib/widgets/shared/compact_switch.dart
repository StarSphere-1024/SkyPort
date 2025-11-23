import 'package:flutter/material.dart';

class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.padding,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
