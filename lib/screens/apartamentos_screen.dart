import 'package:flutter/material.dart';

import '../models/unidade.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';
import 'bloqueios_screen.dart';

/// Lista as unidades (apartamentos/casas) com rota ativa — mesma lista da
/// tela Rotas do painel, em ordem numérica. Discagem normal (passa pela
/// busca de unidade), igual discagem manual.
class ApartamentosScreen extends StatelessWidget {
  final SipService sip;

  /// As unidades com o nome do morador quando o painel tiver um cadastrado
  /// (coluna `nome` de `rotas_horarios`, opcional). Em condomínio sem nomes
  /// preenchidos, a lista é a mesma de sempre — só os números.
  final List<Unidade> unidades;
  final ApiService api;
  final SipAccount conta;

  const ApartamentosScreen({
    super.key,
    required this.sip,
    required this.unidades,
    required this.api,
    required this.conta,
  });

  Future<void> _ligar(
    BuildContext context,
    Unidade unidade, {
    bool video = false,
  }) async {
    if (!sip.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ainda não registrado no servidor. Aguarde e tente de novo.',
          ),
        ),
      );
      return;
    }
    // entreUnidades esconde os atalhos de portão na tela de chamada —
    // ver SipService.chamadaEntreUnidades.
    // O nome do morador (opcional no painel) vai junto para a tela de
    // chamada mostrar "102 — João Silva" em vez de só o número.
    await sip.ligarPara(
      unidade.apartamento,
      video: video,
      entreUnidades: true,
      nomeExibicao: unidade.rotulo,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Unidades'),
        actions: [
          IconButton(
            tooltip: 'Bloquear unidades',
            icon: const Icon(Icons.block),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BloqueiosScreen(api: api, conta: conta),
              ),
            ),
          ),
        ],
      ),
      body: unidades.isEmpty
          ? const Center(child: Text('Nenhuma unidade cadastrada.'))
          : ListView.separated(
              itemCount: unidades.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final unidade = unidades[i];
                final apto = unidade.apartamento;
                final nome = unidade.nome;
                return ListTile(
                  leading: const Text('🏠', style: TextStyle(fontSize: 24)),
                  title: Text('Unidade $apto'),
                  // O nome do morador é opcional no painel: condomínio que
                  // não cadastrar nenhum vê a lista exatamente como antes,
                  // sem um subtítulo vazio ocupando espaço.
                  subtitle: nome == null ? null : Text(nome),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Chamada normal',
                        onPressed: () => _ligar(context, unidade),
                        icon: const Icon(Icons.call),
                      ),
                      IconButton(
                        tooltip: 'Chamada de vídeo',
                        onPressed: () => _ligar(context, unidade, video: true),
                        icon: const Icon(Icons.videocam),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
