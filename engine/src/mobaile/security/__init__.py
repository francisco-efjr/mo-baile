"""Camada de segurança: valida antes de executar, redige antes de guardar.

Regra: nenhum adapter monta comando, caminho ou payload com string vinda de
fora sem passar por aqui primeiro.
"""

from mobaile.security.paths import secure_runtime_dir, write_executable_script
from mobaile.security.redaction import redact_body, redact_headers
from mobaile.security.shell import (
    MAX_INPUT_TEXT,
    build_adb_input_text_args,
    quote_for_device_shell,
    validate_coordinate,
    validate_device_id,
    validate_keycode,
    validate_port,
)
from mobaile.security.xml_safe import MAX_XML_BYTES, parse_untrusted_xml

__all__ = [
    "MAX_INPUT_TEXT",
    "MAX_XML_BYTES",
    "build_adb_input_text_args",
    "parse_untrusted_xml",
    "quote_for_device_shell",
    "redact_body",
    "redact_headers",
    "secure_runtime_dir",
    "validate_coordinate",
    "validate_device_id",
    "validate_keycode",
    "validate_port",
    "write_executable_script",
]
