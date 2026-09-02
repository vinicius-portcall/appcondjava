import 'package:flutter/material.dart';

import '../services/sip_service.dart';

/// Lista os apartamentos com rota ativa (mesma lista da tela Rotas do
/// painel), em ordem numérica. Discagem normal (passa pela busca de
/// apartamento), igual discagem manual.
class ApartamentosScreen extends StatelessWidget {
  final SipService sip;
  final List<String> apartamentos;

  const ApartamentosScreen({
    super.key,
    required this.sip,
    required this.apartamentos,
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
      appBar: AppBar(title: const Text('Apartamentos')),
      body: apartamentos.isEmpty
          ? const Center(child: Text('Nenhum apartamento cadastrado.'))
          : ListView.separated(
              itemCount: apartamentos.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final apto = apartamentos[i];
                return ListTile(
                  leading: const Text('🏠', style: TextStyle(fontSize: 24)),
                  title: Text('Apto $apto'),
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
