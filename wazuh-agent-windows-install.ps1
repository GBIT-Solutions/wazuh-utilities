<#
.SYNOPSIS
    Instala ou atualiza o Wazuh Agent no Windows.

.DESCRIPTION
    Remove versao anterior se encontrada, baixa e instala o Wazuh Agent 4.14.5.
    Registra o agente no Wazuh Manager informado via parametro.

.PARAMETER Manager
    IP ou hostname do Wazuh Manager. Obrigatorio.

.PARAMETER AgentName
    Nome do agente (exibido no Dashboard). Padrao: hostname da maquina.

.PARAMETER Group
    Grupo do agente no Wazuh. Padrao: "default".

.EXAMPLE
    .\install-wazuh-agent.ps1 -Manager 10.14.0.102
    .\install-wazuh-agent.ps1 -Manager 10.14.0.102 -AgentName "srv-financeiro-01" -Group "servidores"

.NOTES
    Requer execucao como Administrador.
    Versao Wazuh: 4.14.5
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "IP ou hostname do Wazuh Manager")]
    [string]$Manager,

    [Parameter(Mandatory = $false)]
    [string]$AgentName = $env:COMPUTERNAME,

    [Parameter(Mandatory = $false)]
    [string]$Group = "default"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ─────────────────────────────────────────────
# Configuracoes
# ─────────────────────────────────────────────
$WAZUH_VERSION   = "4.14.5"
$WAZUH_MSI       = "wazuh-agent-${WAZUH_VERSION}-1.msi"
$WAZUH_URL       = "https://packages.wazuh.com/4.x/windows/${WAZUH_MSI}"
$TEMP_DIR        = $env:TEMP
$MSI_PATH        = Join-Path $TEMP_DIR $WAZUH_MSI
$INSTALL_DIR     = "C:\Program Files (x86)\ossec-agent"
$SERVICE_NAME    = "WazuhSvc"
$LOG_FILE        = Join-Path $TEMP_DIR "wazuh-install.log"

# ─────────────────────────────────────────────
# Funcoes auxiliares
# ─────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Write-Host $line
    Add-Content -Path $LOG_FILE -Value $line -Encoding UTF8
}

function Test-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal   = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledWazuhVersion {
    $paths = @(
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($path in $paths) {
        $entry = Get-ItemProperty $path -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*Wazuh Agent*" } |
                 Select-Object -First 1
        if ($entry) { return $entry }
    }
    return $null
}

function Remove-WazuhAgent {
    Write-Log "Parando servico do agente..."
    Stop-Service -Name $SERVICE_NAME -Force -ErrorAction SilentlyContinue

    $installed = Get-InstalledWazuhVersion
    if ($installed) {
        Write-Log "Versao encontrada: $($installed.DisplayVersion) — removendo..."

        if ($installed.UninstallString) {
            # Extrair ProductCode do UninstallString (MsiExec.exe /I{GUID})
            $productCode = [regex]::Match($installed.UninstallString, '\{[A-F0-9\-]+\}', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase).Value
            if ($productCode) {
                Write-Log "Executando msiexec /x $productCode..."
                $proc = Start-Process "msiexec.exe" -ArgumentList "/x `"$productCode`" /qn /norestart" -Wait -PassThru
                if ($proc.ExitCode -notin @(0, 1605, 3010)) {
                    Write-Log "Aviso: msiexec retornou $($proc.ExitCode)" "WARN"
                }
            }
        }

        # Aguardar finalizacao dos processos
        Start-Sleep -Seconds 5

        # Limpar diretorio residual se necessario
        if (Test-Path $INSTALL_DIR) {
            Write-Log "Removendo diretorio residual: $INSTALL_DIR"
            Remove-Item -Path $INSTALL_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }

        Write-Log "Versao anterior removida com sucesso."
    } else {
        Write-Log "Nenhuma versao anterior encontrada."
    }
}

function Download-WazuhMSI {
    Write-Log "Baixando Wazuh Agent ${WAZUH_VERSION}..."
    Write-Log "URL: $WAZUH_URL"

    if (Test-Path $MSI_PATH) {
        Remove-Item $MSI_PATH -Force
    }

    try {
        $client = New-Object System.Net.WebClient
        $client.DownloadFile($WAZUH_URL, $MSI_PATH)
        Write-Log "Download concluido: $MSI_PATH"
    } catch {
        # Fallback para Invoke-WebRequest
        Write-Log "WebClient falhou, tentando Invoke-WebRequest..." "WARN"
        Invoke-WebRequest -Uri $WAZUH_URL -OutFile $MSI_PATH -UseBasicParsing
        Write-Log "Download concluido via Invoke-WebRequest."
    }

    if (-not (Test-Path $MSI_PATH)) {
        throw "Falha no download: arquivo nao encontrado em $MSI_PATH"
    }
}

function Install-WazuhAgent {
    Write-Log "Instalando Wazuh Agent ${WAZUH_VERSION}..."
    Write-Log "Manager: $Manager | Nome: $AgentName | Grupo: $Group"

    $msiArgs = @(
        "/i", "`"$MSI_PATH`"",
        "WAZUH_MANAGER=`"$Manager`"",
        "WAZUH_AGENT_NAME=`"$AgentName`"",
        "WAZUH_AGENT_GROUP=`"$Group`"",
        "/qn",
        "/norestart",
        "/l*v", "`"$TEMP_DIR\wazuh-msi.log`""
    )

    $proc = Start-Process "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-Log "Instalacao concluida (exit code: $($proc.ExitCode))."
    } else {
        throw "msiexec falhou com exit code: $($proc.ExitCode). Verifique $TEMP_DIR\wazuh-msi.log"
    }
}

function Start-WazuhService {
    Write-Log "Iniciando servico $SERVICE_NAME..."
    Start-Sleep -Seconds 3
    Start-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue

    $svc = Get-Service -Name $SERVICE_NAME -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Log "Servico em execucao. Agente registrado no Manager $Manager."
    } else {
        Write-Log "Aviso: servico nao iniciou automaticamente. Verifique manualmente." "WARN"
    }
}

# ─────────────────────────────────────────────
# Execucao principal
# ─────────────────────────────────────────────
Write-Log "===== Instalacao Wazuh Agent ====="
Write-Log "Manager: $Manager | Agente: $AgentName | Grupo: $Group"

if (-not (Test-Admin)) {
    Write-Log "ERRO: execute este script como Administrador." "ERROR"
    exit 1
}

try {
    Remove-WazuhAgent
    Download-WazuhMSI
    Install-WazuhAgent
    Start-WazuhService
    Write-Log "===== Instalacao finalizada com sucesso ====="
    Write-Log "Log completo em: $LOG_FILE"
} catch {
    Write-Log "ERRO FATAL: $_" "ERROR"
    exit 1
} finally {
    if (Test-Path $MSI_PATH) {
        Remove-Item $MSI_PATH -Force -ErrorAction SilentlyContinue
    }
}
