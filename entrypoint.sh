#!/bin/bash
set -e

ROLE=$(echo "$1" | tr '[:upper:]' '[:lower:]')
echo "=== [AppServer-Worker] Inicializando Modo Especialista: [${ROLE^^}] ==="

# Mapeamento dinâmico das variáveis globais injetadas pelo Docker Compose
PORT=${APP_PORT_MULTI:-5000}
LICENSE_HOST=${LICENSE_SERVER:-protheus_license}
LICENSE_PORT=${LICENSE_SERVER_PORT:-5555}
DB_PORT_INI=${DBACCESS_PORT:-7890}
DB_SERVER_INI=${DBACCESS_SERVER:-protheus_dbaccess}
ENVIRONMENT="${ENV_NAME:-protheus_dev}"
RPO_CUSTOM_TARGET="${RPO_CUSTOM_NAME:-custom}"

case "$ROLE" in
    worker)   LOG_NAME="appserver_worker.log"   ;;
    compile)  LOG_NAME="appserver_compiler.log" ;;
    *)        LOG_NAME="appserver_job.log"      ;;
esac

# 1. Aguarda a retaguarda de infraestrutura estar online de forma flexível
echo "⏳ Validando conectividade com o barramento de infraestrutura..."
while ! nc -z "$DB_SERVER_INI" "$DB_PORT_INI"; do sleep 1; done
while ! nc -z "$LICENSE_HOST" "$LICENSE_PORT"; do sleep 1; done
echo "✅ Conectividade com DbAccess e License Server estabelecida!"

# 2. Garante a árvore mínima necessária dentro dos volumes persistidos
mkdir -p /totvs/protheus/system /totvs/protheus/log /totvs/protheus/apo/aporollback /totvs/protheus/patches_queue

# 📂 2.1. PROVISIONAMENTO DO TOTVS PRINTER (Sidecar)
# Copia o executável do volume compartilhado para a pasta binária para suportar relatórios em background
if [ -f "/tmp/printer_shared/printer" ]; then
    echo "🖨️ [DevOps] Copiando executável TOTVS Printer para a pasta binária..."
    mkdir -p /totvs/protheus/bin/appserver
    cp /tmp/printer_shared/printer /totvs/protheus/bin/appserver/
    chmod +x /totvs/protheus/bin/appserver/printer
else
    echo "⚠️  [DevOps] Aviso: Executável printer não localizado em /tmp/printer_shared/"
fi

# 3. Renderização dinâmica do appserver.ini
cd /totvs/protheus/bin/appserver
echo "📝 Gerando appserver.ini dinâmico para o modo [${ROLE^^}]..."

cat <<EOF > appserver.ini
[${ENVIRONMENT}]
SourcePath=/totvs/protheus/apo
RPOCustom=/totvs/protheus/apo/${RPO_CUSTOM_TARGET}.rpo
RPOTLPP=/totvs/protheus/apo/tlpp.rpo
RootPath=/totvs/protheus
StartPath=/system/
RpoDb=SQL
RpoLanguage=Multi
RpoVersion=120
LocalFiles=SQLITE
LocalDbExtension=.db
StartSysInDB=1
TopMemoMega=50
DBPort=${DB_PORT_INI}
DBAlias=${DB_NAME}
DBServer=${DB_SERVER_INI}
DBDatabase=${DB_TYPE}

[Drivers]
Active=TCP
MultiProtocolPort=0

[TCP]
TYPE=TCPIP
Port=${PORT}

[LicenseClient]
Server=${LICENSE_HOST}
Port=${LICENSE_PORT}

[General]
ShowFullLog=0
MaxStringSize=500
MaxQuerySize=31960
ConsoleFile=/totvs/protheus/log/${LOG_NAME}
ConsoleLog=1
AsyncConsoleLog=1
BuildKillUsers=1

[TDS]
AllowMonitor=*
AllowApplyPatch=*
AllowEdit=*
EnableDisconnectUser=*
EnableSendMessage=*
EnableBlockNewConnection=*
EnableStopServer=*
EOF

# ⚡ 4. ORCHESTRATION ENGINE (Chaveamento de Funções CLI)
if [ "$ROLE" = "worker" ]; then
    if [ -f "/usr/local/bin/patch_deployer.sh" ]; then
        exec /usr/local/bin/patch_deployer.sh
    else
        echo "❌ ERRO CRÍTICO: /usr/local/bin/patch_deployer.sh não encontrado!"
        exit 1
    fi
elif [ "$ROLE" = "compile" ]; then
    if [ -f "/usr/local/bin/code_compiler.sh" ]; then
        exec /usr/local/bin/code_compiler.sh
    else
        echo "❌ ERRO CRÍTICO: /usr/local/bin/code_compiler.sh não encontrado!"
        exit 1
    fi
else
    echo "❌ Modo inválido recebido no command do Compose: Escolha 'worker' ou 'compile'."
    exit 1
fi

# Force rebuild CI: $(date +%s)