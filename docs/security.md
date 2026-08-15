# Минимальные требования безопасности

1. Заменить пароли PostgreSQL и Orthanc до первого запуска.
2. Значения Orthanc должны совпадать в `.env`, `config/orthanc.json` и
   `PACS_AUTHORIZATION`.
3. Не публиковать PostgreSQL, backend `8080` и Orthanc HTTP `8042` наружу.
4. Открыть извне только `80/tcp`, `443/tcp` и при необходимости `4242/tcp`.
5. Хранить Yandex access key только в `.env` или Kubernetes Secret.
6. Делать резервные копии PostgreSQL и всех persistent volumes.
7. Ограничить DICOM `4242` больничными IP на внешнем firewall, если адреса
   стабильны.
8. Не добавлять `.env`, сертификаты и `kubernetes/base/secret.yaml` в Git.

Для формирования Basic-заголовка Orthanc:

```bash
printf '%s' 'mapdr:YOUR_PASSWORD' | base64
```

Полученное значение записывается как `PACS_AUTHORIZATION=Basic ...`.

