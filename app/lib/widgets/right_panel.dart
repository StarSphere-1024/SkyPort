import 'package:flutter/material.dart';

import 'right_panel/receive_display_widget.dart';
import 'right_panel/send_input_widget.dart';

class RightPanel extends StatelessWidget {
  const RightPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          const ReceiveDisplayWidget(),
          const SizedBox(height: 8),
          const SendInputWidget(),
        ],
      ),
    );
  }
}
