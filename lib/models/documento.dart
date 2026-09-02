enum DocumentoCategoria { balancete, regimento, ata, outro }

class Documento {
  final int id;
  final String titulo;
  final DocumentoCategoria categoria;
  final String arquivoUrl;
  final DateTime? criadoEm;

  const Documento({
    required this.id,
    required this.titulo,
    required this.categoria,
    required this.arquivoUrl,
    this.criadoEm,
  });

  factory Documento.fromJson(Map<String, dynamic> json) {
    return Documento(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      titulo: json['titulo'] as String? ?? '',
      categoria: _categoriaFromString(json['categoria'] as String?),
      arquivoUrl: json['arquivo_url'] as String? ?? '',
      criadoEm: DateTime.tryParse(json['criado_em'] as String? ?? ''),
    );
  }

  static DocumentoCategoria _categoriaFromString(String? valor) {
    switch (valor) {
      case 'balancete':
        return DocumentoCategoria.balancete;
      case 'regimento':
        return DocumentoCategoria.regimento;
      case 'ata':
        return DocumentoCategoria.ata;
      default:
        return DocumentoCategoria.outro;
    }
  }

  String get categoriaLabel {
    switch (categoria) {
      case DocumentoCategoria.balancete:
        return 'Balancete';
      case DocumentoCategoria.regimento:
        return 'Regimento Interno';
      case DocumentoCategoria.ata:
        return 'Ata de Assembleia';
      case DocumentoCategoria.outro:
        return 'Outro';
    }
  }
}
