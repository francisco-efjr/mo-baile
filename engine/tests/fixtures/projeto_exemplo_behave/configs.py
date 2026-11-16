"""Capabilities de cada ambiente. Valores sensiveis aqui sao FALSOS.

As chaves `*:accessKey`, `senha_*` e a credencial na URL da Kobiton existem
so para provar que o Mo baile mostra o nome da chave e nunca o valor.
"""

APPIUM_LOCAL = "http://127.0.0.1:4723"

config_android_local_HLG = {
    "url": APPIUM_LOCAL,
    "platformName": "Android",
    "appium:automationName": "UiAutomator2",
    "appium:udid": "emulator-5554",
    "appium:deviceName": "Pixel 7 (emulador)",
    "appium:platformVersion": "14",
    "appium:appPackage": "br.com.exemplo.hlg",
    "appium:appActivity": ".MainActivity",
    "appium:noReset": True,
    "appium:newCommandTimeout": 300,
    "senha_usuario_teste": "FAKE-SENHA-1234",
}

config_ios_local_HLG = {
    "url": "http://localhost:4723",
    "platformName": "iOS",
    "appium:automationName": "XCUITest",
    "appium:udid": "00000000-0000-0000-0000-000000000000",
    "appium:deviceName": "iPhone 16",
    "appium:platformVersion": "18.0",
    "appium:bundleId": "br.com.exemplo.hlg",
    "appium:app": "builds/Exemplo-HLG.app",
}

config_kobiton_android_HLG = {
    "url": "https://usuario-falso:FAKE-KEY-0000@api.kobiton.com/wd/hub",
    "platformName": "Android",
    "appium:deviceName": "Galaxy S23",
    "appium:platformVersion": "14",
    "kobiton:username": "usuario-falso",
    "kobiton:accessKey": "FAKE-KEY-0000",
    "kobiton:sessionName": "HLG Android",
    "appium:app": "kobiton-store:000000",
}

config_kobiton_ios_HLG = {
    "url": "https://usuario-falso:FAKE-KEY-0000@api.kobiton.com/wd/hub",
    "platformName": "iOS",
    "appium:deviceName": "iPhone 15",
    "kobiton:accessKey": "FAKE-KEY-0000",
    "appium:bundleId": "br.com.exemplo.hlg",
}
