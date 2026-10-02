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

  /// Câmera do condomínio associada a este interfone no painel, mostrada
  /// durante a chamada. Serve principalmente pro interfone que não tem câmera
  /// própria: a chamada chega só com áudio, e sem isso o morador atende sem
  /// ver quem está no portão.
  ///
  /// A URL já vem pronta do servidor, com credenciais embutidas — mesma
  /// montagem da tela de Câmeras (`camera_rtsp_url` em funcoes.php).
  final String? cameraNome;
  final String? cameraUrl;

  const Interfone({
    required this.tipo,
    required this.nome,
    this.destino,
    this.suportaVideo = false,
    this.cameraNome,
    this.cameraUrl,
  });

  /// Tem câmera utilizável? URL vazia conta como não ter — o painel pode
  /// devolver string vazia se a câmera foi desativada depois de associada.
  bool get temCamera => cameraUrl != null && cameraUrl!.isNotEmpty;

  factory Interfone.fromJson(Map<String, dynamic> json) {
    return Interfone(
      tipo: json['tipo'] == 'facial' ? TipoInterfone.facial : TipoInterfone.sip,
      nome: json['nome'] as String? ?? '',
      destino: json['destino'] as String?,
      suportaVideo: json['suporta_video'] == true,
      cameraNome: json['camera_nome'] as String?,
      cameraUrl: json['camera_url'] as String?,
    );
  }
}
