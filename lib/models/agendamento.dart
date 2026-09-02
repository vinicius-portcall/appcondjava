enum StatusAgendamento { confirmada, cancelada }

class Agendamento {
  final int id;
  final int espacoId;
  final String espacoNome;
  final int antecedenciaCancelamentoHoras;
  final DateTime? data;
  final String horaInicio;
  final String horaFim;
  final String? convidados;
  final StatusAgendamento status;
  final DateTime? criadoEm;

  const Agendamento({
    required this.id,
    required this.espacoId,
    required this.espacoNome,
    required this.antecedenciaCancelamentoHoras,
    this.data,
    required this.horaInicio,
    required this.horaFim,
    this.convidados,
    required this.status,
    this.criadoEm,
  });

  factory Agendamento.fromJson(Map<String, dynamic> json) {
    return Agendamento(
      id: int.tryParse(json['id'].toString()) ?? 0,
      espacoId: int.tryParse(json['espaco_id'].toString()) ?? 0,
      espacoNome: json['espaco_nome'] as String? ?? '',
      antecedenciaCancelamentoHoras:
          int.tryParse(json['antecedencia_cancelamento_horas'].toString()) ??
          24,
      data: DateTime.tryParse(json['data'] as String? ?? ''),
      horaInicio: _hhmm(json['hora_inicio'] as String?),
      horaFim: _hhmm(json['hora_fim'] as String?),
      convidados: json['convidados'] as String?,
      status: (json['status'] as String?) == 'cancelada'
          ? StatusAgendamento.cancelada
          : StatusAgendamento.confirmada,
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static String _hhmm(String? valor) => valor != null && valor.length >= 5
      ? valor.substring(0, 5)
      : (valor ?? '');

  bool get podeCancelar {
    if (status != StatusAgendamento.confirmada || data == null) return false;
    final partes = horaInicio.split(':');
    final inicio = DateTime(
      data!.year,
      data!.month,
      data!.day,
      int.tryParse(partes.elementAtOrNull(0) ?? '') ?? 0,
      int.tryParse(partes.elementAtOrNull(1) ?? '') ?? 0,
    );
    final limite = inicio.subtract(
      Duration(hours: antecedenciaCancelamentoHoras),
    );
    return DateTime.now().isBefore(limite);
  }
}
