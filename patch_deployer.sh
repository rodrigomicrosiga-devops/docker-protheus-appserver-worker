#!/bin/bash
set -e

PATCH_DIR="/totvs/protheus/patches_queue"
ENVIRONMENT="${ENV_NAME:-protheus_dev}"
TARGET_RPO="tttm120.rpo"

echo "=== [Protheus-Worker] Inicializando Processamento de Patches em Modo CLI ==="

# --- ETAPA A: NORMALIZAÇÃO DE EXTENSÕES ---
if [ -d "$PATCH_DIR" ]; then
    find "$PATCH_DIR" -maxdepth 1 -type f -iname "*.ptm" | while read -r file; do
        ext="${file##*.}"
        if [ "$ext" != "ptm" ]; then
            echo "📝 [Normalizador] Ajustando extensão do arquivo: [$(basename "$file")] para minúsculo..."
            mv "$file" "${file%.*}.ptm"
        fi
    done
fi

# --- ETAPA B: APLICAÇÃO EM LOTE OTIMIZADA ---
if [ -d "$PATCH_DIR" ] && find "$PATCH_DIR" -maxdepth 1 -type f -name "*.ptm" | grep -q .; then
    echo "📦 Encontrado(s) pacote(s) na fila de deploy. Iniciando processamento..."
    cd /totvs/protheus/bin/appserver
    
    find "$PATCH_DIR" -maxdepth 1 -type f -name "*.ptm" | sort | while read -r patch_file; do
        PATCH_NAME=$(basename "$patch_file")
        echo "⚙️ Aplicando [${PATCH_NAME}] no ambiente [${ENVIRONMENT}]..."
        
        # Chamada CLI Nativa sem amarras de logs internos ocultos
        ./appsrvlinux -compile -applypatch -files="$patch_file" -env="$ENVIRONMENT"

        echo "✅ Patch [${PATCH_NAME}] applied com sucesso!"
        mkdir -p "$PATCH_DIR/applied"
        mv "$patch_file" "$PATCH_DIR/applied/"
    done
else
    echo "⏭️  Nenhum patch encontrado na fila de deploy (*.ptm). Finalizando Job."
fi

echo "=== [Protheus-Worker] Trabalho finalizado com sucesso! ==="
exit 0