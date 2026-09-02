class Manutencao {
  final int id;
  final String equipamento;
  final String? descricao;
  final DateTime? ultimaManutencao;
  final DateTime proximaManutencao;

  const Manutencao({
    required this.id,
    required this.equipamento,
    this.descricao,
    this.ultimaManutencao,
    required this.proximaManutencao,
  });

  factory Manutencao.fromJson(Map<String, dynamic> json) {
    return Manutencao(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      equipamento: json['equipamento'] as String? ?? '',
      descricao: json['descricao'] as String?,
      ultimaManutencao: DateTime.tryParse(
        json['ultima_manutencao'] as String? ?? '',
      ),
      proximaManutencao:
          DateTime.tryParse(json['proxima_manutencao'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Dias até a próxima manutenção (negativo = atrasada).
  int get diasRestantes {
    final hoje = DateTime.now();
    final hojeSemHora = DateTime(hoje.year, hoje.month, hoje.day);
    return proximaManutencao.difference(hojeSemHora).inDays;
  }
}
