# ==============================================================================
# ESTÁGIO 1: Builder (Extração limpa sem manter lixo em camadas)
# ==============================================================================
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends tar && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/build

# Copia o binário a partir da raiz do novo contexto
COPY appserver.tar.gz .
RUN mkdir -p appserver && tar -xzf appserver.tar.gz -C appserver/

# ==============================================================================
# ESTÁGIO 2: Runner (Imagem Enxuta e Especialista)
# ==============================================================================
FROM ubuntu:22.04 AS runner
LABEL maintainer="Rodrigo dos Santos Brandão <rodrigomicrosiga>"
LABEL version="24.3.1.5"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=pt_BR.UTF-8
ENV LANGUAGE=pt_BR:pt
ENV LC_ALL=pt_BR.UTF-8
ENV PATH="/totvs/protheus/bin/appserver:${PATH}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6 libtinfo5 libuuid1 netcat-openbsd unzip locales dmidecode \
    && echo "pt_BR.UTF-8 UTF-8" > /etc/locale.gen && locale-gen \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /totvs/protheus/bin/appserver \
             /totvs/protheus/apo \
             /totvs/protheus/system \
             /totvs/protheus/log \
             /totvs/protheus/data

# Copia os binários do estágio do builder
COPY --from=builder /tmp/build/appserver /totvs/protheus/bin/appserver/

# Copia os scripts da raiz do contexto para os diretórios do container
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY patch_deployer.sh /usr/local/bin/patch_deployer.sh
COPY code_compiler.sh /usr/local/bin/code_compiler.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/patch_deployer.sh \
             /usr/local/bin/code_compiler.sh \
             /totvs/protheus/bin/appserver/appsrvlinux

WORKDIR /totvs/protheus/bin/appserver
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]