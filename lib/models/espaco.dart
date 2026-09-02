class Espaco {
  final int id;
  final String nome;
  final double taxa;
  final String horarioAbertura;
  final String horarioFechamento;
  final int duracaoSlotMinutos;
  final int antecedenciaCancelamentoHoras;

  const Espaco({
    required this.id,
    required this.nome,
    required this.taxa,
    required this.horarioAbertura,
    required this.horarioFechamento,
    required this.duracaoSlotMinutos,
    required this.antecedenciaCancelamentoHoras,
  });

  factory Espaco.fromJson(Map<String, dynamic> json) {
    return Espaco(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nome: json['nome'] as String? ?? '',
      taxa: double.tryParse(json['taxa'].toString()) ?? 0,
      horarioAbertura: (json['horario_abertura'] as String? ?? '').substring(
        0,
        5,
      ),
      horarioFechamento: (json['horario_fechamento'] as String? ?? '')
          .substring(0, 5),
      duracaoSlotMinutos:
          int.tryParse(json['duracao_slot_minutos'].toString()) ?? 60,
      antecedenciaCancelamentoHoras:
          int.tryParse(json['antecedencia_cancelamento_horas'].toString()) ??
          24,
    );
  }
}

class SlotDisponibilidade {
  final String horaInicio;
  final String horaFim;
  final bool disponivel;

  const SlotDisponibilidade({
    required this.horaInicio,
    required this.horaFim,
    required this.disponivel,
  });

  factory SlotDisponibilidade.fromJson(Map<String, dynamic> json) {
    return SlotDisponibilidade(
      horaInicio: json['hora_inicio'] as String? ?? '',
      horaFim: json['hora_fim'] as String? ?? '',
      disponivel: json['disponivel'] == true,
    );
  }
}
