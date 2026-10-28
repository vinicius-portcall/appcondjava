/// Uma unidade do condomínio (apartamento, casa, "porteiro") como ela aparece
/// na tela de Apartamentos.
///
/// O [nome] é o do morador e é **opcional** — vem da coluna `nome` de
/// `rotas_horarios`, que o síndico preenche se quiser. Condomínio que não
/// cadastrar nenhum continua vendo só o número, exatamente como antes.
class Unidade {
  const Unidade({required this.apartamento, this.nome});

  /// O que de fato se disca. Nunca vazio.
  final String apartamento;

  /// Nome do morador, quando cadastrado. Nulo é o caso normal.
  final String? nome;

  /// Como a unidade deve ser lida por quem usa o app: "101 — João Silva",
  /// ou só "101" quando não há nome.
  ///
  /// O número vem primeiro de propósito: é por ele que o morador procura na
  /// lista, e é ele que identifica a unidade sem ambiguidade — dois Joões em
  /// prédios grandes não são raros.
  String get rotulo {
    final n = nome?.trim();
    if (n == null || n.isEmpty) return apartamento;
    return '$apartamento — $n';
  }

  factory Unidade.fromJson(Map<String, dynamic> json) {
    final nome = json['nome']?.toString().trim();
    return Unidade(
      apartamento: json['apartamento']?.toString() ?? '',
      nome: (nome == null || nome.isEmpty) ? null : nome,
    );
  }

  /// Para a lista vinda de uma versão do painel que ainda não conhece nomes,
  /// e para o fallback do `apartamentos` antigo da API.
  factory Unidade.semNome(String apartamento) =>
      Unidade(apartamento: apartamento);
}
