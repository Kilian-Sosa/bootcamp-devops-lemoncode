# backend.Dockerfile — Imagen del backend Node.js (Reto 2 y Reto 4).
#
# Contexto de build: node-stack/backend  (se pasa con `docker build -f
# solution/backend.Dockerfile ../node-stack/backend`). Se usa ese contexto para
# copiar únicamente package.json, package-lock.json y app.js, sin node_modules.
#
# No se usa multi-stage porque la app no tiene paso de build: `node app.js`
# ejecuta Express directamente. Un solo stage fino es más eficiente aquí.

FROM node:20-slim

# El directorio de trabajo convencional de las imágenes oficiales de Node.
WORKDIR /usr/src/app

# Copiar primero los manifiestos para aprovechar la caché de capas de Docker:
# si el código cambia pero las dependencias no, no se reinstala todo.
COPY package.json package-lock.json* ./

# Instalación determinista (usa package-lock.json), solo dependencias de
# producción, sin scripts opcionales que puedan fallar en el build.
RUN npm ci --omit=dev --ignore-scripts

# Código de la aplicación.
COPY app.js ./

# El contenedor no debe escribir como root: usamos el usuario `node` que ya
# existe en la imagen oficial node:20-slim.
USER node

# Puerto que escucha app.js (PORT por defecto = 5000).
EXPOSE 5000

# Arranque directo del servidor Express.
CMD ["node", "app.js"]
