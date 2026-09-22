import 'package:flutter/material.dart';

import '../models/branding.dart';

/// Verde da marca (extraído do fundo da logo atual, ex.: MultVirtual Video
/// Atende) — usado só nos anéis de pulso da splash, não no tema do app.
const _brandGreen = Color(0xFF00A85A);

/// Tela de abertura com o logo entrando com um "pop" e anéis de pulso (tipo
/// sinal de chamada tocando) se espalhando a partir dele — referência visual
/// são as ondas de som já desenhadas na própria logo. Usa o branding em
/// cache (ver SessionService.loadBranding) pra aparecer na hora, sem esperar
/// rede — cai no ícone/nome genérico do Portcall só na primeira abertura do
/// app, antes de existir qualquer branding salvo.
class SplashScreen extends StatefulWidget {
  final Branding? branding;

  const SplashScreen({super.key, this.branding});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final branding = widget.branding;
    final colorScheme = Theme.of(context).colorScheme;

    final logoPop = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
    );
    final textoFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
    );

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _AnelDePulso(controller: _controller, inicio: 0.15),
                  _AnelDePulso(controller: _controller, inicio: 0.35),
                  ScaleTransition(
                    scale: Tween(begin: 0.7, end: 1.0).animate(logoPop),
                    child: FadeTransition(
                      opacity: logoPop,
                      child: _logo(branding, colorScheme),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: textoFade,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.3),
                  end: Offset.zero,
                ).animate(textoFade),
                child: Column(
                  children: [
                    Text(
                      branding?.appNome ?? 'Portcall',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (branding?.condominioNome != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        branding!.condominioNome!,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo(Branding? branding, ColorScheme colorScheme) {
    if (branding?.logoUrl == null) return _iconePadrao(colorScheme);

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Image.network(
        branding!.logoUrl!,
        width: 96,
        height: 96,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 250),
            child: child,
          );
        },
        errorBuilder: (_, _, _) => _iconePadrao(colorScheme),
      ),
    );
  }

  Widget _iconePadrao(ColorScheme colorScheme) {
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(
        Icons.apartment,
        size: 52,
        color: colorScheme.onSecondaryContainer,
      ),
    );
  }
}

/// Um anel que nasce colado na logo e se expande enquanto desaparece —
/// como um sinal de chamada tocando. `inicio` escalona o disparo de cada
/// anel dentro do controller compartilhado, pra sair em sequência.
class _AnelDePulso extends StatelessWidget {
  final AnimationController controller;
  final double inicio;

  const _AnelDePulso({required this.controller, required this.inicio});

  @override
  Widget build(BuildContext context) {
    final animacao = CurvedAnimation(
      parent: controller,
      curve: Interval(inicio, (inicio + 0.65).clamp(0.0, 1.0), curve: Curves.easeOut),
    );

    return AnimatedBuilder(
      animation: animacao,
      builder: (context, child) {
        final t = animacao.value;
        return Opacity(
          opacity: (1 - t).clamp(0.0, 1.0) * 0.6,
          child: Transform.scale(
            scale: 0.5 + t * 1.1,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _brandGreen, width: 2),
              ),
            ),
          ),
        );
      },
    );
  }
}
