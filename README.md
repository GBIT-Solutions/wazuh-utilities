# wazuh-utilities

Utilitários para instalação e gerenciamento do Wazuh Agent em ambientes Windows e Linux.

---

## Scripts disponíveis

| Script | Plataforma | Descrição |
|---|---|---|
| `install-wazuh-agent.ps1` | Windows | Instala/atualiza o Wazuh Agent via PowerShell |
| `install-wazuh-agent.sh` | Linux | Instala/atualiza o Wazuh Agent (apt / yum / dnf) |

**Versão instalada:** Wazuh Agent 4.14.5

---

## install-wazuh-agent.ps1 — Windows

### Pré-requisitos

- Windows 10 / Windows Server 2016 ou superior
- PowerShell 5.1+
- Executar como **Administrador**
- Acesso à internet para download do pacote (ou ajustar a URL para repositório interno)

### Parâmetros

| Parâmetro | Obrigatório | Descrição | Padrão |
|---|---|---|---|
| `-Manager` | Sim | IP ou hostname do Wazuh Manager | — |
| `-AgentName` | Não | Nome do agente no Dashboard | Nome do computador (`$env:COMPUTERNAME`) |
| `-Group` | Não | Grupo do agente no Wazuh | `default` |

### Uso

```powershell
# Instalação básica
.\install-wazuh-agent.ps1 -Manager 10.14.0.102

# Especificando nome e grupo
.\install-wazuh-agent.ps1 -Manager 10.14.0.102 -AgentName "srv-financeiro-01" -Group "servidores"

# Com hostname do manager
.\install-wazuh-agent.ps1 -Manager wazuh.empresa.local -AgentName "ws-ti-042" -Group "workstations"
```

### O que o script faz

1. Verifica se está sendo executado como Administrador
2. Detecta versão anterior do Wazuh Agent via registro do Windows
3. Para o serviço e desinstala a versão anterior (via `msiexec /x`)
4. Remove diretório residual se necessário
5. Baixa o instalador `.msi` do repositório oficial da Wazuh
6. Instala o agente com os parâmetros informados
7. Inicia o serviço `WazuhSvc`
8. Grava log em `%TEMP%\wazuh-install.log`

### Política de execução

Caso o PowerShell bloqueie a execução do script, ajuste temporariamente a política:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\install-wazuh-agent.ps1 -Manager 10.14.0.102
```

---

## install-wazuh-agent.sh — Linux

### Pré-requisitos

- Distribuições suportadas:
  - **Debian / Ubuntu** — via `apt`
  - **RHEL / CentOS / Oracle Linux 7** — via `yum`
  - **RHEL / CentOS / Oracle Linux 8+ / Fedora** — via `dnf`
- Executar como **root** ou via `sudo`
- Acesso à internet para download do pacote

### Parâmetros

| Flag | Obrigatório | Descrição | Padrão |
|---|---|---|---|
| `-m` | Sim | IP ou hostname do Wazuh Manager | — |
| `-n` | Não | Nome do agente no Dashboard | `hostname -s` |
| `-g` | Não | Grupo do agente no Wazuh | `default` |

### Uso

```bash
# Dar permissão de execução (apenas na primeira vez)
chmod +x install-wazuh-agent.sh

# Instalação básica
sudo ./install-wazuh-agent.sh -m 10.14.0.102

# Especificando nome e grupo
sudo ./install-wazuh-agent.sh -m 10.14.0.102 -n "srv-app-01" -g "servidores"

# Com hostname do manager
sudo ./install-wazuh-agent.sh -m wazuh.empresa.local -n "db-prod-01" -g "banco-de-dados"
```

### O que o script faz

1. Verifica se está sendo executado como root
2. Detecta automaticamente o gerenciador de pacotes (`apt`, `yum` ou `dnf`)
3. Remove versão anterior do agente (incluindo `--purge` no apt) e limpa `/var/ossec`
4. Adiciona o repositório oficial da Wazuh com verificação de GPG key
5. Instala a versão fixada `4.14.5`
6. Configura o `ossec.conf` com o endereço do Manager informado
7. Habilita e inicia o serviço via `systemd`
8. Grava log em `/tmp/wazuh-install.log`

---

## Verificando o agente após instalação

Após a instalação, verifique se o agente está ativo e conectado:

**Windows:**
```powershell
Get-Service WazuhSvc
# ou
"C:\Program Files (x86)\ossec-agent\wazuh-agent.exe" -t
```

**Linux:**
```bash
sudo systemctl status wazuh-agent
sudo /var/ossec/bin/wazuh-agentd --version
```

No **Wazuh Dashboard**, o agente deve aparecer em **Agents** com status `Active` em alguns minutos após a instalação.

---

## Troubleshooting

**Agente instalado mas não aparece no Dashboard**

Verifique a conectividade com o Manager na porta 1514 (TCP):
```bash
# Linux
nc -zv 10.14.0.102 1514

# Windows (PowerShell)
Test-NetConnection -ComputerName 10.14.0.102 -Port 1514
```

**Log de instalação**

```bash
# Linux
cat /tmp/wazuh-install.log

# Windows
notepad $env:TEMP\wazuh-install.log
```

**Forçar re-registro do agente**

```bash
# Linux
sudo systemctl stop wazuh-agent
sudo rm -f /var/ossec/etc/client.keys
sudo systemctl start wazuh-agent
```

---

## Referências

- [Documentação oficial Wazuh](https://documentation.wazuh.com)
- [Repositório de pacotes Wazuh](https://packages.wazuh.com)
