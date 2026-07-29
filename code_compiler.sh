#!/bin/bash
set -e

STAGING_DIR="/totvs/protheus/patches_queue"
APO_DIR="/totvs/protheus/apo"
ROLLBACK_DIR="/totvs/protheus/apo/aporollback"
ENVIRONMENT="${ENV_NAME:-protheus_dev}"
CUSTOM_RPO="${RPO_CUSTOM_NAME:-custom}.rpo"
LIST_FILE="/tmp/fontes_compilacao.lst"
OUTREPORT_DIR="/tmp/outreport/"
FILE_ERROR="${OUTREPORT_DIR}compile_errors.log"
FILE_SUCCESS="${OUTREPORT_DIR}compile_success.log"

# Includes consolidados nas pastas lógicas montadas do host (modelo do
# worker real: volumes já montados diretamente, sem extração de .zip —
# diferente da versão morta em docker-protheus-appserver, que extraía
# includes.zip em /tmp; aqui não há esse zip, então mantém-se o mount).
INCLUDE_PATHS="/totvs/protheus/includes/advpl;/totvs/protheus/includes/tlpp;/totvs/protheus/includes/custom"

echo "=== [Protheus-Compiler] Inicializando Esteira de Compilação GitOps (.LST) ==="

if [ -d "$STAGING_DIR" ]; then
    echo "🔍 Varrendo diretório de staging para gerar lote .lst..."
    FONTES=$(find "$STAGING_DIR" -type f \( -name "*.prw" -o -name "*.tlpp" \) | tr '\n' ';')
    FONTES=$(echo "$FONTES" | tr -d '\r' | xargs)

    if [ -z "$FONTES" ]; then
        echo "❌ ERRO CRÍTICO: Nenhum arquivo .prw ou .tlpp localizado no staging!"
        exit 1
    fi

    printf "%s" "$FONTES" > "$LIST_FILE"
else
    echo "❌ ERRO CRÍTICO: Diretório de staging não localizado!"
    exit 1
fi

# 🛡️ BACKUP PREVENTIVO DO RPO CUSTOM
mkdir -p "$OUTREPORT_DIR"
if [ -f "${APO_DIR}/${CUSTOM_RPO}" ]; then
    echo "💾 [Segurança] Gerando backup preventivo do RPO [${CUSTOM_RPO}]..."
    mkdir -p "$ROLLBACK_DIR"
    cp -p "${APO_DIR}/${CUSTOM_RPO}" "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    BACKUP_EXISTS="true"
else
    echo "⚠️  Aviso: [${CUSTOM_RPO}] não foi encontrado para backup inicial."
    BACKUP_EXISTS="false"
fi

cd /totvs/protheus/bin/appserver
echo "⚙️ Invocando compilação de lote..."

# set +e/-e ao redor da chamada: sem isso, sob set -e, uma saída não-zero
# do appsrvlinux mata o script antes da auditoria/rollback abaixo.
ERROR=0
set +e
./appsrvlinux -compile -env="$ENVIRONMENT" -files="$LIST_FILE" -includes="$INCLUDE_PATHS" -outreport="$OUTREPORT_DIR"
ERROR=$?
set -e

# 📊 AUDITORIA PÓS-COMPILAÇÃO VIA OUTREPORT
echo "📊 Analisando relatórios de saída do compilador..."

if [ "$ERROR" -ne 0 ] || { [ -f "${FILE_ERROR}" ] && [ -s "${FILE_ERROR}" ]; }; then
    echo "❌ FALHA CRÍTICA: Detectados erros de compilação ou sintaxe nos fontes!"

    if [ -f "${FILE_ERROR}" ]; then
        echo "📝 --- LOG DE ERROS DA TOTVS ---"
        cat "${FILE_ERROR}"
        echo "--------------------------------"
    fi

    if [ "$BACKUP_EXISTS" = "true" ]; then
        echo "🔄 [ROLLBACK] Restaurando versão estável anterior do RPO..."
        cp -p "${ROLLBACK_DIR}/${CUSTOM_RPO}" "${APO_DIR}/${CUSTOM_RPO}"
        rm -f "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    fi

    rm -f "$LIST_FILE"
    rm -rf "$OUTREPORT_DIR"
    exit 1
else
    echo "***************************************************"
    echo "* ✅ SUCESSO TOTAL: RPO compilado com sucesso!   *"
    echo "***************************************************"

    if [ -f "${FILE_SUCCESS}" ]; then
        echo "📝 Fontes integrados:"
        cat "${FILE_SUCCESS}"
    fi

    if [ "$BACKUP_EXISTS" = "true" ]; then
        rm -f "${ROLLBACK_DIR}/${CUSTOM_RPO}"
    fi
fi

rm -f "$LIST_FILE"
rm -rf "$OUTREPORT_DIR"
echo "=== [Protheus-Compiler] Processo GitOps Encerrado ==="
exit 0
