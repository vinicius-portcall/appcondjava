import 'package:flutter/material.dart';

import '../models/agendamento.dart';
import '../models/espaco.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Reserva de espaços comuns (Academia, Churrasqueira, Salão de Festas etc.).
/// Cada espaço tem uma janela de horário fixa dividida em intervalos prontos
/// (não é hora livre) — o morador escolhe um intervalo já pronto, evitando
/// sobreposição sem precisar de lógica de conflito no app.
class AgendamentosScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const AgendamentosScreen({super.key, required this.api, required this.conta});

  @override
  State<AgendamentosScreen> createState() => _AgendamentosScreenState();
}

class _AgendamentosScreenState extends State<AgendamentosScreen> {
  List<Espaco> _espacos = [];
  bool _carregandoEspacos = true;
  String? _erroEspacos;

  Espaco? _espacoSelecionado;
  DateTime _dataSelecionada = DateTime.now();
  List<SlotDisponibilidade> _slots = [];
  bool _carregandoSlots = false;

  List<Agendamento> _minhasReservas = [];
  bool _carregandoReservas = true;

  @override
  void initState() {
    super.initState();
    _carregarEspacos();
    _carregarReservas();
  }

  String _formatarDataApi(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatarDataBr(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _carregarEspacos() async {
    setState(() {
      _carregandoEspacos = true;
      _erroEspacos = null;
    });
    try {
      final espacos = await widget.api.fetchEspacos(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _espacos = espacos;
        _carregandoEspacos = false;
        if (_espacoSelecionado == null && espacos.isNotEmpty) {
          _espacoSelecionado = espacos.first;
        }
      });
      if (_espacoSelecionado != null) await _carregarSlots();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroEspacos = 'Não foi possível carregar os espaços comuns.';
        _carregandoEspacos = false;
      });
    }
  }

  Future<void> _carregarReservas() async {
    setState(() => _carregandoReservas = true);
    try {
      final reservas = await widget.api.fetchAgendamentos(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _minhasReservas = reservas;
        _carregandoReservas = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoReservas = false);
    }
  }

  Future<void> _carregarSlots() async {
    final espaco = _espacoSelecionado;
    if (espaco == null) return;
    setState(() => _carregandoSlots = true);
    try {
      final slots = await widget.api.fetchDisponibilidade(
        widget.conta.ramal,
        widget.conta.senha,
        espacoId: espaco.id,
        data: _formatarDataApi(_dataSelecionada),
      );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _carregandoSlots = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _slots = [];
        _carregandoSlots = false;
      });
    }
  }

  Future<void> _escolherData() async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataSelecionada.isBefore(agora) ? agora : _dataSelecionada,
      firstDate: agora,
      lastDate: agora.add(const Duration(days: 90)),
    );
    if (escolhida == null) return;
    setState(() => _dataSelecionada = escolhida);
    await _carregarSlots();
  }

  Future<void> _reservarSlot(SlotDisponibilidade slot) async {
    final espaco = _espacoSelecionado;
    if (espaco == null) return;

    final convidadosCtrl = TextEditingController();
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reservar ${espaco.nome}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_formatarDataBr(_dataSelecionada)} · ${slot.horaInicio}–${slot.horaFim}',
            ),
            if (espaco.taxa > 0) ...[
              const SizedBox(height: 4),
              Text('Taxa: R\$ ${espaco.taxa.toStringAsFixed(2)}'),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: convidadosCtrl,
              decoration: const InputDecoration(
                labelText: 'Convidados (opcional)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar reserva'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      await widget.api.criarAgendamento(
        widget.conta.ramal,
        widget.conta.senha,
        espacoId: espaco.id,
        data: _formatarDataApi(_dataSelecionada),
        horaInicio: slot.horaInicio,
        horaFim: slot.horaFim,
        convidados: convidadosCtrl.text.trim().isEmpty
            ? null
            : convidadosCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reserva confirmada!')));
      await _carregarSlots();
      await _carregarReservas();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível reservar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _cancelarReserva(Agendamento a) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar reserva?'),
        content: Text(
          '${a.espacoNome} · ${_formatarDataBr(a.data)} ${a.horaInicio}–${a.horaFim}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await widget.api.cancelarAgendamento(
        widget.conta.ramal,
        widget.conta.senha,
        a.id,
      );
      await _carregarReservas();
      await _carregarSlots();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cancelar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agendamentos'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Reservar'),
              Tab(text: 'Minhas reservas'),
            ],
          ),
        ),
        body: TabBarView(
          children: [_buildReservar(context), _buildMinhasReservas(context)],
        ),
      ),
    );
  }

  Widget _buildReservar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_carregandoEspacos) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erroEspacos != null) return Center(child: Text(_erroEspacos!));
    if (_espacos.isEmpty) {
      return const Center(child: Text('Nenhum espaço comum disponível.'));
    }

    final espaco = _espacoSelecionado;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _espacos.map((e) {
            final selecionado = e.id == espaco?.id;
            return ChoiceChip(
              label: Text(e.nome),
              selected: selecionado,
              onSelected: (_) {
                setState(() => _espacoSelecionado = e);
                _carregarSlots();
              },
            );
          }).toList(),
        ),
        if (espaco != null) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Data: ${_formatarDataBr(_dataSelecionada)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextButton.icon(
                onPressed: _escolherData,
                icon: const Icon(Icons.calendar_month),
                label: const Text('Trocar data'),
              ),
            ],
          ),
          Text(
            'Horário: ${espaco.horarioAbertura}–${espaco.horarioFechamento} · '
            '${espaco.taxa > 0 ? 'Taxa R\$ ${espaco.taxa.toStringAsFixed(2)}' : 'Gratuito'}',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (_carregandoSlots)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_slots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('Nenhum horário disponível nesse dia.'),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _slots.map((s) {
                return FilterChip(
                  label: Text('${s.horaInicio}–${s.horaFim}'),
                  selected: false,
                  showCheckmark: false,
                  backgroundColor: s.disponivel
                      ? null
                      : scheme.surfaceContainerHighest,
                  labelStyle: TextStyle(
                    color: s.disponivel
                        ? null
                        : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  onSelected: s.disponivel ? (_) => _reservarSlot(s) : null,
                );
              }).toList(),
            ),
        ],
      ],
    );
  }

  Widget _buildMinhasReservas(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _carregarReservas,
      child: _carregandoReservas
          ? const Center(child: CircularProgressIndicator())
          : _minhasReservas.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('Nenhuma reserva ainda.')),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _minhasReservas.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final a = _minhasReservas[i];
                final cancelada = a.status == StatusAgendamento.cancelada;
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
                                a.espacoNome,
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
                                color: (cancelada ? Colors.red : Colors.green)
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                cancelada ? 'Cancelada' : 'Confirmada',
                                style: TextStyle(
                                  color: cancelada ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${_formatarDataBr(a.data)} · ${a.horaInicio}–${a.horaFim}',
                        ),
                        if (a.convidados != null &&
                            a.convidados!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Convidados: ${a.convidados}',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        if (a.podeCancelar) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _cancelarReserva(a),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('Cancelar reserva'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
