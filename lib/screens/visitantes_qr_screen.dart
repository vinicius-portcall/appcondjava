import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../models/convidado_lista.dart';
import '../models/visitante_pass.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Visitante esperado, nos dois jeitos que a especificação prevê: passe de
/// QR Code de uso único (validado na portaria) ou um simples aviso na lista
/// da portaria (sem validação, só informativo). Duas abas, mesmo domínio.
class VisitantesQrScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const VisitantesQrScreen({super.key, required this.api, required this.conta});

  @override
  State<VisitantesQrScreen> createState() => _VisitantesQrScreenState();
}

class _VisitantesQrScreenState extends State<VisitantesQrScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  List<VisitantePass> _passes = [];
  bool _carregandoPasses = true;
  String? _erroPasses;
  int? _cancelandoPasseId;
  int? _apagandoPasseId;

  List<ConvidadoLista> _convidados = [];
  bool _carregandoConvidados = true;
  String? _erroConvidados;
  int? _cancelandoConvidadoId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    _carregarPasses();
    _carregarConvidados();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '—';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    final hora = data.hour.toString().padLeft(2, '0');
    final minuto = data.minute.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year} às $hora:$minuto';
  }

  // ---------------- QR Code ----------------

  Future<void> _carregarPasses() async {
    setState(() {
      _carregandoPasses = true;
      _erroPasses = null;
    });
    try {
      final passes = await widget.api.fetchVisitantesPass(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _passes = passes;
        _carregandoPasses = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroPasses = 'Não foi possível carregar os passes de visitante.';
        _carregandoPasses = false;
      });
    }
  }

  Future<void> _novoPasse() async {
    final nomeCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    int validadeHoras = 12;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Novo passe de visitante'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome do visitante',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: validadeHoras,
                decoration: const InputDecoration(labelText: 'Válido por'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 hora')),
                  DropdownMenuItem(value: 2, child: Text('2 horas')),
                  DropdownMenuItem(value: 6, child: Text('6 horas')),
                  DropdownMenuItem(value: 12, child: Text('12 horas')),
                  DropdownMenuItem(value: 24, child: Text('24 horas')),
                  DropdownMenuItem(value: 72, child: Text('3 dias')),
                ],
                onChanged: (v) => setDialogState(() => validadeHoras = v ?? 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: nomeCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Gerar QR'),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true || nomeCtrl.text.trim().isEmpty) return;

    try {
      await widget.api.criarVisitantePass(
        widget.conta.ramal,
        widget.conta.senha,
        nomeVisitante: nomeCtrl.text.trim(),
        observacao: obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
        validadeHoras: validadeHoras,
      );
      await _carregarPasses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível gerar o passe: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _cancelarPasse(VisitantePass p) async {
    setState(() => _cancelandoPasseId = p.id);
    try {
      await widget.api.cancelarVisitantePass(
        widget.conta.ramal,
        widget.conta.senha,
        p.id,
      );
      await _carregarPasses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cancelar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelandoPasseId = null);
    }
  }

  Future<void> _apagarPasse(VisitantePass p) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apagar passe'),
        content: Text('Apagar o passe de "${p.nomeVisitante}"? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _apagandoPasseId = p.id);
    try {
      await widget.api.apagarVisitantePass(
        widget.conta.ramal,
        widget.conta.senha,
        p.id,
      );
      await _carregarPasses();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível apagar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _apagandoPasseId = null);
    }
  }

  void _mostrarQr(VisitantePass p) {
    final qrKey = GlobalKey();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(p.nomeVisitante),
        content: SizedBox(
          width: 220,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RepaintBoundary(
                key: qrKey,
                child: QrImageView(
                  data: p.codigo,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Código: ${p.codigo}',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 4),
              Text('Válido até ${_formatarData(p.validadeFim)}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () => _compartilharQr(p, qrKey),
            icon: const Icon(Icons.share),
            label: const Text('Compartilhar'),
          ),
        ],
      ),
    );
  }

  Future<void> _compartilharQr(VisitantePass p, GlobalKey qrKey) async {
    try {
      final boundary =
          qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData!.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final dir = await getTemporaryDirectory();
      final arquivo = await File(
        '${dir.path}/qr_visitante_${p.id}.png',
      ).writeAsBytes(bytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(arquivo.path)],
          text:
              'QR Code de acesso para ${p.nomeVisitante}, válido até '
              '${_formatarData(p.validadeFim)}.',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível compartilhar o QR: $e')),
      );
    }
  }

  Color _corStatusPasse(StatusPass status) {
    switch (status) {
      case StatusPass.ativo:
        return Colors.green;
      case StatusPass.usado:
        return Colors.blueGrey;
      case StatusPass.expirado:
        return Colors.orange;
      case StatusPass.cancelado:
        return Colors.red;
    }
  }

  // ---------------- Lista pra portaria ----------------

  Future<void> _carregarConvidados() async {
    setState(() {
      _carregandoConvidados = true;
      _erroConvidados = null;
    });
    try {
      final convidados = await widget.api.fetchConvidados(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _convidados = convidados;
        _carregandoConvidados = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroConvidados = 'Não foi possível carregar a lista de convidados.';
        _carregandoConvidados = false;
      });
    }
  }

  Future<void> _novoConvidado() async {
    final nomeCtrl = TextEditingController();
    final obsCtrl = TextEditingController();
    DateTime inicio = DateTime.now();
    DateTime fim = DateTime.now().add(const Duration(hours: 4));

    Future<void> escolherData(
      BuildContext context,
      bool isInicio,
      StateSetter setDialogState,
    ) async {
      final base = isInicio ? inicio : fim;
      final data = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 90)),
      );
      if (data == null) return;
      if (!context.mounted) return;
      final hora = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(base),
      );
      if (hora == null) return;
      setDialogState(() {
        final novaData = DateTime(
          data.year,
          data.month,
          data.day,
          hora.hour,
          hora.minute,
        );
        if (isInicio) {
          inicio = novaData;
        } else {
          fim = novaData;
        }
      });
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Avisar portaria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nomeCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nome do convidado',
                ),
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: obsCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('A partir de'),
                subtitle: Text(_formatarData(inicio)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => escolherData(context, true, setDialogState),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Até'),
                subtitle: Text(_formatarData(fim)),
                trailing: const Icon(Icons.calendar_month),
                onTap: () => escolherData(context, false, setDialogState),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: nomeCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Avisar'),
            ),
          ],
        ),
      ),
    );

    if (confirmado != true || nomeCtrl.text.trim().isEmpty) return;

    if (!fim.isAfter(inicio)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O horário final precisa ser depois do inicial.'),
        ),
      );
      return;
    }

    try {
      await widget.api.criarConvidado(
        widget.conta.ramal,
        widget.conta.senha,
        nomeConvidado: nomeCtrl.text.trim(),
        observacao: obsCtrl.text.trim().isEmpty ? null : obsCtrl.text.trim(),
        dataInicio: inicio,
        dataFim: fim,
      );
      await _carregarConvidados();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível avisar a portaria: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _cancelarConvidado(ConvidadoLista c) async {
    setState(() => _cancelandoConvidadoId = c.id);
    try {
      await widget.api.cancelarConvidado(
        widget.conta.ramal,
        widget.conta.senha,
        c.id,
      );
      await _carregarConvidados();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cancelar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _cancelandoConvidadoId = null);
    }
  }

  Color _corStatusConvidado(StatusConvidado status) {
    switch (status) {
      case StatusConvidado.aguardando:
        return Colors.orange;
      case StatusConvidado.chegou:
        return Colors.green;
      case StatusConvidado.expirado:
        return Colors.blueGrey;
      case StatusConvidado.cancelado:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Visitantes'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'QR Code'),
            Tab(text: 'Lista (portaria)'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tabController.index == 0 ? _novoPasse : _novoConvidado,
        icon: Icon(
          _tabController.index == 0 ? Icons.qr_code_2 : Icons.person_add_alt_1,
        ),
        label: Text(
          _tabController.index == 0 ? 'Novo passe' : 'Avisar portaria',
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildQrCode(context), _buildListaPortaria(context)],
      ),
    );
  }

  Widget _buildQrCode(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _carregarPasses,
      child: _carregandoPasses
          ? const Center(child: CircularProgressIndicator())
          : _erroPasses != null
          ? Center(child: Text(_erroPasses!))
          : _passes.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text('Nenhum passe de visitante gerado ainda.'),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _passes.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final p = _passes[i];
                final cancelando = _cancelandoPasseId == p.id;
                final apagando = _apagandoPasseId == p.id;
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
                                p.nomeVisitante,
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
                                color: _corStatusPasse(
                                  p.status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                p.statusLabel,
                                style: TextStyle(
                                  color: _corStatusPasse(p.status),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (p.observacao != null &&
                            p.observacao!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            p.observacao!,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          p.status == StatusPass.usado
                              ? 'Usado em ${_formatarData(p.usadoEm)}'
                              : 'Válido até ${_formatarData(p.validadeFim)}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (p.status == StatusPass.ativo) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _mostrarQr(p),
                                  icon: const Icon(Icons.qr_code_2),
                                  label: const Text('Ver QR'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: cancelando
                                      ? null
                                      : () => _cancelarPasse(p),
                                  icon: cancelando
                                      ? const SizedBox(
                                          height: 16,
                                          width: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.close),
                                  label: const Text('Cancelar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ] else ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: apagando ? null : () => _apagarPasse(p),
                              icon: apagando
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.delete_outline),
                              label: const Text('Apagar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
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

  Widget _buildListaPortaria(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _carregarConvidados,
      child: _carregandoConvidados
          ? const Center(child: CircularProgressIndicator())
          : _erroConvidados != null
          ? Center(child: Text(_erroConvidados!))
          : _convidados.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: Text('Nenhum convidado avisado ainda.')),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _convidados.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final c = _convidados[i];
                final cancelando = _cancelandoConvidadoId == c.id;
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
                                c.nomeConvidado,
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
                                color: _corStatusConvidado(
                                  c.status,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                c.statusLabel,
                                style: TextStyle(
                                  color: _corStatusConvidado(c.status),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (c.observacao != null &&
                            c.observacao!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            c.observacao!,
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          '${_formatarData(c.dataInicio)} até ${_formatarData(c.dataFim)}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                        if (c.status == StatusConvidado.aguardando) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: cancelando
                                  ? null
                                  : () => _cancelarConvidado(c),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: cancelando
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Cancelar aviso'),
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
