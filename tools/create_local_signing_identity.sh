#!/usr/bin/env bash
#
# Cria, uma vez só, a identidade de assinatura local "Mo baile Local".
#
# Por que existe: com assinatura ad-hoc, a identidade do app muda a cada
# build, e o macOS esquece as permissões dadas a ele (pasta Documentos,
# gravação de tela, rede local). Com um certificado próprio, a identidade fica
# a mesma entre builds: o "Permitir" dado uma vez continua valendo depois de
# cada `make update-native`.
#
# O que faz:
#   1. gera uma chave e um certificado autoassinado só para assinar código
#      (validade de 10 anos), numa pasta temporária;
#   2. importa os dois no Keychain de login, liberando só o `codesign`;
#   3. marca o certificado como confiável para assinatura de código. O macOS
#      pede a sua senha nesse passo.
#
# Depois disso, `tools/package_macos_app.sh` acha a identidade sozinho. Nada
# sai da máquina, e o certificado não serve para distribuir o app para outras
# pessoas (para isso, Developer ID: docs/RELEASE.md).
#
# Para desfazer: Acesso às Chaves > login > Meus Certificados > "Mo baile
# Local" > Apagar.
set -euo pipefail

NOME="Mo baile Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NOME\""; then
    echo "A identidade \"$NOME\" já existe e é válida. Nada a fazer."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Gerando o certificado \"$NOME\""
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -sha256 \
    -subj "/CN=$NOME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -keyout "$TMP/chave.pem" -out "$TMP/cert.pem" 2>/dev/null

# Senha só para o transporte do .p12 até o Keychain; o arquivo some no fim.
SENHA="$(openssl rand -hex 16)"
openssl pkcs12 -export -inkey "$TMP/chave.pem" -in "$TMP/cert.pem" -name "$NOME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -passout "pass:$SENHA" -out "$TMP/identidade.p12"

echo "==> Importando no Keychain de login (só o codesign pode usar a chave)"
security import "$TMP/identidade.p12" -k "$KEYCHAIN" -P "$SENHA" -T /usr/bin/codesign >/dev/null

echo "==> Confiando no certificado para assinatura de código (o macOS pede a sua senha)"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NOME\""; then
    echo "OK: identidade \"$NOME\" pronta. Rode make update-native para assinar o app com ela."
else
    echo "A identidade foi importada, mas o macOS não a lista como válida para assinar." >&2
    echo "Confira em Acesso às Chaves se \"$NOME\" está como confiável para Assinatura de Código." >&2
    exit 1
fi
