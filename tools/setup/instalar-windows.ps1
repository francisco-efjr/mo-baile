# Instala o Mo baile num PC com Windows 10 ou 11: interface Tkinter e Android.
#
#   powershell -ExecutionPolicy Bypass -File tools\setup\instalar-windows.ps1 [alvo ...]
#
# Alvos:
#   python     Python 3.12 (winget) e o Python do Mo baile, com o motor e a interface
#   android    Android Platform Tools (adb), pelo winget
#   scrcpy     espelho Android a 60 quadros, pelo winget (opcional)
#   tudo       python, android e scrcpy (o padrão, sem alvo)
#   verificar  só mostra o que está pronto e o que falta
#
# Rode de dentro da pasta do código-fonte (git clone ou o zip "Source code" da
# página de Releases). O app nativo é SwiftUI e só existe para macOS; no Windows
# a interface é a Tkinter (apps/tk-legacy), congelada (ADR 0005), e só o
# Android funciona: o iOS precisa de um Mac. Veja docs/INSTALACAO.md.
#
# Precisa de internet só agora. Depois, tudo roda nesta máquina, offline.
# NÃO TESTADO EM WINDOWS de verdade até a 4.0.0: veja as pendências em
# docs/INSTALACAO.md antes de distribuir.

param([Parameter(ValueFromRemainingArguments = $true)] [string[]] $Alvos)

$ErrorActionPreference = 'Stop'
$Raiz = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$AppVenv = Join-Path $env:LOCALAPPDATA 'MoBaile\python'
$PythonDoApp = Join-Path $AppVenv 'Scripts\python.exe'

function Titulo($texto) { Write-Host ''; Write-Host $texto -ForegroundColor Cyan }
function Rodar([string] $exe, [string[]] $argumentos) {
    Write-Host "  > $exe $($argumentos -join ' ')"
    & $exe @argumentos
    if ($LASTEXITCODE -ne 0) { throw "$exe terminou com código $LASTEXITCODE." }
}
function Tem($comando) { [bool](Get-Command $comando -ErrorAction SilentlyContinue) }

function Garantir-Winget {
    if (-not (Tem 'winget')) {
        throw 'O winget não foi encontrado. Instale o "Instalador de Aplicativo" pela Microsoft Store e rode de novo.'
    }
}

# O PATH muda depois de um winget install; relê sem abrir outro terminal.
function Reler-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

function Python-Base {
    foreach ($candidato in @('py', 'python')) {
        if (Tem $candidato) {
            $versao = & $candidato -c 'import sys; print(1 if sys.version_info >= (3, 10) else 0)' 2>$null
            if ($versao -eq '1') { return $candidato }
        }
    }
    return $null
}

function Alvo-Python {
    Titulo 'Python do Mo baile'
    $base = Python-Base
    if (-not $base) {
        Garantir-Winget
        Rodar 'winget' @('install', '--id', 'Python.Python.3.12', '-e', '--accept-source-agreements', '--accept-package-agreements')
        Reler-Path
        $base = Python-Base
        if (-not $base) { throw 'O Python 3.12 não apareceu no PATH. Abra outro PowerShell e rode de novo.' }
    }
    if (-not (Test-Path $PythonDoApp)) {
        New-Item -ItemType Directory -Force -Path (Split-Path $AppVenv) | Out-Null
        Rodar $base @('-m', 'venv', $AppVenv)
    }
    Rodar $PythonDoApp @('-m', 'pip', 'install', '--quiet', '--upgrade', 'pip')
    # Motor e interface Tkinter, do próprio código-fonte. O Tkinter vem com o
    # Python do python.org (o do winget).
    Rodar $PythonDoApp @('-m', 'pip', 'install', '--quiet', (Join-Path $Raiz 'engine'), (Join-Path $Raiz 'apps\tk-legacy'))

    $atalho = Join-Path $Raiz 'Mo baile.cmd'
    Set-Content -Encoding ASCII -Path $atalho -Value "@echo off`r`n`"$PythonDoApp`" -m mobaile_tk.main_window %*"
    Write-Host "  Para abrir: $atalho"
}

function Alvo-Android {
    Titulo 'Android Platform Tools (adb)'
    if (Tem 'adb') { Write-Host "  Já instalado: $((Get-Command adb).Source)"; return }
    Garantir-Winget
    Rodar 'winget' @('install', '--id', 'Google.PlatformTools', '-e', '--accept-source-agreements', '--accept-package-agreements')
    Reler-Path
    Write-Host '  No aparelho: ative Opções do desenvolvedor > Depuração USB.'
    Write-Host '  O Windows precisa do driver USB do fabricante, ou do Google USB Driver'
    Write-Host '  (https://developer.android.com/studio/run/win-usb), para o adb ver o aparelho.'
}

function Alvo-Scrcpy {
    Titulo 'scrcpy'
    if (Tem 'scrcpy') { Write-Host "  Já instalado: $((Get-Command scrcpy).Source)"; return }
    Garantir-Winget
    Rodar 'winget' @('install', '--id', 'Genymobile.scrcpy', '-e', '--accept-source-agreements', '--accept-package-agreements')
    Reler-Path
}

function Alvo-Verificar {
    Titulo 'O que está pronto'
    if (-not (Test-Path $PythonDoApp)) { Write-Host '  O Python do Mo baile ainda não foi criado (alvo python).'; return }
    $env:PYTHONPATH = Join-Path $Raiz 'engine\src'
    & $PythonDoApp -m mobaile.services.setup
}

if (-not $Alvos -or $Alvos.Count -eq 0) { $Alvos = @('tudo') }
foreach ($alvo in $Alvos) {
    switch ($alvo) {
        'python' { Alvo-Python }
        'android' { Alvo-Android }
        'scrcpy' { Alvo-Scrcpy }
        'tudo' { Alvo-Python; Alvo-Android; Alvo-Scrcpy }
        'verificar' { }
        default { throw "Alvo desconhecido: $alvo" }
    }
}
Alvo-Verificar
