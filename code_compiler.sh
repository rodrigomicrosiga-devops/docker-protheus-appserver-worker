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

# 📦 EXTRAÇÃO REAL DOS INCLUDES (obrigatória -- ver nota abaixo)
#
# Cada volume de includes (advpl/tlpp/custom) traz só um includes.zip, não
# os .ch/.th soltos. Testado e confirmado ao vivo: o appsrvlinux até
# consegue abrir o arquivo de topo (ex.: protheus.ch) direto de dentro do
# zip, mas a resolução de #include ANINHADO dentro desse mesmo zip é
# case-sensitive -- protheus.ch referencia "PRTOPDEF.CH" (maiúsculo) e o
# membro real no zip é "prtopdef.ch" (minúsculo), então falha com
# "File not found PRTOPDEF.CH" mesmo com o pacote de includes íntegro.
# Em um diretório real extraído, o mesmo arquivo minúsculo resolve sem
# problema -- a tratativa de maiúsculo/minúsculo do compilador existe,
# mas só se aplica a diretórios reais, não a leitura direta de zip.
EXTRACT_ROOT="/tmp/includes_extracted"
rm -rf "$EXTRACT_ROOT"
INCLUDE_PATHS=""
for SRC in advpl tlpp custom; do
    ZIP_FILE="/totvs/protheus/includes/${SRC}/includes.zip"
    DEST_DIR="${EXTRACT_ROOT}/${SRC}"
    mkdir -p "$DEST_DIR"
    if [ -f "$ZIP_FILE" ]; then
        echo "📂 Extraindo includes [${SRC}] para área isolada do container..."
        # unzip retorna 1 (não-fatal) pro aviso de separador "\" dos
        # pacotes da TOTVS -- mesma tolerância já usada nos entrypoints
        # das imagens seed (rpo/system/systemload).
        set +e
        unzip -oq "$ZIP_FILE" -d "$DEST_DIR"
        UNZIP_RC=$?
        set -e
        if [ "$UNZIP_RC" -gt 1 ]; then
            echo "❌ ERRO CRÍTICO: Falha real ao extrair ${ZIP_FILE} (rc=${UNZIP_RC})!"
            exit 1
        fi
    fi
    INCLUDE_PATHS="${INCLUDE_PATHS}${DEST_DIR};"
done
INCLUDE_PATHS="${INCLUDE_PATHS%;}"

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
    rm -rf "$OUTREPORT_DIR" "$EXTRACT_ROOT"
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
rm -rf "$OUTREPORT_DIR" "$EXTRACT_ROOT"
echo "=== [Protheus-Compiler] Processo GitOps Encerrado ==="
exit 0
