import 'package:flutter/material.dart';
import 'package:jscan_ui/jscan_ui.dart';

import '../discovery_controller.dart';

/// Muestra el resultado de una prueba de conexión cifrada con una PC.
///
/// Se comparte entre la pantalla de descubrimiento y la lista de PCs
/// emparejadas.
class ProbeResultView extends StatelessWidget {
  const ProbeResultView({super.key, required this.result});

  final PeerProbeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!result.ok) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline,
            size: 17,
            color: JScanColors.danger,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Sin conexión: ${result.error}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: JScanColors.danger,
              ),
            ),
          ),
        ],
      );
    }

    final average = result.averageRtt;
    final best = result.bestRtt;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Icon(Icons.lock_outline, size: 17, color: JScanColors.success),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            'Sesión cifrada con ${result.serverName ?? 'la PC'} · '
            '${average?.inMilliseconds ?? 0} ms de promedio '
            '(${best?.inMilliseconds ?? 0} ms el mejor de '
            '${result.rtts.length})',
            style: theme.textTheme.bodySmall?.copyWith(
              color: JScanColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
