# Архитектура развёртывания

Публичной точкой входа является frontend на Nginx. Он раздаёт PWA и
проксирует `/api/*` в Go backend, `/dicom-web/*` в Orthanc и потоковые
`/api/xa-cache/*` без промежуточной буферизации.

```text
Safari / Edge / hospital agent
              |
          HTTPS :443
              |
        frontend (Nginx)
          |           |
       /api        /dicom-web
          |           |
      Go backend ---- Orthanc PACS <---- DICOM MAPDR:4242
          |              |
      PostgreSQL      DICOM volume
          |
  reports / plans / XA cache
          |
      Yandex Object Storage
```

Hospital Agent не входит в серверный Compose или Kubernetes workload. Он
работает на больничном компьютере, имеет доступ к локальным каталогам и PACS и
использует внешний адрес `https://SERVER/api`.

## Почему frontend является edge-прокси

Так сохраняется один внешний HTTPS origin для PWA, API и DICOMweb. Браузеру не
нужны CORS-исключения, Orthanc и PostgreSQL не публикуются в интернет, а MP4 XA
получает корректную поддержку HTTP Range.

## Хранилища

- `postgres-data` — протоколы, задания, статусы и статистика;
- `orthanc-data` — временное DICOM-хранилище PACS;
- `xa-cache-data` — MP4/JPEG текущей недели;
- `reports-data` — сформированные отчёты;
- `plans-data` — редактируемый операционный план.

Удаление volumes/PVC означает удаление соответствующих данных. Обычное
обновление не должно удалять хранилища.

