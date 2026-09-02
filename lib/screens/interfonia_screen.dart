import 'package:flutter/material.dart';

import '../models/interfone.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';

/// Lista os interfones do condomínio: equipamentos SIP de verdade
/// (cadastrados em Interfones SIP no painel, dá pra ligar normal/vídeo) e
/// leitores faciais Control iD (cadastrados em Dispositivos Faciais, só
/// informativo — não são ramais SIP, não dá pra ligar).
class InterfoniaScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;
  final SipService sip;

  const InterfoniaScreen({
    super.key,
    required this.api,
    required this.conta,
    required this.sip,
  });

  @override
  State<InterfoniaScreen> createState() => _InterfoniaScreenState();
}

class _InterfoniaScreenState extends State<InterfoniaScreen> {
  List<Interfone> _interfones = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final interfones = await widget.api.fetchInterfonia(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _interfones = interfones;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os interfones.';
        _carregando = false;
      });
    }
  }

  Future<void> _ligar(Interfone i, {bool video = false}) async {
    if (i.destino == null || i.destino!.isEmpty) return;
    if (!widget.sip.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ainda não registrado no servidor. Aguarde e tente de novo.',
          ),
        ),
      );
      return;
    }
    await widget.sip.ligarPara(i.destino!, video: video);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Interfonia')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : _interfones.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Nenhum interfone cadastrado ainda.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _interfones.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final i = _interfones[index];
                  final isSip = i.tipo == TipoInterfone.sip;
                  return Card(
                    elevation: 0,
                    color: scheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            isSip ? Icons.call_outlined : Icons.face_retouching_natural,
                            color: isSip ? scheme.primary : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  i.nome,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isSip
                                      ? 'Interfone (ramal ${i.destino})'
                                      : 'Reconhecimento facial — só informativo',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isSip) ...[
                            IconButton(
                              tooltip: 'Ligar',
                              onPressed: () => _ligar(i),
                              icon: const Icon(Icons.call),
                            ),
                            if (i.suportaVideo)
                              IconButton(
                                tooltip: 'Chamada em vídeo',
                                onPressed: () => _ligar(i, video: true),
                                icon: const Icon(Icons.videocam),
                              ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
