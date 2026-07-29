#!/bin/bash
set -e

PATCH_DIR="/totvs/protheus/patches_queue"
APO_DIR="/totvs/protheus/apo"
ROLLBACK_DIR="/totvs/protheus/apo/aporollback"
ENVIRONMENT="${ENV_NAME:-protheus_dev}"
TARGET_RPO="tttm120.rpo"

echo "=== [Protheus-Worker] Inicializando Processamento de Patches em Modo CLI ==="

# --- ETAPA A: NORMALIZAÇÃO DE EXTENSÕES ---
if [ -d "$PATCH_DIR" ]; then
    while read -r file; do
        ext="${file##*.}"
        if [ "$ext" != "ptm" ]; then
            echo "📝 [Normalizador] Ajustando extensão do arquivo: [$(basename "$file")] para minúsculo..."
            mv "$file" "${file%.*}.ptm"
        fi
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -iname "*.ptm")
fi

# --- ETAPA B: APLICAÇÃO EM LOTE COM REDE DE SEGURANÇA ---
if [ -d "$PATCH_DIR" ] && find "$PATCH_DIR" -maxdepth 1 -type f -name "*.ptm" | grep -q .; then
    echo "📦 Encontrado(s) pacote(s) na fila de deploy. Iniciando processamento..."

    # 🛡️ INTERCEPTOR: BACKUP PREVENTIVO ÚNICO (Antes de iniciar o loop do lote)
    mkdir -p "$ROLLBACK_DIR"
    if [ -f "${APO_DIR}/${TARGET_RPO}" ]; then
        echo "💾 [Segurança] Iniciando BACKUP ÚNICO do repositório [${TARGET_RPO}] antes do lote..."
        cp -p "${APO_DIR}/${TARGET_RPO}" "${ROLLBACK_DIR}/${TARGET_RPO}"
        BACKUP_EXISTS="true"
        echo "✅ Backup preventivo gerado com sucesso em ${ROLLBACK_DIR}/"
    else
        echo "⚠️  Aviso: [${TARGET_RPO}] não foi encontrado para backup inicial."
        BACKUP_EXISTS="false"
    fi

    cd /totvs/protheus/bin/appserver

    # Varre e processa a fila de patches de forma sequencial ordenada.
    # process substitution (não pipe) de propósito: o loop roda no shell
    # principal, então "exit 1" dentro dele encerra o script de verdade
    # em vez de só a subshell do pipe (o bug do "set -e sobre pipeline"
    # documentado na versão anterior deste script).
    while read -r patch_file; do
        PATCH_NAME=$(basename "$patch_file")

        echo "⚙️ Aplicando [${PATCH_NAME}] no ambiente [${ENVIRONMENT}]..."
        TMP_LOG="/tmp/patch_exec.log"

        # EXECUÇÃO CLI OFICIAL NATIVA DO TDN
        # set +e/-e ao redor da chamada (mesmo padrão do code_compiler.sh):
        # sem isso, sob set -e, qualquer saída não-zero do appsrvlinux
        # (lock de RPO, patch malformado, crash) mata o script AQUI MESMO,
        # pulando o rollback e o isolamento do pacote defeituoso abaixo.
        set +e
        ./appsrvlinux -compile -applypatch -files="$patch_file" -env="$ENVIRONMENT" > "$TMP_LOG" 2>&1
        EXEC_RC=$?
        set -e
        cat "$TMP_LOG"

        # ⚡ VALIDAÇÃO: exit code E assinatura no log
        if [ "$EXEC_RC" -eq 0 ] && grep -q "Patch successfully applied" "$TMP_LOG"; then
            EXEC_SUCCESS="true"
        else
            EXEC_SUCCESS="false"
        fi

        rm -f "$TMP_LOG"

        if [ "$EXEC_SUCCESS" = "true" ]; then
            echo "✅ Patch [${PATCH_NAME}] aplicado com sucesso!"
            mkdir -p "$PATCH_DIR/applied"
            mv "$patch_file" "$PATCH_DIR/applied/"
        else
            echo "❌ ERRO CRÍTICO detectado durante a aplicação de [${PATCH_NAME}]!"
            if [ "$BACKUP_EXISTS" = "true" ]; then
                echo "🔄 [ROLLBACK ATIVADO] Interrompendo lote e restaurando RPO estável do início do processo..."
                cp -p "${ROLLBACK_DIR}/${TARGET_RPO}" "${APO_DIR}/${TARGET_RPO}"
                rm -f "${ROLLBACK_DIR}/${TARGET_RPO}"
                echo "💥 Restauração executada com sucesso. O RPO voltou ao estado original pré-lote."
            fi

            echo "📁 Isolando o pacote defeituoso para análise..."
            mkdir -p "$PATCH_DIR/error"
            mv "$patch_file" "$PATCH_DIR/error/"

            exit 1 # Aborta o script e sinaliza erro imediatamente para o run.sh
        fi
    done < <(find "$PATCH_DIR" -maxdepth 1 -type f -name "*.ptm" | sort)

    # 🧼 LIMPEZA PÓS-SUCESSO DO LOTE INTEIRO
    if [ "$BACKUP_EXISTS" = "true" ]; then
        echo "🧹 [Limpeza] Todos os patches do lote passaram! Removendo backup de contingência temporário..."
        rm -f "${ROLLBACK_DIR}/${TARGET_RPO}"
    fi
else
    echo "⏭️  Nenhum patch encontrado na fila de deploy (*.ptm). Finalizando Job."
fi

echo "=== [Protheus-Worker] Trabalho finalizado com sucesso! ==="
exit 0
