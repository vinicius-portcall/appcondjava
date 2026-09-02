import 'package:flutter/material.dart';

import '../models/acesso_portao.dart';

/// Histórico de acessos, unindo as três fontes reais que o sistema tem:
/// acionamentos de botão de portão (DTMF) feitos pelos moradores pelo app,
/// eventos recebidos de um leitor facial Control iD (quando o condomínio
/// tiver um cadastrado no painel — ver Dispositivos Faciais), e passes de
/// QR Code de visitante validados na portaria. Sem catraca integrada.
/// Visível para todo o condomínio (log de segurança compartilhado, não
/// privado por morador).
class HistoricoAcessosScreen extends StatelessWidget {
  final List<AcessoPortao> acessos;

  const HistoricoAcessosScreen({super.key, required this.acessos});

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year} às $hora:$minuto';
  }

  IconData _iconePara(TipoAcesso tipo) {
    switch (tipo) {
      case TipoAcesso.portaoApp:
        return Icons.lock_open_rounded;
      case TipoAcesso.facial:
        return Icons.face_retouching_natural_rounded;
      case TipoAcesso.qrcode:
        return Icons.qr_code_2_rounded;
      case TipoAcesso.outro:
        return Icons.door_front_door_outlined;
    }
  }

  String _subtitulo(AcessoPortao a) {
    if (a.tipo == TipoAcesso.facial) {
      final identificacao = a.nome != null && a.nome!.isNotEmpty
          ? a.tipoLabel
          : 'ID reconhecido: ${a.detalhe ?? '—'}';
      return '$identificacao · ${_formatarData(a.criadoEm)}';
    }
    if (a.tipo == TipoAcesso.qrcode) {
      return 'Visitante de ${a.ramal ?? '—'} · ${_formatarData(a.criadoEm)}';
    }
    return 'Ramal ${a.ramal ?? '—'} · ${_formatarData(a.criadoEm)}';
  }

  String _titulo(AcessoPortao a) {
    if (a.tipo == TipoAcesso.facial) {
      return a.nome != null && a.nome!.isNotEmpty ? a.nome! : a.tipoLabel;
    }
    return a.detalhe ?? a.tipoLabel;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de Acessos')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: scheme.surfaceContainerLow,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Mostra acionamentos de portão pelo app, eventos de leitores faciais cadastrados e passes de QR Code '
              'de visitante validados na portaria (todo o condomínio). Não inclui catraca.',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Expanded(
            child: acessos.isEmpty
                ? const Center(child: Text('Nenhum acesso registrado ainda.'))
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: acessos.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final a = acessos[i];
                      return ListTile(
                        leading: a.fotoUrl != null
                            ? CircleAvatar(
                                backgroundColor: scheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                backgroundImage: NetworkImage(a.fotoUrl!),
                              )
                            : CircleAvatar(
                                backgroundColor: scheme.primary.withValues(
                                  alpha: 0.12,
                                ),
                                child: Icon(
                                  _iconePara(a.tipo),
                                  color: scheme.primary,
                                  size: 20,
                                ),
                              ),
                        title: Text(
                          _titulo(a),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(_subtitulo(a)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
