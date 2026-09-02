import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/morador_facial.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Cadastro de reconhecimento facial self-service: qualquer morador da casa
/// pode cadastrar o próprio rosto direto pelo app, sem depender do síndico
/// nem da interface própria da Control iD. O apartamento é resolvido pelo
/// ramal logado — como o login é compartilhado por apartamento (não por
/// pessoa), a tela mostra uma lista de "moradores" cadastrados, cada um com
/// seu próprio nome/rosto, todos atrelados à mesma casa.
class MoradoresFacialScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const MoradoresFacialScreen({
    super.key,
    required this.api,
    required this.conta,
  });

  @override
  State<MoradoresFacialScreen> createState() => _MoradoresFacialScreenState();
}

class _MoradoresFacialScreenState extends State<MoradoresFacialScreen> {
  List<MoradorFacial> _moradores = [];
  bool _carregando = true;
  String? _erro;
  bool _enviando = false;
  int? _removendoId;

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
      final moradores = await widget.api.fetchMoradoresFacial(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _moradores = moradores;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os moradores cadastrados.';
        _carregando = false;
      });
    }
  }

  Future<ImageSource?> _escolherOrigemFoto() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _novoMorador() async {
    final nomeCtrl = TextEditingController();
    final nomeConfirmado = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Cadastrar rosto'),
          content: TextField(
            controller: nomeCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Nome do morador',
            ),
            onChanged: (_) => setDialogState(() {}),
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
              child: const Text('Continuar'),
            ),
          ],
        ),
      ),
    );

    if (nomeConfirmado != true || nomeCtrl.text.trim().isEmpty) return;
    if (!mounted) return;

    final origem = await _escolherOrigemFoto();
    if (origem == null) return;
    if (!mounted) return;

    final XFile? foto = await ImagePicker().pickImage(
      source: origem,
      maxWidth: 1280,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );
    if (foto == null) return;

    setState(() => _enviando = true);
    try {
      await widget.api.cadastrarMoradorFacial(
        widget.conta.ramal,
        widget.conta.senha,
        nome: nomeCtrl.text.trim(),
        foto: File(foto.path),
      );
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rosto cadastrado com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível cadastrar: ${e.toString().replaceFirst('Exception: ', '')}'),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _remover(MoradorFacial m) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover cadastro'),
        content: Text(
          'Remover o rosto de "${m.nome}" do reconhecimento facial? Essa ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _removendoId = m.id);
    try {
      await widget.api.removerMoradorFacial(
        widget.conta.ramal,
        widget.conta.senha,
        m.id,
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível remover: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _removendoId = null);
    }
  }

  String _formatarData(DateTime? data) {
    if (data == null) return '—';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return 'Cadastrado em $dia/$mes/${data.year}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cadastro Facial')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _enviando ? null : _novoMorador,
        icon: _enviando
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.face_retouching_natural),
        label: Text(_enviando ? 'Enviando…' : 'Cadastrar rosto'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Cada morador da casa pode cadastrar o próprio rosto '
                      'aqui — todos ficam liberados no reconhecimento facial '
                      'da portaria vinculados ao apartamento deste ramal.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_moradores.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text('Nenhum rosto cadastrado ainda.'),
                      ),
                    )
                  else
                    ..._moradores.map((m) {
                      final removendo = _removendoId == m.id;
                      return Card(
                        elevation: 0,
                        color: scheme.surfaceContainer,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.face),
                          ),
                          title: Text(
                            m.nome,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_formatarData(m.criadoEm)),
                          trailing: removendo
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Remover',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _remover(m),
                                ),
                        ),
                      );
                    }),
                ],
              ),
      ),
    );
  }
}
