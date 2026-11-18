# Release do app nativo

Como uma versão vira um zip baixável no GitHub Releases. A regra de qual número
subir está em [VERSIONAMENTO.md](VERSIONAMENTO.md).

## Fluxo

1. Suba a versão e descreva a mudança no `CHANGELOG.md`
   ([VERSIONAMENTO.md](VERSIONAMENTO.md), seção "A cada subida").
2. Integre na `main` com o CI verde.
3. Crie e envie a tag anotada:

   ```bash
   python3 tools/version.py tag     # tag anotada vX.Y.Z no HEAD
   git push origin vX.Y.Z
   ```

4. O workflow [`release.yml`](../.github/workflows/release.yml) roda num runner
   `macos-26` (Apple Silicon; o binário sai só arm64):
   - confere que a tag é igual a `VERSION` e que as cópias batem;
   - roda a suíte do motor, os testes do gate de QA e os fluxos com aparelho
     falso;
   - empacota com `tools/package_macos_app.sh` em `$RUNNER_TEMP/dist`
     (`DEST_DIR`), o que roda `swift test` antes e assina ad-hoc;
   - gera `MoBaile-X.Y.Z-macOS.zip` com `ditto -c -k --keepParent` e o
     `.sha256` ao lado;
   - assina o zip com o secret `MOBAILE_UPDATE_SIGNING_KEY`, confere a
     assinatura contra as chaves embutidas no app e gera o `.sig` (seção
     "Atualização dentro do app", abaixo). Sem o secret, o release não sai;
   - cria o GitHub Release `vX.Y.Z` com a seção `## [X.Y.Z]` do CHANGELOG
     como notas, mais o aviso de app não notarizado.

Para testar o empacotamento sem publicar: aba *Actions* > *Release* >
*Run workflow*, com "publicar" desmarcado. O zip fica como artefato do
workflow por 14 dias.

O workflow tem `permissions: {}` no topo e `contents: write` só no job que cria
o Release. Ações fixadas por SHA.

## Empacotar localmente fora de /Applications

```bash
DEST_DIR="$PWD/dist" bash tools/package_macos_app.sh
```

O script monta o bundle num diretório temporário no mesmo volume do destino,
assina, roda `codesign --verify --deep --strict` e só então troca o app de
forma atômica (o anterior vira backup e é restaurado se algo falhar). Ele
recusa rodar com o app aberto e grava o commit em `MoBaileGitCommit` no
`Info.plist`. `make verify-native` confere esse commit contra o `HEAD`.

Variáveis aceitas:

| Variável | Padrão | Uso |
|---|---|---|
| `DEST_DIR` | `/Applications` | Onde o `.app` final fica |
| `APP_NAME` | `Mo baile (nativo)` | Nome do bundle. `Mo baile` exige confirmação digitada |
| `SIGN_IDENTITY` | `Mo baile Local`, se existir; senão `-` (ad-hoc) | Identidade do `codesign`. Outra que não essas duas liga hardened runtime e timestamp |

### Identidade local (máquina de desenvolvimento)

Com assinatura ad-hoc, a identidade do app muda a cada build e o macOS
esquece as permissões dadas a ele: a pasta Documentos voltava a ser pedida
depois de todo `make update-native`. Rode uma vez:

```bash
bash tools/create_local_signing_identity.sh
```

Ele cria o certificado autoassinado "Mo baile Local" no Keychain de login, só
para assinatura de código (o macOS pede a sua senha para confiar nele). Daí em
diante o empacotamento assina com ele sozinho, e o "Permitir" vale entre
builds. Não serve para distribuir: para isso, Developer ID (abaixo).

Desde a 3.10.0 o motor também sobe com `python3 -S` e não segue os `.pth` do
site-packages (`engine/src/mobaile/_site.py`): um `.pth` de instalação
editável com a pasta em `~/Documents` fazia o macOS pedir acesso a cada
abertura do app.

## Assinatura e notarização (ainda desligadas)

Hoje o app sai com assinatura **ad-hoc**. O Gatekeeper bloqueia na primeira
abertura em outra máquina; o README explica como abrir e o risco envolvido.

Para distribuir sem esse aviso é preciso uma conta Apple Developer (pessoa
física serve), um certificado **Developer ID Application** e notarização. Os
passos já estão no `release.yml`, comentados. Para ligar:

1. Crie os secrets no repositório (*Settings* > *Secrets and variables* >
   *Actions*):

   | Secret | Conteúdo |
   |---|---|
   | `MACOS_CERT_P12_BASE64` | Certificado Developer ID Application exportado como `.p12`, em base64 (`base64 -i cert.p12`) |
   | `MACOS_CERT_PASSWORD` | Senha do `.p12` |
   | `MACOS_KEYCHAIN_PASSWORD` | Senha aleatória para o keychain temporário do runner |
   | `MACOS_SIGNING_IDENTITY` | Nome da identidade, ex.: `Developer ID Application: Nome (TEAMID)` |
   | `APPLE_API_KEY_P8_BASE64` | Chave da App Store Connect API (`AuthKey_XXXX.p8`) em base64 |
   | `APPLE_API_KEY_ID` | ID da chave |
   | `APPLE_API_ISSUER_ID` | Issuer ID da conta |

2. No `release.yml`, descomente os passos "Importar certificado Developer ID"
   e "Notarizar e grampear", e a linha `SIGN_IDENTITY` do passo "Empacotar".
3. Rode o workflow manualmente sem publicar e confira o log do `spctl`.

A sintaxe de `notarytool`, `stapler` e `security` nos passos comentados não foi
executada neste repositório. Confira com `xcrun notarytool --help` antes de
ligar. O `codesign --deep` atual também deve virar assinatura de dentro para
fora quando houver binários aninhados.

## Atualização dentro do app

Desde a 3.26.0 o app se atualiza sozinho com dois cliques: **Atualizar** e
**Reiniciar e Atualizar** ([ADR 0008](adr/0008-atualizacao-no-lugar.md)). Ele
só instala um zip cuja assinatura Ed25519 bata com uma das chaves públicas de
[`UpdateSignature.swift`](../apps/MoBaile/Sources/MoBaile/App/UpdateSignature.swift).
A ferramenta é [`tools/update_signing.swift`](../tools/update_signing.swift),
que roda com o Swift do Xcode ou das Command Line Tools.

### Chave de assinatura

A chave atual foi gerada em 18/11/2026 e fica em `.privado/update-signing-key.b64`
(fora do git). Guarde uma cópia fora da máquina, por exemplo num gerenciador de
senhas. O release lê a chave do secret `MOBAILE_UPDATE_SIGNING_KEY`:

```bash
gh secret set MOBAILE_UPDATE_SIGNING_KEY -R francisco-efjr/mo-baile < .privado/update-signing-key.b64
```

Conferir que a chave guardada é a que o app aceita:

```bash
swift tools/update_signing.swift public-key --key-file .privado/update-signing-key.b64
```

A saída tem de estar na lista `publicKeys`.

**Trocar a chave** (perda ou vazamento):

1. Gere uma chave nova com `swift tools/update_signing.swift keygen <arquivo>`.
   O comando recusa sobrescrever uma chave que já existe.
2. Acrescente a chave pública nova a `publicKeys` e publique uma versão ainda
   assinada com a chave antiga, se ela não tiver vazado.
3. Troque o secret e publique a versão seguinte já com a chave nova.

Se a chave antiga se perdeu ou vazou, pule o passo 2. Nesse caso, quem está numa
versão anterior atualiza aquela versão à mão, uma vez.

### Testar a atualização sem publicar

1. Monte duas versões num diretório temporário. A versão nova pode ser uma
   cópia da antiga com `CFBundleShortVersionString` maior no `Info.plist` e
   assinada de novo com `codesign --force --deep --sign -`.
2. Gere o zip com `ditto -c -k --keepParent` e assine com `sign --key-file`.
3. Sirva a pasta em loopback, por exemplo com `python3 -m http.server --bind 127.0.0.1 8765`.
   Ponha nela um `latest.json` no formato da API de releases (`tag_name`,
   `html_url`, `assets[].name` e `browser_download_url`).
4. Abra o app antigo com `MOBAILE_UPDATE_URL=http://127.0.0.1:8765/latest.json`.
   O release falso fica guardado à parte (`mobaile.update.lastFeed`) e não
   aparece no app de uso diário.

Para não precisar clicar, um build de depuração (`swift build`) aceita
`MOBAILE_UPDATE_AUTOINSTALL=1`, ou a chave `mobaile.update.debugAutoInstall`
em UserDefaults. Com ela, o app baixa e reinicia sozinho. O app distribuído é
compilado em release e não tem esse atalho.

## Conferir um zip baixado

```bash
shasum -a 256 -c MoBaile-X.Y.Z-macOS.zip.sha256
```

A autenticidade, que o `.sha256` não garante, vem do `.sig`:

```bash
swift tools/update_signing.swift verify MoBaile-X.Y.Z-macOS.zip MoBaile-X.Y.Z-macOS.zip.sig \
  --app-keys apps/MoBaile/Sources/MoBaile/App/UpdateSignature.swift
```
