import 'package:flutter/material.dart';

import '../models/aviso.dart';

/// Mural de avisos do condomínio — somente leitura, publicado pelo painel
/// administrativo (síndico/operador). A lista já vem carregada da HomeScreen.
class MuralScreen extends StatelessWidget {
  final List<Aviso> avisos;

  const MuralScreen({super.key, required this.avisos});

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year} às $hora:$minuto';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Mural de Avisos')),
      body: avisos.isEmpty
          ? const Center(child: Text('Nenhum aviso publicado.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: avisos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final aviso = avisos[i];
                return Card(
                  elevation: 0,
                  color: scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (aviso.imagemUrl != null)
                        Image.network(
                          aviso.imagemUrl!,
                          width: double.infinity,
                          height: 160,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aviso.titulo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              aviso.mensagem,
                              style: const TextStyle(height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              [
                                if (aviso.criadoPor != null &&
                                    aviso.criadoPor!.isNotEmpty)
                                  aviso.criadoPor,
                                if (aviso.criadoEm != null)
                                  _formatarData(aviso.criadoEm),
                              ].whereType<String>().join(' — '),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
