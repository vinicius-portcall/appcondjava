import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sip_ua/sip_ua.dart';

import '../models/acesso_portao.dart';
import '../models/app_button.dart';
import '../models/aviso.dart';
import '../models/branding.dart';
import '../models/documento.dart';
import '../models/manutencao.dart';
import '../services/api_service.dart';
import '../services/foreground_service.dart';
import '../services/push_service.dart';
import '../services/session_service.dart';
import '../services/sip_service.dart';
import '../services/theme_service.dart';
import '../theme/app_colors.dart';
import 'agendamentos_screen.dart';
import 'apartamentos_screen.dart';
import 'call_screen.dart';
import 'cameras_screen.dart';
import 'dialpad_screen.dart';
import 'documentos_screen.dart';
import 'emergencia_screen.dart';
import 'encomendas_screen.dart';
import 'historico_acessos_screen.dart';
import 'interfonia_screen.dart';
import 'login_screen.dart';
import 'manutencoes_screen.dart';
import 'moradores_facial_screen.dart';
import 'mural_screen.dart';
import 'ouvidoria_screen.dart';
import 'rota_screen.dart';
import 'salas_conferencia_screen.dart';
import 'visitantes_qr_screen.dart';

class HomeScreen extends StatefulWidget {
  final SipAccount conta;
  final ThemeService themeService;

  /// Criado no main(), fora da árvore de widgets — ver o comentário em
  /// main.dart sobre o engine subindo sem Activity depois de um reboot.
  /// A tela só usa e escuta; quem controla o ciclo de vida é o main().
  final SipService sip;

  const HomeScreen({
    super.key,
    required this.conta,
    required this.themeService,
    required this.sip,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ApiService _api;
  late final SipService _sip;
  late final PushService _push;

  Branding _branding = Branding.fallback();
  List<AppButton> _botoes = [];
  List<String> _apartamentos = [];
  List<Aviso> _avisos = [];
  List<Manutencao> _manutencoes = [];
  List<Documento> _documentos = [];
  List<AcessoPortao> _historicoAcessos = [];
  bool _carregandoBotoes = true;
  bool _callScreenAberta = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _api = ApiService(widget.conta.painelUrl);
    _sip = widget.sip;
    _sip.addListener(_onSipChange);
    _push = PushService(api: _api, conta: widget.conta);
    // Com o engine persistente (ver PersistentEngineService), o app pode
    // ficar "aberto" (registrado, vivo) por dias sem nunca reiniciar de
    // verdade — _iniciar() só roda uma vez por vida do engine. Sem recarregar
    // ao voltar pro primeiro plano, uma mudança de botão/DTMF no painel (ex:
    // trocar o dígito do portão) nunca aparece no app até alguém forçar
    // parar e reabrir.
    _lifecycleListener = AppLifecycleListener(onResume: _recarregarDados);
    _iniciar();
  }

  /// Pede as permissões que exigem uma Activity visível (mic, câmera, tela
  /// cheia do CallKit) — normalmente sempre tem uma aqui (é o fluxo comum de
  /// abrir o app), mas se o engine persistente for recriado do zero em
  /// segundo plano (ex: Android matou o processo inteiro e o
  /// PersistentEngineService reiniciou sozinho antes do usuário abrir o app
  /// de novo), pedir permissão sem Activity lança erro — não pode deixar
  /// isso abortar o resto de _iniciar() e travar o registro SIP.
  Future<void> _pedirPermissoesDeMidia() async {
    try {
      final micStatus = await Permission.microphone.request();
      if (!mounted) return;
      if (!micStatus.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permissão de microfone negada — as chamadas não vão funcionar até você liberar nas configurações do celular.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      }
      await Permission.camera.request();
      unawaited(SipService.solicitarPermissaoTelaCheia());
    } catch (_) {
      // Sem Activity anexada agora — segue sem pedir; o SipService ainda
      // registra com o que já estiver concedido de uma sessão anterior.
    }
  }

  Future<void> _recarregarDados() async {
    Branding branding;
    try {
      branding = await _api.fetchBranding(widget.conta.ramal, widget.conta.senha);
      unawaited(SessionService().saveBranding(branding));
    } catch (_) {
      branding = await SessionService().loadBranding() ?? Branding.fallback();
    }
    final resultado = await _api
        .fetchBotoes(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => (botoes: <AppButton>[], apartamentos: <String>[]));
    final avisos = await _api
        .fetchAvisos(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => <Aviso>[]);
    final manutencoes = await _api
        .fetchManutencoes(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => <Manutencao>[]);
    final documentos = await _api
        .fetchDocumentos(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => <Documento>[]);
    final historicoAcessos = await _api
        .fetchHistoricoAcessos(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => <AcessoPortao>[]);

    if (!mounted) return;
    setState(() {
      _branding = branding;
      _botoes = resultado.botoes;
      _apartamentos = resultado.apartamentos;
      _avisos = avisos;
      _manutencoes = manutencoes;
      _documentos = documentos;
      _historicoAcessos = historicoAcessos;
      _carregandoBotoes = false;
    });
  }

  /// O registro SIP vem PRIMEIRO de propósito, e todo o resto é
  /// best-effort sem `await` que o bloqueie.
  ///
  /// Quando o engine sobe sozinho depois de reiniciar o celular
  /// (`RestartReceiver` → `PersistentEngineService`, sem nenhuma Activity),
  /// pedir permissão de microfone/câmera não tem Activity pra onde mostrar o
  /// diálogo e pode ficar pendurado pra sempre em vez de lançar erro — e o
  /// painel ainda está inalcançável porque o Wi-Fi demora dezenas de segundos
  /// pra reconectar no boot. Com `conectar()` no fim da fila, qualquer um
  /// desses dois segurava o registro e o ramal ficava fora do ar até alguém
  /// abrir o app na mão (confirmado em teste: boot limpo = nenhum REGISTER
  /// chegando no Asterisk; assim que a tela abriu, registrou na hora).
  ///
  /// Um único SipService, sempre o mesmo objeto, com ou sem tela visível — o
  /// PersistentEngineService só mantém o processo/engine vivo, não existe
  /// handoff entre dois registros pra fazer aqui.
  Future<void> _iniciar() async {
    debugPrint('[Portcall] _iniciar: começando (ramal ${widget.conta.ramal})');

    if (!_sip.isRegistered) {
      try {
        debugPrint('[Portcall] _iniciar: chamando conectar()');
        await _sip.conectar(widget.conta);
        debugPrint('[Portcall] _iniciar: conectar() retornou');
      } catch (e) {
        debugPrint('[Portcall] _iniciar: conectar() falhou: $e');
      }
    }

    if (!mounted) return;
    unawaited(_pedirPermissoesDeMidia());
    unawaited(
      _push.iniciar(aoReceberEmPrimeiroPlano: _mostrarNotificacaoPrimeiroPlano),
    );
    unawaited(_recarregarDados());
    unawaited(_garantirServicoEmSegundoPlano());
  }

  /// Sem o serviço de segundo plano o registro ainda funciona enquanto o app
  /// estiver em primeiro plano — não pode travar o resto do início por causa
  /// disso.
  Future<void> _garantirServicoEmSegundoPlano() async {
    try {
      await ForegroundService.start(ramal: widget.conta.ramal);
      unawaited(ForegroundService.requestIgnoreBatteryOptimizations());
    } catch (e) {
      debugPrint('[Portcall] ForegroundService.start falhou: $e');
    }
  }

  void _onSipChange() {
    if (!mounted) return;
    setState(() {});

    final call = _sip.activeCall;
    if (call != null && _sip.emChamada && !_callScreenAberta) {
      final entrante = call.session.direction == Direction.incoming;
      _abrirTelaChamada(entrante);
    }
  }

  /// Também chamado pelo banner "voltar pra ligação" — se o usuário sair da
  /// CallScreen pelo botão voltar do Android com a ligação ainda ativa (ex:
  /// pra checar outra tela), nada de novo acontece no SipService (sem
  /// notifyListeners), então _onSipChange nunca dispara de novo sozinho e a
  /// ligação ficava inacessível até desligar ou o outro lado desligar.
  void _abrirTelaChamada(bool entrante) {
    _callScreenAberta = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => CallScreen(
              sip: _sip,
              botoesDtmf: _botoes
                  .where((b) => b.tipo == AppButtonType.dtmf)
                  .toList(),
              chamadaEntrante: entrante,
              api: _api,
              conta: widget.conta,
            ),
          ),
        )
        .then((_) => setState(() => _callScreenAberta = false));
  }

  Future<void> _tocarBotao(AppButton botao, {bool video = false}) async {
    try {
      if (botao.tipo == AppButtonType.discar) {
        if (botao.destino == null || botao.destino!.isEmpty) return;
        if (!_sip.isRegistered) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Ainda não registrado no servidor (status: ${_statusRegistro()}). Aguarde e tente de novo.',
              ),
            ),
          );
          return;
        }
        await _sip.ligarPara(botao.destino!, video: video);
      } else {
        if (_sip.emChamada) {
          _sip.enviarDtmf(botao.dtmfDigitos ?? '');
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Esse botão só funciona durante uma chamada ativa.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao executar o botão: $e'),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  Future<void> _sair() async {
    await _sip.desconectar();
    await ForegroundService.stop();
    await SessionService().clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            LoginScreen(themeService: widget.themeService, sip: widget.sip),
      ),
    );
  }

  String _statusRegistro() {
    switch (_sip.registrationState) {
      case RegistrationStateEnum.REGISTERED:
        return 'Online';
      case RegistrationStateEnum.REGISTRATION_FAILED:
        return 'Falha ao conectar';
      case RegistrationStateEnum.UNREGISTERED:
        return 'Desconectado';
      default:
        return 'Conectando…';
    }
  }

  Color _corStatus() {
    switch (_sip.registrationState) {
      case RegistrationStateEnum.REGISTERED:
        return Colors.green;
      case RegistrationStateEnum.REGISTRATION_FAILED:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _sip.removeListener(_onSipChange);
    // Sem _sip.dispose() de propósito: o SipService é do main(), não desta
    // tela — ele precisa continuar registrado depois que a Activity morre
    // (tela apagada, app fora dos recentes), que é justamente o cenário em
    // que o interfone toca.
    _push.dispose();
    super.dispose();
  }

  void _mostrarNotificacaoPrimeiroPlano(RemoteMessage mensagem) {
    if (!mounted) return;
    final notificacao = mensagem.notification;
    if (notificacao != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${notificacao.title ?? ''}: ${notificacao.body ?? ''}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    // Com o app aberto, o FCM só entrega a mensagem — não atualiza a tela
    // sozinho. Recarrega a lista certa conforme o "tipo" mandado pelo backend.
    switch (mensagem.data['tipo']) {
      case 'mural':
        unawaited(_recarregarAvisos());
        break;
      case 'chamada':
        _reconectarSipSeNecessario();
        break;
    }
  }

  /// Chamada chegando (avisado por push, ver fcm_avisar_chamada_async no
  /// servidor) — reconecta o SIP na hora se a conexão tiver caído em segundo
  /// plano, em vez de esperar a próxima tentativa automática do sip_ua.
  void _reconectarSipSeNecessario() {
    if (!_sip.isRegistered) {
      unawaited(_sip.conectar(widget.conta));
    }
  }

  Future<void> _recarregarAvisos() async {
    final avisos = await _api
        .fetchAvisos(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => <Aviso>[]);
    if (!mounted) return;
    setState(() => _avisos = avisos);
  }

  void _abrirDiscador() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => DialpadScreen(sip: _sip)));
  }

  void _abrirApartamentos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ApartamentosScreen(sip: _sip, apartamentos: _apartamentos),
      ),
    );
  }

  void _abrirInterfonia() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InterfoniaScreen(
          api: _api,
          conta: widget.conta,
          sip: _sip,
        ),
      ),
    );
  }

  Future<void> _abrirConfiguracoesBateria() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receber ligações sempre'),
        content: const Text(
          'Alguns celulares (principalmente Samsung) limitam apps em '
          'segundo plano mesmo com a permissão de bateria já concedida, o '
          'que pode fazer o app parar de receber ligações depois de um '
          'tempo. Vamos abrir as configurações do app — procure por '
          '"Bateria" e escolha "Sem restrições".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir configurações'),
          ),
        ],
      ),
    );
    if (confirmou == true) {
      await ForegroundService.abrirConfiguracoesBateria();
    }
  }

  void _abrirRota() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RotaScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirCameras() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CamerasScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirEmergencia() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmergenciaScreen(
          api: _api,
          conta: widget.conta,
          branding: _branding,
        ),
      ),
    );
  }

  void _abrirManutencoes() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ManutencoesScreen(manutencoes: _manutencoes),
      ),
    );
  }

  void _abrirOuvidoria() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OuvidoriaScreen(
          api: _api,
          conta: widget.conta,
          apartamentos: _apartamentos,
        ),
      ),
    );
  }

  void _abrirEncomendas() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EncomendasScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirDocumentos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentosScreen(documentos: _documentos),
      ),
    );
  }

  Future<void> _abrirHistoricoAcessos() async {
    // Recarrega na hora de abrir — a lista pré-carregada na Home pode estar
    // desatualizada (eventos de acesso/facial não disparam notificação push
    // pra não gerar spam a cada identificação; então é aqui que atualiza).
    final historicoAcessos = await _api
        .fetchHistoricoAcessos(widget.conta.ramal, widget.conta.senha)
        .catchError((_) => _historicoAcessos);
    if (mounted) setState(() => _historicoAcessos = historicoAcessos);

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HistoricoAcessosScreen(acessos: _historicoAcessos),
      ),
    );
  }

  void _abrirVisitantesQr() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VisitantesQrScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirCadastroFacial() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MoradoresFacialScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirSalasConferencia() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SalasConferenciaScreen(
          api: _api,
          conta: widget.conta,
          sip: _sip,
        ),
      ),
    );
  }

  void _abrirAgendamentos() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AgendamentosScreen(api: _api, conta: widget.conta),
      ),
    );
  }

  void _abrirMural() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => MuralScreen(avisos: _avisos)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final botoesDiscar = _botoes
        .where((b) => b.tipo == AppButtonType.discar)
        .toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirDiscador,
        icon: const Icon(Icons.dialpad),
        label: const Text('Discar'),
      ),
      appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            if (_branding.logoUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  _branding.logoUrl!,
                  height: 28,
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _branding.appNome,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_branding.condominioNome != null)
                    Text(
                      _branding.condominioNome!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: widget.themeService.isDark ? 'Tema claro' : 'Tema escuro',
            onPressed: () => widget.themeService.alternar(),
            icon: Icon(
              widget.themeService.isDark
                  ? Icons.light_mode_rounded
                  : Icons.dark_mode_rounded,
            ),
          ),
          IconButton(onPressed: _sair, icon: const Icon(Icons.logout)),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _corStatus().withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _corStatus().withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 10, color: _corStatus()),
                    const SizedBox(width: 8),
                    Text(
                      '${_statusRegistro()} — Ramal ${widget.conta.ramal}',
                      style: TextStyle(
                        color: _corStatus(),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_sip.emChamada && !_callScreenAberta)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Material(
                color: Colors.green,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _abrirTelaChamada(
                    _sip.activeCall?.session.direction == Direction.incoming,
                  ),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.call, color: Colors.white),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ligação em andamento — toque para voltar',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _abrirEmergencia,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.isDark
                      ? Colors.redAccent.shade100
                      : Colors.red.shade700,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.warning_amber_rounded),
                label: const Text(
                  'Emergência',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          Expanded(
            child: _carregandoBotoes
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                    children: [
                      Text(
                        'AÇÕES RÁPIDAS',
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.92,
                        children: [
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.home_rounded,
                            cor: colors.tileAccents[0],
                            titulo: 'Apartamentos',
                            subtitulo: _apartamentos.isNotEmpty
                                ? '${_apartamentos.length}'
                                : null,
                            onTap: _apartamentos.isNotEmpty
                                ? _abrirApartamentos
                                : null,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.videocam_rounded,
                            cor: colors.tileAccents[1],
                            titulo: 'Câmeras',
                            onTap: _abrirCameras,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.campaign_rounded,
                            cor: colors.tileAccents[2],
                            titulo: 'Mural',
                            subtitulo: _avisos.isNotEmpty
                                ? '${_avisos.length}'
                                : null,
                            onTap: _abrirMural,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.build_circle_outlined,
                            cor: colors.tileAccents[3],
                            titulo: 'Manutenções',
                            subtitulo: _manutencoes.isNotEmpty
                                ? '${_manutencoes.length}'
                                : null,
                            onTap: _abrirManutencoes,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.forum_outlined,
                            cor: colors.tileAccents[4],
                            titulo: 'Ouvidoria',
                            onTap: _abrirOuvidoria,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.inventory_2_outlined,
                            cor: colors.tileAccents[5],
                            titulo: 'Encomendas',
                            onTap: _abrirEncomendas,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.description_outlined,
                            cor: colors.tileAccents[6],
                            titulo: 'Documentos',
                            subtitulo: _documentos.isNotEmpty
                                ? '${_documentos.length}'
                                : null,
                            onTap: _abrirDocumentos,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.door_front_door_outlined,
                            cor: colors.tileAccents[7],
                            titulo: 'Acessos',
                            subtitulo: _historicoAcessos.isNotEmpty
                                ? '${_historicoAcessos.length}'
                                : null,
                            onTap: _abrirHistoricoAcessos,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.qr_code_2_rounded,
                            cor: colors.tileAccents[8],
                            titulo: 'Visitantes',
                            onTap: _abrirVisitantesQr,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.pool_rounded,
                            cor: colors.tileAccents[9],
                            titulo: 'Agendamentos',
                            onTap: _abrirAgendamentos,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.phone_in_talk_outlined,
                            cor: colors.tileAccents[1],
                            titulo: 'Interfonia',
                            onTap: _abrirInterfonia,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.swap_vert_rounded,
                            cor: colors.tileAccents[0],
                            titulo: 'Ordem de Chamada',
                            onTap: _abrirRota,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.battery_alert_rounded,
                            cor: colors.tileAccents[3],
                            titulo: 'Bateria',
                            onTap: _abrirConfiguracoesBateria,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.face_retouching_natural_rounded,
                            cor: colors.tileAccents[6],
                            titulo: 'Cadastro Facial',
                            onTap: _abrirCadastroFacial,
                          ),
                          _tileAcaoRapida(
                            context,
                            colors: colors,
                            icone: Icons.groups_rounded,
                            cor: colors.tileAccents[7],
                            titulo: 'Reuniões',
                            onTap: _abrirSalasConferencia,
                          ),
                        ],
                      ),
                      if (botoesDiscar.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'Ramais',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: colors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 0.85,
                              ),
                          itemCount: botoesDiscar.length,
                          itemBuilder: (context, i) {
                            final b = botoesDiscar[i];
                            return _cardBotao(
                              context,
                              colors: colors,
                              icone: b.icone,
                              titulo: b.nome,
                              onTapChamada: () => _tocarBotao(b),
                              onTapVideo: () => _tocarBotao(b, video: true),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tileAcaoRapida(
    BuildContext context, {
    required AppColors colors,
    required IconData icone,
    required Color cor,
    required String titulo,
    String? subtitulo,
    VoidCallback? onTap,
  }) {
    final desabilitado = onTap == null;
    return Container(
      decoration: BoxDecoration(
        color: colors.tileBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cor.withValues(alpha: desabilitado ? 0.08 : 0.35),
        ),
        boxShadow: desabilitado || !colors.tileGlow
            ? null
            : [
                BoxShadow(
                  color: cor.withValues(alpha: 0.22),
                  blurRadius: 14,
                  spreadRadius: -2,
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: cor.withValues(alpha: desabilitado ? 0.08 : 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icone,
                    color: desabilitado ? cor.withValues(alpha: 0.4) : cor,
                    size: 17,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: desabilitado ? colors.textMuted : colors.textBright,
                  ),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(
                      color: cor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBotao(
    BuildContext context, {
    required AppColors colors,
    required String? icone,
    required String titulo,
    VoidCallback? onTap,
    VoidCallback? onTapChamada,
    VoidCallback? onTapVideo,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colors.tileBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.brandAccent.withValues(alpha: 0.25)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.brandAccent.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      icone ?? '🔘',
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.textBright,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (onTapChamada != null && onTapVideo != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Chamada normal',
                        onPressed: onTapChamada,
                        icon: const Icon(Icons.call),
                      ),
                      IconButton(
                        tooltip: 'Chamada de vídeo',
                        onPressed: onTapVideo,
                        icon: const Icon(Icons.videocam),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
