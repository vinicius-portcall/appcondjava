import 'package:flutter/material.dart';

import '../models/chamada_historico.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Histórico de chamadas do morador — recebidas, efetuadas e perdidas.
///
/// Diferente do Histórico de Acessos, que é um log de segurança do condomínio
/// inteiro, este é **privado do morador**: mostra só as chamadas do ramal dele
/// e das unidades que a rota aponta pra ele. Quem decide esse recorte é o
/// servidor, em `api_historico_chamadas.php`.
///
/// A gravação do áudio não é oferecida aqui de propósito: a política de
/// privacidade publicada diz que as gravações ficam sob responsabilidade da
/// administração, que define quem acessa e por quanto tempo. Expor no app
/// contradiria a política e a declaração de Segurança dos Dados na loja.
///
/// Busca os dados sozinha (não recebe prontos como a de acessos) porque a
/// lista pode passar de cem linhas e não faz sentido carregar isso na abertura
/// do app, junto com o resto.
class HistoricoChamadasScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const HistoricoChamadasScreen({
    super.key,
    required this.api,
    required this.conta,
  });

  @override
  State<HistoricoChamadasScreen> createState() =>
      _HistoricoChamadasScreenState();
}

class _HistoricoChamadasScreenState extends State<HistoricoChamadasScreen> {
  List<ChamadaHistorico>? _chamadas;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final lista = await widget.api.fetchHistoricoChamadas(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() => _chamadas = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar o histórico.';
        _chamadas = [];
      });
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '';
    final agora = DateTime.now();
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');

    final mesmoDia =
        data.year == agora.year &&
        data.month == agora.month &&
        data.day == agora.day;
    if (mesmoDia) return 'Hoje às $hora:$minuto';

    final ontem = agora.subtract(const Duration(days: 1));
    final foiOntem =
        data.year == ontem.year &&
        data.month == ontem.month &&
        data.day == ontem.day;
    if (foiOntem) return 'Ontem às $hora:$minuto';

    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes às $hora:$minuto';
  }

  ({IconData icone, Color cor}) _marcaDe(TipoChamada tipo, ColorScheme scheme) {
    switch (tipo) {
      case TipoChamada.recebida:
        return (icone: Icons.call_received_rounded, cor: Colors.green);
      case TipoChamada.efetuada:
        return (icone: Icons.call_made_rounded, cor: scheme.primary);
      case TipoChamada.perdida:
        return (icone: Icons.call_missed_rounded, cor: Colors.redAccent);
    }
  }

  String _subtitulo(ChamadaHistorico c) {
    final quando = _formatarData(c.data);
    final duracao = c.duracaoLabel;
    if (duracao == null) {
      // Chamada que saiu e ninguém atendeu não é "perdida" (isso é coisa de
      // chamada recebida) — por isso o texto muda conforme a direção.
      final motivo = c.tipo == TipoChamada.efetuada
          ? 'Não atendida'
          : 'Perdida';
      return '$motivo · $quando';
    }
    return '${c.tipoLabel} · $duracao · $quando';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chamadas = _chamadas;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Chamadas'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: chamadas == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: chamadas.isEmpty
                  ? ListView(
                      // ListView e não Center: sem rolagem o "puxar pra
                      // atualizar" não funciona, e a tela vazia é justamente
                      // onde o morador mais tenta recarregar.
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            _erro ?? 'Nenhuma chamada registrada ainda.',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: chamadas.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final c = chamadas[i];
                        final marca = _marcaDe(c.tipo, scheme);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: marca.cor.withValues(alpha: 0.12),
                            child: Icon(
                              marca.icone,
                              color: marca.cor,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            c.outro,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_subtitulo(c)),
                        );
                      },
                    ),
            ),
    );
  }
}
