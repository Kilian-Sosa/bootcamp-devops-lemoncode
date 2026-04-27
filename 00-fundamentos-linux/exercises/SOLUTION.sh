#!/usr/bin/env bash

show_structure() {
  local dir="$1"

  echo
  echo "Estructura de $dir:"
  if command -v tree >/dev/null 2>&1; then
    tree "$dir"
  else
    find "$dir" -print | sort
  fi
  echo
}

show_file() {
  local file="$1"

  echo "Contenido de $file:"
  if [[ -f "$file" ]]; then
    cat "$file"
    echo
  else
    echo "El fichero no existe"
  fi
  echo
}

echo "========================================"
echo "Ejercicio 1"
echo "========================================"

rm -rf foo
mkdir -p foo/dummy foo/empty

printf '%s\n' 'Me encanta la bash!!' > foo/dummy/file1.txt
: > foo/dummy/file2.txt

show_structure "foo"

echo

show_file "foo/dummy/file1.txt"

echo "Tamaño de file2.txt, debe ser 0 bytes:"
wc -c foo/dummy/file2.txt
echo

echo "========================================"
echo "Ejercicio 2"
echo "========================================"

cat foo/dummy/file1.txt > foo/dummy/file2.txt
mv foo/dummy/file2.txt foo/empty/file2.txt

show_structure "foo"

echo

show_file "foo/dummy/file1.txt"
show_file "foo/empty/file2.txt"

echo "========================================"
echo "Ejercicio 3"
echo "========================================"

cat > ejercicio3.sh <<'EOF'
#!/usr/bin/env bash

show_structure() {
  local dir="$1"

  echo
  echo "Estructura de $dir:"
  if command -v tree >/dev/null 2>&1; then
    tree "$dir"
  else
    find "$dir" -print | sort
  fi
  echo
}

show_file() {
  local file="$1"

  echo "Contenido de $file:"
  cat "$file"
  echo
  echo
}

TEXT="${1:-}"

if [[ -z "$TEXT" ]]; then
  TEXT="Que me gusta la bash!!!!"
fi

rm -rf foo
mkdir -p foo/dummy foo/empty

printf '%s\n' "$TEXT" > foo/dummy/file1.txt
: > foo/dummy/file2.txt

echo "Estado inicial creado:"
show_structure "foo"
ls -la foo/dummy
show_file "foo/dummy/file1.txt"

cat foo/dummy/file1.txt > foo/dummy/file2.txt
mv foo/dummy/file2.txt foo/empty/file2.txt

echo "Estado final después de copiar file1.txt a file2.txt y mover file2.txt:"
show_structure "foo"
ls -la foo/dummy
ls -la foo/empty
show_file "foo/dummy/file1.txt"
show_file "foo/empty/file2.txt"
EOF

chmod +x ejercicio3.sh

echo "Script ejercicio3.sh creado:"
ls -la ejercicio3.sh
echo

echo "Ejecutando ejercicio3.sh con texto personalizado:"
./ejercicio3.sh "Texto personalizado desde parámetro"

echo "Ejecutando ejercicio3.sh con texto vacío para comprobar valor por defecto:"
./ejercicio3.sh ""

echo "========================================"
echo "Ejercicio 4"
echo "========================================"

cat > ejercicio4.sh <<'EOF'
#!/usr/bin/env bash

URL="https://lemoncode.net/"
OUTPUT_FILE="ejercicio4_page.html"

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  echo "Uso: $0 palabra"
  exit 1
fi

WORD="$1"

download_page() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$OUTPUT_FILE"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$URL" -O "$OUTPUT_FILE"
  else
    echo "Se necesita curl o wget para descargar la página"
    exit 1
  fi
}

download_page

COUNT=$(grep -oiF -- "$WORD" "$OUTPUT_FILE" | wc -l | tr -d ' ')
FIRST_LINE=$(grep -niF -- "$WORD" "$OUTPUT_FILE" | head -n 1 | cut -d ':' -f 1 || true)

if [[ "$COUNT" -eq 0 ]]; then
  echo "No se ha encontrado la palabra \"$WORD\""
else
  echo "La palabra \"$WORD\" aparece $COUNT veces"
  echo "Aparece por primera vez en la línea $FIRST_LINE"
fi
EOF

chmod +x ejercicio4.sh

echo "Script ejercicio4.sh creado:"
ls -la ejercicio4.sh
echo

echo "Ejecutando ejercicio4.sh con una palabra de prueba:"
./ejercicio4.sh "lemoncode" || true
echo
./ejercicio4.sh "patata" || true
echo

echo "Fichero descargado por ejercicio4.sh:"
ls -la ejercicio4_page.html 2>/dev/null || echo "No se ha creado ejercicio4_page.html"
echo

echo "========================================"
echo "Ejercicio 5 opcional"
echo "========================================"

cat > ejercicio5.sh <<'EOF'
#!/usr/bin/env bash

OUTPUT_FILE="ejercicio5_page.html"

if [[ $# -ne 2 ]]; then
  echo "Se necesitan únicamente dos parámetros para ejecutar este script"
  exit 1
fi

URL="$1"
WORD="$2"

if [[ -z "$URL" || -z "$WORD" ]]; then
  echo "Se necesitan únicamente dos parámetros para ejecutar este script"
  exit 1
fi

download_page() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$URL" -o "$OUTPUT_FILE"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$URL" -O "$OUTPUT_FILE"
  else
    echo "Se necesita curl o wget para descargar la página"
    exit 1
  fi
}

download_page

COUNT=$(grep -oiF -- "$WORD" "$OUTPUT_FILE" | wc -l | tr -d ' ')
FIRST_LINE=$(grep -niF -- "$WORD" "$OUTPUT_FILE" | head -n 1 | cut -d ':' -f 1 || true)

if [[ "$COUNT" -eq 0 ]]; then
  echo "No se ha encontrado la palabra \"$WORD\""
elif [[ "$COUNT" -eq 1 ]]; then
  echo "La palabra \"$WORD\" aparece 1 vez"
  echo "Aparece únicamente en la línea $FIRST_LINE"
else
  echo "La palabra \"$WORD\" aparece $COUNT veces"
  echo "Aparece por primera vez en la línea $FIRST_LINE"
fi
EOF

chmod +x ejercicio5.sh

echo "Script ejercicio5.sh creado:"
ls -la ejercicio5.sh
echo

echo "Probando llamada incorrecta con tres parámetros:"
./ejercicio5.sh "https://lemoncode.net/" "patata" "27" || true
echo

echo "Probando llamada correcta:"
./ejercicio5.sh "https://lemoncode.net/" "lemoncode" || true
echo
./ejercicio5.sh "https://lemoncode.net/" "politica" || true

echo "Fichero descargado por ejercicio5.sh:"
ls -la ejercicio5_page.html 2>/dev/null || echo "No se ha creado ejercicio5_page.html"
echo

echo "========================================"
echo "Todo terminado"
echo "========================================"

echo "Scripts generados:"
ls -la ejercicio3.sh ejercicio4.sh ejercicio5.sh
echo

echo "Estado final de foo:"
show_structure "foo"
