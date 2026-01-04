#!/bin/bash
set -e

# ==========================================
# 1. Обновляем систему
# ==========================================
sudo apt update && sudo apt upgrade -y

# ==========================================
# 2. Устанавливаем Docker CE (без docker.io)
# ==========================================
# Удаляем старые пакеты Docker, если они есть
sudo apt remove -y docker docker-engine docker.io containerd runc
sudo apt autoremove -y

# Устанавливаем зависимости
sudo apt install -y ca-certificates curl gnupg lsb-release

# Добавляем официальный репозиторий Docker CE
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Обновляем пакеты
sudo apt update

# Устанавливаем только официальные пакеты Docker CE (без docker.io)
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Проверяем версию Docker
docker --version
docker compose version


# ==========================================
# 3. Клонируем репозиторий проекта
# ==========================================
git clone https://github.com/GlebkaF/tt-tournament
cd tt-tournament

# ==========================================
# 4. Создаем директорию nginx и nginx.conf, если нет
# ==========================================
mkdir -p nginx
if [ ! -f nginx/nginx.conf ]; then
cat > nginx/nginx.conf <<EOL
events {}

http {
    upstream app_backend {
        server tt-app:3000;
    }

    server {
        listen 80;
        server_name new.ebtt.ru www.new.ebtt.ru;
        return 301 https://\$host\$request_uri;
    }

    server {
        listen 443 ssl;
        server_name new.ebtt.ru www.new.ebtt.ru;

        ssl_certificate /etc/letsencrypt/live/new.ebtt.ru/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/new.ebtt.ru/privkey.pem;
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
fi

# ==========================================
# 5. Создаем Docker network и volume
# ==========================================
docker network create tt-network || true
docker volume create tt-postgres-data || true

# ==========================================
# 6. Запускаем PostgreSQL
# ==========================================
docker run -d \
  --name tt-postgres \
  --network tt-network \
  -e POSTGRES_DB=tt_tournament \
  -e POSTGRES_USER=tournament_user \
  -e POSTGRES_PASSWORD=strong_password \
  -p 5433:5432 \
  -v tt-postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  --health-cmd="pg_isready -U tournament_user" \
  --health-interval=5s \
  --health-timeout=5s \
  --health-retries=5 \
  postgres:16

# ==========================================
# 7. Скачиваем дамп базы, если его нет
# ==========================================
DUMP_FILE="neon_tt_tournament.dump"
if [ ! -f "$DUMP_FILE" ]; then
    echo "Скачиваем дамп базы..."
    docker run --rm -e PGPASSWORD=Password postgres:16 \
        pg_dump -h link.com \
                -U UserName \
                -p 5432 \
                -d DBName \
                -F c > $DUMP_FILE
fi

# ==========================================
# 8. Переносим дамп в контейнер PostgreSQL и восстанавливаем
# ==========================================
if [ -f "$DUMP_FILE" ]; then
    docker cp $DUMP_FILE tt-postgres:/neon_tt_tournament.dump
    docker exec -i tt-postgres pg_restore \
      -U tournament_user \
      -C \
      -d postgres \
      --no-owner \
      --no-privileges \
      /neon_tt_tournament.dump
fi

# ==========================================
# 9. Сборка и запуск Node.js приложения
# ==========================================
docker run --rm \
  --name tt-app-build \
  --network tt-network \
  -e DATABASE_URL="postgresql://tournament_user:strong_password@tt-postgres:5432/tt_tournament" \
  -v $(pwd):/app \
  node:20-alpine \
  sh -c "cd /app && npm install && npm run build"

docker run -d \
  --name tt-app \
  --network tt-network \
  -e DATABASE_URL="postgresql://tournament_user:strong_password@tt-postgres:5432/tt_tournament" \
  -p 3000:3000 \
  -v $(pwd):/app \
  node:20-alpine \
  sh -c "cd /app && npm run start"

# ==========================================
# 10. Настройка Certbot и SSL
# ==========================================
mkdir -p certbot/conf certbot/www

# Резервная копия nginx.conf
cp nginx/nginx.conf nginx/nginx.conf.backup || true

# Временно nginx для получения сертификата
cat > nginx/nginx.conf <<EOL
events {}

http {
  server {
    listen 80;
    server_name example.com www.example.com;

    location /.well-known/acme-challenge/ {
      root /var/www/certbot;
    }

    location / {
      return 404;
    }
  }
}
EOL

docker rm -f tt-nginx || true
docker run -d \
  --name tt-nginx \
  --network tt-network \
  -p 80:80 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/certbot/www:/var/www/certbot \
  nginx:alpine

# Получаем сертификат (замени на свои домены и email)
docker run --rm \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  certbot/certbot certonly \
  --webroot \
  --webroot-path=/var/www/certbot \
  -d example.com \
  -d www.example.com \
  --email your@email.com \
  --agree-tos \
  --no-eff-email

# Возвращаем исходный nginx.conf с HTTPS
cp nginx/nginx.conf.backup nginx/nginx.conf || true

docker rm -f tt-nginx || true
docker run -d \
  --name tt-nginx \
  --network tt-network \
  -p 80:80 -p 443:443 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  nginx:alpine

# ==========================================
# 11. Настройка автозапуска контейнеров
# ==========================================
docker update --restart=always tt-app
docker update --restart=always tt-postgres
docker update --restart=always tt-nginx

echo "========================================"
echo "🎉 Деплой завершен! Приложение работает с SSL."
echo "Проверьте контейнеры: docker ps"

