import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/documento.dart';

/// Repositório de documentos do condomínio (balancetes, regimento, atas) —
/// somente leitura, publicado pelo painel administrativo. Tocar num item
/// abre o arquivo no navegador/leitor de PDF do celular.
class DocumentosScreen extends StatelessWidget {
  final List<Documento> documentos;

  const DocumentosScreen({super.key, required this.documentos});

  IconData _iconePara(DocumentoCategoria categoria) {
    switch (categoria) {
      case DocumentoCategoria.balancete:
        return Icons.bar_chart_rounded;
      case DocumentoCategoria.regimento:
        return Icons.gavel_rounded;
      case DocumentoCategoria.ata:
        return Icons.groups_rounded;
      case DocumentoCategoria.outro:
        return Icons.description_outlined;
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  Future<void> _abrir(BuildContext context, Documento d) async {
    final uri = Uri.tryParse(d.arquivoUrl);
    final abriu =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o documento.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Documentos')),
      body: documentos.isEmpty
          ? const Center(child: Text('Nenhum documento publicado.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: documentos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final d = documentos[i];
                return Card(
                  elevation: 0,
                  color: scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    leading: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _iconePara(d.categoria),
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(
                      d.titulo,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${d.categoriaLabel} · ${_formatarData(d.criadoEm)}',
                    ),
                    trailing: const Icon(Icons.open_in_new_rounded),
                    onTap: () => _abrir(context, d),
                  ),
                );
              },
            ),
    );
  }
}
