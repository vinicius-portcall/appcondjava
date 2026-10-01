/// Chaves dos módulos que a administração liga e desliga no painel, por
/// condomínio (tela "Aplicativo → Opções do app" do clienteauto, que grava
/// em `condominios_modulos`).
///
/// As chaves viajam como texto dentro do `modulos` do `api_app_config.php` e
/// são gravadas no banco do painel, então **não podem ser renomeadas** depois
/// que um condomínio já salvou sua seleção: renomear faria o módulo sumir da
/// tela do morador sem ninguém ter desmarcado nada. Para trocar o texto que
/// aparece, mude o rótulo na tela — nunca a chave.
///
/// Ao acrescentar um módulo novo aqui, acrescente também na lista do painel;
/// módulo que o painel não conhece nunca chega marcado e ficaria invisível.
class ModulosApp {
  const ModulosApp._();

  static const unidades = 'unidades';
  static const cameras = 'cameras';
  static const mural = 'mural';
  static const manutencoes = 'manutencoes';
  static const ouvidoria = 'ouvidoria';
  static const encomendas = 'encomendas';
  static const documentos = 'documentos';
  static const acessos = 'acessos';
  static const visitantes = 'visitantes';
  static const agendamentos = 'agendamentos';
  static const interfonia = 'interfonia';
  static const ordemChamada = 'ordem_chamada';
  static const bateria = 'bateria';
  static const facial = 'facial';
  static const reunioes = 'reunioes';
  static const historicoChamadas = 'historico_chamadas';

  /// Todas as chaves, na mesma ordem em que aparecem na tela inicial.
  static const todas = <String>[
    unidades,
    cameras,
    mural,
    manutencoes,
    ouvidoria,
    encomendas,
    documentos,
    acessos,
    visitantes,
    agendamentos,
    interfonia,
    ordemChamada,
    bateria,
    facial,
    reunioes,
    historicoChamadas,
  ];
}
