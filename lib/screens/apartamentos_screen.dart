import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';
import 'bloqueios_screen.dart';

/// Lista as unidades (apartamentos/casas) com rota ativa — mesma lista da
/// tela Rotas do painel, em ordem numérica. Discagem normal (passa pela
/// busca de unidade), igual discagem manual.
class ApartamentosScreen extends StatelessWidget {
  final SipService sip;
  final List<String> apartamentos;
  final ApiService api;
  final SipAccount conta;

  const ApartamentosScreen({
    super.key,
    required this.sip,
    required this.apartamentos,
    required this.api,
    required this.conta,
  });

  Future<void> _ligar(
    BuildContext context,
    String apto, {
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
    await sip.ligarPara(apto, video: video);
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
      body: apartamentos.isEmpty
          ? const Center(child: Text('Nenhuma unidade cadastrada.'))
          : ListView.separated(
              itemCount: apartamentos.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final apto = apartamentos[i];
                return ListTile(
                  leading: const Text('🏠', style: TextStyle(fontSize: 24)),
                  title: Text('Unidade $apto'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Chamada normal',
                        onPressed: () => _ligar(context, apto),
                        icon: const Icon(Icons.call),
                      ),
                      IconButton(
                        tooltip: 'Chamada de vídeo',
                        onPressed: () => _ligar(context, apto, video: true),
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
