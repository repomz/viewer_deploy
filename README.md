# Viewer Deploy

Единая конфигурация развёртывания Viewer: React Native Web/PWA frontend, Go
backend, PostgreSQL и Orthanc PACS. Больничный агент запускается отдельно на
Windows-компьютере больницы и в этот серверный стек не входит.

## Актуальные компоненты

| Компонент | Образ |
|---|---|
| Frontend | `ghcr.io/repomz/viewer_frontend:0.2.31` |
| Backend | `idrisovmarat/viewer_backend:0.2.7` |
| Миграции | `idrisovmarat/viewer_backend-migrations:0.2.0` |
| PostgreSQL | `postgres:17-alpine` |
| Orthanc | `jodogne/orthanc-plugins:1.12.11` |

Структура репозитория:

```text
viewer_deploy/
├── compose.yaml                 # полный Docker Compose стек
├── .env.example                 # шаблон конфигурации и секретов
├── config/orthanc.json          # конфигурация MAPDR, Agent и RadiAnt
├── kubernetes/base/             # Kubernetes + Kustomize
├── scripts/                     # проверка, backup и HTTPS
└── docs/                        # архитектура и безопасность
```

## Docker Compose: первый запуск

Требования: Linux-сервер, Docker Engine с Compose v2, открытые порты `80/tcp`,
`443/tcp` и `4242/tcp`.

```bash
cd /opt/viewer/viewer_deploy
cp .env.example .env
```

До запуска обязательно:

1. Заменить `POSTGRES_PASSWORD` в `.env`.
2. Придумать один пароль Orthanc и записать его в:
   - `ORTHANC_PASSWORD`;
   - `REMOTE_PACS_PASSWORD`;
   - `config/orthanc.json` → `RegisteredUsers.mapdr`.
3. Сформировать Basic authorization:

   ```bash
   printf '%s' 'mapdr:YOUR_ORTHANC_PASSWORD' | base64
   ```

   Результат записать в `.env` после `PACS_AUTHORIZATION=Basic `.
4. Заполнить Yandex access key и secret key.

Проверка и запуск:

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --wait --remove-orphans
docker compose ps
```

Доступ после запуска:

- приложение: `http://SERVER/` или `https://SERVER/` после установки TLS;
- API больничного агента: `https://SERVER/api`;
- DICOM: AE Title `MAPDR`, порт `4242`;
- backend admin: только `127.0.0.1:8080` на сервере;
- Orthanc Explorer: только `127.0.0.1:8042` на сервере.

Для временного доступа к закрытым admin-портам используйте SSH tunnel:

```bash
ssh -L 8042:127.0.0.1:8042 -L 8080:127.0.0.1:8080 root@SERVER
```

После этого Orthanc доступен локально по `http://127.0.0.1:8042`.

### Настройка Hospital Agent

На больничном компьютере в `agent_config.json`:

```json
{
  "viewer_url": "https://SERVER/api"
}
```

Прямые внешние порты `8080` и `8042` агенту не нужны.

### Обновление без потери данных

```bash
cd /opt/viewer/viewer_deploy
git pull --ff-only
docker compose pull
docker compose up -d --wait --remove-orphans
```

Выполнять `docker compose down` перед обновлением не требуется. Не используйте
`docker compose down --volumes`: этот параметр удаляет PostgreSQL, PACS,
операционный план, отчёты и XA-кэш.

### Логи и проверка

```bash
docker compose ps
docker compose logs -f --tail=200 backend frontend pacs
./scripts/check-compose.sh
```

### Резервная копия

Скрипт сохраняет дамп PostgreSQL и архивы persistent volumes:

```bash
./scripts/backup-compose.sh
```

Резервные копии создаются в `backups/YYYYMMDD-HHMMSS`. Каталог должен затем
копироваться за пределы сервера. Скрипт восстановления намеренно не
автоматизирован: перед восстановлением нужно отдельно проверить целевой стек и
состав архива.

## HTTPS для IP-адреса

Frontend включает HTTPS автоматически, если в `VIEWER_TLS_DIR` присутствуют
`fullchain.pem` и `privkey.pem`.

Для первичного короткоживущего Let's Encrypt сертификата на IP:

```bash
export VIEWER_SERVER_IP=135.106.130.37
./scripts/issue-ip-certificate.sh
docker compose up -d --force-recreate frontend
```

Для обновления сертификата:

```bash
export VIEWER_SERVER_IP=135.106.130.37
./scripts/renew-ip-certificate.sh
```

В production вызов renewal нужно выполнять systemd timer или cron ежедневно.
Для доменного имени предпочтительнее обычный сертификат и reverse proxy/Ingress.

## Kubernetes

Манифесты находятся в `kubernetes/base` и собираются Kustomize. Требования:

- Kubernetes 1.29+;
- default `StorageClass` либо явно заданный `storageClassName` в PVC;
- Nginx Ingress Controller;
- реализация `LoadBalancer` для DICOM-порта (cloud LB или MetalLB);
- TLS Secret `viewer-tls`.

### Подготовка секретов

```bash
cd kubernetes/base
cp secret.example.yaml secret.yaml
```

Отредактируйте `secret.yaml`: пароли, `DB_DSN`, Basic authorization, Yandex
credentials и пароль внутри `orthanc.json` должны быть согласованы.
`secret.yaml` исключён из Git.

Создание TLS secret из существующего сертификата:

```bash
kubectl create namespace viewer --dry-run=client -o yaml | kubectl apply -f -
kubectl -n viewer create secret tls viewer-tls \
  --cert=/path/to/fullchain.pem \
  --key=/path/to/privkey.pem
```

Проверьте размеры PVC в `storage.yaml`, затем примените стек:

```bash
kubectl apply -k kubernetes/base
kubectl -n viewer rollout status deployment/postgres --timeout=180s
kubectl -n viewer rollout status deployment/orthanc --timeout=180s
kubectl -n viewer rollout status deployment/backend --timeout=300s
kubectl -n viewer rollout status deployment/frontend --timeout=180s
kubectl -n viewer get pods,svc,ingress,pvc
```

Backend применяет миграции в init container перед собственным запуском.
Orthanc DICOM публикуется отдельным LoadBalancer service `orthanc-dicom`, а
HTTP-интерфейс Orthanc остаётся только внутри кластера.

Логи:

```bash
kubectl -n viewer logs -f deployment/backend
kubectl -n viewer logs -f deployment/frontend
kubectl -n viewer logs -f deployment/orthanc
```

Обновление образа:

```bash
kubectl -n viewer set image deployment/frontend \
  frontend=idrisovmarat/viewer_frontend:NEW_TAG
kubectl -n viewer rollout status deployment/frontend
```

Удаление Kubernetes-ресурсов командой `kubectl delete -k` не гарантирует
сохранение PVC во всех инфраструктурах. Перед удалением проверьте reclaim policy
StorageClass и наличие резервной копии.

## Дополнительная документация

- [Архитектура](docs/architecture.md)
- [Безопасность](docs/security.md)
