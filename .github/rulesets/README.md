# Rulesets de ramas

- `develop.json`: protege `develop`.
- `certification-main.json`: protege `certification` y `main`.

Ambos exigen pull request, conversaciones resueltas y el check `build` de
GitHub Actions con la rama actualizada. Impiden borrados y force pushes, sin
excepciones de bypass. No exigen aprobaciones de otra persona (0 aprobaciones).

## Importación desde la terminal

1. Crea `develop` y `certification` y configura `develop` como rama por defecto.
2. Sube el workflow `.github/workflows/ci.yml` y espera una ejecución exitosa
   de CI con el job `build`. También puedes iniciarlo manualmente desde Actions
   una vez que el workflow esté en la rama por defecto.
3. Importa estos dos archivos después de ese primer CI. Sustituye `OWNER/REPO`:

```sh
gh api --method POST repos/OWNER/REPO/rulesets --input .github/rulesets/develop.json
gh api --method POST repos/OWNER/REPO/rulesets --input .github/rulesets/certification-main.json
gh api repos/OWNER/REPO/rulesets
```

Los archivos ya incluyen `build` como obligatorio y la integración de GitHub
Actions (`15368`, GitHub.com). No repitas los POST si ya importaste los rulesets:
crearían duplicados; actualiza los existentes usando su ID y el método PUT.

Los rulesets no crean ramas, no cambian la rama por defecto y no activan secret
scanning ni push protection. Esos ajustes se realizan por separado en GitHub.

Formato: https://docs.github.com/en/rest/repos/rules#create-a-repository-ruleset
