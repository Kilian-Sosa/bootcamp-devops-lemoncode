# frontend.Dockerfile — Imagen del frontend Node.js (Reto 3 y Reto 4).
#
# Contexto de build: node-stack/frontend  (se pasa con `docker build -f
# solution/frontend.Dockerfile ../node-stack/frontend`).
#
# El frontend es un servidor Express que renderiza EJS en servidor (server.js
# hace el fetch al backend con node-fetch). No hay paso de build del frontend,
# así que un solo stage es lo correcto y más eficiente.

FROM node:20-slim

WORKDIR /usr/src/app

# Copiar primero los manifiestos para aprovechar la caché de capas de Docker.
COPY package.json package-lock.json* ./

# Instalación determinista (package-lock.json), solo dependencias de producción.
RUN npm ci --omit=dev --ignore-scripts

# Código de la aplicación y plantillas EJS.
COPY server.js ./
COPY views ./views

# El usuario `node` existe en la imagen oficial node:20-slim.
USER node

# Puerto que escucha server.js (3000).
EXPOSE 3000

# Arranque directo del servidor Express.
CMD ["node", "server.js"]
