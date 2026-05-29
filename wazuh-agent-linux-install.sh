#!/usr/bin/env bash
# =============================================================================
# install-wazuh-agent.sh
# Instala ou atualiza o Wazuh Agent no Linux (apt / yum / dnf).
# Remove versao anterior se encontrada.
#
# USO:
#   ./install-wazuh-agent.sh -m <manager> [-n <nome>] [-g <grupo>]
#
# PARAMETROS:
#   -m  IP ou hostname do Wazuh Manager  (obrigatorio)
#   -n  Nome do agente no Dashboard      (padrao: hostname)
#   -g  Grupo do agente                  (padrao: default)
#
# EXEMPLOS:
#   ./install-wazuh-agent.sh -m 10.14.0.102
#   ./install-wazuh-agent.sh -m 10.14.0.102 -n "srv-app-01" -g "servidores"
#
# SUPORTE: RHEL/CentOS/Oracle (yum ou dnf), Debian/Ubuntu (apt)
# VERSAO WAZUH: 4.14.5
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────
# Configuracoes
# ─────────────────────────────────────────────
WAZUH_VERSION="4.14.5"
WAZUH_MAJOR="4"
LOG_FILE="/tmp/wazuh-install.log"
OSSEC_CONF="/var/ossec/etc/ossec.conf"

# ─────────────────────────────────────────────
# Funcoes auxiliares
# ─────────────────────────────────────────────
log() {
    local level="${2:-INFO}"
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

die() {
    log "$1" "ERROR"
    exit 1
}

usage() {
    echo "Uso: $0 -m <manager_ip> [-n <agent_name>] [-g <group>]"
    echo ""
    echo "  -m  IP ou hostname do Wazuh Manager (obrigatorio)"
    echo "  -n  Nome do agente (padrao: hostname)"
    echo "  -g  Grupo do agente (padrao: default)"
    exit 1
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Execute como root ou via sudo."
    fi
}

detect_pkg_manager() {
    if command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v apt-get &>/dev/null; then
        echo "apt"
    else
        die "Gerenciador de pacotes nao suportado. Requer apt, yum ou dnf."
    fi
}

detect_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)       echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        armv7l)       echo "armhf" ;;
        *)            die "Arquitetura nao suportada: $arch" ;;
    esac
}

# ─────────────────────────────────────────────
# Remocao de versao anterior
# ─────────────────────────────────────────────
remove_previous() {
    local pkg_manager="$1"
    log "Verificando versao anterior do Wazuh Agent..."

    case "$pkg_manager" in
        apt)
            if dpkg -l wazuh-agent &>/dev/null 2>&1; then
                local ver
                ver=$(dpkg -l wazuh-agent 2>/dev/null | awk '/^ii/{print $3}')
                log "Versao encontrada: $ver — removendo..."
                systemctl stop wazuh-agent 2>/dev/null || true
                apt-get remove --purge -y wazuh-agent >> "$LOG_FILE" 2>&1
                log "Versao anterior removida."
            else
                log "Nenhuma versao anterior encontrada."
            fi
            ;;
        yum|dnf)
            if rpm -q wazuh-agent &>/dev/null 2>&1; then
                local ver
                ver=$(rpm -q wazuh-agent)
                log "Versao encontrada: $ver — removendo..."
                systemctl stop wazuh-agent 2>/dev/null || true
                "$pkg_manager" remove -y wazuh-agent >> "$LOG_FILE" 2>&1
                log "Versao anterior removida."
            else
                log "Nenhuma versao anterior encontrada."
            fi
            ;;
    esac

    # Limpar residuos
    if [[ -d /var/ossec ]]; then
        log "Removendo diretorio residual /var/ossec..."
        rm -rf /var/ossec
    fi
}

# ─────────────────────────────────────────────
# Adicionar repositorio e instalar
# ─────────────────────────────────────────────
install_via_apt() {
    log "Configurando repositorio Wazuh (apt)..."

    # Dependencias
    apt-get update -qq >> "$LOG_FILE" 2>&1
    apt-get install -y curl gnupg apt-transport-https >> "$LOG_FILE" 2>&1

    # GPG key
    curl -fsSL https://packages.wazuh.com/key/GPG-KEY-WAZUH \
        | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg 2>> "$LOG_FILE"

    # Repositorio
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/${WAZUH_MAJOR}.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list

    apt-get update -qq >> "$LOG_FILE" 2>&1

    log "Instalando wazuh-agent=${WAZUH_VERSION}-1..."
    WAZUH_MANAGER="$MANAGER" \
    WAZUH_AGENT_NAME="$AGENT_NAME" \
    WAZUH_AGENT_GROUP="$AGENT_GROUP" \
    apt-get install -y wazuh-agent="${WAZUH_VERSION}-1" >> "$LOG_FILE" 2>&1
}

install_via_rpm() {
    local pkg_manager="$1"
    local arch
    arch=$(detect_arch)

    log "Configurando repositorio Wazuh (${pkg_manager})..."

    # GPG key
    rpm --import https://packages.wazuh.com/key/GPG-KEY-WAZUH 2>> "$LOG_FILE"

    # Arquivo de repositorio
    cat > /etc/yum.repos.d/wazuh.repo << EOF
[wazuh]
gpgcheck=1
gpgkey=https://packages.wazuh.com/key/GPG-KEY-WAZUH
enabled=1
name=EL-\$releasever - Wazuh
baseurl=https://packages.wazuh.com/${WAZUH_MAJOR}.x/yum/
protect=1
EOF

    log "Instalando wazuh-agent-${WAZUH_VERSION}-1.${arch}..."
    WAZUH_MANAGER="$MANAGER" \
    WAZUH_AGENT_NAME="$AGENT_NAME" \
    WAZUH_AGENT_GROUP="$AGENT_GROUP" \
    "$pkg_manager" install -y "wazuh-agent-${WAZUH_VERSION}-1.${arch}" >> "$LOG_FILE" 2>&1
}

# ─────────────────────────────────────────────
# Configurar ossec.conf (garante o manager correto)
# ─────────────────────────────────────────────
configure_manager() {
    log "Configurando manager em $OSSEC_CONF..."

    if [[ ! -f "$OSSEC_CONF" ]]; then
        die "Arquivo $OSSEC_CONF nao encontrado apos instalacao."
    fi

    # Substituir bloco <client><server><address>
    python3 - << PYEOF
import re, sys

conf_path = "${OSSEC_CONF}"
manager   = "${MANAGER}"

with open(conf_path, 'r') as f:
    content = f.read()

# Substitui o address dentro do bloco <client>
updated = re.sub(
    r'(<client>.*?<server>.*?<address>)([^<]*)(</address>)',
    lambda m: m.group(1) + manager + m.group(3),
    content, flags=re.DOTALL
)

if updated == content:
    # Se nao encontrou o padrao, injeta no inicio do bloco <client>
    updated = re.sub(
        r'(<client>)',
        r'\1\n    <server>\n      <address>' + manager + r'</address>\n      <port>1514</port>\n      <protocol>tcp</protocol>\n    </server>',
        content, count=1
    )

with open(conf_path, 'w') as f:
    f.write(updated)

print("ossec.conf atualizado.")
PYEOF
}

# ─────────────────────────────────────────────
# Habilitar e iniciar servico
# ─────────────────────────────────────────────
start_service() {
    log "Habilitando e iniciando wazuh-agent..."
    systemctl daemon-reload >> "$LOG_FILE" 2>&1
    systemctl enable wazuh-agent >> "$LOG_FILE" 2>&1
    systemctl start wazuh-agent

    sleep 3

    if systemctl is-active --quiet wazuh-agent; then
        log "Servico wazuh-agent em execucao."
        log "Agente '$AGENT_NAME' registrado no Manager $MANAGER (grupo: $AGENT_GROUP)."
    else
        log "Aviso: servico nao iniciou. Verifique: journalctl -u wazuh-agent -n 30" "WARN"
    fi
}

# ─────────────────────────────────────────────
# Parsear argumentos
# ─────────────────────────────────────────────
MANAGER=""
AGENT_NAME=""
AGENT_GROUP="default"

while getopts ":m:n:g:h" opt; do
    case $opt in
        m) MANAGER="$OPTARG" ;;
        n) AGENT_NAME="$OPTARG" ;;
        g) AGENT_GROUP="$OPTARG" ;;
        h) usage ;;
        :) die "Opcao -$OPTARG requer um argumento." ;;
        \?) die "Opcao invalida: -$OPTARG" ;;
    esac
done

[[ -z "$MANAGER" ]] && usage

# Valor padrao para nome do agente
[[ -z "$AGENT_NAME" ]] && AGENT_NAME=$(hostname -s)

# ─────────────────────────────────────────────
# Execucao principal
# ─────────────────────────────────────────────
log "===== Instalacao Wazuh Agent ${WAZUH_VERSION} ====="
log "Manager: $MANAGER | Agente: $AGENT_NAME | Grupo: $AGENT_GROUP"
log "Log em: $LOG_FILE"

check_root

PKG_MANAGER=$(detect_pkg_manager)
log "Gerenciador de pacotes detectado: $PKG_MANAGER"

remove_previous "$PKG_MANAGER"

case "$PKG_MANAGER" in
    apt)        install_via_apt ;;
    yum|dnf)    install_via_rpm "$PKG_MANAGER" ;;
esac

configure_manager
start_service

log "===== Instalacao finalizada com sucesso ====="
