"""Camada de segurança: valida antes de executar, redige antes de guardar.

Regra: nenhum adapter monta comando, caminho ou payload com string vinda de
fora sem passar por aqui primeiro.
"""

from mobaile.security.files import (
    IMAGE_SUFFIXES,
    MAX_LOG_BYTES,
    MAX_SPEC_BYTES,
    prepare_output_dir,
    safe_file_stem,
    unique_path,
    validate_input_dir,
    validate_input_file,
)
from mobaile.security.paths import secure_runtime_dir, write_executable_script
from mobaile.security.redaction import redact_body, redact_headers, redact_url
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
    "IMAGE_SUFFIXES",
    "MAX_INPUT_TEXT",
    "MAX_LOG_BYTES",
    "MAX_SPEC_BYTES",
    "MAX_XML_BYTES",
    "build_adb_input_text_args",
    "parse_untrusted_xml",
    "prepare_output_dir",
    "quote_for_device_shell",
    "redact_body",
    "redact_headers",
    "redact_url",
    "safe_file_stem",
    "secure_runtime_dir",
    "unique_path",
    "validate_coordinate",
    "validate_device_id",
    "validate_input_dir",
    "validate_input_file",
    "validate_keycode",
    "validate_port",
    "write_executable_script",
]
