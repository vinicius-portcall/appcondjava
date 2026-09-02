enum EncomendaTipo { pacote, carta, envelope, remedio, outro }

class Encomenda {
  final int id;
  final String apartamento;
  final EncomendaTipo tipo;
  final String? codigoRastreio;
  final String? infoAdicional;
  final String? fotoUrl;
  final bool retirada;
  final String? retiradoPor;
  final DateTime? retiradoEm;
  final DateTime? criadoEm;

  const Encomenda({
    required this.id,
    required this.apartamento,
    required this.tipo,
    this.codigoRastreio,
    this.infoAdicional,
    this.fotoUrl,
    required this.retirada,
    this.retiradoPor,
    this.retiradoEm,
    this.criadoEm,
  });

  factory Encomenda.fromJson(Map<String, dynamic> json) {
    return Encomenda(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      apartamento: json['apartamento'] as String? ?? '',
      tipo: _tipoFromString(json['tipo'] as String?),
      codigoRastreio: json['codigo_rastreio'] as String?,
      infoAdicional: json['info_adicional'] as String?,
      fotoUrl: json['foto_url'] as String?,
      retirada: json['status'] == 'retirada',
      retiradoPor: json['retirado_por'] as String?,
      retiradoEm: DateTime.tryParse(json['retirado_em'] as String? ?? ''),
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static EncomendaTipo _tipoFromString(String? valor) {
    switch (valor) {
      case 'pacote':
        return EncomendaTipo.pacote;
      case 'carta':
        return EncomendaTipo.carta;
      case 'envelope':
        return EncomendaTipo.envelope;
      case 'remedio':
        return EncomendaTipo.remedio;
      default:
        return EncomendaTipo.outro;
    }
  }

  String get tipoLabel {
    switch (tipo) {
      case EncomendaTipo.pacote:
        return 'Pacote';
      case EncomendaTipo.carta:
        return 'Carta';
      case EncomendaTipo.envelope:
        return 'Envelope';
      case EncomendaTipo.remedio:
        return 'Remédio';
      case EncomendaTipo.outro:
        return 'Outro';
    }
  }
}
