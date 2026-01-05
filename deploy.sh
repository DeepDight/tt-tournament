#!/usr/bin/env bash
set -e

echo "=== TT Tournament auto-deploy started ==="

# -----------------------------
# Проверка root
# -----------------------------
if [ "$EUID" -ne 0 ]; then
  echo "❌ Запусти скрипт через sudo"
  exit 1
fi

# -----------------------------
# Переменные
# -----------------------------
REPO_URL="https://github.com/DeepDight/tt-tournament.git"
REPO_BRANCH="instdockervpsnginx"
APP_DIR="/opt/tt-tournament"

APP_NAME="tt-app"
POSTGRES_CONTAINER="tt-postgres"
NGINX_CONTAINER="tt-nginx"
NETWORK="tt-network"
VOLUME="tt-postgres-data"

POSTGRES_DB="tt_tournament"
POSTGRES_USER="tournament_user"
POSTGRES_PORT="5433"

# -----------------------------
# Обновление системы
# -----------------------------
echo ">>> Обновление системы"
apt update && apt upgrade -y

# -----------------------------
# Установка базовых пакетов
# -----------------------------
echo ">>> Установка базовых пакетов"
apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  git

# -----------------------------
# Установка Docker
# -----------------------------
if ! command -v docker &> /dev/null; then
  echo ">>> Установка Docker"

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt update
  apt install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin \
    docker.io
fi

# -----------------------------
# Клонирование репозитория
# -----------------------------
echo ">>> Клонирование репозитория"

if [ -d "$APP_DIR" ]; then
  echo "⚠️ $APP_DIR уже существует, используем его"
else
  git clone $REPO_URL $APP_DIR
fi

cd $APP_DIR
git checkout $REPO_BRANCH

# -----------------------------
# Docker network & volume
# -----------------------------
echo ">>> Создание docker network и volume"
docker network inspect $NETWORK >/dev/null 2>&1 || docker network create $NETWORK
docker volume inspect $VOLUME >/dev/null 2>&1 || docker volume create $VOLUME

# -----------------------------
# Ввод паролей
# -----------------------------
echo ">>> Ввод паролей"

read -s -p "Пароль для локального PostgreSQL: " POSTGRES_PASSWORD
echo
read -s -p "Пароль BASIC_AUTH (admin): " BASIC_AUTH_PASSWORD
echo

# -----------------------------
# PostgreSQL
# -----------------------------
echo ">>> Запуск PostgreSQL"

docker rm -f $POSTGRES_CONTAINER 2>/dev/null || true

docker run -d \
  --name $POSTGRES_CONTAINER \
  --network $NETWORK \
  -e POSTGRES_DB=$POSTGRES_DB \
  -e POSTGRES_USER=$POSTGRES_USER \
  -e POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
  -p ${POSTGRES_PORT}:5432 \
  -v $VOLUME:/var/lib/postgresql/data \
  --restart unless-stopped \
  --health-cmd="pg_isready -U $POSTGRES_USER" \
  --health-interval=5s \
  --health-timeout=5s \
  --health-retries=5 \
  postgres:16

echo ">>> Ожидание PostgreSQL"
sleep 10

# -----------------------------
# Nginx (HTTP)
# -----------------------------
echo ">>> Запуск nginx"

docker rm -f $NGINX_CONTAINER 2>/dev/null || true

docker run -d \
  --name $NGINX_CONTAINER \
  --network $NETWORK \
  -p 80:80 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine

# -----------------------------
# Сборка приложения
# -----------------------------
echo ">>> Сборка приложения"
docker build -t $APP_NAME .

# -----------------------------
# Запуск приложения
# -----------------------------
echo ">>> Запуск приложения"

docker rm -f $APP_NAME 2>/dev/null || true

docker run -d \
  --name $APP_NAME \
  --network $NETWORK \
  -e DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_CONTAINER}:5432/${POSTGRES_DB}" \
  -e BASIC_AUTH_USERNAME=admin \
  -e BASIC_AUTH_PASSWORD=$BASIC_AUTH_PASSWORD \
  -p 3000:3000 \
  --restart unless-stopped \
  $APP_NAME

# -----------------------------
# Загрузка дампа (опционально)
# -----------------------------
echo ">>> Загрузить дамп из Neon?"
read -p "Загрузить дамп? (y/n): " LOAD_DUMP

if [[ "$LOAD_DUMP" == "y" ]]; then
  read -p "Neon host: " NEON_HOST
  read -p "Neon user: " NEON_USER
  read -p "Neon db name: " NEON_DB
  read -s -p "Neon password: " NEON_PASSWORD
  echo

  docker run --rm -it \
    -e PGPASSWORD="$NEON_PASSWORD" \
    postgres:16 \
    pg_dump -h "$NEON_HOST" \
            -U "$NEON_USER" \
            -p 5432 \
            -d "$NEON_DB" \
            -F c > neon_tt_tournament.dump

  docker cp neon_tt_tournament.dump $POSTGRES_CONTAINER:/neon_tt_tournament.dump

  docker exec -i $POSTGRES_CONTAINER pg_restore \
    -U $POSTGRES_USER \
    -C \
    -d postgres \
    --no-owner \
    --no-privileges \
    /neon_tt_tournament.dump
fi

# -----------------------------
# Автозапуск
# -----------------------------
docker update --restart=always $APP_NAME
docker update --restart=always $POSTGRES_CONTAINER
docker update --restart=always $NGINX_CONTAINER

echo "✅ Deploy completed successfully"
echo "🌍 Открой сайт по IP VPS"
