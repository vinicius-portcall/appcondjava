enum TipoAcesso { portaoApp, facial, qrcode, outro }

class AcessoPortao {
  final TipoAcesso tipo;
  final String? ramal;
  final String? detalhe;
  final String? nome;
  final String? fotoUrl;
  final DateTime? criadoEm;

  const AcessoPortao({
    required this.tipo,
    this.ramal,
    this.detalhe,
    this.nome,
    this.fotoUrl,
    this.criadoEm,
  });

  factory AcessoPortao.fromJson(Map<String, dynamic> json) {
    return AcessoPortao(
      tipo: _tipoFromString(json['tipo'] as String?),
      ramal: json['ramal'] as String?,
      detalhe: json['detalhe'] as String?,
      nome: json['nome'] as String?,
      fotoUrl: json['foto_url'] as String?,
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static TipoAcesso _tipoFromString(String? valor) {
    switch (valor) {
      case 'portao_app':
        return TipoAcesso.portaoApp;
      case 'facial':
        return TipoAcesso.facial;
      case 'qrcode':
        return TipoAcesso.qrcode;
      default:
        return TipoAcesso.outro;
    }
  }

  String get tipoLabel {
    switch (tipo) {
      case TipoAcesso.portaoApp:
        return 'Portão (app)';
      case TipoAcesso.facial:
        return 'Reconhecimento facial';
      case TipoAcesso.qrcode:
        return 'QR Visitante';
      case TipoAcesso.outro:
        return 'Outro';
    }
  }
}
