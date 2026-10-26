/// Versão do app, fixada em código.
///
/// Serve para responder, do lado do servidor, uma pergunta que já custou
/// horas: "o celular está rodando qual build?". Ela viaja no User-Agent do
/// SIP (aparece em todo REGISTER e INVITE no log do Asterisk) e no diário
/// de bordo do painel (`api_diag.php`).
///
/// As métricas de instalação do TestFlight demoram horas para atualizar e
/// não servem para confirmar isso na hora do teste.
///
/// Mantenha igual ao `version:` do pubspec.yaml ao subir uma versão.
const String versaoApp = '1.2.1+23';
