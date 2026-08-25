// ---------------------------------------------------------------------------
// index.js - Custom JavaScript Action "Motivate"
//
// Imprime un mensaje motivacional por consola cuando una issue recibe la
// etiqueta "motivate".
//
// Fuente de la cita:
//   1. Intenta obtenerla de https://type.fit/api/quotes (fetch nativo de Node 24).
//   2. Valida la respuesta y elige una cita util aleatoria.
//   3. Si la red o la API fallan, usa un fallback local (mensajes embebidos).
//   4. Imprime el mensaje por consola (logs del workflow).
//
// El fallo de la API de terceros NO hace fallar la accion: siempre imprime
// un mensaje (preferido de type.fit, si no, del fallback local).
//
// Sin dependencias: solo usa fetch nativo (Node >= 18) y fs/process estandar.
// No se necesita @vercel/ncc ni un directorio dist.
// ---------------------------------------------------------------------------

// Mensajes motivacionales locales de respaldo (sin dependencia de red).
const FALLBACK_MESSAGES = [
  '¡Sigue así! Cada commit te acerca a un despliegue más estable.',
  'El mejor momento para mejorar la pipeline fue ayer; el segundo mejor es ahora.',
  'Los tests en verde no son suerte, son disciplina. ¡Buen trabajo!',
  'Un pipeline rojo hoy es una lección para un release más seguro mañana.',
  'La constancia vence al talento cuando el talento no hace CI/CD. 💪',
  'Cada build verde es un paso más hacia producción con confianza.',
];

async function fetchTypeFitQuote() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 5000);

  try {
    const response = await fetch('https://type.fit/api/quotes', {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const quotes = await response.json();

    // type.fit devuelve un array de { text, author }.
    if (!Array.isArray(quotes) || quotes.length === 0) {
      throw new Error('Respuesta sin citas');
    }

    const usable = quotes.filter(
      (q) => q && typeof q.text === 'string' && q.text.trim() !== ''
    );
    if (usable.length === 0) {
      throw new Error('No hay citas usables');
    }

    const chosen = usable[Math.floor(Math.random() * usable.length)];
    const author = chosen.author && chosen.author.trim() !== '' ? ` — ${chosen.author}` : '';
    return `${chosen.text}${author}`;
  } finally {
    clearTimeout(timeout);
  }
}

function fallbackMessage() {
  return FALLBACK_MESSAGES[Math.floor(Math.random() * FALLBACK_MESSAGES.length)];
}

// Expone el mensaje como output de la accion (vía GITHUB_OUTPUT),
// por si un paso posterior quisiera reusarlo (la accion en si no lo necesita).
function setOutput(name, value) {
  const file = process.env.GITHUB_OUTPUT;
  if (file) {
    const { appendFileSync } = require('fs');
    appendFileSync(file, `${name}=${value}\n`);
  }
}

async function main() {
  let message;
  let source;

  try {
    message = await fetchTypeFitQuote();
    source = 'type.fit';
  } catch (error) {
    message = fallbackMessage();
    source = 'fallback-local';
    // No es un error fatal: se avisa por consola y se usa el fallback.
    console.error(
      `Aviso: type.fit API no disponible (${error.message}). Usando mensaje local de respaldo.`
    );
  }

  setOutput('message', message);

  // Lineas destacadas para localizarlas facilmente en los logs del workflow.
  console.log('=============================================');
  console.log('  🌟 MENSAJE MOTIVACIONAL 🌟');
  console.log('=============================================');
  console.log(message);
  console.log('---------------------------------------------');
  console.log(`Fuente: ${source}`);
  console.log('=============================================');
}

main().catch((error) => {
  // Si todo lo anterior fallara de forma inesperada, aun asi no bloqueamos
  // el workflow: imprimimos el fallback y salimos 0.
  console.log('=============================================');
  console.log('  🌟 MENSAJE MOTIVACIONAL 🌟');
  console.log('=============================================');
  console.log(fallbackMessage());
  console.log('=============================================');
  console.error(`Error inesperado (no bloquea la accion): ${error.message}`);
  process.exitCode = 0;
});
