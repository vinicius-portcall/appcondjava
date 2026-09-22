import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';

/// Deixa o morador escolher unidades que não podem ligar pra ele.
///
/// O bloqueio vale de verdade: quem barra a ligação é o servidor
/// (`portcall_router.agi`), antes de montar a rota — nem o app, nem o ramal,
/// nem os celulares cadastrados chegam a tocar, e quem ligou ouve o sinal de
/// ocupado. A portaria/interfone nunca aparece aqui de propósito, pra o
/// morador não se isolar de entrega, visita e aviso de emergência.
class BloqueiosScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const BloqueiosScreen({super.key, required this.api, required this.conta});

  @override
  State<BloqueiosScreen> createState() => _BloqueiosScreenState();
}

class _BloqueiosScreenState extends State<BloqueiosScreen> {
  List<String> _unidades = [];
  Set<String> _bloqueadas = {};
  String _minhaUnidade = '';
  bool _carregando = true;
  bool _disponivel = false;
  String? _erro;

  /// Unidades com alteração em voo — evita o usuário tocar duas vezes no
  /// mesmo item enquanto a requisição não voltou.
  final Set<String> _salvando = {};

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
      final r = await widget.api.fetchBloqueios(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _disponivel = r.disponivel;
        _minhaUnidade = r.minhaUnidade;
        _unidades = r.unidades;
        _bloqueadas = r.bloqueadas.toSet();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar a lista de unidades.';
        _carregando = false;
      });
    }
  }

  Future<void> _alternar(String unidade, bool bloquear) async {
    setState(() => _salvando.add(unidade));

    // Otimista: o switch mexe na hora e só volta atrás se o servidor recusar
    // — a lista inteira piscando a cada toque ficava ruim de usar.
    setState(() {
      if (bloquear) {
        _bloqueadas.add(unidade);
      } else {
        _bloqueadas.remove(unidade);
      }
    });

    try {
      await widget.api.salvarBloqueio(
        widget.conta.ramal,
        widget.conta.senha,
        unidade: unidade,
        bloquear: bloquear,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (bloquear) {
          _bloqueadas.remove(unidade);
        } else {
          _bloqueadas.add(unidade);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar. Tente de novo.')),
      );
    } finally {
      if (mounted) setState(() => _salvando.remove(unidade));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bloquear unidades')),
      body: SafeArea(child: _corpo()),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_erro!, textAlign: TextAlign.center),
            ),
            FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ],
        ),
      );
    }
    if (!_disponivel) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Esse recurso ainda não está configurado pra sua unidade. '
            'Fale com o síndico ou a administração do condomínio.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_unidades.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Não há outras unidades cadastradas no condomínio.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Unidades bloqueadas não conseguem ligar pra você — quem '
                'tentar vai ouvir o sinal de ocupado.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'A portaria nunca é bloqueada, pra você não perder aviso de '
                'entrega, visita ou emergência.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              if (_minhaUnidade.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Sua unidade: $_minhaUnidade',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _unidades.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final unidade = _unidades[i];
              final bloqueada = _bloqueadas.contains(unidade);
              final salvando = _salvando.contains(unidade);

              return SwitchListTile(
                secondary: Icon(
                  bloqueada ? Icons.block : Icons.home_outlined,
                  color: bloqueada ? scheme.error : null,
                ),
                title: Text('Unidade $unidade'),
                subtitle: Text(
                  bloqueada ? 'Não pode te ligar' : 'Pode te ligar',
                  style: TextStyle(
                    color: bloqueada
                        ? scheme.error
                        : scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                value: bloqueada,
                onChanged: salvando
                    ? null
                    : (valor) => _alternar(unidade, valor),
              );
            },
          ),
        ),
      ],
    );
  }
}
