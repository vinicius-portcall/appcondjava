import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

import '../models/app_button.dart';
import '../models/aviso.dart';
import '../models/branding.dart';
import '../models/acesso_portao.dart';
import '../models/chamado.dart';
import '../models/documento.dart';
import '../models/encomenda.dart';
import '../models/agendamento.dart';
import '../models/camera.dart';
import '../models/interfone.dart';
import '../models/convidado_lista.dart';
import '../models/espaco.dart';
import '../models/manutencao.dart';
import '../models/morador_facial.dart';
import '../models/sala_conferencia.dart';
import '../models/visitante_pass.dart';

class ApiService {
  final String painelUrl;

  ApiService(this.painelUrl);

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = painelUrl.endsWith('/')
        ? painelUrl.substring(0, painelUrl.length - 1)
        : painelUrl;
    return Uri.parse('$base/$path').replace(queryParameters: query);
  }

  /// Também serve como checagem de credenciais no login: `api_app_config.php`
  /// valida ramal+senha e já devolve o servidor/porta SIP corretos pro
  /// condomínio, então login não precisa mais pedir esses campos técnicos.
  Future<Branding> fetchBranding(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_app_config.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Ramal ou senha inválidos.');
    }

    return Branding.fromJson(json);
  }

  Future<({List<AppButton> botoes, List<String> apartamentos})> fetchBotoes(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(_uri('api_botoes.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar botões.');
    }

    final lista = (json['botoes'] as List<dynamic>? ?? [])
        .map((e) => AppButton.fromJson(e as Map<String, dynamic>))
        .toList();
    lista.sort((a, b) => a.ordem.compareTo(b.ordem));

    final apartamentos = (json['apartamentos'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();

    return (botoes: lista, apartamentos: apartamentos);
  }

  Future<List<Aviso>> fetchAvisos(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_mural.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar avisos.');
    }

    return (json['avisos'] as List<dynamic>? ?? [])
        .map((e) => Aviso.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Manutencao>> fetchManutencoes(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_manutencoes.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar manutenções.');
    }

    return (json['manutencoes'] as List<dynamic>? ?? [])
        .map((e) => Manutencao.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Chamado>> fetchChamados(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_chamados.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar chamados.');
    }

    return (json['chamados'] as List<dynamic>? ?? [])
        .map((e) => Chamado.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> enviarChamado(
    String ramal,
    String senha, {
    String? apartamento,
    required String assunto,
    required String mensagem,
  }) async {
    final res = await http
        .post(
          _uri('api_chamado_criar.php'),
          body: {
            'ramal': ramal,
            'senha': senha,
            'apartamento': ?apartamento,
            'assunto': assunto,
            'mensagem': mensagem,
          },
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao enviar chamado.');
    }
  }

  Future<List<Encomenda>> fetchEncomendas(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_encomendas.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar encomendas.');
    }

    return (json['encomendas'] as List<dynamic>? ?? [])
        .map((e) => Encomenda.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> confirmarRetirada(
    String ramal,
    String senha,
    int id,
    String retiradoPor,
  ) async {
    final res = await http
        .post(
          _uri('api_encomenda_retirar.php'),
          body: {
            'ramal': ramal,
            'senha': senha,
            'id': '$id',
            'retirado_por': retiradoPor,
          },
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao confirmar retirada.');
    }
  }

  Future<List<Documento>> fetchDocumentos(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_documentos.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar documentos.');
    }

    return (json['documentos'] as List<dynamic>? ?? [])
        .map((e) => Documento.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AcessoPortao>> fetchHistoricoAcessos(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(
          _uri('api_historico_acessos.php', {'ramal': ramal, 'senha': senha}),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar histórico de acessos.');
    }

    return (json['acessos'] as List<dynamic>? ?? [])
        .map((e) => AcessoPortao.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// "Fire-and-forget": erro aqui não deve travar o uso do botão de portão
  /// em si (a chamada já foi feita, o DTMF já foi enviado) — quem chama
  /// decide se ignora a falha silenciosamente.
  Future<void> registrarAcessoPortao(
    String ramal,
    String senha,
    String botaoNome,
  ) async {
    final res = await http
        .post(
          _uri('api_acesso_portao.php'),
          body: {'ramal': ramal, 'senha': senha, 'botao_nome': botaoNome},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao registrar acesso.');
    }
  }

  Future<void> enviarAlerta(String ramal, String senha, String tipo) async {
    final res = await http
        .post(
          _uri('api_alerta.php'),
          body: {'ramal': ramal, 'senha': senha, 'tipo': tipo},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao enviar alerta.');
    }
  }

  Future<VisitantePass> criarVisitantePass(
    String ramal,
    String senha, {
    required String nomeVisitante,
    String? observacao,
    required int validadeHoras,
  }) async {
    final res = await http
        .post(
          _uri('api_qr_criar.php'),
          body: {
            'ramal': ramal,
            'senha': senha,
            'nome_visitante': nomeVisitante,
            'observacao': ?observacao,
            'validade_horas': '$validadeHoras',
          },
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao gerar passe de visitante.');
    }

    return VisitantePass.fromJson(json['passe'] as Map<String, dynamic>);
  }

  Future<List<VisitantePass>> fetchVisitantesPass(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(_uri('api_qr_listar.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar passes de visitante.');
    }

    return (json['passes'] as List<dynamic>? ?? [])
        .map((e) => VisitantePass.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelarVisitantePass(String ramal, String senha, int id) async {
    final res = await http
        .post(
          _uri('api_qr_cancelar.php'),
          body: {'ramal': ramal, 'senha': senha, 'id': '$id'},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao cancelar passe.');
    }
  }

  Future<List<Interfone>> fetchInterfonia(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_interfonia.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar interfones.');
    }

    return (json['interfones'] as List<dynamic>? ?? [])
        .map((e) => Interfone.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Camera>> fetchCameras(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_cameras.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar câmeras.');
    }

    return (json['cameras'] as List<dynamic>? ?? [])
        .map((e) => Camera.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> apagarVisitantePass(String ramal, String senha, int id) async {
    final res = await http
        .post(
          _uri('api_qr_apagar.php'),
          body: {'ramal': ramal, 'senha': senha, 'id': '$id'},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao apagar passe.');
    }
  }

  Future<List<Espaco>> fetchEspacos(String ramal, String senha) async {
    final res = await http
        .get(_uri('api_espacos.php', {'ramal': ramal, 'senha': senha}))
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar espaços comuns.');
    }

    return (json['espacos'] as List<dynamic>? ?? [])
        .map((e) => Espaco.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<SlotDisponibilidade>> fetchDisponibilidade(
    String ramal,
    String senha, {
    required int espacoId,
    required String data,
  }) async {
    final res = await http
        .get(
          _uri('api_agenda_disponibilidade.php', {
            'ramal': ramal,
            'senha': senha,
            'espaco_id': '$espacoId',
            'data': data,
          }),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar disponibilidade.');
    }

    return (json['slots'] as List<dynamic>? ?? [])
        .map((e) => SlotDisponibilidade.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> criarAgendamento(
    String ramal,
    String senha, {
    required int espacoId,
    required String data,
    required String horaInicio,
    required String horaFim,
    String? convidados,
  }) async {
    final res = await http
        .post(
          _uri('api_agendamento_criar.php'),
          body: {
            'ramal': ramal,
            'senha': senha,
            'espaco_id': '$espacoId',
            'data': data,
            'hora_inicio': horaInicio,
            'hora_fim': horaFim,
            'convidados': ?convidados,
          },
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao criar reserva.');
    }
  }

  Future<List<Agendamento>> fetchAgendamentos(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(
          _uri('api_agendamentos_listar.php', {'ramal': ramal, 'senha': senha}),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar reservas.');
    }

    return (json['agendamentos'] as List<dynamic>? ?? [])
        .map((e) => Agendamento.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelarAgendamento(String ramal, String senha, int id) async {
    final res = await http
        .post(
          _uri('api_agendamento_cancelar.php'),
          body: {'ramal': ramal, 'senha': senha, 'id': '$id'},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao cancelar reserva.');
    }
  }

  Future<ConvidadoLista> criarConvidado(
    String ramal,
    String senha, {
    required String nomeConvidado,
    String? observacao,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final res = await http
        .post(
          _uri('api_convidado_criar.php'),
          body: {
            'ramal': ramal,
            'senha': senha,
            'nome_convidado': nomeConvidado,
            'observacao': ?observacao,
            'data_inicio': dataInicio.toIso8601String(),
            'data_fim': dataFim.toIso8601String(),
          },
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao cadastrar convidado.');
    }

    return ConvidadoLista(
      id: int.tryParse(json['id'].toString()) ?? 0,
      nomeConvidado: nomeConvidado,
      observacao: observacao,
      dataInicio: dataInicio,
      dataFim: dataFim,
      status: StatusConvidado.aguardando,
    );
  }

  Future<List<ConvidadoLista>> fetchConvidados(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(
          _uri('api_convidados_listar.php', {'ramal': ramal, 'senha': senha}),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar convidados.');
    }

    return (json['convidados'] as List<dynamic>? ?? [])
        .map((e) => ConvidadoLista.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelarConvidado(String ramal, String senha, int id) async {
    final res = await http
        .post(
          _uri('api_convidado_cancelar.php'),
          body: {'ramal': ramal, 'senha': senha, 'id': '$id'},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao cancelar convidado.');
    }
  }

  /// Best-effort: quem chama decide se ignora falha (não deve travar login).
  Future<void> registrarPushToken(
    String ramal,
    String senha,
    String fcmToken,
  ) async {
    final res = await http
        .post(
          _uri('api_push_registrar.php'),
          body: {'ramal': ramal, 'senha': senha, 'fcm_token': fcmToken},
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao registrar notificações.');
    }
  }

  Future<List<MoradorFacial>> fetchMoradoresFacial(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(
          _uri('api_facial_moradores_listar.php', {
            'ramal': ramal,
            'senha': senha,
          }),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(
        json['error'] ?? 'Erro ao buscar moradores cadastrados no facial.',
      );
    }

    return (json['moradores'] as List<dynamic>? ?? [])
        .map((e) => MoradorFacial.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Envia nome + foto pra cadastro self-service direto no equipamento
  /// facial. O apartamento é resolvido no servidor a partir do ramal
  /// logado — o morador não escolhe/digita apartamento. O backend já faz a
  /// checagem de qualidade da foto (rosto visível, iluminação etc) e
  /// recusa fotos ruins, então essa chamada pode demorar mais que as outras.
  Future<void> cadastrarMoradorFacial(
    String ramal,
    String senha, {
    required String nome,
    required File foto,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('api_facial_moradores_cadastrar.php'),
    )
      ..fields['ramal'] = ramal
      ..fields['senha'] = senha
      ..fields['nome'] = nome
      ..files.add(await http.MultipartFile.fromPath('foto', foto.path));

    final streamed = await request.send().timeout(
      const Duration(seconds: 25),
    );
    final res = await http.Response.fromStream(streamed);

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao cadastrar rosto no facial.');
    }
  }

  Future<void> removerMoradorFacial(String ramal, String senha, int id) async {
    final res = await http
        .post(
          _uri('api_facial_moradores_remover.php'),
          body: {'ramal': ramal, 'senha': senha, 'id': '$id'},
        )
        .timeout(const Duration(seconds: 10));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao remover morador do facial.');
    }
  }

  /// Salas são criadas pelo síndico no painel — o app só lista as ativas
  /// e entra discando o número normal, igual qualquer outra chamada.
  Future<List<SalaConferencia>> fetchSalasConferencia(
    String ramal,
    String senha,
  ) async {
    final res = await http
        .get(
          _uri('api_salas_conferencia_listar.php', {
            'ramal': ramal,
            'senha': senha,
          }),
        )
        .timeout(const Duration(seconds: 8));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao buscar salas de reunião.');
    }

    return (json['salas'] as List<dynamic>? ?? [])
        .map((e) => SalaConferencia.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Consultado sob demanda (polling) pela tela de chamada enquanto o
  /// usuário está numa sala — não é algo pra guardar em cache.
  Future<int> fetchParticipantesSala(
    String ramal,
    String senha,
    int salaId,
  ) async {
    final res = await http
        .get(
          _uri('api_salas_conferencia_participantes.php', {
            'ramal': ramal,
            'senha': senha,
            'id': '$salaId',
          }),
        )
        .timeout(const Duration(seconds: 6));

    final json = jsonDecode(res.body) as Map<String, dynamic>;
    if (json['ok'] != true) {
      throw Exception(json['error'] ?? 'Erro ao consultar participantes.');
    }
    return int.tryParse(json['participantes'].toString()) ?? 0;
  }
}
