/// Câmera de vídeo do condomínio (IP direta ou canal de DVR/NVR) — a URL RTSP
/// já vem pronta do servidor, com usuário/senha/canal já embutidos conforme o
/// tipo cadastrado no admin.
class Camera {
  final int id;
  final String nome;
  final String url;

  const Camera({required this.id, required this.nome, required this.url});

  factory Camera.fromJson(Map<String, dynamic> json) {
    return Camera(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nome: json['nome'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}
