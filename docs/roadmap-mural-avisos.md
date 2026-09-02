# Roadmap — Módulo Mural de Avisos

Acompanhamento do desenvolvimento do módulo "Mural de Avisos" (item 2.5 da `documentacao-tecnica-app.md`), o primeiro módulo novo do INOVASEG a ser implementado sobre a base do Portcall.

Legenda de status: 🔴 Pendente · 🟡 Em andamento · 🟢 Concluído

**Status geral: 🟢 Módulo concluído e validado pelo usuário (14/08/2026).** Backend no ar, testado, e app Flutter integrado e validado (`dart analyze`: nenhum problema encontrado). Testado de ponta a ponta num celular físico real (Samsung SM S916B) com o ramal `5500` do condomínio Jardim Botânico 03 — login funcionou e o Mural apareceu corretamente com o aviso de teste.

Servidor de referência: `clienteauto.portcallvoip.com.br` (painel PHP em `/var/www/html`, banco `azcall`).

## Backend (painel PHP + MySQL)

| # | Item | Status |
|---|---|---|
| 1 | Criar tabela `avisos` no banco `azcall` | 🟢 Concluído |
| 2 | Criar endpoint `api_mural.php` (consumido pelo app, mesmo padrão de auth ramal/senha de `api_botoes.php`) | 🟢 Concluído |
| 3 | Criar página de listagem `mural.php` no painel admin | 🟢 Concluído |
| 4 | Criar formulário `mural_form.php` (criar/editar, com upload de imagem) | 🟢 Concluído |
| 5 | Criar `mural_save.php` e `mural_delete.php` | 🟢 Concluído |
| 6 | Adicionar item "📢 Mural" no menu lateral (`render_sidebar` em `funcoes.php`) | 🟢 Concluído |
| 7 | Testar o endpoint `api_mural.php` via curl no próprio servidor | 🟢 Concluído |

## App Flutter

| # | Item | Status |
|---|---|---|
| 8 | Criar model `Aviso` (`lib/models/aviso.dart`) | 🟢 Concluído |
| 9 | Adicionar `ApiService.fetchAvisos()` | 🟢 Concluído |
| 10 | Criar `MuralScreen` (`lib/screens/mural_screen.dart`) | 🟢 Concluído |
| 11 | Adicionar atalho "Mural" na `HomeScreen` | 🟢 Concluído |
| 12 | Rodar `flutter analyze` para validar | 🟢 Concluído |

## Documentação

| # | Item | Status |
|---|---|---|
| 13 | Atualizar `docs/05-tela-inicial-e-navegacao.md` e `docs/06-integracao-com-o-painel.md` com o novo módulo | 🟢 Concluído |

## Teste em dispositivo real (14/08/2026)

Build instalado e validado num Samsung SM S916B (Android 16) conectado via USB. Ambiente Windows não tinha Flutter nem JDK 17 — resolvido via `winget` (Puro pra gerenciar o Flutter, Eclipse Temurin 17 pro Gradle) e dois ajustes permanentes em `android/gradle.properties` (caminho do projeto com "ç" exige `android.overridePathCheck=true`; JDK 17 explícito via `org.gradle.java.home`/`org.gradle.java.installations.paths`, já que só havia Java 8 no PATH e o JBR do Android Studio é Java 25, incompatível com o toolchain exigido por um dos plugins). Detalhes também registrados no `CLAUDE.md`.

**Credenciais de teste criadas no servidor** (condomínio "Jardim Botânico 03", id 19):
- Painel: `https://clienteauto.portcallvoip.com.br`
- Servidor/porta SIP: `clienteauto.portcallvoip.com.br` / `5061`
- Ramal: `5500` — senha: `Jardim5500`
- Um botão de teste (`Portão Social`, DTMF `1#`) e um aviso de teste (`Bem-vindo ao Portcall`) cadastrados pra esse condomínio, pra já aparecer conteúdo real na Home e no Mural.

## Achados corrigidos no caminho

- **`app_botoes` não existia** neste banco — sem ela, `api_botoes.php` lançava exceção e todo login novo no app falhava. Recriada com o schema inferido do código PHP existente, sem dados.
- **Ramais duplicados entre condomínios**: o painel (`ramais_save.php`) não valida se um número de ramal já está em uso por outro condomínio antes de criar o peer PJSIP/SIP no Asterisk — como os nomes de endpoint são globais no Asterisk (não isolados por tenant), um ramal "1000" ou "1001" novo simplesmente colide com um já existente (neste caso, do condomínio Doha) e nunca fica de fato acessível, mesmo aparecendo "criado" no banco. **Não corrigido ainda** (ficou como próximo passo, se quiserem) — o ramal de teste `5500` foi escolhido manualmente por estar fora da faixa já usada (`1000–1021`, `6001`, `9001`, `9090`).
- **Limpeza da tabela `ramais`**: a pedido do usuário, a tabela `ramais` inteira foi zerada (removidos os ramais de todos os condomínios, exceto o recriado do Jardim Botânico 03) para começar do zero. Confirmado que isso é seguro porque o Asterisk usa configuração 100% estática (arquivos `.conf`, sem realtime/ODBC) — nenhum registro/ligação ativa de outros condomínios foi afetado. Uma tentativa de backup de precaução (`mysqldump` para `/root/backups/`) falhou silenciamente antes do DELETE por causa de um caminho inexistente — **foi um erro de processo**: o delete não deveria ter rodado sem confirmar que o backup funcionou. Existe um dump completo anterior em `/root/azcall.sql` (23/07/2026) que permite restaurar os ramais de outros condomínios caso necessário no futuro.
- **`app_config` do condomínio 19 estava com `sip_servidor` e `painel_url_publica` em branco** — corrigido para apontar para `clienteauto.portcallvoip.com.br` (HTTPS confirmado funcionando).
