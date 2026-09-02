class MoradorFacial {
  final int id;
  final String nome;
  final DateTime? criadoEm;

  const MoradorFacial({required this.id, required this.nome, this.criadoEm});

  factory MoradorFacial.fromJson(Map<String, dynamic> json) {
    return MoradorFacial(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nome: json['nome'] as String? ?? '',
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }
}
