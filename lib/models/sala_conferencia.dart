class SalaConferencia {
  final int id;
  final String nome;
  final String numeroDiscagem;

  const SalaConferencia({
    required this.id,
    required this.nome,
    required this.numeroDiscagem,
  });

  factory SalaConferencia.fromJson(Map<String, dynamic> json) {
    return SalaConferencia(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nome: json['nome'] as String? ?? '',
      numeroDiscagem: json['numero_discagem'] as String? ?? '',
    );
  }
}
