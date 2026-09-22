import 'package:flutter/material.dart';

import '../models/rota.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Deixa o morador escolher a ordem de quem toca primeiro quando alguém
/// liga pro apartamento (celular, app como ramal digital, ou ramal
/// analógico). A sub-ordem dentro de cada bloco (ex.: qual celular toca
/// primeiro) continua sendo o que o síndico configurou no painel — aqui só
/// dá pra reordenar os 3 blocos entre si.
class RotaScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const RotaScreen({super.key, required this.api, required this.conta});

  @override
  State<RotaScreen> createState() => _RotaScreenState();
}

class _RotaScreenState extends State<RotaScreen> {
  List<CategoriaRota> _ordem = [];
  bool _carregando = true;
  bool _disponivel = false;
  bool _salvando = false;
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
      final resultado = await widget.api.fetchOrdemRota(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _disponivel = resultado.disponivel;
        _ordem = resultado.ordem;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar a ordem de chamada.';
        _carregando = false;
      });
    }
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await widget.api.salvarOrdemRota(
        widget.conta.ramal,
        widget.conta.senha,
        _ordem,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ordem de chamada salva!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar. Tente de novo.')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  void _reordenar(int oldIndex, int newIndex) {
    setState(() {
      final item = _ordem.removeAt(oldIndex);
      _ordem.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ordem de Chamada')),
      body: SafeArea(child: _corpo()),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(child: Text(_erro!));
    }
    if (!_disponivel) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esse recurso ainda não está configurado pro seu apartamento. '
            'Fale com o síndico ou a administração do condomínio.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Segure o ícone e arraste pra escolher quem toca primeiro '
            'quando alguém liga pro seu apartamento.',
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            buildDefaultDragHandles: false,
            onReorderItem: _reordenar,
            children: [
              for (var i = 0; i < _ordem.length; i++)
                Card(
                  key: ValueKey(_ordem[i]),
                  elevation: 0,
                  color: scheme.surfaceContainer,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Text(
                      '${i + 1}º',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                    title: Text(_ordem[i].label),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: _salvando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ),
      ],
    );
  }
}
