import 'package:flutter/material.dart';

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
          Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Sin conexión: ${result.error}',
              style: TextStyle(color: theme.colorScheme.error),
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
        const Icon(Icons.lock, size: 18, color: Colors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Sesión cifrada con ${result.serverName ?? 'la PC'} · '
            '${average?.inMilliseconds ?? 0} ms de promedio '
            '(${best?.inMilliseconds ?? 0} ms el mejor de '
            '${result.rtts.length})',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
