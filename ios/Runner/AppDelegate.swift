import Flutter
import UIKit
import PushKit
import flutter_callkit_incoming

/// No Android o app continua registrado no SIP com a tela apagada através do
/// `PersistentEngineService` — um foreground service que segura o mesmo
/// FlutterEngine vivo. No iPhone isso não existe: o sistema suspende o app e
/// o WebSocket do SIP morre junto, então ninguém recebe o INVITE do
/// interfone.
///
/// O caminho equivalente no iOS é PushKit + CallKit: o servidor manda um push
/// VoIP (ver `apns_helper.php` no painel), o iOS acorda o app só por causa
/// dele, e o app tem poucos segundos para reportar uma chamada ao CallKit —
/// se não reportar, o iOS mata o processo e passa a ignorar os próximos
/// pushes.
///
/// Este arquivo é o pedaço que faltava: o `flutter_callkit_incoming` oferece
/// `setDevicePushTokenVoIP`/`showCallkitIncoming(fromPushKit:)`, mas NÃO
/// registra o PKPushRegistry sozinho — isso é responsabilidade do app. Sem o
/// registro abaixo, `getDevicePushTokenVoIP()` devolvia string vazia, o
/// `PushService` nunca mandava `voip_token` ao painel e o servidor não tinha
/// para onde enviar o push. O interfone simplesmente não tocava com a tela
/// apagada.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  /// Guardado numa propriedade de propósito: o PKPushRegistry para de
  /// funcionar se for desalocado, e um registry criado como variável local
  /// some no fim do método sem emitir erro nenhum.
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Depois do super de propósito: é ele que sobe o FlutterEngine implícito
    // e registra os plugins. Registrar o PushKit antes abriria uma janela em
    // que um push poderia chegar sem o plugin do CallKit existir — e push
    // VoIP não reportado faz o iOS matar o app.
    let resultado = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    registrarPushKit()
    return resultado
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func registrarPushKit() {
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
  }

  // MARK: - PKPushRegistryDelegate

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate pushCredentials: PKPushCredentials,
    for type: PKPushType
  ) {
    guard type == .voIP else { return }
    // O APNs espera o token em hexadecimal. O painel guarda exatamente esta
    // string na coluna voip_token e a usa como `apns-device-token`.
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    NSLog("[Portcall] token VoIP recebido (\(token.count) caracteres)")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    NSLog("[Portcall] token VoIP invalidado pelo sistema")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }

    let dados = payload.dictionaryPayload
    NSLog("[Portcall] push VoIP recebido: \(dados)")

    // O `id` vem do servidor e é o MESMO identificador que o app usa quando
    // o INVITE do SIP chega logo depois — sem ele, o CallKit ficaria com
    // duas chamadas para o mesmo toque (a do push e a do INVITE) e encerrar
    // uma deixaria a outra presa na tela. Se o payload vier sem id, geramos
    // um: melhor uma chamada com id improvisado do que não reportar nada e
    // ser morto pelo iOS.
    let id = (dados["id"] as? String)
      ?? (dados["uuid"] as? String)
      ?? UUID().uuidString
    // Os campos vêm do fcm_chamada_async.php. O `origem` é o ramal do
    // interfone e existe desde sempre (é o que o Android usa); nameCaller e
    // handle foram acrescentados para esta tela. Os fallbacks cobrem um
    // servidor ainda não atualizado.
    let nome = (dados["nameCaller"] as? String)
      ?? (dados["origem"] as? String)
      ?? "Interfone"
    let numero = (dados["handle"] as? String)
      ?? (dados["origem"] as? String)
      ?? ""
    let temVideo = leBooleano(dados["hasVideo"]) ?? true

    var args: [String: Any?] = [
      "id": id,
      "nameCaller": nome,
      "handle": numero,
      "appName": "Vídeo Atende",
      // type 1 = chamada de vídeo. O interfone liga com vídeo por padrão;
      // errar para menos esconderia a imagem da portaria na tela de chamada.
      "type": temVideo ? 1 : 0,
      "duration": 45000,
    ]
    args["ios"] = [
      "iconName": "AppIcon",
      "handleType": "generic",
      "supportsVideo": true,
      "supportsDTMF": true,
      "supportsHolding": false,
      "supportsGrouping": false,
      "supportsUngrouping": false,
      // Sem isso a chamada entraria no histórico do app Telefone do iPhone,
      // onde tocar no número tentaria discá-lo pela operadora.
      "includesCallsInRecents": false,
      // Quem manda na sessão de áudio num app WebRTC é o WebRTC. Com `true`
      // (o padrão), o plugin reconfigura a AVAudioSession por fora do
      // RTCAudioSession assim que o CallKit a ativa, e desfaz o viva-voz que
      // o app tinha acabado de pedir. Mesmo valor usado no IOSParams do
      // SipService — os dois caminhos precisam concordar, ou a chamada
      // vinda de push se comportaria diferente da vinda de INVITE.
      "configureAudioSession": false,
      "audioSessionMode": "voiceChat",
    ]

    reportarAoCallKit(args: args, completion: completion)
  }

  private func leBooleano(_ valor: Any?) -> Bool? {
    if let b = valor as? Bool { return b }
    if let n = valor as? NSNumber { return n.boolValue }
    if let s = valor as? String { return s == "1" || s.lowercased() == "true" }
    return nil
  }

  /// O plugin só existe depois que o FlutterEngine sobe e registra os
  /// plugins. Quando o iOS acorda o app do zero só para entregar o push, há
  /// uma janela curta em que `sharedInstance` ainda é nil — reportar nessa
  /// janela significaria não reportar, e o iOS derruba o app que recebe um
  /// push VoIP sem informar uma chamada.
  ///
  /// Por isso a tentativa é repetida por até ~2s. O prazo do sistema é da
  /// ordem de 5s, então ainda sobra margem para o CallKit aparecer.
  private func reportarAoCallKit(
    args: [String: Any?],
    tentativa: Int = 0,
    completion: @escaping () -> Void
  ) {
    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.showCallkitIncoming(Data(args: args), fromPushKit: true) {
        completion()
      }
      return
    }

    if tentativa >= 20 {
      NSLog("[Portcall] push VoIP: plugin do CallKit não subiu a tempo")
      completion()
      return
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
      self?.reportarAoCallKit(args: args, tentativa: tentativa + 1, completion: completion)
    }
  }
}
