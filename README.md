# k8s-manifests

GitOps-репозиторий для кластера [week-book.ru](https://week-book.ru). Все манифесты управляются через ArgoCD — изменение файла в `main` автоматически применяется в кластере.

## Стек

| Слой | Инструмент |
|---|---|
| Кластер | k3s |
| GitOps | ArgoCD |
| Ingress | ingress-nginx |
| TLS | cert-manager + Let's Encrypt |
| Секреты | Sealed Secrets |
| Шаблонизация | Kustomize |

## Структура

```
.
├── applications/          # ArgoCD Application-ресурсы (то, что активно деплоится)
│   ├── web-site.yml
│   └── affiche.yml
│
├── web-site/              # Основной сайт
│   ├── frontend/          # Nuxt-приложение
│   └── minio/             # S3-хранилище (доступно только через SSH-туннель)
│
├── archive/               # Задеплоенные ресурсы снесены, манифесты сохранены
│   ├── affiche-bot/
│   ├── affiche/
│   └── artic-bot/
│
├── root-application.yml   # Корневой App of Apps, следит за applications/
├── sealed-secrets.pub.pem # Публичный ключ для шифрования секретов
└── Makefile               # Утилиты для работы с Sealed Secrets
```

### App of Apps

`root-application.yml` — точка входа. Он следит за папкой `applications/` и создаёт/удаляет Application-ресурсы автоматически. Достаточно положить или убрать файл из `applications/` — ArgoCD сам разберётся.

```
root-application
└── applications/
    └── web-site     →  web-site/ (frontend + minio)
```

## Работа с секретами

Секреты хранятся зашифрованными через [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). В репозитории никогда не должно быть plaintext-значений.

### Зашифровать секрет

1. Создай `.env`-файл рядом с манифестами:
```
# web-site/minio/secrets/web-site-minio.env
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=supersecret
```

2. Зашифруй через Makefile:
```bash
make seal PARENT=web-site RESOURCE=minio
# → создаст web-site/minio/secrets/web-site-minio-sealed.yaml
```

3. Закоммить `*-sealed.yaml`, `.env` — **никогда не коммитить**.

### Создать структуру для нового ресурса

```bash
make create PARENT=my-app RESOURCE=my-service
# → создаст my-app/my-service/kustomization.yaml
# → создаст my-app/my-service/secrets/my-app-my-service.env
```

## Добавить новое приложение

1. Создай папку с манифестами (`deployment.yaml`, `service.yaml`, `kustomization.yaml`)
2. Добавь `applications/my-app.yml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/week-book/k8s-manifests.git
    targetRevision: main
    path: my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

3. Запушь — ArgoCD задеплоит автоматически.

## Удалить приложение (правильно)

Удаление без `finalizers` оставит поды живыми. Правильный порядок:

**Шаг 1** — добавить finalizer, закоммитить, дождаться синхронизации ArgoCD:
```bash
kubectl get application my-app -n argocd -o jsonpath='{.metadata.finalizers}'
# ["resources-finalizer.argocd.argoproj.io"] — можно идти дальше
```

**Шаг 2** — убрать файл из `applications/`, манифесты перенести в `archive/`:
```bash
git rm applications/my-app.yml
git mv my-app/ archive/my-app/
git commit -m "chore: decommission my-app, archive manifests"
git push
```

## Связанные репозитории

| Репозиторий | Описание |
|---|---|
| [week-book/web-site](https://github.com/week-book/web-site) | Frontend (Nuxt) |
| [week-book/node-setup](https://github.com/week-book/node-setup) | Ansible-плейбуки для настройки сервера |
