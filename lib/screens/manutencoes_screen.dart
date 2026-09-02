import 'package:flutter/material.dart';

import '../models/manutencao.dart';

/// Lista de manutenções prediais programadas — somente leitura, publicada
/// pelo painel administrativo (síndico/operador).
class ManutencoesScreen extends StatelessWidget {
  final List<Manutencao> manutencoes;

  const ManutencoesScreen({super.key, required this.manutencoes});

  String _formatarData(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  String _textoPrazo(int dias) {
    if (dias < 0) return 'Atrasada há ${-dias} dia${-dias == 1 ? '' : 's'}';
    if (dias == 0) return 'Hoje';
    return 'Faltam $dias dia${dias == 1 ? '' : 's'}';
  }

  Color _corPrazo(int dias, ColorScheme scheme) {
    if (dias < 0) return Colors.red;
    if (dias <= 30) return Colors.orange;
    return scheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manutenções Prediais')),
      body: manutencoes.isEmpty
          ? const Center(child: Text('Nenhuma manutenção programada.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: manutencoes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final m = manutencoes[i];
                final dias = m.diasRestantes;
                final cor = _corPrazo(dias, scheme);
                return Card(
                  elevation: 0,
                  color: scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.build_circle_outlined,
                              color: cor,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.equipamento,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (m.descricao != null && m.descricao!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            m.descricao!,
                            style: const TextStyle(height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: cor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _textoPrazo(dias),
                            style: TextStyle(
                              color: cor,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          [
                            'Próxima: ${_formatarData(m.proximaManutencao)}',
                            if (m.ultimaManutencao != null)
                              'Última: ${_formatarData(m.ultimaManutencao!)}',
                          ].join('  •  '),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
