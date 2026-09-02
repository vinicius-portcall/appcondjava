import 'package:flutter/material.dart';

import '../services/sip_service.dart';

/// Teclado pra digitar e ligar pra qualquer número/ramal, não só os botões
/// pré-configurados do condomínio.
class DialpadScreen extends StatefulWidget {
  final SipService sip;

  const DialpadScreen({super.key, required this.sip});

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _numero = '';

  void _adicionar(String tecla) {
    setState(() => _numero += tecla);
  }

  void _apagar() {
    if (_numero.isEmpty) return;
    setState(() => _numero = _numero.substring(0, _numero.length - 1));
  }

  Future<void> _ligar({bool video = false}) async {
    if (_numero.isEmpty) return;
    if (!widget.sip.isRegistered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ainda não registrado no servidor. Aguarde e tente de novo.',
          ),
        ),
      );
      return;
    }
    await widget.sip.ligarPara(_numero, video: video);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    const teclas = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];

    return Scaffold(
      appBar: AppBar(title: const Text('Discar')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _numero.isEmpty ? ' ' : _numero,
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GridView.count(
                shrinkWrap: true,
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: teclas.map((tecla) {
                  return Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _adicionar(tecla),
                      child: Center(
                        child: Text(
                          tecla,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _numero.isEmpty ? null : _apagar,
                    icon: const Icon(Icons.backspace_outlined),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    heroTag: 'discar-voz',
                    backgroundColor: Colors.green,
                    onPressed: () => _ligar(),
                    child: const Icon(Icons.call),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    heroTag: 'discar-video',
                    backgroundColor: Colors.blue,
                    onPressed: () => _ligar(video: true),
                    child: const Icon(Icons.videocam),
                  ),
                  const SizedBox(width: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
