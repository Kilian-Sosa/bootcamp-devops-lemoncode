# Motivate - Custom JavaScript Action

Acción de GitHub escrita en JavaScript que **imprime un mensaje motivacional
por consola** cuando una issue recibe la etiqueta `motivate`.

## Cómo funciona

- Runtime `node24` (Node 24 con `fetch` nativo; sin dependencias ni bundling).
- Intenta obtener una cita de `https://type.fit/api/quotes` (con timeout de 5s).
- Valida la respuesta y elige una cita usuable al azar.
- **Si la red o la API fallan, usa un mensaje local embebido** (fallback). El
  fallo de la API de terceros **nunca** hace fallar la acción: siempre imprime
  un mensaje.
- No necesita secretos. No escribe comentarios en la issue (el ejercicio solo
  pide pintar por consola).

## Uso

Se invoca desde `.github/workflows/motivate-issue.yml` cuando se añade la
etiqueta `motivate` a una issue:

```yaml
- uses: ./.github/actions/motivate
```

## Validación local (sin GitHub)

Como solo usa Node estándar (`fetch`, `fs`), se puede ejecutar fuera de
GitHub para probar la lógica:

```bash
node .github/actions/motivate/index.js
```

Esto imprime un mensaje motivacional (de type.fit si hay red, o del fallback
local en caso contrario) y sale con código 0.
