enum TipoChamada { recebida, efetuada, perdida }

/// Uma linha do histórico de chamadas, vinda do CDR do Asterisk via
/// `api_historico_chamadas.php`.
///
/// A classificação em recebida/efetuada/perdida é feita no servidor, não aqui:
/// só lá dá pra saber quais números pertencem ao morador (o ramal dele mais as
/// unidades que a rota aponta pra ele). Pelo app, "5500 ligou para 102" não
/// diria nada sobre quem é quem.
class ChamadaHistorico {
  final TipoChamada tipo;
  final DateTime? data;

  /// O outro lado da conversa — já resolvido pelo servidor, que sabe se o
  /// morador foi a origem ou o destino.
  final String outro;
  final bool atendida;

  /// Duração em segundos da conversa (não do toque): zero em chamada não
  /// atendida.
  final int segundos;

  const ChamadaHistorico({
    required this.tipo,
    required this.outro,
    required this.atendida,
    required this.segundos,
    this.data,
  });

  factory ChamadaHistorico.fromJson(Map<String, dynamic> json) {
    return ChamadaHistorico(
      tipo: _tipoFromString(json['tipo'] as String?),
      outro: (json['outro'] as String?) ?? '',
      atendida: json['atendida'] == true,
      segundos: (json['segundos'] as num?)?.toInt() ?? 0,
      data: DateTime.tryParse(json['data'] as String? ?? ''),
    );
  }

  static TipoChamada _tipoFromString(String? valor) {
    switch (valor) {
      case 'recebida':
        return TipoChamada.recebida;
      case 'perdida':
        return TipoChamada.perdida;
      default:
        return TipoChamada.efetuada;
    }
  }

  String get tipoLabel {
    switch (tipo) {
      case TipoChamada.recebida:
        return 'Recebida';
      case TipoChamada.efetuada:
        return 'Efetuada';
      case TipoChamada.perdida:
        return 'Perdida';
    }
  }

  /// Duração em formato de relógio. Chamada não atendida não tem duração
  /// nenhuma pra mostrar — devolve nulo pra tela decidir o que exibir.
  String? get duracaoLabel {
    if (!atendida || segundos <= 0) return null;
    final minutos = segundos ~/ 60;
    final resto = segundos % 60;
    if (minutos == 0) return '${resto}s';
    return '${minutos}min ${resto.toString().padLeft(2, '0')}s';
  }
}
