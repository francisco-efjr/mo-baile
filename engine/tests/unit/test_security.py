"""Regressao das falhas encontradas na auditoria.

Cada teste aqui corresponde a um vetor concreto que existia no codigo antes da
reorganizacao. Se algum voltar a passar como "aceito", a falha voltou.
"""

import os
import stat
import unittest

from mobaile.domain.errors import InvalidInputError
from mobaile.security import (
    MAX_INPUT_TEXT,
    build_adb_input_text_args,
    parse_untrusted_xml,
    quote_for_device_shell,
    redact_body,
    redact_headers,
    secure_runtime_dir,
    validate_coordinate,
    validate_device_id,
    validate_keycode,
    validate_port,
    write_executable_script,
)


class TestValidacaoDeSerial(unittest.TestCase):
    """O serial vem de `adb devices` e de `adb connect`: e entrada externa."""

    def test_aceita_formatos_reais(self):
        for valido in ("emulator-5554", "R58N12ABCDE", "192.168.0.10:5555",
                       "00008030-001A2C3D4E5F6G7H", "ce0417a1b2c3d4e5"):
            with self.subTest(serial=valido):
                self.assertEqual(validate_device_id(valido), valido)

    def test_recusa_metacaracteres_e_quebras(self):
        for invalido in (
            "emulator-5554; rm -rf /",
            'emulator-5554"; import os',
            "emulator\n5554",
            "../../etc/passwd",
            "$(id)",
            "`id`",
            "",
            "a" * 200,
        ):
            with self.subTest(serial=invalido), self.assertRaises(InvalidInputError):
                validate_device_id(invalido)


class TestEscapingDeEntradaNoDispositivo(unittest.TestCase):
    """`adb shell input text` roda no sh do aparelho: quoting nao e opcional."""

    def test_texto_vira_argumento_unico_com_aspas_simples(self):
        args = build_adb_input_text_args("ola mundo")
        self.assertEqual(args[0], "shell")
        self.assertEqual(len(args), 2, "o comando remoto precisa ir como string unica")
        self.assertEqual(args[1], "input text 'ola%smundo'")

    def test_metacaracteres_ficam_dentro_das_aspas(self):
        for payload in ("a; rm -rf /", "$(id)", "`id`", "a && reboot", "a | nc host 1234", "a > /sdcard/x"):
            with self.subTest(payload=payload):
                comando = build_adb_input_text_args(payload)[1]
                corpo = comando[len("input text "):]
                self.assertTrue(corpo.startswith("'") and corpo.endswith("'"))
                # Nenhuma aspa simples solta no meio: seria fuga do quoting.
                self.assertNotIn("'", corpo[1:-1].replace("'\\''", ""))

    def test_aspa_simples_e_escapada_corretamente(self):
        self.assertEqual(quote_for_device_shell("it's"), "'it'\\''s'")

    def test_texto_gigante_e_recusado(self):
        with self.assertRaises(InvalidInputError):
            build_adb_input_text_args("a" * (MAX_INPUT_TEXT + 1))

    def test_caractere_de_controle_e_recusado(self):
        with self.assertRaises(InvalidInputError):
            build_adb_input_text_args("linha1\nlinha2")


class TestValidacaoNumerica(unittest.TestCase):
    def test_coordenadas(self):
        self.assertEqual(validate_coordinate(10), 10)
        self.assertEqual(validate_coordinate(10.7), 10)
        for invalida in (-1, 999999, "10", None, True):
            with self.subTest(valor=invalida), self.assertRaises(InvalidInputError):
                validate_coordinate(invalida)

    def test_keycode_e_porta(self):
        self.assertEqual(validate_keycode(224), 224)
        self.assertEqual(validate_port(8082), 8082)
        for invalido in (-1, 70000, "8082", None, True):
            with self.subTest(valor=invalido), self.assertRaises(InvalidInputError):
                validate_port(invalido)


class TestParsingDeXML(unittest.TestCase):
    """A hierarquia vem do app sob teste: XML de origem nao confiavel."""

    BILLION_LAUGHS = (
        '<?xml version="1.0"?><!DOCTYPE lolz [<!ENTITY lol "lol">'
        '<!ENTITY lol2 "&lol;&lol;&lol;&lol;">]><hierarchy>&lol2;</hierarchy>'
    )
    XXE = (
        '<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>'
        "<hierarchy>&xxe;</hierarchy>"
    )

    def test_doctype_e_recusado(self):
        for nome, doc in (("billion laughs", self.BILLION_LAUGHS), ("xxe", self.XXE)):
            with self.subTest(vetor=nome), self.assertRaises(InvalidInputError):
                parse_untrusted_xml(doc)

    def test_hierarquia_normal_continua_funcionando(self):
        root = parse_untrusted_xml('<hierarchy rotation="0"><node text="Continuar"/></hierarchy>')
        self.assertEqual(root.tag, "hierarchy")
        self.assertEqual(root[0].attrib["text"], "Continuar")

    def test_xml_malformado_devolve_none_sem_excecao(self):
        self.assertIsNone(parse_untrusted_xml("<a><b>"))
        self.assertIsNone(parse_untrusted_xml(""))


class TestRedacao(unittest.TestCase):
    def test_headers_de_credencial(self):
        redigidos = redact_headers({
            "Authorization": "Bearer token-do-cliente",
            "Cookie": "session=abc",
            "Accept": "application/json",
        })
        self.assertNotIn("token-do-cliente", redigidos["Authorization"])
        self.assertNotIn("session=abc", redigidos["Cookie"])
        self.assertEqual(redigidos["Accept"], "application/json", "header inocente nao muda")

    def test_campos_sensiveis_no_corpo(self):
        saida = redact_body('{"user":"bella","password":"1234","cpf":"000.000.000-00","total":42}')
        self.assertNotIn("1234", saida)
        self.assertNotIn("000.000.000-00", saida)
        self.assertIn('"user":"bella"', saida, "campo inocente preservado")
        self.assertIn('"total":42', saida)

    def test_corpo_nao_json_passa_intacto(self):
        self.assertEqual(redact_body("texto solto"), "texto solto")


class TestArtefatoExecutavel(unittest.TestCase):
    def test_diretorio_e_arquivo_com_permissao_restrita(self):
        caminho = write_executable_script("print('ok')", filename="teste_permissao.py")
        try:
            self.assertEqual(stat.S_IMODE(os.stat(caminho).st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(os.stat(secure_runtime_dir()).st_mode), 0o700)
            self.assertNotIn(os.getcwd(), str(caminho), "artefato nao vai para a raiz do projeto")
        finally:
            os.unlink(caminho)


if __name__ == "__main__":
    unittest.main()
