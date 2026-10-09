"""Dados de OCR sintéticos dos cards do Figma, com os ruídos vistos nos prints reais.

Veio dos testes do `tag_audit`: ícone lido como "5", alternância sem "|", chave
quebrada em duas linhas, "[0/1]", "clickifechar" e itens com vírgula no lugar
de ponto.
"""

from mobaile.domain.report import OcrLine


def linha(text, x, y, c=1.0):
    return OcrLine(t=text, x=x, y=y, w=0.3, h=0.03, c=c)


# Card por fluxo, com ícone lido como "5", alternância sem "|", chave quebrada e Observação
CARD_INTERACTION = [
    linha("Anotações", 0.02, 0.0),
    linha("5 interaction_credito_[pessoal |investimentos]", 0.04, 0.03),
    linha("screen name", 0.04, 0.10), linha("app:credito:[pessoal|", 0.42, 0.10), linha("investimentos]:simulacao", 0.42, 0.13),
    linha("flow_name", 0.04, 0.20), linha("credito-[pessoal investimentos]", 0.42, 0.20),
    linha("component", 0.04, 0.27), linha("[elemento]", 0.42, 0.27),
    linha("detail", 0.04, 0.33), linha("click:[numero de parcelas]-parcela-", 0.42, 0.33), linha("[com |sem]-seguro", 0.42, 0.36),
    linha("interactio", 0.85, 0.30),
    linha('Observação "interaction_credito_[pessoal| investimentos]"', 0.04, 0.42),
    linha("O evento interaction_credito_[pessoal|investimentos] deve disparar", 0.04, 0.49),
    linha("Preenchimento de [elemento] no parâmetro component:", 0.04, 0.63),
    linha("• modal", 0.06, 0.67),
    linha("Preenchimento de [label do botao] no", 0.04, 0.79), linha("parâmetro detail:", 0.04, 0.82),
    linha("• click:10-parcela-com-seguro", 0.06, 0.86), linha("• clickifechar", 0.06, 0.90),
]

# Card de e-commerce com chave quebrada em 2 linhas, [0/1], placeholders descritivos e items com ruído
CARD_CHECKOUT = [
    linha("add_to cart", 0.04, 0.03, 0.3),
    linha("screen_name", 0.04, 0.09), linha("app:credito:[pessoal|", 0.42, 0.09), linha("investimentos]:simulacao", 0.42, 0.11),
    linha("flow_name", 0.04, 0.17), linha("credito-[pessoal | investimentos]", 0.42, 0.17),
    linha("installments", 0.04, 0.22), linha("[número de parcelas]", 0.42, 0.22),
    linha("items", 0.04, 0.27),
    linha('"item_id": "14063",', 0.45, 0.30), linha('"item_name": "credito-pessoal",', 0.45, 0.32),
    linha('"item_category": "Simulacao"', 0.45, 0.34), linha("}", 0.44, 0.36),
    linha("due_date", 0.04, 0.42), linha("[data primeiro vencimento]", 0.42, 0.42),
    linha("insurance", 0.04, 0.48), linha("[0/1]", 0.41, 0.48),
    linha("loan_insurance_va", 0.04, 0.54), linha("[valor do seguro]", 0.42, 0.54), linha("lue", 0.04, 0.57),
    linha("operation_type", 0.04, 0.62), linha("[pessoal| investimentos]-pre-", 0.41, 0.62), linha("aprovado", 0.42, 0.65),
]

# Card sem fluxo, com vários itens exemplo
CARD_LIST = [
    linha("view item_list", 0.04, 0.02, 0.3),
    linha("screen_name", 0.04, 0.08), linha("app:credito:antecipacao-de-", 0.41, 0.08), linha("producao", 0.41, 0.10),
    linha("item_list_name", 0.03, 0.19), linha("agenda-financeira", 0.41, 0.20),
    linha("items", 0.03, 0.35),
    linha('"item_name": "recebivel-1",', 0.46, 0.40), linha('"item_id": "card-1".', 0.46, 0.42),
    linha('"price": [valor liquido]', 0.46, 0.52),
    linha('"item_name": "recebivel-2".', 0.46, 0.59), linha("'item_id\": \"card-2", 0.46, 0.62),
    linha('"price": [valor liquido]', 0.46, 0.72),
]
