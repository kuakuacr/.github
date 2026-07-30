# .github — configuración compartida de Kua'kua

Este repositorio contiene lo que se comparte entre **todos** los repositorios de
`kuakuacr`: los workflows reutilizables de CI/despliegue/release, las plantillas de
issues y pull requests, y las convenciones de ingeniería.

> **Es público a propósito.** Los workflows reutilizables solo son invocables desde otros
> repositorios si viven en un repo público, y las plantillas por defecto solo aplican
> desde un repo público llamado `.github`.
>
> Por eso aquí **no hay** nombres de host, IPs, rutas de servidor, dominios internos ni
> ningún dato de la topología. Todo eso llega como *input* desde los repositorios
> privados que invocan estos workflows.

---

## Contenido

| Ruta | Qué es |
|---|---|
| [`CONVENTIONS.md`](CONVENTIONS.md) | Cómo se nombran, ramifican, versionan y despliegan los repos. **Empezar por aquí.** |
| `.github/workflows/ci.yml` | CI reutilizable: gitleaks siempre + linters activables por input. |
| `.github/workflows/deploy-tailscale.yml` | Despliegue reutilizable a los VPS a través de la tailnet. |
| `.github/workflows/release.yml` | Versionado y CHANGELOG con release-please. |
| `.github/workflows/pat-expiry-check.yml` | Vigilancia semanal de la expiración de `RELEASE_BOT_PAT`. |
| `.github/ISSUE_TEMPLATE/` | Plantillas de reporte de falla y solicitud de cambio. |
| `.github/PULL_REQUEST_TEMPLATE.md` | Plantilla de PR. |

## Cómo se usan los workflows reutilizables

```yaml
# .github/workflows/ci.yml en cualquier repo de kuakuacr
name: CI
on:
  pull_request:
  push:
    branches: [main, test]

jobs:
  ci:
    uses: kuakuacr/.github/.github/workflows/ci.yml@main
    with:
      node: true
      docker: true
```

```yaml
# despliegue
jobs:
  deploy:
    uses: kuakuacr/.github/.github/workflows/deploy-tailscale.yml@main
    with:
      host: kuakua-core
      source_path: sinpes/
      remote_path: /opt/kuakua/sinpes/
      post_deploy: docker restart kuakua-sinpes
      stamp_html: true
    secrets: inherit
```

## Mapa de repositorios

| Repositorio | Sistema | Nivel de despliegue |
|---|---|---|
| `kuakua-infra` | Docker Compose, Traefik, CoreDNS de ambos VPS | 🟡 |
| `kuakua-n8n` | Workflows de automatización | 🔴 |
| `kuakua-web` | Dashboard SINPE, contador, sitios estáticos | 🟢 |
| `kuakua-chatwoot` | Imagen personalizada y configuración de Chatwoot | 🟡 |
| `kuakua-slack-bot` | Bot de Slack (comandos `chatwoot …`) | 🟢 |
| `kuakua-odoo` | Configuración, parámetros y módulos de Odoo | 🟡 |
| `kuakua-cms` | Strapi | 🟡 |
| `kuakua-brand` | Identidad visual, logos, tokens de color | 🟢 |
| `kuakua-template` | Plantilla para repositorios nuevos | — |

🟢 automático al mergear a `main` · 🟡 requiere aprobación manual · 🔴 despliegue a mano

El inventario detallado (host, ruta, contenedor, dominio) vive en
`kuakua-infra/docs/registry.md`.
