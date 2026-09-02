import 'package:flutter/material.dart';

import '../models/sala_conferencia.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';

/// Sala de conferência de áudio (reunião/assembleia): criada pelo síndico
/// no painel, os moradores só listam e entram — entrar é uma chamada
/// normal pro número da sala, cai direto no ConfBridge do Asterisk.
class SalasConferenciaScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;
  final SipService sip;

  const SalasConferenciaScreen({
    super.key,
    required this.api,
    required this.conta,
    required this.sip,
  });

  @override
  State<SalasConferenciaScreen> createState() =>
      _SalasConferenciaScreenState();
}

class _SalasConferenciaScreenState extends State<SalasConferenciaScreen> {
  List<SalaConferencia> _salas = [];
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
      final salas = await widget.api.fetchSalasConferencia(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _salas = salas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as salas de reunião.';
        _carregando = false;
      });
    }
  }

  Future<void> _entrar(SalaConferencia sala, {bool video = false}) async {
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
    await widget.sip.ligarPara(sala.numeroDiscagem, video: video);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Salas de Reunião')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : _salas.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Nenhuma sala de reunião ativa no momento.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _salas.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final sala = _salas[i];
                  return Card(
                    elevation: 0,
                    color: scheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.groups)),
                      title: Text(
                        sala.nome,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text(
                        'O vídeo mostra quem está falando no momento',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Entrar só com áudio',
                            onPressed: () => _entrar(sala),
                            icon: const Icon(Icons.call),
                          ),
                          IconButton(
                            tooltip: 'Entrar com vídeo',
                            onPressed: () => _entrar(sala, video: true),
                            icon: const Icon(Icons.videocam),
                          ),
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
