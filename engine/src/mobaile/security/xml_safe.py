"""Parsing de XML vindo do dispositivo.

`uiautomator dump` e o `/source` do WebDriverAgent devolvem XML gerado pelo app
sob teste — conteúdo que o time de automação não controla. O parser padrão do
ElementTree aceita DOCTYPE e definições de entidade, o que abre espaço para
expansão exponencial (billion laughs) e para leitura de arquivo local por
entidade externa.

A correção não exige dependência nova: o expat da biblioteca padrão permite
recusar DOCTYPE e entidades diretamente, e a árvore é montada com o
`TreeBuilder` do próprio ElementTree, de modo que o resto do código continua
recebendo `Element` como sempre.
"""

from __future__ import annotations

import xml.etree.ElementTree as ET
from xml.parsers import expat

from mobaile.domain.errors import InvalidInputError

# Um dump de hierarquia real fica na casa de centenas de KB.
MAX_XML_BYTES = 16 * 1024 * 1024


def _reject_doctype(*_args, **_kwargs):
    raise InvalidInputError("XML com DOCTYPE recusado pelo parser seguro.")


def _reject_entity(*_args, **_kwargs):
    raise InvalidInputError("XML com definição de entidade recusado.")


def _build_parser(builder: ET.TreeBuilder) -> expat.XMLParserType:
    parser = expat.ParserCreate()
    # Agrupa texto em menos callbacks — hierarquias grandes ficam bem mais rápidas.
    parser.buffer_text = True
    parser.StartElementHandler = lambda tag, attrs: builder.start(tag, attrs)
    parser.EndElementHandler = builder.end
    parser.CharacterDataHandler = builder.data
    # As três defesas:
    parser.StartDoctypeDeclHandler = _reject_doctype
    parser.EntityDeclHandler = _reject_entity
    parser.ExternalEntityRefHandler = lambda *_args: False
    return parser


def parse_untrusted_xml(xml_content: str) -> ET.Element | None:
    """Faz o parse com as proteções ligadas.

    Devolve `None` quando o XML é apenas inválido — hierarquia malformada é
    rotina em app instrumentado e não merece exceção. Já DOCTYPE e entidade são
    recusa explícita: isso é tentativa de abuso, não ruído.
    """
    if not xml_content:
        return None

    payload = xml_content.encode("utf-8", errors="replace")
    if len(payload) > MAX_XML_BYTES:
        raise InvalidInputError(
            "Hierarquia XML acima do limite suportado.",
            detail=f"Limite: {MAX_XML_BYTES} bytes",
        )

    builder = ET.TreeBuilder()
    parser = _build_parser(builder)
    try:
        parser.Parse(payload, True)
        return builder.close()
    except expat.ExpatError:
        return None
