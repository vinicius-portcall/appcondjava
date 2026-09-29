class Branding {
  final String appNome;
  final String? condominioNome;
  final String? logoUrl;
  final String? sipServidorPadrao;
  final String? sipPortaPadrao;
  final String? socorroMedicoInicio;
  final String? socorroMedicoFim;

  /// Módulos que a administração liberou para o condomínio, pelas chaves de
  /// `ModulosApp`. `null` significa "o painel não informou" — e aí tudo
  /// aparece. Ver [moduloLiberado].
  final Set<String>? modulosLiberados;

  const Branding({
    required this.appNome,
    this.condominioNome,
    this.logoUrl,
    this.sipServidorPadrao,
    this.sipPortaPadrao,
    this.socorroMedicoInicio,
    this.socorroMedicoFim,
    this.modulosLiberados,
  });

  factory Branding.fallback() => const Branding(appNome: 'Portcall');

  /// Se a opção deve aparecer na tela inicial.
  ///
  /// Erra sempre para o lado de MOSTRAR: se o painel não mandou a lista (versão
  /// antiga do `api_app_config.php`) ou mandou vazia, o morador vê tudo. Sumir
  /// com a tela inteira porque o painel respondeu errado seria muito pior do
  /// que exibir uma opção que o condomínio não usa — o morador não tem como
  /// saber que o problema é no servidor, ele só vê o app pela metade.
  bool moduloLiberado(String chave) {
    final liberados = modulosLiberados;
    if (liberados == null || liberados.isEmpty) return true;
    return liberados.contains(chave);
  }

  factory Branding.fromJson(Map<String, dynamic> json) {
    return Branding(
      appNome: (json['app_nome'] as String?)?.trim().isNotEmpty == true
          ? json['app_nome']
          : 'Portcall',
      condominioNome: (json['condominio_nome'] as String?)?.trim().isNotEmpty == true
          ? json['condominio_nome']
          : null,
      logoUrl: json['logo_url'] as String?,
      sipServidorPadrao: json['sip_servidor'] as String?,
      sipPortaPadrao: json['sip_porta'] as String?,
      socorroMedicoInicio: json['socorro_medico_inicio'] as String?,
      socorroMedicoFim: json['socorro_medico_fim'] as String?,
      modulosLiberados: _modulosFromJson(json['modulos']),
    );
  }

  /// Aceita o que o painel mandar sem quebrar: qualquer coisa que não seja
  /// uma lista vira `null` (= tudo liberado).
  static Set<String>? _modulosFromJson(dynamic valor) {
    if (valor is! List) return null;
    return valor
        .map((item) => item.toString().trim().toLowerCase())
        .where((chave) => chave.isNotEmpty)
        .toSet();
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
