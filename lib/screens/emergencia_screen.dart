import 'package:flutter/material.dart';

import '../models/branding.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

class _TipoAlerta {
  final String valor;
  final String label;
  final IconData icone;

  const _TipoAlerta(this.valor, this.label, this.icone);
}

const _tiposAlerta = [
  _TipoAlerta('elevador_parado', 'Elevador Parado', Icons.elevator_outlined),
  _TipoAlerta('emergencia', 'Emergência', Icons.warning_amber_rounded),
  _TipoAlerta(
    'entrada_assistida',
    'Entrada Assistida',
    Icons.accessible_forward_rounded,
  ),
  _TipoAlerta(
    'socorro_medico',
    'Socorro Médico',
    Icons.medical_services_outlined,
  ),
];

/// Disparo de alertas de emergência para a portaria/monitoramento do
/// condomínio. Cada botão pede confirmação antes de enviar — não tem
/// cancelamento depois, é um alerta, não uma reserva.
class EmergenciaScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;
  final Branding branding;

  const EmergenciaScreen({
    super.key,
    required this.api,
    required this.conta,
    required this.branding,
  });

  @override
  State<EmergenciaScreen> createState() => _EmergenciaScreenState();
}

class _EmergenciaScreenState extends State<EmergenciaScreen> {
  String? _enviando;

  Future<void> _confirmarEEnviar(_TipoAlerta tipo) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Confirmar alerta: ${tipo.label}'),
        content: const Text(
          'A portaria/monitoramento do condomínio será avisada imediatamente. Confirma o envio?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enviar alerta'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _enviando = tipo.valor);
    try {
      await widget.api.enviarAlerta(
        widget.conta.ramal,
        widget.conta.senha,
        tipo.valor,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerta de "${tipo.label}" enviado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível enviar o alerta: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipos = _tiposAlerta.where(
      (t) =>
          t.valor != 'socorro_medico' ||
          widget.branding.socorroMedicoDisponivelAgora,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Emergência')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Toque em um alerta para avisar a portaria imediatamente.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          ...tipos.map((tipo) {
            final enviandoEste = _enviando == tipo.valor;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: FilledButton.icon(
                onPressed: _enviando == null
                    ? () => _confirmarEEnviar(tipo)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: enviandoEste
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(tipo.icone),
                label: Text(tipo.label, style: const TextStyle(fontSize: 16)),
              ),
            );
          }),
        ],
      ),
    );
  }
}
