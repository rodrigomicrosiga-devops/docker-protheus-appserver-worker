# TOTVS Protheus AppServer - Automated DevOps Worker 🚀

Imagem Docker especialista desenvolvida para atuar de forma efêmera (Job CLI) executando esteiras automatizadas de **Aplicação de Patches** e **Compilação de Fontes** em repositórios do ecossistema Protheus (Sustentando conexões nativas com **MSSQL Server**, **PostgreSQL** e **Oracle**).

## 📊 Fluxo de Orquestração Efêmero (Job Lifecycle)

O diagrama abaixo ilustra o comportamento do container ao ser acionado via linha de comando:

```mermaid
graph TD
    A[Docker Compose Run] --> B[Entrypoint.sh]
    B --> C{Conectividade OK?}
    C -- Não --> D[Aguardar DbAccess & License]
    D --> C
    C -- Sim --> E[Gerar appserver.ini Dinâmico]
    E --> F{Argumento do Command?}
    F -- 'worker' --> G[Executar patch_deployer.sh]
    F -- 'compile' --> H[Executar code_compiler.sh]
    G --> I[Varre .ptm / Aplica no RPO]
    H --> J[Gera .lst / Compila Fontes]
    I --> K[Mover arquivos para /applied]
    J --> L[Limpar relatórios temporários]
    K --> M[Container morre e limpa RAM --rm]
    L --> M
```

## 🏷️ Rastreabilidade de Build

A tag da imagem publicada permanece fixa entre builds — só muda em uma nova release de versão. Para rastrear qual commit gerou um build específico sem depender da tag, o `pipeline` grava o label `org.opencontainers.image.revision` com o SHA do commit em toda imagem publicada:

```bash
docker inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' rodrigomicrosiga/appserver-dev-worker:24.3.1.5
```

