import 'package:flutter/material.dart';

import '../models/chamado.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import 'novo_chamado_screen.dart';

/// Pedidos e manifestações (ouvidoria) enviados pelo morador à administração.
/// Diferente do Mural, cada morador só vê os próprios chamados.
class OuvidoriaScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;
  final List<String> apartamentos;

  const OuvidoriaScreen({
    super.key,
    required this.api,
    required this.conta,
    required this.apartamentos,
  });

  @override
  State<OuvidoriaScreen> createState() => _OuvidoriaScreenState();
}

class _OuvidoriaScreenState extends State<OuvidoriaScreen> {
  List<Chamado> _chamados = [];
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
      final chamados = await widget.api.fetchChamados(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _chamados = chamados;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar seus chamados.';
        _carregando = false;
      });
    }
  }

  Future<void> _novoChamado() async {
    final enviado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NovoChamadoScreen(
          api: widget.api,
          conta: widget.conta,
          apartamentos: widget.apartamentos,
        ),
      ),
    );
    if (enviado == true) _carregar();
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'aberto':
        return Colors.red;
      case 'em_andamento':
        return Colors.orange;
      case 'respondido':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Ouvidoria')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novoChamado,
        icon: const Icon(Icons.add),
        label: const Text('Novo chamado'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : _chamados.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Você ainda não enviou nenhum chamado.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: _chamados.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final c = _chamados[i];
                  final cor = _corStatus(c.status);
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
                              Expanded(
                                child: Text(
                                  c.assunto,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: cor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  c.statusLabel,
                                  style: TextStyle(
                                    color: cor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(c.mensagem, style: const TextStyle(height: 1.4)),
                          const SizedBox(height: 8),
                          Text(
                            [
                              if (c.apartamento != null &&
                                  c.apartamento!.isNotEmpty)
                                'Apto ${c.apartamento}',
                              _formatarData(c.criadoEm),
                            ].join('  •  '),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                          if (c.resposta != null && c.resposta!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Resposta da administração${c.respondidoEm != null ? ' — ${_formatarData(c.respondidoEm)}' : ''}:',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(c.resposta!),
                                ],
                              ),
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
