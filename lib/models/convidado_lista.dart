enum StatusConvidado { aguardando, chegou, expirado, cancelado }

class ConvidadoLista {
  final int id;
  final String nomeConvidado;
  final String? observacao;
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final StatusConvidado status;
  final DateTime? chegouEm;
  final DateTime? criadoEm;

  const ConvidadoLista({
    required this.id,
    required this.nomeConvidado,
    this.observacao,
    this.dataInicio,
    this.dataFim,
    required this.status,
    this.chegouEm,
    this.criadoEm,
  });

  factory ConvidadoLista.fromJson(Map<String, dynamic> json) {
    return ConvidadoLista(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nomeConvidado: json['nome_convidado'] as String? ?? '',
      observacao: json['observacao'] as String?,
      dataInicio: DateTime.tryParse(json['data_inicio'] as String? ?? ''),
      dataFim: DateTime.tryParse(json['data_fim'] as String? ?? ''),
      status: _statusFromString(json['status'] as String?),
      chegouEm: DateTime.tryParse(json['chegou_em'] as String? ?? ''),
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static StatusConvidado _statusFromString(String? valor) {
    switch (valor) {
      case 'chegou':
        return StatusConvidado.chegou;
      case 'expirado':
        return StatusConvidado.expirado;
      case 'cancelado':
        return StatusConvidado.cancelado;
      default:
        return StatusConvidado.aguardando;
    }
  }

  String get statusLabel {
    switch (status) {
      case StatusConvidado.aguardando:
        return 'Aguardando';
      case StatusConvidado.chegou:
        return 'Chegou';
      case StatusConvidado.expirado:
        return 'Expirado';
      case StatusConvidado.cancelado:
        return 'Cancelado';
    }
  }
}
