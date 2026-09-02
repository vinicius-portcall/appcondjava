enum StatusPass { ativo, usado, expirado, cancelado }

class VisitantePass {
  final int id;
  final String codigo;
  final String nomeVisitante;
  final String? observacao;
  final DateTime? validadeFim;
  final StatusPass status;
  final DateTime? usadoEm;
  final String? usadoPor;
  final DateTime? criadoEm;

  const VisitantePass({
    required this.id,
    required this.codigo,
    required this.nomeVisitante,
    this.observacao,
    this.validadeFim,
    required this.status,
    this.usadoEm,
    this.usadoPor,
    this.criadoEm,
  });

  factory VisitantePass.fromJson(Map<String, dynamic> json) {
    return VisitantePass(
      id: int.tryParse(json['id'].toString()) ?? 0,
      codigo: json['codigo'] as String? ?? '',
      nomeVisitante: json['nome_visitante'] as String? ?? '',
      observacao: json['observacao'] as String?,
      validadeFim: DateTime.tryParse(json['validade_fim'] as String? ?? ''),
      status: _statusFromString(json['status'] as String?),
      usadoEm: DateTime.tryParse(json['usado_em'] as String? ?? ''),
      usadoPor: json['usado_por'] as String?,
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static StatusPass _statusFromString(String? valor) {
    switch (valor) {
      case 'usado':
        return StatusPass.usado;
      case 'expirado':
        return StatusPass.expirado;
      case 'cancelado':
        return StatusPass.cancelado;
      default:
        return StatusPass.ativo;
    }
  }

  String get statusLabel {
    switch (status) {
      case StatusPass.ativo:
        return 'Ativo';
      case StatusPass.usado:
        return 'Usado';
      case StatusPass.expirado:
        return 'Expirado';
      case StatusPass.cancelado:
        return 'Cancelado';
    }
  }
}
