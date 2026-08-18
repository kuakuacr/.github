# Convenciones de ingeniería — Kua'kua

Este documento es la referencia única para cómo se organizan, nombran, versionan y
despliegan los repositorios de `kuakuacr`. Un repositorio nuevo no requiere volver a
tomar estas decisiones: se crea desde `kuakua-template` y ya viene alineado.

---

## 1. Nombres de repositorio

- Formato: `kuakua-<sistema>`, todo en minúsculas, separado por guiones.
- **Un desplegable por repositorio.** Si dos cosas se despliegan por separado, van en
  repos separados. Si siempre se despliegan juntas, van en el mismo repo.
- Excepciones: `.github` (configuración compartida de la cuenta) y `kuakua-template`.

Módulos nuevos de Odoo **no** llevan repo propio: van en `kuakua-odoo/addons/`.

## 2. Visibilidad

Todos los repositorios son **privados**, salvo `.github`, que debe ser público para que
los workflows reutilizables sean invocables y para que las plantillas de issues/PR
apliquen por defecto.

Por eso `.github` **nunca** contiene: nombres de host, IPs, rutas de servidores,
dominios internos, ni nada de la topología. Todo eso viaja como *input* desde los repos
privados que lo invocan.

## 3. Ramas

```
feat/<slug> ──PR──► test ──PR──► main
```

| Rama | Rol |
|---|---|
| `main` | Lo que está EN PRODUCCIÓN. Rama por defecto. |
| `test` | Integración y revisión previa. |
| `feat/*`, `fix/*`, `chore/*`, `docs/*` | Trabajo en curso. Vida corta. |

- Nada se commitea directo a `main`. Todo entra por PR.
- No se hace force-push a `main` ni a `test`.
- Las ramas de trabajo se borran al mergear.

### Después de promover `test` → `main`: sincronizar de vuelta

El merge con squash crea en `main` un commit **distinto** al de `test`, aunque el
contenido sea idéntico. Las dos ramas quedan divergentes, y la siguiente rama que
salga de `main` va a entrar en conflicto contra `test` sin razón aparente.

Por eso, inmediatamente después de mergear `test` en `main`:

```bash
git switch test
git merge --no-edit origin/main    # sin conflicto: el contenido ya es el mismo
git push origin test
```

Sin este paso la divergencia se acumula en cada ciclo y los conflictos se vuelven
cada vez más difíciles de leer.

### El PR de promoción `test` → `main`: dos reglas

Las dos se aprendieron rompiendo el CHANGELOG, y las dos fallan **en silencio**:
el workflow de release termina en `success` y no publica nada.

```bash
git switch test && git pull origin test
gh pr create --base main --head test --title "feat: descripción del cambio"
gh pr merge --squash --body "Promoción de test a main. Detalle por PR en test."
```

**1. El título lleva el prefijo real del cambio, no `chore:`.**

`release-please` sólo mira el título del commit de squash. Con
`chore: promote test to main` no hay nada que versionar, aunque adentro vengan
diez `feat:`. Si la promoción trae features el título va `feat:`; si sólo trae
arreglos, `fix:`. Validado en `kuakua-envios`: retitular el PR de promoción
publicó `v1.1.0` con su entrada de CHANGELOG automáticamente.

**2. El squash va con `--body` corto — no es opcional.**

`gh pr merge --squash` sin `--body` concatena el mensaje completo de cada commit
del PR. Y como el squash reescribe los SHA, los commits originales de `test`
nunca quedan como ancestros de `main`: **cada promoción vuelve a listar el
historial completo de `test` desde el primer PR**. En `kuakua-n8n` el mensaje
llegó a 86 commits, 1 533 líneas y 78 KB, creciendo ~6 KB por promoción.

El daño no lo hace el tamaño sino lo que arrastra. El parser que usa
`release-please` (`@conventional-commits/parser`) aborta con una línea de cuerpo
que **empiece en la columna 1** con `identificador(` y lleve un paréntesis
anidado adentro:

```
JSON.stringify(String(x)), which double-quotes values …
```

La lee como un footer `tipo(scope)`, y `<scope>` no admite paréntesis:
`unexpected token '(' … valid tokens [)]`. El commit completo se descarta
(`commits: 0`, `No commits for path: .`) y no sale release. Ocho promociones de
`kuakua-n8n` murieron así, todas en la misma línea, porque el mensaje sólo crece
por el final y la línea envenenada quedó fija adentro.

La misma línea a mitad de renglón o con sangría parsea bien: sólo duele en la
columna 1. Por eso el riesgo escala con el largo del mensaje — con suficientes
líneas, el wrap a 80 columnas termina dejando una llamada anidada al principio de
alguna. Con `--body` corto el mensaje deja de acumular y el problema no puede
reaparecer. `release-please` no tiene opción para ignorar el cuerpo.

### Guardrails — quién los hace cumplir

`kuakuacr` es una **cuenta personal en plan Free**, donde GitHub *no* ofrece protección
de ramas en repositorios privados. Por lo tanto:

| Regla | La hace cumplir |
|---|---|
| No commitear secretos | Hook `pre-commit` (gitleaks) + check de CI |
| Conventional Commits | Hook `commit-msg` |
| No push directo a `main` | Hook `pre-push` local |
| Lint y validación | Check de CI en el PR |

Los hooks son locales: se instalan con `pre-commit install`. Son la primera línea, pero
CI es la que no se puede saltar de forma involuntaria. Si algún día se pasa a GitHub Team,
estas mismas reglas se activan como *rulesets* del lado del servidor sin cambiar nada más.

## 4. Commits

**Conventional Commits**, en inglés (release-please depende de este formato para
calcular la versión y armar el CHANGELOG):

```
feat: agregar filtro por rango de fechas al dashboard SINPE
fix: corregir check de número espejo en el auto-link
docs: documentar el procedimiento de restauración
chore: actualizar pin de la acción de checkout
```

| Prefijo | Efecto en la versión |
|---|---|
| `fix:` | patch (1.2.3 → 1.2.4) |
| `feat:` | minor (1.2.3 → 1.3.0) |
| `feat!:` o `BREAKING CHANGE:` | major (1.2.3 → 2.0.0) |
| `docs:`, `chore:`, `refactor:`, `test:` | sin release |

## 5. Releases

- `release-please` abre un PR de release al mergear a `main`; al mergear ese PR se crea
  el tag `vX.Y.Z`, el GitHub Release y la entrada en `CHANGELOG.md`.
- **El CHANGELOG es el registro de cambios oficial.** No se edita a mano.
- Rollback: `gh workflow run deploy.yml -f ref=v1.3.0`.
- Si un release no sale y el workflow igual dice `success`, empezar por
  [las dos reglas del PR de promoción](#el-pr-de-promoción-test--main-dos-reglas):
  el título con `chore:` y el cuerpo gigante del squash son las dos causas ya vistas.

## 6. Niveles de despliegue

| Nivel | Qué es | Disparo |
|---|---|---|
| 🟢 Automático | Sitios estáticos, bot de Slack, frontend en Vercel | **Publicación de un release** (tag `vX.Y.Z`) |
| 🟡 Con aprobación | Cambios de compose, imágenes, Odoo, CMS | Click manual en `workflow_dispatch` |
| 🔴 Manual | Workflows de n8n | Procedimiento documentado, a mano |

### Por qué el disparo es el release y no el merge a `main`

```
PR → test → main → release-please abre PR de release → merge → tag → deploy
```

Cada despliegue queda atado a una versión con nombre y a su entrada en el
`CHANGELOG`. Revertir es `-f ref=v1.2.0` contra algo que existe de verdad, en
lugar de contra un SHA suelto.

Un merge a `main` **no despliega por sí solo**. Para desplegar sin publicar
versión está el disparo manual.

⚠️ Esto depende de que `release-please` corra con **`RELEASE_BOT_PAT`**. Con el
`GITHUB_TOKEN` por defecto, el tag no dispararía el workflow de despliegue y
nada se desplegaría — en silencio.

El nivel de cada repo se declara en su `README.md` y en
`kuakua-infra/docs/registry.md`.

**Por qué n8n es 🔴:** desplegar un workflow implica cirugía sobre la SQLite de n8n
(parchar `workflow_entity` *y* `workflow_history`, insertar en `shared_workflow`, hacer
checkpoint del WAL antes de reemplazar la base). Ese procedimiento ya causó dos
corrupciones y un crash loop *con una persona supervisando*. No se automatiza hasta
tener un importador idempotente probado.

## 7. Secretos

- **Nunca** un valor real en el repositorio, ni siquiera en un archivo de ejemplo.
- Los valores reales viven cifrados con SOPS + age en `*.enc.env` dentro del repo que
  los consume.
- Cada repositorio tiene **su propio par de llaves age**. Una llave comprometida expone
  un sistema, no todos.
- La llave privada vive en: el secreto `AGE_PRIVATE_KEY` del repo + el gestor de
  contraseñas + una copia offline. En ningún otro lado.
- Los nombres de las claves (sin valores) se documentan en `.env.example`.

### Regla de oro para agentes y automatización

**Nunca ejecutar `sops <archivo>` a secas.** Abre `vim` y congela cualquier terminal no
interactiva. Para modificar un secreto se usa siempre:

```bash
./scripts/update-secret.sh NOMBRE_CLAVE archivo.enc.env
# el valor se escribe por stdin, nunca como argumento
```

Pasar el valor como argumento lo deja visible en `ps` y en el historial del shell.

## 8. Archivos obligatorios en cada repositorio

`README.md` · `CLAUDE.md` · `CONTRIBUTING.md` · `SECURITY.md` · `CHANGELOG.md` ·
`CODEOWNERS` · `.gitignore` · `.gitattributes` · `.editorconfig` · `.sops.yaml` ·
`.gitleaks.toml` · `.pre-commit-config.yaml` · `.github/workflows/` · `docs/`

`CLAUDE.md` contiene los **invariantes** del repositorio: las reglas que, si se rompen,
reproducen un incidente que ya ocurrió. Se escribe pensando en alguien —o algo— que
llega sin contexto.

## 9. Idioma

| Qué | Idioma |
|---|---|
| README, `docs/`, runbooks, plantillas, prosa de `CLAUDE.md` | **Español** |
| Código, identificadores, nombres de rama, mensajes de commit, YAML de CI | **Inglés** |

Los commits van en inglés porque `release-please` y el hook de `commit-msg` dependen de
los prefijos `feat:`/`fix:`.

## 10. Acciones de terceros en CI

Siempre fijadas a un **SHA de commit**, nunca a un tag flotante:

```yaml
- uses: actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09 # v5   ✅
- uses: actions/checkout@v5                                              ❌
```

Un tag se puede mover; un SHA no. Como los workflows de despliegue tienen acceso a la
llave de descifrado, una acción comprometida podría exfiltrar todos los secretos del
repositorio.

Además: `permissions:` explícito y mínimo en cada workflow, y `pull_request_target`
nunca se usa.

## 11. Crear un repositorio nuevo

```bash
gh repo create kuakuacr/kuakua-<sistema> \
  --template kuakuacr/kuakua-template \
  --private \
  --description "<qué es>"
```

Después: crear la rama `test`, generar el par de llaves age, registrar los secretos del
repo y agregar la fila correspondiente en `kuakua-infra/docs/registry.md`.
