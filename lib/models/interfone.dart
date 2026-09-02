enum TipoInterfone { sip, facial }

/// Equipamento de interfonia do condomínio: um ramal SIP de verdade
/// (interfone externo, cadastrado em Interfones SIP no painel) ou um leitor
/// facial Control iD (cadastrado em Dispositivos Faciais) — esse último é só
/// informativo, não dá pra ligar pra ele.
class Interfone {
  final TipoInterfone tipo;
  final String nome;
  final String? destino;
  final bool suportaVideo;

  const Interfone({
    required this.tipo,
    required this.nome,
    this.destino,
    this.suportaVideo = false,
  });

  factory Interfone.fromJson(Map<String, dynamic> json) {
    return Interfone(
      tipo: json['tipo'] == 'facial' ? TipoInterfone.facial : TipoInterfone.sip,
      nome: json['nome'] as String? ?? '',
      destino: json['destino'] as String?,
      suportaVideo: json['suporta_video'] == true,
    );
  }
}
