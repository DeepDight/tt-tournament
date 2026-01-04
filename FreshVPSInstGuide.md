**Только, что созданная VPS:**

sudo apt update && sudo apt upgrade -y (Обновление пакетов)

**Установка docker:**

sudo apt install -y ca-certificates curl gnupg lsb-release

sudo mkdir -p /etc/apt/keyrings curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo apt install -y docker.io

git clone https://github.com/GlebkaF/tt-tournament

**Начало контента(создание всего, что только можно):**

docker network create tt-network(создаем все сами, из-за того, что не используем докеркомпоз)

docker volume create tt-postgres-data(чтобы после рестарта базы не пропали)

docker run -d \
  --name tt-postgres \
  --network tt-network \
  -e POSTGRES_DB=tt_tournament \
  -e POSTGRES_USER=tournament_user \
  -e POSTGRES_PASSWORD=strong_password \
  -p 5433:5432 \
  -v tt-postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  --health-cmd='pg_isready -U tournament_user' \
  --health-interval=5s \
  --health-timeout=5s \
  --health-retries=5 \
  postgres:16


**Проверка**

docker ps
docker logs tt-postgres

**Запускаем nginx в Docker**

docker run -d \
  --name tt-nginx \
  --network tt-network \
  -p 80:80 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx:alpine

Проверка(Если все в порядке, сайт должен открываться без :3000)
docker exec -it tt-nginx wget -qO- http://tt-app:3000


**Создаем образ**

docker build -t tt-app .

**Запускаем контейнер приложения:**

docker run -d \
  --name tt-app \
  --network tt-network \
  -e DATABASE_URL="postgresql://tournament_user:strong_password@tt-postgres:5432/tt_tournament" \
  -e BASIC_AUTH_USERNAME=admin \
  -e BASIC_AUTH_PASSWORD=admin1 \
  -p 3000:3000 \
  --restart unless-stopped \
  tt-app

На этом моменте сайт is working, но мы не перенесли дамп базы данных.

**Качаем дамп бд ну или создаем новую**

docker run --rm -e PGPASSWORD=Password postgres:16 \
    pg_dump -h link.com \
            -U UserName \
            -p 5432 \
            -d DBName \
            -F c > neon_tt_tournament.dump

Проверим скачался ли файл?
ls -lh neon_tt_tournament.dump 

docker cp neon_tt_tournament.dump tt-postgres:/neon_tt_tournament.dump

docker exec -i tt-postgres pg_restore \
  -U tournament_user \
  -C \
  -d postgres \
  --no-owner \
  --no-privileges \
  /neon_tt_tournament.dump

**После того, как сделали все выше, делаем так, чтобы контейнеры запускались автоматически при старте VPS:**

docker update --restart=always tt-app
docker update --restart=always tt-postgres
docker update --restart=always tt-nginx

**Подарок для друзей, подключение сертификатов к сайту:**

docker rm -f tt-nginx

mkdir -p certbot/conf
mkdir -p certbot/www

Временно меняем nginx.conf:

nano nginx/nginx.conf

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

Запускаем:

docker run -d \
  --name tt-nginx \
  --network tt-network \
  -p 80:80 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/certbot/www:/var/www/certbot \
  nginx:alpine

Получаем сертификат:

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

Возвращаем назад исходный nginx.conf
Перезапускаем nginx:

docker rm -f tt-nginx

docker run -d \
  --name tt-nginx \
  --network tt-network \
  -p 80:80 \
  -p 443:443 \
  -v $(pwd)/nginx/nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/certbot/conf:/etc/letsencrypt \
  -v $(pwd)/certbot/www:/var/www/certbot \
  nginx:alpine




**Создание дампа:**
docker exec -t tt-postgres pg_dump -U tournament_user -F c -v tt_tournament > tt_tournament.dump
Проверка создался ли:
ls -lh tt_tournament.dump

**Восстановление бд:**
docker exec -it tt-postgres psql -U tournament_user -d tt_tournament
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

После этого:
docker cp neon_tt_tournament.dump tt-postgres:/neon_tt_tournament.dump
docker exec -i tt-postgres pg_restore -U tournament_user -d tt_tournament --no-owner --no-privileges /neon_tt_tournament.dump