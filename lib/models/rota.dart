/// Os 3 blocos de "quem toca primeiro" que o morador pode reordenar.
/// `ramalDigital` é rotulado como "App Celular" na UI — é o próprio
/// Portcall registrado como ramal SIP no celular do morador, diferente
/// de `celular`, que é uma ligação comum pro número de telefone.
enum CategoriaRota {
  celular,
  ramalDigital,
  ramalAnalogico;

  String get label => switch (this) {
    CategoriaRota.celular => 'Celular',
    CategoriaRota.ramalDigital => 'App Celular',
    CategoriaRota.ramalAnalogico => 'Ramal Analógico',
  };

  String get token => switch (this) {
    CategoriaRota.celular => 'celular',
    CategoriaRota.ramalDigital => 'ramal_digital',
    CategoriaRota.ramalAnalogico => 'ramal_analogico',
  };

  static CategoriaRota? fromToken(String token) {
    for (final categoria in CategoriaRota.values) {
      if (categoria.token == token) return categoria;
    }
    return null;
  }
}
