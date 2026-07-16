# ==============================================================================
# ESTÁGIO 1: Builder (Extração e Limpeza por Strip)
# ==============================================================================
FROM debian:bookworm-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    tar \
    binutils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

# 🌟 SUPORTE DINÂMICO: Copia apenas o instalador do AppServer com tolerância de caixa no nome
COPY ./*[aA][pP][pP][sS][eE][rR][vV][eE][rR]*.[tT][aA][rR].[gG][zZ] ./appserver.tar.gz

RUN mkdir -p appserver && \
    tar -xzf appserver.tar.gz -C appserver/

# ⚡ A MÁGICA DO STRIP: Remove símbolos de debug recursivamente de todas as libs e binários
RUN find appserver/ -type f -name "*.so*" -exec strip --strip-unneeded {} + 2>/dev/null || true
RUN strip --strip-unneeded appserver/appsrvlinux 2>/dev/null || true

# ==============================================================================
# ESTÁGIO 2: Runner (Imagem Enxuta e Especialista)
# ==============================================================================
FROM debian:bookworm-slim AS runner
LABEL maintainer="Rodrigo dos Santos Brandão <rodrigomicrosiga>"
LABEL version="24.3.1.5"
LABEL description="TOTVS AppServer Worker 24.3.1.5 - Ultra Light"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=pt_BR.UTF-8 \
    LANGUAGE=pt_BR:pt \
    LC_ALL=pt_BR.UTF-8 \
    PATH="/totvs/protheus/bin/appserver:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6 \
    libtinfo5 \
    libuuid1 \
    netcat-openbsd \
    unzip \
    locales \
    dmidecode \
    # 🖨️ Dependências nativas necessárias para o TOTVS Printer rodar perfeitamente em background
    libdrm2 \
    libxcb-glx0 \
    libx11-xcb1 \
    libxkbcommon-x11-0 \
    libxcb-icccm4 \
    libxcb-image0 \
    libxcb-keysyms1 \
    libxcb-render-util0 \
    libsm6 \
    libcups2 \
    libglx0 \
    libopengl0 \
    libegl1 \
    libfreetype6 \
    libfontconfig1 \
    # 🌟 Adições para resolver o erro do XCB Shape e Fixes:
    libxcb-shape0 \
    libxcb-xfixes0 \
    && echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen && locale-gen \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /totvs/protheus/bin/appserver \
             /totvs/protheus/apo \
             /totvs/protheus/system \
             /totvs/protheus/log \
             /totvs/protheus/data

# Copia os binários limpos e otimizados do estágio do builder
COPY --from=builder /tmp/build/appserver /totvs/protheus/bin/appserver/

# Copia os scripts da raiz do contexto para os diretórios do container
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY patch_deployer.sh /usr/local/bin/patch_deployer.sh
COPY code_compiler.sh /usr/local/bin/code_compiler.sh

# 🚀 HIGIENIZAÇÃO FORÇADA DE INFRAESTRUTURA:
# Purifica os scripts eliminando quebras de linha Windows, caracteres BOM e ajusta permissões
RUN sed -i 's/\r$//' /usr/local/bin/entrypoint.sh /usr/local/bin/patch_deployer.sh /usr/local/bin/code_compiler.sh \
    && sed -i '1s/^\xef\xbb\xbf//' /usr/local/bin/entrypoint.sh \
    && sed -i '1s/^\xef\xbb\xbf//' /usr/local/bin/patch_deployer.sh \
    && sed -i '1s/^\xef\xbb\xbf//' /usr/local/bin/code_compiler.sh \
    && sed -i '1c\#!/bin/bash' /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh \
                 /usr/local/bin/patch_deployer.sh \
                 /usr/local/bin/code_compiler.sh \
                 /totvs/protheus/bin/appserver/appsrvlinux

WORKDIR /totvs/protheus/bin/appserver
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]