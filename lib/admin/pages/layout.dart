import 'package:encrypta/admin/pages/auth_page.dart';
import 'package:flutter/material.dart';

class ResponsiveScreen extends StatelessWidget {
  const ResponsiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        double sWidth = constraints.maxWidth;
        double minWidth = sWidth * 0.5;
        return Center(
          child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth, maxWidth: sWidth),
              child: SizedBox(
                height: constraints.maxHeight,
                child: AuthPage(),
              )),
        );
      }),
    );
  }
}
