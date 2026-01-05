#!/usr/bin/env bash
set -e

echo "=== TT Tournament setup (update & Docker install) ==="

# -----------------------------
# Обновление системы
# -----------------------------
echo ">>> Обновление системы"
sudo apt update && sudo apt upgrade -y

# -----------------------------
# Проверка и установка Docker
# -----------------------------
if ! command -v docker &> /dev/null; then
  echo ">>> Docker не найден, устанавливаем Docker CE"

  # Добавляем официальный репозиторий Docker
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "✅ Docker установлен"
else
  echo "✅ Docker уже установлен"
fi
