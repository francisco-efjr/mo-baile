"""Validação e escaping de tudo que vira comando.

Contexto do risco: `adb -s <serial> shell input text <txt>` NÃO é seguro só por
usar lista de argumentos. O `adb` concatena os argumentos depois de `shell` e
entrega a string ao `sh` do aparelho. Ou seja, `;`, `&`, `$()` e afins são
interpretados no dispositivo. Quem protege é o quoting feito aqui.

O serial também é entrada externa: vem de `adb devices`, e um alvo conectado por
TCP tem o endereço escolhido por quem conecta. Ele entra em nomes de arquivo e
em código gerado, então passa por allowlist.
"""

from __future__ import annotations

import re

from mobaile.domain.errors import InvalidInputError

# Serial ADB (emulator-5554, R58N12ABCDE, 192.168.0.10:5555) ou UDID iOS.
_DEVICE_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$")

# Limite defensivo: `input text` não foi feito para payloads grandes.
MAX_INPUT_TEXT = 1024

# Faixa válida de keycodes Android.
_MAX_KEYCODE = 1000

# Coordenadas fora disso não existem em nenhuma tela real.
_MAX_COORD = 20_000


def validate_device_id(device_id: str) -> str:
    """Aceita apenas seriais/UDIDs com formato conhecido. Levanta em vez de sanitizar."""
    if not isinstance(device_id, str) or not device_id:
        raise InvalidInputError("Identificador de dispositivo vazio.")
    if not _DEVICE_ID_RE.match(device_id):
        raise InvalidInputError(
            "Identificador de dispositivo inválido.",
            detail=f"Recebido: {device_id!r}",
        )
    return device_id


def validate_coordinate(value: object, axis: str = "x") -> int:
    """Coordenada de toque: precisa ser inteiro finito dentro de uma tela plausível."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise InvalidInputError(f"Coordenada {axis} inválida: {value!r}")
    coord = int(value)
    if coord < 0 or coord > _MAX_COORD:
        raise InvalidInputError(f"Coordenada {axis} fora da faixa: {coord}")
    return coord


def validate_keycode(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidInputError(f"Keycode inválido: {value!r}")
    if value < 0 or value > _MAX_KEYCODE:
        raise InvalidInputError(f"Keycode fora da faixa: {value}")
    return value


def validate_port(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidInputError(f"Porta inválida: {value!r}")
    if not (1 <= value <= 65535):
        raise InvalidInputError(f"Porta fora da faixa: {value}")
    return value


def quote_for_device_shell(raw: str) -> str:
    """Envolve o texto em aspas simples para o `sh` do dispositivo.

    A aspa simples é a única forma de quoting em que o shell POSIX não
    interpreta nada no interior. Para incluir uma aspa simples literal,
    fecha-se a string, escapa-se a aspa e abre-se de novo: `'\\''`.
    """
    return "'" + raw.replace("'", "'\\''") + "'"


def build_adb_input_text_args(text: str) -> list[str]:
    """Monta os argumentos de `adb shell` para digitar `text` com segurança.

    Duas camadas:
      1. `input text` interpreta `%s` como espaço, então espaços viram `%s`.
      2. O resultado é passado como *um* argumento com aspas simples, de modo
         que o shell do aparelho não veja metacaracteres.

    Retorna a lista a ser concatenada após o `-s <serial>` — repare que o
    comando remoto vai como string única, e não como argumentos soltos, que é
    justamente o que impede a concatenação insegura feita pelo adb.
    """
    if not isinstance(text, str):
        raise InvalidInputError("Texto de entrada deve ser string.")
    if len(text) > MAX_INPUT_TEXT:
        raise InvalidInputError(
            f"Texto excede o limite de {MAX_INPUT_TEXT} caracteres.",
            detail=f"Tamanho recebido: {len(text)}",
        )
    if any(ord(ch) < 32 and ch not in "\t" for ch in text):
        raise InvalidInputError("Texto contém caracteres de controle não imprimíveis.")

    encoded = text.replace(" ", "%s")
    return ["shell", f"input text {quote_for_device_shell(encoded)}"]
