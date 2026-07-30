# Política de seguridad — Kua'kua

## Reportar una vulnerabilidad

Estos repositorios son privados y de uso interno de Floristería Kua'kua. Si encontrás un
problema de seguridad, escribí directamente a Diego en lugar de abrir un issue público.

## Manejo de secretos

### Regla principal

**Ningún valor real de credencial se commitea jamás en texto plano.** Ni en código, ni en
comentarios, ni en documentación, ni en un archivo de ejemplo, ni "temporalmente".

### Dónde vive cada cosa

| Tipo | Dónde |
|---|---|
| Valores reales de producción | `*.enc.env` cifrado con SOPS + age, dentro del repo que los consume |
| Llave privada age | Secreto `AGE_PRIVATE_KEY` del repo + gestor de contraseñas + copia offline |
| Nombres de claves (sin valores) | `.env.example` |
| Tokens de CI (`TS_OAUTH_*`, `RELEASE_BOT_PAT`) | Secretos del repositorio en GitHub |

Cada repositorio tiene **su propio par de llaves age**. Si una llave se compromete, se
expone un sistema, no toda la infraestructura.

### Defensas activas

1. **`pre-commit` con gitleaks** — bloquea el commit localmente.
2. **CI con gitleaks** — bloquea el PR; escanea el árbol de trabajo *y* la historia del
   branch, así que un secreto en un commit anterior tampoco pasa.
3. **`.gitignore`** — excluye `*.env` (no cifrados), `*.sqlite`, `Secrets.txt`,
   `passwords.txt`, `*HANDOFF*.md` y respaldos `*.bak.*`.

### Si un secreto llegó a un commit

Rotarlo primero, limpiar la historia después. El orden importa: mientras el valor siga
siendo válido, sigue comprometido aunque se borre del repositorio.

1. Rotar la credencial en el servicio de origen.
2. Actualizar el valor nuevo en el `*.enc.env` correspondiente.
3. Confirmar que el sistema afectado sigue funcionando.
4. Recién entonces, limpiar la historia si hace falta.

## Endurecimiento de CI

- Todas las acciones de terceros fijadas a **SHA de commit**, nunca a un tag flotante.
  Un tag se puede mover a otro código; un SHA no.
- `permissions:` explícito y mínimo en cada workflow.
- `pull_request_target` no se usa.
- Los workflows de despliegue tienen acceso a la llave de descifrado, así que se tratan
  como código privilegiado: cualquier cambio en `.github/workflows/` se revisa con el
  mismo cuidado que un cambio de credenciales.

## Acceso a los servidores

- CI llega a los VPS por **Tailscale SSH**, no con llaves SSH almacenadas en GitHub.
- El runner efímero se autentica con `tag:ci`, que por ACL solo alcanza el puerto 22 de
  `tag:prod` como usuario `kuakua`.
- El nodo se destruye al terminar el job.
