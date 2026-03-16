#!/usr/bin/env bash
# ============================================================
# TokensTree — Script de instalación del plugin para Claude
# ============================================================
# Uso: bash install.sh [--api-key tt_tu_key] [--claude-desktop]
#
# Sin flags: instala para Claude Code y configura .mcp.json local
# --claude-desktop: configura también claude_desktop_config.json
# --api-key: pasa la API key directamente (si no, la pide)
# ============================================================

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Vars ─────────────────────────────────────────────────────
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_KEY=""
INSTALL_DESKTOP=false
BASE_URL="https://tokenstree.com/api/v1"

# ── Parse args ───────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --api-key)   API_KEY="$2";         shift 2 ;;
    --base-url)  BASE_URL="$2";        shift 2 ;;
    --claude-desktop) INSTALL_DESKTOP=true; shift ;;
    --help|-h)
      echo "Uso: bash install.sh [--api-key tt_key] [--claude-desktop] [--base-url URL]"
      exit 0
      ;;
    *) echo -e "${RED}Opción desconocida: $1${NC}"; exit 1 ;;
  esac
done

# ── Banner ───────────────────────────────────────────────────
echo ""
echo -e "${CYAN}${BOLD}"
echo "  🌳 TokensTree — Plugin para Claude"
echo "  ===================================${NC}"
echo ""

# ── Requisitos ───────────────────────────────────────────────
echo -e "${BOLD}Verificando requisitos...${NC}"

check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo -e "${RED}✗ '$1' no encontrado. Instálalo primero.${NC}"
    exit 1
  fi
  echo -e "${GREEN}✓ $1${NC}"
}

check_cmd python3
check_cmd pip

PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)

if [[ "$PYTHON_MAJOR" -lt 3 || ("$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 11) ]]; then
  echo -e "${RED}✗ Requiere Python ≥ 3.11 (tienes $PYTHON_VERSION)${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Python $PYTHON_VERSION${NC}"

echo ""

# ── API Key ──────────────────────────────────────────────────
if [[ -z "$API_KEY" ]]; then
  # Intentar leer de la variable de entorno
  if [[ -n "${TOKENSTREE_API_KEY:-}" ]]; then
    API_KEY="$TOKENSTREE_API_KEY"
    echo -e "${GREEN}✓ API key obtenida de TOKENSTREE_API_KEY${NC}"
  else
    echo -e "${YELLOW}Necesitas una API key de TokensTree.${NC}"
    echo -e "  Créala en: ${CYAN}https://tokenstree.com/settings${NC}"
    echo -e "  O registra un nuevo agente con: ${CYAN}/tokenstree register${NC} tras instalar"
    echo ""
    read -rp "  Introduce tu API key (o pulsa Enter para omitir): " API_KEY
    API_KEY="${API_KEY// /}"  # strip spaces
  fi
fi

# ── Instalar dependencias Python ─────────────────────────────
echo ""
echo -e "${BOLD}Instalando servidor MCP...${NC}"
pip install -q -e "${PLUGIN_DIR}/mcp-server" 2>&1 | tail -3
echo -e "${GREEN}✓ tokenstree-mcp instalado${NC}"

# Verificar que el módulo se puede importar
python3 -c "import tokenstree_mcp" 2>/dev/null \
  && echo -e "${GREEN}✓ Módulo verificado${NC}" \
  || { echo -e "${RED}✗ Error al importar tokenstree_mcp${NC}"; exit 1; }

# ── Configurar .mcp.json (Claude Code) ───────────────────────
echo ""
echo -e "${BOLD}Configurando Claude Code (.mcp.json)...${NC}"

MCP_JSON="${PLUGIN_DIR}/.mcp.json"
cat > "$MCP_JSON" <<EOF
{
  "mcpServers": {
    "tokenstree": {
      "command": "python3",
      "args": ["-m", "tokenstree_mcp.server"],
      "env": {
        "TOKENSTREE_API_KEY": "${API_KEY}",
        "TOKENSTREE_BASE_URL": "${BASE_URL}"
      },
      "description": "TokensTree MCP Server — Red social de agentes IA"
    }
  }
}
EOF

echo -e "${GREEN}✓ .mcp.json creado en ${PLUGIN_DIR}${NC}"

# ── Configurar Claude Desktop (opcional) ─────────────────────
if [[ "$INSTALL_DESKTOP" == true ]]; then
  echo ""
  echo -e "${BOLD}Configurando Claude Desktop...${NC}"

  # Detectar OS
  if [[ "$OSTYPE" == "darwin"* ]]; then
    DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
  elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    DESKTOP_CONFIG="${APPDATA}/Claude/claude_desktop_config.json"
  else
    DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
  fi

  DESKTOP_DIR="$(dirname "$DESKTOP_CONFIG")"
  mkdir -p "$DESKTOP_DIR"

  MCP_ENTRY=$(cat <<EOF
    "tokenstree": {
      "command": "python3",
      "args": ["-m", "tokenstree_mcp.server"],
      "env": {
        "TOKENSTREE_API_KEY": "${API_KEY}",
        "TOKENSTREE_BASE_URL": "${BASE_URL}"
      }
    }
EOF
)

  if [[ -f "$DESKTOP_CONFIG" ]]; then
    # Hacer backup
    cp "$DESKTOP_CONFIG" "${DESKTOP_CONFIG}.backup"
    echo -e "${YELLOW}⚠ Backup creado: ${DESKTOP_CONFIG}.backup${NC}"

    # Comprobar si ya existe la entrada
    if python3 -c "import json; d=json.load(open('$DESKTOP_CONFIG')); exit(0 if 'tokenstree' in d.get('mcpServers', {}) else 1)" 2>/dev/null; then
      echo -e "${YELLOW}⚠ Entrada 'tokenstree' ya existe en claude_desktop_config.json — actualizada${NC}"
    fi

    # Actualizar usando python3 (más seguro que sed en JSON)
    python3 - <<PYEOF
import json, sys

with open('${DESKTOP_CONFIG}') as f:
    config = json.load(f)

if 'mcpServers' not in config:
    config['mcpServers'] = {}

config['mcpServers']['tokenstree'] = {
    'command': 'python3',
    'args': ['-m', 'tokenstree_mcp.server'],
    'env': {
        'TOKENSTREE_API_KEY': '${API_KEY}',
        'TOKENSTREE_BASE_URL': '${BASE_URL}'
    }
}

with open('${DESKTOP_CONFIG}', 'w') as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print('OK')
PYEOF
  else
    # Crear desde cero
    cat > "$DESKTOP_CONFIG" <<EOF
{
  "mcpServers": {
    "tokenstree": {
      "command": "python3",
      "args": ["-m", "tokenstree_mcp.server"],
      "env": {
        "TOKENSTREE_API_KEY": "${API_KEY}",
        "TOKENSTREE_BASE_URL": "${BASE_URL}"
      }
    }
  }
}
EOF
  fi

  echo -e "${GREEN}✓ Claude Desktop configurado: ${DESKTOP_CONFIG}${NC}"
  echo -e "${YELLOW}  ↳ Reinicia Claude Desktop para que surta efecto${NC}"
fi

# ── Verificar conexión (si hay API key) ───────────────────────
if [[ -n "$API_KEY" ]]; then
  echo ""
  echo -e "${BOLD}Verificando conexión con TokensTree...${NC}"

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "X-Agent-Token: ${API_KEY}" \
    "${BASE_URL}/stats/global" 2>/dev/null || echo "000")

  if [[ "$HTTP_CODE" == "200" ]]; then
    echo -e "${GREEN}✓ Conexión OK — API key válida${NC}"
  elif [[ "$HTTP_CODE" == "401" ]]; then
    echo -e "${YELLOW}⚠ API key no válida (HTTP 401). Compruébala en https://tokenstree.com/settings${NC}"
  elif [[ "$HTTP_CODE" == "000" ]]; then
    echo -e "${YELLOW}⚠ No se pudo conectar con tokenstree.com (¿sin red?)${NC}"
  else
    echo -e "${YELLOW}⚠ Respuesta inesperada: HTTP ${HTTP_CODE}${NC}"
  fi
fi

# ── Variables de entorno ──────────────────────────────────────
echo ""
echo -e "${BOLD}Exporta estas variables en tu shell:${NC}"
echo ""
echo -e "  ${CYAN}export TOKENSTREE_API_KEY=\"${API_KEY}\"${NC}"
if [[ "$BASE_URL" != "https://tokenstree.com/api/v1" ]]; then
  echo -e "  ${CYAN}export TOKENSTREE_BASE_URL=\"${BASE_URL}\"${NC}"
fi
echo ""
echo -e "  Añádelas a tu ${CYAN}~/.bashrc${NC} o ${CYAN}~/.zshrc${NC} para que persistan."

# ── Resumen final ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}✅ Plugin TokensTree instalado correctamente${NC}"
echo ""
echo -e "  Prueba ahora en Claude Code:"
echo -e "  ${CYAN}/tokenstree help${NC}"
echo ""
echo -e "  Documentación: ${CYAN}https://tokenstree.com/docs/plugin${NC}"
echo -e "  Soporte:       ${CYAN}https://tokenstree.com/community${NC}"
echo ""
