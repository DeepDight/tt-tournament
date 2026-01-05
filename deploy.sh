#!/usr/bin/env bash
set -e

echo "=== TT Tournament auto-deploy started ==="

# -----------------------------
# Переменные
# -----------------------------
REPO_URL="https://github.com/DeepDight/tt-tournament.git"
REPO_BRANCH="instdockervpsnginx"
APP_DIR="$HOME/tt-tournament"

APP_NAME="tt-app"
POSTGRES_CONTAINER="tt-postgres"
NGINX_CONTAINER="tt-nginx"
NETWORK="tt-network"
VOLUME="tt-postgres-data"

POSTGRES_DB="tt_tournament"
POSTGRES_USER="tournament_user"
POSTGRES_PORT="5433"

CERTBOT_DIR="$APP_DIR/certbot"

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
git fetch
git checkout $REPO_BRANCH
git pull origin $REPO_BRANCH

# -----------------------------
# Docker network & volume
# -----------------------------
echo ">>> Создание docker network и volume"
docker network inspect $NETWORK >/dev/null 2>&1 || docker network create $NETWORK
docker volume inspect $VOLUME >/dev/null 2>&1 || docker volume create $VOLUME

# -----------------------------
# Ввод паролей и домена
# -----------------------------
echo ">>> Ввод паролей и домена"
read -s -p "Пароль для локального PostgreSQL: " POSTGRES_PASSWORD </dev/tty
echo
read -s -p "Пароль BASIC_AUTH (admin): " BASIC_AUTH_PASSWORD </dev/tty
echo
read -p "Введите домен для сайта (например, new.ebtt.ru): " DOMAIN </dev/tty

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
# Загрузка дампа (опционально)
# -----------------------------
echo ">>> Загрузить дамп из Neon?"
read -p "Загрузить дамп? (y/n): " LOAD_DUMP </dev/tty

if [[ "$LOAD_DUMP" == "y" ]]; then
  read -p "Neon host: " NEON_HOST </dev/tty
  read -p "Neon user: " NEON_USER </dev/tty
  read -p "Neon db name: " NEON_DB </dev/tty
  read -s -p "Neon password: " NEON_PASSWORD </dev/tty
  echo

  echo ">>> Скачивание дампа из Neon"
  docker run --rm \
    -e PGPASSWORD="$NEON_PASSWORD" \
    postgres:16 \
    pg_dump -h "$NEON_HOST" \
            -U "$NEON_USER" \
            -p 5432 \
            -d "$NEON_DB" \
            -F c > "$APP_DIR/neon_tt_tournament.dump"

  echo ">>> Копирование дампа в локальный контейнер PostgreSQL"
  docker cp "$APP_DIR/neon_tt_tournament.dump" $POSTGRES_CONTAINER:/neon_tt_tournament.dump

  echo ">>> Восстановление дампа в локальную базу"
  docker exec -i $POSTGRES_CONTAINER pg_restore \
    -U $POSTGRES_USER \
    -d $POSTGRES_DB \
    --no-owner \
    --no-privileges \
    /neon_tt_tournament.dump

  echo "✅ Дамп успешно восстановлен"
fi

# -----------------------------
# Подготовка certbot
# -----------------------------
mkdir -p "$CERTBOT_DIR/conf" "$CERTBOT_DIR/www"

# -----------------------------
# Временный nginx для certbot
# -----------------------------
echo ">>> Запуск временного nginx для certbot"
docker rm -f $NGINX_CONTAINER 2>/dev/null || true

cat > nginx/nginx-temp.conf <<EOL
events {}
http {
    server {
        listen 80;
        server_name $DOMAIN www.$DOMAIN;

        location /.well-known/acme-challenge/ {
            root /var/www/certbot;
        }

        location / {
            return 404;
        }
    }
}
EOL

docker run -d \
  --name $NGINX_CONTAINER \
  --network $NETWORK \
  -p 80:80 \
  -v $APP_DIR/nginx/nginx-temp.conf:/etc/nginx/nginx.conf:ro \
  -v $CERTBOT_DIR/www:/var/www/certbot \
  nginx:alpine

# -----------------------------
# Генерация сертификата
# -----------------------------
if [ ! -d "$CERTBOT_DIR/conf/live/$DOMAIN" ]; then
    echo ">>> Генерация Let's Encrypt сертификата для $DOMAIN"
    
    docker run --rm \
      -v $CERTBOT_DIR/conf:/etc/letsencrypt \
      -v $CERTBOT_DIR/www:/var/www/certbot \
      certbot/certbot certonly \
      --webroot \
      --webroot-path=/var/www/certbot \
      -d $DOMAIN \
      -d www.$DOMAIN \
      --email your@email.com \
      --agree-tos \
      --no-eff-email \
      --non-interactive \
      --keep-until-expiring
else
    echo "✅ Сертификат для $DOMAIN уже существует, пропускаем генерацию"
fi

docker rm -f $NGINX_CONTAINER

# -----------------------------
# Сборка приложения
# -----------------------------
if docker image inspect "$APP_NAME" >/dev/null 2>&1; then
  echo ">>> Docker image '$APP_NAME' уже существует, пропускаем сборку"
else
  echo ">>> Сборка Docker image '$APP_NAME'"
  docker build -t "$APP_NAME" .
fi

# -----------------------------
# nginx с HTTPS
# -----------------------------
cat > nginx/nginx.conf <<EOL
events {}
http {
    upstream app_backend {
        server $APP_NAME:3000;
    }

    server {
        listen 80;
        server_name $DOMAIN www.$DOMAIN;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name $DOMAIN www.$DOMAIN;

        ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;

        location / {
            proxy_pass http://app_backend;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection "upgrade";
        }
    }
}
EOL

echo ">>> Запуск nginx с HTTPS"
docker rm -f $NGINX_CONTAINER 2>/dev/null || true

docker run -d \
  --name $NGINX_CONTAINER \
  --network $NETWORK \
  -p 80:80 -p 443:443 \
  -v $APP_DIR/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $CERTBOT_DIR/conf:/etc/letsencrypt \
  -v $CERTBOT_DIR/www:/var/www/certbot \
  nginx:alpine

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

docker exec -it $APP_NAME npx prisma generate
docker restart $APP_NAME

# -----------------------------
# Автозапуск
# -----------------------------
docker update --restart=always $APP_NAME
docker update --restart=always $POSTGRES_CONTAINER
docker update --restart=always $NGINX_CONTAINER

echo "✅ Deploy completed successfully"
echo "🌍 Сайт доступен по https://$DOMAIN"
echo "📂 Репозиторий находится в $APP_DIR, можно зайти: cd $APP_DIR"
