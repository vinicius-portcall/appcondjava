class Chamado {
  final int id;
  final String? apartamento;
  final String assunto;
  final String mensagem;
  final String status;
  final String? resposta;
  final DateTime? respondidoEm;
  final DateTime? criadoEm;

  const Chamado({
    required this.id,
    this.apartamento,
    required this.assunto,
    required this.mensagem,
    required this.status,
    this.resposta,
    this.respondidoEm,
    this.criadoEm,
  });

  factory Chamado.fromJson(Map<String, dynamic> json) {
    return Chamado(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      apartamento: json['apartamento'] as String?,
      assunto: json['assunto'] as String? ?? '',
      mensagem: json['mensagem'] as String? ?? '',
      status: json['status'] as String? ?? 'aberto',
      resposta: json['resposta'] as String?,
      respondidoEm: DateTime.tryParse(json['respondido_em'] as String? ?? ''),
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'aberto':
        return 'Aberto';
      case 'em_andamento':
        return 'Em andamento';
      case 'respondido':
        return 'Respondido';
      case 'fechado':
        return 'Fechado';
      default:
        return status;
    }
  }
}
