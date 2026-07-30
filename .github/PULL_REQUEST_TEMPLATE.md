## Qué cambia

<!-- Una o dos frases. Qué hace distinto el sistema después de este PR. -->

## Por qué

<!-- El problema que resuelve. Si hay un issue, enlazarlo: Closes #NN -->

## Cómo se probó

<!-- Qué corriste para convencerte de que funciona. "No probado" es una respuesta
     válida y útil; "funciona" sin decir cómo, no. -->

## Impacto en producción

- [ ] No toca producción (docs, CI, refactor interno)
- [ ] 🟢 Se despliega solo al mergear a `main`
- [ ] 🟡 Requiere despliegue manual con aprobación
- [ ] 🔴 Requiere procedimiento manual documentado

**Si algo sale mal, cómo se revierte:**
<!-- ej: gh workflow run deploy.yml -f ref=v1.2.0 -->

## Checklist

- [ ] Los commits siguen Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`)
- [ ] No hay ningún valor de credencial en el diff (gitleaks pasa en verde)
- [ ] Si cambié una clave de configuración, actualicé `.env.example`
- [ ] Si cambié un invariante del sistema, actualicé `CLAUDE.md`
- [ ] Si esto documenta una trampa que costó tiempo descubrir, quedó escrita en `docs/`
