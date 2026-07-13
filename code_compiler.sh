#!/bin/bash
set -e

STAGING_DIR="/totvs/protheus/patches_queue"
ENVIRONMENT="${ENV_NAME:-protheus_dev}"
LIST_FILE="/tmp/fontes_compilacao.lst"
OUTREPORT_DIR="/tmp/outreport/"

# Includes consolidados nas pastas lógicas montadas do host
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

mkdir -p "$OUTREPORT_DIR"
cd /totvs/protheus/bin/appserver

echo "⚙️ Invocando compilação de lote..."
./appsrvlinux -compile -env="$ENVIRONMENT" -files="$LIST_FILE" -includes="$INCLUDE_PATHS" -outreport="$OUTREPORT_DIR"

echo "***************************************************"
echo "* ✅ SUCESSO TOTAL: RPO compilado com sucesso!   *"
echo "***************************************************"

rm -f "$LIST_FILE"
rm -rf "$OUTREPORT_DIR"
exit 0