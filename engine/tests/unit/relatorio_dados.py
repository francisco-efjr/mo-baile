"""Cenário sintético da aba Relatório, compartilhado pelos testes.

Veio dos testes do `tag_audit`: uma spec com dois fluxos (CPA e CPAGI) e um log
misto Android + iOS com cada armadilha que o casamento precisa tratar
(duplicado, mesma ação em outra tela, `screen_name` errado na tela certa,
disparo antigo divergente, evento fora da spec e alerta). Dados inventados:
nenhum log real de cliente entra no repositório.
"""

from __future__ import annotations

import json
from pathlib import Path


def android(time, name, bundle, id_=0):
    raw = f"10-08 {time} V/FA-SVC  (1): Logging event: origin=app,name={name},params=Bundle[{{{bundle}}}]"
    # `params` quebrado de propósito: no Android vale o que está no raw_log.
    return {"id": id_, "event_name": name, "params": {"quebrado": "sim"}, "platform": "android",
            "raw_log": raw, "tag": "FA-SVC", "time_str": time}


def ios(time, name, params):
    return {"id": 99, "event_name": name, "params": params, "platform": "ios",
            "raw_log": "[FirebaseAnalytics][I-ACS023073] ...", "tag": "iOS (Firebase)", "time_str": time}


SPEC = {
    "projeto": "Teste",
    "plataforma": "android",
    "fluxos": {"pessoal": "CPA · credito-pessoal", "investimentos": "CPAGI · credito-investimentos"},
    "cards": [
        {"secao": "Home", "evento": "screen_view",
         "params": {"screen_name": "app:credito:home", "flow_name": "credito"}},
        {"secao": "Simulação", "evento": "interaction_credito_{fluxo}",
         "params": {"screen_name": "app:credito:{fluxo}:simulacao", "flow_name": "credito-{fluxo}",
                    "component": "button"},
         "variacoes": [{"detail": "click:parcelas"}, {"detail": "click:[numero]-parcela-sem-seguro"}]},
        {"secao": "Simulação", "evento": "add_to_cart",
         "params": {"screen_name": "app:credito:{fluxo}:simulacao", "flow_name": "credito-{fluxo}",
                    "insurance": "[0|1]", "value": "[numero]",
                    "items": [{"item_id": "[preenchido]", "item_name": "credito-{fluxo}"}]},
         "params_por_fluxo": {"pessoal": {"items": [{"item_id": "14063"}]}}},
    ],
}

LOG = [
    android("10:00:00.000", "screen_view(_vs)",
            "flow_name=credito, ga_event_origin(_o)=app, ga_screen(_sn)=app:credito:home"),
    android("10:00:00.000", "screen_view(_vs)",
            "flow_name=credito, ga_event_origin(_o)=app, ga_screen(_sn)=app:credito:home"),  # duplicado
    ios("10:00:01.000", "screen_view", {"ga_screen": "app:credito:home", "flow_name": "credito"}),
    android("10:01:00.000", "interaction_credito_pessoal",
            "screen_name=app:credito:pessoal:simulacao, flow_name=credito-pessoal, component=button, "
            "detail=click:parcelas, ga_screen(_sn)=app:credito:pessoal:simulacao"),
    # mesmo detail em outra tela, mais recente: não pode roubar o match da tela certa
    android("10:01:30.000", "interaction_credito_pessoal",
            "screen_name=app:credito:pessoal:detalhes-da-proposta, flow_name=credito-pessoal, component=button, "
            "detail=click:parcelas"),
    # investimentos: add_to_cart na simulação (ga_screen) com screen_name errado -> erro de screen_name
    android("10:01:45.000", "add_to_cart",
            "screen_name=app:credito:investimentos:parcelas, flow_name=credito-investimentos, insurance=1, "
            "value=1, items=[Bundle[{item_name=credito-investimentos, item_id=14019}]], "
            "ga_screen(_sn)=app:credito:investimentos:simulacao"),
    # mesmo evento e fluxo numa tela fora da spec: não é a variação -> "fora da spec"
    android("10:01:50.000", "screen_view(_vs)",
            "flow_name=credito, ga_event_origin(_o)=app, ga_screen(_sn)=app:credito:outra-tela"),
    # investimentos: clique com component errado
    android("10:02:00.000", "interaction_credito_investimentos",
            "screen_name=app:credito:investimentos:simulacao, flow_name=credito-investimentos, component=toggle, "
            "detail=click:parcelas"),
    # pessoal: build antigo com item_name errado, depois o correto
    android("10:03:00.000", "add_to_cart",
            "screen_name=app:credito:pessoal:simulacao, flow_name=credito-pessoal, insurance=1, value=100.0, "
            "items=[Bundle[{item_name=credito-errado, item_id=14063}]]"),
    android("10:04:00.000", "add_to_cart",
            "screen_name=app:credito:pessoal:simulacao, flow_name=credito-pessoal, insurance=0, value=200.5, "
            "items=[Bundle[{item_name=credito-pessoal, item_category=simulacao, item_id=14063}]]"),
    # fora da spec + alerta
    android("10:05:00.000", "modal_view",
            "screen_name=app:credito:pessoal:simulacao, flow_name=credito-pessoal, component=modal, detail=calendario"),
    android("10:06:00.000", "app_exception(_ae)", "ga_screen(_sn)=app:credito:pessoal:simulacao, fatal=1"),
]

# Totais esperados do cenário: 7 validações, 3 OK, 2 divergentes e 2 não disparadas.
TOTAL, OK, DIVERGENTES, AUSENTES = 7, 3, 2, 2


def gravar(pasta: Path, spec: dict | None = None, log: list | None = None) -> tuple[Path, Path]:
    """Grava spec e log numa pasta e devolve os dois caminhos."""
    spec_path = pasta / "spec.json"
    log_path = pasta / "log.json"
    spec_path.write_text(json.dumps(spec if spec is not None else SPEC, ensure_ascii=False), encoding="utf-8")
    log_path.write_text(json.dumps(log if log is not None else LOG, ensure_ascii=False), encoding="utf-8")
    return spec_path, log_path
