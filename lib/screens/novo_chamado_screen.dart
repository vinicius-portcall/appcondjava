import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';

/// Formulário de novo chamado (pedido/dúvida/reclamação) para a
/// administração do condomínio. Sem anexo de arquivo/foto nesta versão.
class NovoChamadoScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;
  final List<String> apartamentos;

  const NovoChamadoScreen({
    super.key,
    required this.api,
    required this.conta,
    required this.apartamentos,
  });

  @override
  State<NovoChamadoScreen> createState() => _NovoChamadoScreenState();
}

class _NovoChamadoScreenState extends State<NovoChamadoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _assuntoCtrl = TextEditingController();
  final _mensagemCtrl = TextEditingController();
  String? _apartamento;
  bool _enviando = false;

  Future<void> _enviar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enviando = true);
    try {
      await widget.api.enviarChamado(
        widget.conta.ramal,
        widget.conta.senha,
        apartamento: _apartamento,
        assunto: _assuntoCtrl.text.trim(),
        mensagem: _mensagemCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  void dispose() {
    _assuntoCtrl.dispose();
    _mensagemCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Novo chamado')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.apartamentos.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _apartamento,
                    decoration: const InputDecoration(
                      labelText: 'Unidade (opcional)',
                    ),
                    items: widget.apartamentos
                        .map(
                          (a) => DropdownMenuItem(
                            value: a,
                            child: Text('Apto $a'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _apartamento = v),
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _assuntoCtrl,
                  decoration: const InputDecoration(labelText: 'Assunto'),
                  maxLength: 150,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o assunto.'
                      : null,
                ),
                TextFormField(
                  controller: _mensagemCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mensagem',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 6,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe a mensagem.'
                      : null,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _enviando ? null : _enviar,
                  child: _enviando
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Enviar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
