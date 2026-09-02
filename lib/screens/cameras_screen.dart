import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/camera.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

/// Lista as câmeras do condomínio (IP direta ou canal de DVR/NVR, tanto faz
/// pro app — a URL RTSP já vem pronta do servidor) e abre o stream ao vivo
/// em tela cheia ao tocar.
class CamerasScreen extends StatefulWidget {
  final ApiService api;
  final SipAccount conta;

  const CamerasScreen({super.key, required this.api, required this.conta});

  @override
  State<CamerasScreen> createState() => _CamerasScreenState();
}

class _CamerasScreenState extends State<CamerasScreen> {
  List<Camera> _cameras = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final cameras = await widget.api.fetchCameras(
        widget.conta.ramal,
        widget.conta.senha,
      );
      if (!mounted) return;
      setState(() {
        _cameras = cameras;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar as câmeras.';
        _carregando = false;
      });
    }
  }

  void _abrirCamera(Camera camera) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _CameraStreamScreen(camera: camera)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Câmeras')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
            ? Center(child: Text(_erro!))
            : _cameras.isEmpty
            ? ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.only(top: 80),
                    child: Center(
                      child: Text('Nenhuma câmera cadastrada ainda.'),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _cameras.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final c = _cameras[i];
                  return Card(
                    elevation: 0,
                    color: scheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(12),
                      leading: CircleAvatar(
                        backgroundColor: scheme.primaryContainer,
                        child: Icon(
                          Icons.videocam_rounded,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                        c.nome,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Toque para ver ao vivo'),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () => _abrirCamera(c),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _CameraStreamScreen extends StatefulWidget {
  final Camera camera;

  const _CameraStreamScreen({required this.camera});

  @override
  State<_CameraStreamScreen> createState() => _CameraStreamScreenState();
}

class _CameraStreamScreenState extends State<_CameraStreamScreen> {
  late final Player _player;
  late final VideoController _videoController;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _player.open(Media(widget.camera.url));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.camera.nome),
      ),
      body: Center(
        child: Video(
          controller: _videoController,
          fill: Colors.black,
        ),
      ),
    );
  }
}
