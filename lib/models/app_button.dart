enum AppButtonType { discar, dtmf }

class AppButton {
  final String nome;
  final AppButtonType tipo;
  final String? destino;
  final String? dtmfDigitos;
  final String? icone;
  final int ordem;

  const AppButton({
    required this.nome,
    required this.tipo,
    this.destino,
    this.dtmfDigitos,
    this.icone,
    this.ordem = 0,
  });

  factory AppButton.fromJson(Map<String, dynamic> json) {
    return AppButton(
      nome: json['nome'] as String? ?? '',
      tipo: (json['tipo'] as String?) == 'dtmf'
          ? AppButtonType.dtmf
          : AppButtonType.discar,
      destino: json['destino'] as String?,
      dtmfDigitos: json['dtmf_digitos'] as String?,
      icone: json['icone'] as String?,
      ordem: int.tryParse('${json['ordem'] ?? 0}') ?? 0,
    );
  }
}
