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
   `macos-latest`:
   - confere que a tag é igual a `VERSION` e que as cópias batem;
   - roda a suíte do motor, os testes do gate de QA e os fluxos com aparelho
     falso;
   - empacota com `tools/package_macos_app.sh` em `$RUNNER_TEMP/dist`
     (`DEST_DIR`), o que roda `swift test` antes e assina ad-hoc;
   - gera `MoBaile-X.Y.Z-macOS.zip` com `ditto -c -k --keepParent` e o
     `.sha256` ao lado;
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
| `SIGN_IDENTITY` | `-` (ad-hoc) | Identidade do `codesign`. Diferente de `-` liga hardened runtime e timestamp |

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

## Conferir um zip baixado

```bash
shasum -a 256 -c MoBaile-X.Y.Z-macOS.zip.sha256
```
