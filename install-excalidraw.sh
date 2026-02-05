#!/bin/bash

# ============================================================================
# УСТАНОВЩИК EXCALIDRAW С СОВМЕСТНОЙ РАБОТОЙ
# Версия: 2.0 - Оптимизированный порядок установки
# ============================================================================

set -e

# ============================================================================
# КОНФИГУРАЦИЯ
# ============================================================================
SERVER_IP="10.100.100.162"
WORKDIR="$HOME/excalidraw-server"
FRONTEND_PORT="4173"
BACKEND_PORT="8444"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}➜ $1${NC}"
}

# ============================================================================
# ПРОВЕРКА ПРАВ
# ============================================================================
print_header "УСТАНОВКА EXCALIDRAW С СОВМЕСТНОЙ РАБОТОЙ"
echo -e "${BLUE}Версия: 2.0${NC}"
echo -e "${BLUE}Дата: $(date)${NC}"

if [ "$EUID" -eq 0 ]; then 
    print_error "Не запускайте скрипт от root! Используйте обычного пользователя."
    exit 1
fi

# ============================================================================
# 1. ОБНОВЛЕНИЕ СИСТЕМЫ И УСТАНОВКА ЗАВИСИМОСТЕЙ
# ============================================================================
print_header "1. УСТАНОВКА СИСТЕМНЫХ ЗАВИСИМОСТЕЙ"

print_info "Обновление пакетов..."
sudo apt update && sudo apt upgrade -y

print_info "Установка системных пакетов..."
sudo apt install -y \
    curl \
    wget \
    git \
    build-essential \
    libssl-dev \
    ca-certificates \
    python3 \
    python3-pip \
    net-tools \
    openssl

print_success "Системные зависимости установлены"

# ============================================================================
# 2. УСТАНОВКА NODE.JS ЧЕРЕЗ NVM
# ============================================================================
print_header "2. УСТАНОВКА NODE.JS И NPM"

if [ ! -d "$HOME/.nvm" ]; then
    print_info "Установка nvm..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash > /dev/null 2>&1
    
    # Загрузка nvm в текущую сессию
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    
    print_success "nvm установлен"
fi

# Перезагружаем nvm для текущей сессии
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

print_info "Установка Node.js 18..."
nvm install 18 > /dev/null 2>&1
nvm use 18 > /dev/null 2>&1
nvm alias default 18 > /dev/null 2>&1

print_success "Node.js $(node --version) установлен"
print_success "npm $(npm --version) установлен"

# ============================================================================
# 3. ПОДГОТОВКА РАБОЧЕЙ ДИРЕКТОРИИ
# ============================================================================
print_header "3. ПОДГОТОВКА РАБОЧЕЙ ДИРЕКТОРИИ"

if [ -d "$WORKDIR" ]; then
    print_warning "Директория $WORKDIR уже существует"
    read -p "Удалить и переустановить? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Удаление старой директории..."
        rm -rf "$WORKDIR"
    else
        print_info "Использую существующую директорию..."
    fi
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

print_success "Рабочая директория: $WORKDIR"

# ============================================================================
# 4. КЛОНИРОВАНИЕ И УСТАНОВКА EXCALIDRAW
# ============================================================================
print_header "4. УСТАНОВКА EXCALIDRAW"

print_info "Клонирование Excalidraw v0.17.6..."
git clone --depth 1 --branch v0.17.6 https://github.com/excalidraw/excalidraw.git . > /dev/null 2>&1

print_info "Установка зависимостей (это может занять несколько минут)..."
npm install --legacy-peer-deps > /dev/null 2>&1
print_success "Зависимости Excalidraw установлены"

# ============================================================================
# 5. СОЗДАНИЕ SSL СЕРТИФИКАТОВ
# ============================================================================
print_header "5. СОЗДАНИЕ SSL СЕРТИФИКАТОВ"

mkdir -p ssl
cd ssl

print_info "Генерация самоподписанных сертификатов..."
openssl req -x509 -newkey rsa:4096 -keyout key.pem -out cert.pem \
    -days 365 -nodes -subj "/C=RU/ST=Moscow/L=Moscow/O=Company/CN=$SERVER_IP" > /dev/null 2>&1

cd ..
print_success "SSL сертификаты созданы в $WORKDIR/ssl/"

# ============================================================================
# 6. НАСТРОЙКА БЭКЕНДА (SOCKET.IO СЕРВЕР)
# ============================================================================
print_header "6. НАСТРОЙКА БЭКЕНДА СОВМЕСТНОЙ РАБОТЫ"

mkdir -p excalidraw-room
cd excalidraw-room

cat > package.json << 'EOF'
{
  "name": "excalidraw-room",
  "version": "1.0.0",
  "description": "Backend for Excalidraw collaboration",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "cors": "^2.8.5",
    "https": "^1.0.0",
    "socket.io": "^4.5.4",
    "ws": "^8.13.0",
    "dotenv": "^16.0.3"
  }
}
EOF

print_info "Установка зависимостей бэкенда..."
npm install > /dev/null 2>&1

cat > server.js << EOF
const { createServer } = require('https');
const { readFileSync } = require('fs');
const { resolve } = require('path');
const express = require('express');
const cors = require('cors');
const { Server } = require('socket.io');

const PORT = $BACKEND_PORT;
const SSL_DIR = resolve(__dirname, '../ssl');

const app = express();

app.use(cors({
    origin: ['https://$SERVER_IP:$FRONTEND_PORT', 'https://localhost:$FRONTEND_PORT'],
    credentials: true,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));

app.options('*', cors());

app.get('/health', (req, res) => {
    res.json({
        status: 'ok',
        service: 'excalidraw-room',
        timestamp: new Date().toISOString()
    });
});

const options = {
    key: readFileSync(resolve(SSL_DIR, 'key.pem')),
    cert: readFileSync(resolve(SSL_DIR, 'cert.pem')),
    requestCert: false,
    rejectUnauthorized: false
};

const server = createServer(options, app);
const io = new Server(server, {
    cors: {
        origin: ['https://$SERVER_IP:$FRONTEND_PORT', 'https://localhost:$FRONTEND_PORT'],
        credentials: true
    },
    path: '/socket.io/'
});

const rooms = new Map();

io.on('connection', (socket) => {
    console.log('Клиент подключен:', socket.id);

    socket.on('join-room', (roomId, username) => {
        socket.join(roomId);
        
        if (!rooms.has(roomId)) {
            rooms.set(roomId, new Set());
        }
        rooms.get(roomId).add(socket.id);
        
        console.log(\`\${username} присоединился к комнате \${roomId}\`);
        socket.to(roomId).emit('user-joined', { userId: socket.id, username });
        
        const users = Array.from(rooms.get(roomId)).map(id => ({
            userId: id,
            username: id === socket.id ? username : 'Пользователь'
        }));
        socket.emit('room-users', users);
    });

    socket.on('server-broadcast', (roomId, data) => {
        socket.to(roomId).emit('client-broadcast', data);
    });

    socket.on('excalidraw-room', (roomId, data) => {
        socket.to(roomId).emit('excalidraw-room', data);
    });

    socket.on('leave-room', (roomId) => {
        socket.leave(roomId);
        if (rooms.has(roomId)) {
            rooms.get(roomId).delete(socket.id);
            if (rooms.get(roomId).size === 0) {
                rooms.delete(roomId);
            }
        }
        socket.to(roomId).emit('user-left', { userId: socket.id });
    });

    socket.on('disconnect', () => {
        console.log('Клиент отключен:', socket.id);
        for (const [roomId, users] of rooms.entries()) {
            if (users.has(socket.id)) {
                users.delete(socket.id);
                socket.to(roomId).emit('user-left', { userId: socket.id });
                if (users.size === 0) {
                    rooms.delete(roomId);
                }
            }
        }
    });
});

server.listen(PORT, '0.0.0.0', () => {
    console.log(\`Excalidraw Room Server запущен на https://0.0.0.0:\${PORT}\`);
    console.log(\`Health check: https://$SERVER_IP:\${PORT}/health\`);
    console.log(\`WebSocket: wss://$SERVER_IP:\${PORT}/socket.io/\`);
});

server.on('error', (error) => {
    console.error('Ошибка сервера:', error);
});
EOF

print_success "Бэкенд настроен"
cd ..

# ============================================================================
# 7. НАСТРОЙКА ФРОНТЕНДА
# ============================================================================
print_header "7. НАСТРОЙКА ФРОНТЕНДА"

print_info "Создание конфигурационных файлов..."

# Создаем index.html
cat > index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <title>Excalidraw | Hand-drawn look & feel • Collaborative • Secure</title>
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover, shrink-to-fit=no" />
    <meta name="referrer" content="origin" />
    <meta name="mobile-web-app-capable" content="yes" />
    <meta name="theme-color" content="#121212" />
    <meta name="description" content="Excalidraw is a virtual collaborative whiteboard tool that lets you easily sketch diagrams that have a hand-drawn feel to them." />
    
    <script>
      try {
        const theme = window.localStorage.getItem("excalidraw-theme");
        if (theme === "dark") {
          document.documentElement.classList.add("dark");
        }
      } catch {}
    </script>
    
    <style>
      html.dark {
        background-color: #121212;
        color: #fff;
      }
      
      body, html {
        margin: 0;
        -webkit-text-size-adjust: 100%;
        width: 100%;
        height: 100%;
        overflow: hidden;
      }
      
      .visually-hidden {
        position: absolute !important;
        height: 1px;
        width: 1px;
        overflow: hidden;
        clip: rect(1px, 1px, 1px, 1px);
        white-space: nowrap;
        user-select: none;
      }
      
      #root {
        height: 100%;
        -webkit-touch-callout: none;
        -webkit-user-select: none;
        -khtml-user-select: none;
        -moz-user-select: none;
        -ms-user-select: none;
        user-select: none;
      }
      
      @media screen and (min-width: 1200px) {
        #root {
          -webkit-touch-callout: default;
          -webkit-user-select: auto;
          -khtml-user-select: auto;
          -moz-user-select: auto;
          -ms-user-select: auto;
          user-select: auto;
        }
      }
    </style>
    
    <link rel="apple-touch-icon" sizes="180x180" href="/apple-touch-icon.png" />
    <link rel="icon" type="image/png" sizes="32x32" href="/favicon-32x32.png" />
    <link rel="icon" type="image/png" sizes="16x16" href="/favicon-16x16.png" />
    <meta name="version" content="dev" />
    
    <link rel="preload" href="/Virgil.woff2" as="font" type="font/woff2" crossorigin="anonymous" />
    <link rel="preload" href="/Cascadia.woff2" as="font" type="font/woff2" crossorigin="anonymous" />
    <link rel="stylesheet" href="/fonts.css" type="text/css" />
    
    <script>
      window.EXCALIDRAW_ASSET_PATH = "/";
      window.name = "_excalidraw";
      window.env = {
        VITE_APP_SOCKET_SERVER_URL: "https://10.100.100.162:8444",
        VITE_APP_BACKEND_V1_GET_URL: "https://10.100.100.162:8444",
        VITE_APP_BACKEND_V2_GET_URL: "https://10.100.100.162:8444",
        VITE_APP_BACKEND_V2_POST_URL: "https://10.100.100.162:8444",
        VITE_APP_FIREBASE_CONFIG: "{}"
      };
    </script>
  </head>
  
  <body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <header>
      <h1 class="visually-hidden">Excalidraw</h1>
    </header>
    <div id="root"></div>
    <script type="module" src="/src/index.tsx"></script>
  </body>
</html>
EOF

# Создаем .env файл
cat > .env << EOF
VITE_APP_BACKEND_V1_GET_URL=https://$SERVER_IP:$BACKEND_PORT
VITE_APP_BACKEND_V2_GET_URL=https://$SERVER_IP:$BACKEND_PORT
VITE_APP_BACKEND_V2_POST_URL=https://$SERVER_IP:$BACKEND_PORT
VITE_APP_SOCKET_SERVER_URL=https://$SERVER_IP:$BACKEND_PORT
VITE_APP_FIREBASE_CONFIG={}
VITE_APP_PORT=$FRONTEND_PORT
VITE_APP_HTTPS=true
VITE_APP_WS_PROTOCOL=wss
EOF

# Дополнительный env файл
cat > .env.development << EOF
VITE_APP_BACKEND_V2_GET_URL=https://$SERVER_IP:$BACKEND_PORT
VITE_APP_BACKEND_V2_POST_URL=https://$SERVER_IP:$BACKEND_PORT

VITE_APP_LIBRARY_URL=https://libraries.excalidraw.com
VITE_APP_LIBRARY_BACKEND=https://us-central1-excalidraw-room-persistence.cloudfunctions.net/libraries

# collaboration WebSocket server (https://github.com/excalidraw/excalidraw-room)
VITE_APP_WS_SERVER_URL=https://$SERVER_IP:$BACKEND_PORT

# set this only if using the collaboration workflow we use on excalidraw.com
VITE_APP_PORTAL_URL=

VITE_APP_PLUS_LP=https://plus.excalidraw.com
VITE_APP_PLUS_APP=https://app.excalidraw.com

VITE_APP_FIREBASE_CONFIG='{"apiKey":"AIzaSyCMkxA60XIW8KbqMYL7edC4qT5l4qHX2h8","authDomain":"excalidraw-oss-dev.firebaseapp.com","projectId":"excalidraw-oss-dev","storageBucket":"excalidraw-oss-dev.appspot.com","messagingSenderId":"1045469430677","appId":"1:1045469430677:web:81eb65dac2de398ce2c16b","measurementId":"G-8XGF4KFY62"}'

# put these in your .env.local, or make sure you don't commit!
# must be lowercase `true` when turned on
#
# whether to enable Service Workers in development
VITE_APP_DEV_ENABLE_SW=
# whether to disable live reload / HMR. Usuaully what you want to do when
# debugging Service Workers.
VITE_APP_DEV_DISABLE_LIVE_RELOAD=
VITE_APP_DISABLE_TRACKING=true

FAST_REFRESH=false

# The port the run the dev server
VITE_APP_PORT=$FRONTEND_PORT

#Debug flags

# To enable bounding box for text containers
VITE_APP_DEBUG_ENABLE_TEXT_CONTAINER_BOUNDING_BOX=

# Set this flag to false if you want to open the overlay by default
VITE_APP_COLLAPSE_OVERLAY=true

# Set this flag to false to disable eslint
VITE_APP_ENABLE_ESLINT=true

# HTTPS for local development
VITE_APP_HTTPS=true
EOF

# Создаем vite.config.ts
cat > vite.config.ts << 'EOF'
import { defineConfig, loadEnv } from "vite";
import react from "@vitejs/plugin-react";
import { VitePWA } from "vite-plugin-pwa";
import svgr from "vite-plugin-svgr";
import checker from "vite-plugin-checker";
import { readFileSync } from 'fs';
import { resolve } from 'path';

const SSL_DIR = resolve(__dirname, './ssl');

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");

  return {
    plugins: [
      react(),
      svgr(),
      VitePWA({
        registerType: "autoUpdate",
        workbox: {
          globPatterns: ["**/*.{js,css,html,ico,png,svg,woff2}"],
          navigateFallback: null,
        },
      }),
      checker({
        typescript: true,
      }),
    ],
    server: {
      port: parseInt(env.VITE_APP_PORT) || 4173,
      host: "0.0.0.0",
      https: {
        key: readFileSync(resolve(SSL_DIR, 'key.pem')),
        cert: readFileSync(resolve(SSL_DIR, 'cert.pem'))
      },
      cors: {
        origin: ['https://10.100.100.162:4173', 'https://localhost:4173'],
        credentials: true
      },
    },
    build: {
      sourcemap: false,
      rollupOptions: {
        input: {
          main: resolve(__dirname, 'index.html')
        },
        output: {
          manualChunks: undefined,
        },
      },
    },
    define: {
      "process.env": env,
    },
  };
});
EOF

# Создаем fonts.css если его нет
mkdir -p public
cat > public/fonts.css << 'EOF'
@font-face {
  font-family: "Virgil";
  src: url("/Virgil.woff2") format("woff2");
  font-display: swap;
}

@font-face {
  font-family: "Cascadia";
  src: url("/Cascadia.woff2") format("woff2");
  font-display: swap;
}
EOF

# Фиксим проблему с PWA в исходном коде
if [ -f "src/index.tsx" ]; then
    print_info "Исправление проблемы с PWA..."
    sed -i "s|import { registerSW } from \"virtual:pwa-register\";|// import { registerSW } from \"virtual:pwa-register\";|g" src/index.tsx
    sed -i "s|registerSW();|// registerSW();|g" src/index.tsx
    print_success "Проблема с PWA исправлена"
fi

print_success "Фронтенд настроен"

# ============================================================================
# 8. СОЗДАНИЕ СКРИПТОВ УПРАВЛЕНИЯ
# ============================================================================
print_header "8. СОЗДАНИЕ СКРИПТОВ УПРАВЛЕНИЯ"

# Скрипт запуска всей системы
cat > start-all.sh << EOF
#!/bin/bash
cd "$WORKDIR"
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}🚀 ЗАПУСК EXCALIDRAW${NC}"
echo -e "${BLUE}========================================${NC}"

# Останавливаем старые процессы
echo "Останавливаем старые процессы..."
pkill -f "node server.js" 2>/dev/null || true
pkill -f "vite" 2>/dev/null || true
pkill -f "npm start" 2>/dev/null || true
pkill -f "npm run dev" 2>/dev/null || true
sleep 2

echo ""
echo "1. Запуск бэкенда для совместной работы..."
source ~/.nvm/nvm.sh
nvm use 18
cd excalidraw-room
nohup node server.js > ../backend.log 2>&1 &
BACKEND_PID=\$!
echo "   ✅ Бэкенд запущен (PID: \$BACKEND_PID)"
cd ..

sleep 3

echo ""
echo "2. Проверка бэкенда..."
if curl -k -s https://$SERVER_IP:$BACKEND_PORT/health > /dev/null; then
    echo "   ✅ Бэкенд работает"
else
    echo "   ❌ Бэкенд не отвечает"
fi

echo ""
echo "3. Запуск фронтенда..."
export NODE_OPTIONS="--openssl-legacy-provider"
nohup npm start -- --host 0.0.0.0 > frontend.log 2>&1 &
FRONTEND_PID=\$!
echo "   ✅ Фронтенд запущен (PID: \$FRONTEND_PID)"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ СИСТЕМА ЗАПУЩЕНА!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "🌐 Фронтенд: https://$SERVER_IP:$FRONTEND_PORT"
echo "🔧 Бэкенд:   https://$SERVER_IP:$BACKEND_PORT"
echo "📊 Health:   https://$SERVER_IP:$BACKEND_PORT/health"
echo ""
echo "🤝 СОВМЕСТНАЯ РАБОТА:"
echo "   1. Откройте https://$SERVER_IP:$FRONTEND_PORT"
echo "   2. Нажмите 'Начать сеанс' → 'Создать комнату'"
echo "   3. Скопируйте ссылку из адресной строки"
echo "   4. Отправьте ссылку коллегам"
echo ""
echo "⚠️  ВАЖНО: Примите самоподписанный сертификат!"
echo "   'Дополнительно' → 'Перейти на сайт (небезопасно)'"
echo ""
echo "📊 КОМАНДЫ УПРАВЛЕНИЯ:"
echo "   • Статус:    ./check-status.sh"
echo "   • Логи:      tail -f frontend.log"
echo "   • Остановка: ./stop-all.sh"
echo ""
EOF

# Скрипт проверки статуса
cat > check-status.sh << EOF
#!/bin/bash
cd "$WORKDIR"
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}📊 ПРОВЕРКА СТАТУСА EXCALIDRAW${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo "1. Проверка бэкенда (порт $BACKEND_PORT):"
if curl -k -s https://$SERVER_IP:$BACKEND_PORT/health > /dev/null; then
    echo -e "   ${GREEN}✅ Бэкенд работает${NC}"
    echo "   Ответ:"
    curl -k https://$SERVER_IP:$BACKEND_PORT/health 2>/dev/null | head -3 || echo "   Не удалось получить данные"
else
    echo -e "   ${RED}❌ Бэкенд не отвечает${NC}"
fi

echo ""
echo "2. Проверка фронтенда (порт $FRONTEND_PORT):"
if curl -k -s https://$SERVER_IP:$FRONTEND_PORT > /dev/null; then
    echo -e "   ${GREEN}✅ Фронтенд работает${NC}"
else
    echo -e "   ${RED}❌ Фронтенд не отвечает${NC}"
fi

echo ""
echo "3. Проверка процессов:"
echo "   Бэкенд:"
if pgrep -f "node server.js" > /dev/null; then
    echo -e "   ${GREEN}✅ Процесс найден${NC}"
else
    echo -e "   ${RED}❌ Процесс не найден${NC}"
fi
echo "   Фронтенд:"
if pgrep -f "vite" > /dev/null; then
    echo -e "   ${GREEN}✅ Процесс найден${NC}"
else
    echo -e "   ${RED}❌ Процесс не найден${NC}"
fi

echo ""
echo "4. Использование портов:"
echo "   Порт $BACKEND_PORT (бэкенд):"
if netstat -tlnp 2>/dev/null | grep -q ":$BACKEND_PORT"; then
    echo -e "   ${GREEN}✅ Порт слушается${NC}"
else
    echo -e "   ${RED}❌ Порт не слушается${NC}"
fi
echo "   Порт $FRONTEND_PORT (фронтенд):"
if netstat -tlnp 2>/dev/null | grep -q ":$FRONTEND_PORT"; then
    echo -e "   ${GREEN}✅ Порт слушается${NC}"
else
    echo -e "   ${RED}❌ Порт не слушается${NC}"
fi

echo ""
echo "5. Логи (последние 5 строк):"
echo "   Бэкенд лог:"
tail -5 backend.log 2>/dev/null || echo "   Файл лога не найден"
echo ""
echo "   Фронтенд лог:"
tail -5 frontend.log 2>/dev/null || echo "   Файл лога не найден"
EOF

# Скрипт остановки
cat > stop-all.sh << EOF
#!/bin/bash
cd "$WORKDIR"
echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}🛑 ОСТАНОВКА EXCALIDRAW${NC}"
echo -e "${BLUE}========================================${NC}"

echo ""
echo "Останавливаю процессы..."
pkill -f "node server.js" 2>/dev/null && echo -e "   ${GREEN}✅ Бэкенд остановлен${NC}" || echo -e "   ${YELLOW}⚠ Бэкенд не запущен${NC}"
pkill -f "vite" 2>/dev/null && echo -e "   ${GREEN}✅ Фронтенд остановлен${NC}" || echo -e "   ${YELLOW}⚠ Фронтенд не запущен${NC}"
pkill -f "npm start" 2>/dev/null && echo -e "   ${GREEN}✅ Процессы npm остановлены${NC}" || echo -e "   ${YELLOW}⚠ Процессы npm не найдены${NC}"
sleep 2

echo ""
echo -e "${GREEN}✅ Все процессы остановлены${NC}"
EOF

# Скрипт запуска бэкенда
cat > start-backend.sh << 'EOF'
#!/bin/bash
cd "$WORKDIR/excalidraw-room"
echo -e "\n${BLUE}🔧 ЗАПУСК БЭКЕНДА EXCALIDRAW${NC}"
echo "   Сервер: https://10.100.100.162:8444"
echo "   WebSocket: wss://10.100.100.162:8444/socket.io/"
source ~/.nvm/nvm.sh
nvm use 18
node server.js
EOF

# Скрипт запуска фронтенда
cat > start-frontend.sh << 'EOF'
#!/bin/bash
cd "$WORKDIR"
echo -e "\n${BLUE}🎨 ЗАПУСК ФРОНТЕНДА EXCALIDRAW${NC}"
echo "   Приложение: https://10.100.100.162:4173"
echo "   Для совместной работы: https://10.100.100.162:4173/#room=..."
source ~/.nvm/nvm.sh
nvm use 18
export NODE_OPTIONS="--openssl-legacy-provider"
npm start -- --host 0.0.0.0
EOF

# Делаем скрипты исполняемыми
chmod +x start-all.sh start-backend.sh start-frontend.sh check-status.sh stop-all.sh

# ============================================================================
# 9. ДОБАВЛЕНИЕ АЛИАСОВ В .BASHRC
# ============================================================================
print_header "9. ДОБАВЛЕНИЕ КОМАНД ДЛЯ УПРАВЛЕНИЯ"

cat >> ~/.bashrc << EOF

# ============================================
# Алиасы для управления Excalidraw
# ============================================
export EXCALIDRAW_HOME="$WORKDIR"
alias exc-start="cd \$EXCALIDRAW_HOME && ./start-all.sh"
alias exc-status="cd \$EXCALIDRAW_HOME && ./check-status.sh"
alias exc-stop="cd \$EXCALIDRAW_HOME && ./stop-all.sh"
alias exc-backend="cd \$EXCALIDRAW_HOME && ./start-backend.sh"
alias exc-frontend="cd \$EXCALIDRAW_HOME && ./start-frontend.sh"
alias exc-logs="cd \$EXCALIDRAW_HOME && tail -f frontend.log backend.log"
alias exc-log-backend="cd \$EXCALIDRAW_HOME && tail -f backend.log"
alias exc-log-frontend="cd \$EXCALIDRAW_HOME && tail -f frontend.log"

echo "✅ Excalidraw алиасы добавлены:"
echo "   exc-start       - запуск всей системы"
echo "   exc-status      - проверка статуса"
echo "   exc-stop        - остановка системы"
echo "   exc-logs        - просмотр всех логов"
echo "   exc-log-backend - просмотр логов бэкенда"
echo "   exc-log-frontend - просмотр логов фронтенда"
echo "   exc-backend     - запуск только бэкенда"
echo "   exc-frontend    - запуск только фронтенда"
EOF

print_success "Алиасы добавлены в ~/.bashrc"

# ============================================================================
# ЗАВЕРШЕНИЕ УСТАНОВКИ
# ============================================================================
print_header "✅ УСТАНОВКА ЗАВЕРШЕНА"

echo "🎉 ВСЁ ГОТОВО! Для запуска выполните:"
echo ""
echo "   cd $WORKDIR"
echo "   ./start-all.sh"
echo ""
echo "🔧 ИЛИ ПОСЛЕ ПЕРЕЗАГРУЗКИ ТЕРМИНАЛА:"
echo "   exc-start     - запуск всей системы"
echo "   exc-status    - проверка статуса"
echo "   exc-stop      - остановка системы"
echo "   exc-logs      - просмотр логов"
echo ""
echo "⚠️  ПЕРЕД ПЕРВЫМ ЗАПУСКОМ ПЕРЕЗАГРУЗИТЕ ТЕРМИНАЛ:"
echo "   source ~/.bashrc"
echo ""
echo "================================================================"
echo "📞 При возникновении проблем проверьте:"
echo "   • Файлы логов: frontend.log и backend.log"
echo "   • Наличие процессов: ps aux | grep -E '(node|vite)'"
echo "   • Доступность портов: netstat -tlnp | grep -E '(4173|8444)'"
echo "================================================================"