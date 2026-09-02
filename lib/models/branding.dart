class Branding {
  final String appNome;
  final String? logoUrl;
  final String? sipServidorPadrao;
  final String? sipPortaPadrao;
  final String? socorroMedicoInicio;
  final String? socorroMedicoFim;

  const Branding({
    required this.appNome,
    this.logoUrl,
    this.sipServidorPadrao,
    this.sipPortaPadrao,
    this.socorroMedicoInicio,
    this.socorroMedicoFim,
  });

  factory Branding.fallback() => const Branding(appNome: 'Portcall');

  factory Branding.fromJson(Map<String, dynamic> json) {
    return Branding(
      appNome: (json['app_nome'] as String?)?.trim().isNotEmpty == true
          ? json['app_nome']
          : 'Portcall',
      logoUrl: json['logo_url'] as String?,
      sipServidorPadrao: json['sip_servidor'] as String?,
      sipPortaPadrao: json['sip_porta'] as String?,
      socorroMedicoInicio: json['socorro_medico_inicio'] as String?,
      socorroMedicoFim: json['socorro_medico_fim'] as String?,
    );
  }

  /// Se o botão de Socorro Médico deve aparecer agora, considerando a janela
  /// configurada pelo condomínio (nulo = sempre disponível). Só decide a
  /// exibição no app — a validação de verdade é sempre feita no servidor.
  bool get socorroMedicoDisponivelAgora {
    final inicioMin = _minutosDesdeMeiaNoite(socorroMedicoInicio);
    final fimMin = _minutosDesdeMeiaNoite(socorroMedicoFim);
    if (inicioMin == null || fimMin == null) return true;

    final agora = DateTime.now();
    final agoraMin = agora.hour * 60 + agora.minute;

    if (inicioMin <= fimMin) {
      return agoraMin >= inicioMin && agoraMin <= fimMin;
    }
    // janela cruza a meia-noite (ex: 22:00 às 06:00)
    return agoraMin >= inicioMin || agoraMin <= fimMin;
  }

  static int? _minutosDesdeMeiaNoite(String? hhmmss) {
    if (hhmmss == null) return null;
    final partes = hhmmss.split(':');
    if (partes.length < 2) return null;
    final h = int.tryParse(partes[0]);
    final m = int.tryParse(partes[1]);
    if (h == null || m == null) return null;
    return h * 60 + m;
  }
}
