import 'package:flutter/material.dart';

import '../models/encomenda.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Encomendas recebidas na portaria para a unidade do morador. Cadastradas
/// (com foto opcional) só pelo painel administrativo; o morador confirma a
/// retirada pelo app, informando quem retirou.
class EncomendasScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const EncomendasScreen({super.key, required this.api, required this.conta});

  @override
  State<EncomendasScreen> createState() => _EncomendasScreenState();
}

class _EncomendasScreenState extends State<EncomendasScreen> {
  List<Encomenda> _encomendas = [];
  bool _carregando = true;
  String? _erro;
  int? _confirmandoId;

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
      final encomendas = await widget.api.fetchEncomendas(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _encomendas = encomendas;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as encomendas.';
        _carregando = false;
      });
    }
  }

  Future<void> _confirmarRetirada(Encomenda e) async {
    final nomeCtrl = TextEditingController();
    final nome = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirmar retirada'),
        content: TextField(
          controller: nomeCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quem está retirando?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (nomeCtrl.text.trim().isNotEmpty)
                Navigator.of(context).pop(nomeCtrl.text.trim());
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (nome == null || nome.isEmpty) return;

    setState(() => _confirmandoId = e.id);
    try {
      await widget.api.confirmarRetirada(
        widget.conta.ramal,
        widget.conta.senha,
        e.id,
        nome,
      );
      await _carregar();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível confirmar: $err'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _confirmandoId = null);
    }
  }

  IconData _iconePara(EncomendaTipo tipo) {
    switch (tipo) {
      case EncomendaTipo.pacote:
        return Icons.inventory_2_outlined;
      case EncomendaTipo.carta:
        return Icons.mail_outline;
      case EncomendaTipo.envelope:
        return Icons.markunread_mailbox_outlined;
      case EncomendaTipo.remedio:
        return Icons.medication_outlined;
      case EncomendaTipo.outro:
        return Icons.local_shipping_outlined;
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
      appBar: AppBar(title: const Text('Encomendas')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : _encomendas.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Nenhuma encomenda para a sua unidade.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _encomendas.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final e = _encomendas[i];
                  final confirmando = _confirmandoId == e.id;
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
                        if (e.fotoUrl != null)
                          Image.network(
                            e.fotoUrl!,
                            width: double.infinity,
                            height: 140,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(),
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _iconePara(e.tipo),
                                    color: scheme.primary,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      e.tipoLabel,
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
                                      color:
                                          (e.retirada
                                                  ? Colors.green
                                                  : Colors.red)
                                              .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      e.retirada ? 'Retirada' : 'Não retirada',
                                      style: TextStyle(
                                        color: e.retirada
                                            ? Colors.green
                                            : Colors.red,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (e.codigoRastreio != null &&
                                  e.codigoRastreio!.isNotEmpty)
                                Text('Código: ${e.codigoRastreio}'),
                              if (e.infoAdicional != null &&
                                  e.infoAdicional!.isNotEmpty)
                                Text(
                                  e.infoAdicional!,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Recebida em ${_formatarData(e.criadoEm)}',
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                              if (e.retirada) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Retirada por ${e.retiradoPor ?? '—'} em ${_formatarData(e.retiradoEm)}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: confirmando
                                        ? null
                                        : () => _confirmarRetirada(e),
                                    child: confirmando
                                        ? const SizedBox(
                                            height: 18,
                                            width: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Text('Confirmar retirada'),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
