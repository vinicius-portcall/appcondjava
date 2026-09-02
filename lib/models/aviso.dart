class Aviso {
  final int id;
  final String titulo;
  final String mensagem;
  final String? imagemUrl;
  final String? criadoPor;
  final DateTime? criadoEm;

  const Aviso({
    required this.id,
    required this.titulo,
    required this.mensagem,
    this.imagemUrl,
    this.criadoPor,
    this.criadoEm,
  });

  factory Aviso.fromJson(Map<String, dynamic> json) {
    return Aviso(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      titulo: json['titulo'] as String? ?? '',
      mensagem: json['mensagem'] as String? ?? '',
      imagemUrl: json['imagem_url'] as String?,
      criadoPor: json['criado_por'] as String?,
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }
}
