NAMESPACE ?= $(PARENT)
PUBKEY    := sealed-secrets.pub.pem

RESOURCE ?=
PARENT   ?=
TYPE     ?=
DOMAIN   ?=
PORT     ?=

FULL_RESOURCE_NAME := $(PARENT)-$(RESOURCE)
TARGET_PATH        := $(PARENT)/$(RESOURCE)
ENV_FILE           := $(TARGET_PATH)/secrets/$(RESOURCE).env
SEALED_FILE        := $(TARGET_PATH)/secrets/$(RESOURCE)-sealed.yaml
SECRET_NAME        := $(RESOURCE)-secrets

.PHONY: help seal create check secret status pubkey-update scaffold scaffold-check

# ──────────────────────────────────────────────────────────────
# Документация
# ──────────────────────────────────────────────────────────────

help: ## Показать список доступных команд
	@echo ""
	@echo "  Управление манифестами и секретами в k8s-manifests"
	@echo ""
	@echo "  scaffold — создать структуру манифестов для нового компонента"
	@echo ""
	@echo "    make scaffold TYPE=frontend PARENT=week-art RESOURCE=ui DOMAIN=art.week-book.ru PORT=3000"
	@echo "    make scaffold TYPE=backend  PARENT=week-art RESOURCE=api DOMAIN=api.week-book.ru PORT=8080"
	@echo "    make scaffold TYPE=bot      PARENT=week-art RESOURCE=bot"
	@echo ""
	@echo "    TYPE     — тип компонента: frontend | backend | bot"
	@echo "    PARENT   — имя проекта     (например: week-art)"
	@echo "    RESOURCE — имя компонента  (например: api, ui, bot)"
	@echo "    DOMAIN   — публичный домен (обязателен для frontend и backend)"
	@echo "    PORT     — порт контейнера (по умолчанию: frontend=3000, backend=8080)"
	@echo ""
	@echo "  create / seal — ручное управление секретами"
	@echo ""
	@echo "    make create  PARENT=week-art RESOURCE=api"
	@echo "    make seal    PARENT=week-art RESOURCE=api"
	@echo "    make status"
	@echo "    make pubkey-update"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""

# ──────────────────────────────────────────────────────────────
# Внутренние проверки
# ──────────────────────────────────────────────────────────────

check:
	@test -n "$(RESOURCE)" || (echo "❌ Укажи RESOURCE=имя ресурса"; exit 1)
	@test -n "$(PARENT)"   || (echo "❌ Укажи PARENT=имя приложения"; exit 1)

secret:
	@test -f $(ENV_FILE) || (echo "❌ Нет файла $(ENV_FILE)"; exit 1)
	@test -f $(PUBKEY)   || (echo "❌ Нет публичного ключа $(PUBKEY). Запусти: make pubkey-update"; exit 1)

scaffold-check:
	@test -n "$(TYPE)"     || (echo "❌ Укажи TYPE=frontend|backend|bot"; exit 1)
	@test -n "$(RESOURCE)" || (echo "❌ Укажи RESOURCE=имя компонента"; exit 1)
	@test -n "$(PARENT)"   || (echo "❌ Укажи PARENT=имя проекта"; exit 1)
	@case "$(TYPE)" in \
		frontend|backend) \
			test -n "$(DOMAIN)" || (echo "❌ Укажи DOMAIN=домен для TYPE=$(TYPE)"; exit 1) ;; \
	esac

# ──────────────────────────────────────────────────────────────
# Scaffold
# ──────────────────────────────────────────────────────────────

scaffold: scaffold-check ## Создать манифесты для нового компонента (TYPE=frontend|backend|bot)
	$(eval _PORT := $(or $(PORT),$(if $(filter frontend,$(TYPE)),3000,8080)))
	$(eval _IMAGE := ghcr.io/week-book/$(RESOURCE))
	$(eval _NAME := $(RESOURCE))
	@echo ""
	@echo "── Scaffold: $(TYPE) · $(PARENT)/$(RESOURCE) ────────────────────"

	@# Создаём папки
	@mkdir -p $(TARGET_PATH)/secrets

	@# deployment.yaml
	@if [ -f "$(TARGET_PATH)/deployment.yaml" ]; then \
		echo "⚠️  $(TARGET_PATH)/deployment.yaml уже существует, пропускаю"; \
	else \
		case "$(TYPE)" in \
		frontend) \
			printf '%s\n' \
			'apiVersion: apps/v1' \
			'kind: Deployment' \
			'metadata:' \
			'  name: $(_NAME)' \
			'spec:' \
			'  replicas: 1' \
			'  selector:' \
			'    matchLabels:' \
			'      app: $(_NAME)' \
			'  template:' \
			'    metadata:' \
			'      labels:' \
			'        app: $(_NAME)' \
			'    spec:' \
			'      containers:' \
			'        - name: $(RESOURCE)' \
			'          image: $(_IMAGE)' \
			'          ports:' \
			'            - containerPort: $(_PORT)' \
			'          livenessProbe:' \
			'            httpGet:' \
			'              path: /' \
			'              port: $(_PORT)' \
			'            initialDelaySeconds: 5' \
			'            periodSeconds: 10' \
			'            timeoutSeconds: 2' \
			'          readinessProbe:' \
			'            httpGet:' \
			'              path: /' \
			'              port: $(_PORT)' \
			'            initialDelaySeconds: 3' \
			'            periodSeconds: 10' \
			'            timeoutSeconds: 2' \
			'          imagePullPolicy: IfNotPresent' \
			> $(TARGET_PATH)/deployment.yaml ;; \
		backend) \
			printf '%s\n' \
			'apiVersion: apps/v1' \
			'kind: Deployment' \
			'metadata:' \
			'  name: $(_NAME)' \
			'spec:' \
			'  replicas: 1' \
			'  selector:' \
			'    matchLabels:' \
			'      app: $(_NAME)' \
			'  template:' \
			'    metadata:' \
			'      labels:' \
			'        app: $(_NAME)' \
			'    spec:' \
			'      containers:' \
			'        - name: $(RESOURCE)' \
			'          image: $(_IMAGE)' \
			'          envFrom:' \
			'            - secretRef:' \
			'                name: $(RESOURCE)-secrets' \
			'          ports:' \
			'            - containerPort: $(_PORT)' \
			'          livenessProbe:' \
			'            httpGet:' \
			'              path: /healthz' \
			'              port: $(_PORT)' \
			'            initialDelaySeconds: 10' \
			'            periodSeconds: 10' \
			'            timeoutSeconds: 2' \
			'          readinessProbe:' \
			'            httpGet:' \
			'              path: /readyz' \
			'              port: $(_PORT)' \
			'            initialDelaySeconds: 5' \
			'            periodSeconds: 10' \
			'            timeoutSeconds: 2' \
			'          imagePullPolicy: IfNotPresent' \
			> $(TARGET_PATH)/deployment.yaml ;; \
		bot) \
			printf '%s\n' \
			'apiVersion: apps/v1' \
			'kind: Deployment' \
			'metadata:' \
			'  name: $(_NAME)' \
			'spec:' \
			'  replicas: 1' \
			'  selector:' \
			'    matchLabels:' \
			'      app: $(_NAME)' \
			'  template:' \
			'    metadata:' \
			'      labels:' \
			'        app: $(_NAME)' \
			'    spec:' \
			'      containers:' \
			'        - name: $(RESOURCE)' \
			'          image: $(_IMAGE)' \
			'          envFrom:' \
			'            - secretRef:' \
			'                name: $(RESOURCE)-secrets' \
			'          imagePullPolicy: IfNotPresent' \
			> $(TARGET_PATH)/deployment.yaml ;; \
		esac; \
		echo "📄 Создан $(TARGET_PATH)/deployment.yaml"; \
	fi

	@# service.yaml (frontend и backend)
	@if [ "$(TYPE)" != "bot" ]; then \
		if [ -f "$(TARGET_PATH)/service.yaml" ]; then \
			echo "⚠️  $(TARGET_PATH)/service.yaml уже существует, пропускаю"; \
		else \
			printf '%s\n' \
			'apiVersion: v1' \
			'kind: Service' \
			'metadata:' \
			'  name: $(_NAME)' \
			'spec:' \
			'  type: ClusterIP' \
			'  selector:' \
			'    app: $(_NAME)' \
			'  ports:' \
			'    - name: http' \
			'      port: 80' \
			"      targetPort: $(_PORT)" \
			> $(TARGET_PATH)/service.yaml; \
			echo "📄 Создан $(TARGET_PATH)/service.yaml"; \
		fi; \
	fi

	@# ingress.yaml (frontend и backend)
	@if [ "$(TYPE)" != "bot" ]; then \
		if [ -f "$(TARGET_PATH)/ingress.yaml" ]; then \
			echo "⚠️  $(TARGET_PATH)/ingress.yaml уже существует, пропускаю"; \
		else \
			printf '%s\n' \
			'apiVersion: networking.k8s.io/v1' \
			'kind: Ingress' \
			'metadata:' \
			'  name: $(_NAME)' \
			'  annotations:' \
			'    nginx.ingress.kubernetes.io/ssl-redirect: "true"' \
			'    cert-manager.io/cluster-issuer: "letsencrypt-prod"' \
			'    nginx.ingress.kubernetes.io/use-forwarded-headers: "true"' \
			'    nginx.ingress.kubernetes.io/forwarded-for-header: "CF-Connecting-IP"' \
			'spec:' \
			'  ingressClassName: nginx' \
			'  rules:' \
			'    - host: $(DOMAIN)' \
			'      http:' \
			'        paths:' \
			'          - path: /' \
			'            pathType: Prefix' \
			'            backend:' \
			'              service:' \
			'                name: $(_NAME)' \
			'                port:' \
			'                  number: 80' \
			'  tls:' \
			'    - hosts:' \
			'        - $(DOMAIN)' \
			'      secretName: $(_NAME)-tls' \
			> $(TARGET_PATH)/ingress.yaml; \
			echo "📄 Создан $(TARGET_PATH)/ingress.yaml"; \
		fi; \
	fi

	@# kustomization.yaml компонента
	@if [ -f "$(TARGET_PATH)/kustomization.yaml" ]; then \
		echo "⚠️  $(TARGET_PATH)/kustomization.yaml уже существует, пропускаю"; \
	else \
		case "$(TYPE)" in \
		frontend) \
			printf '%s\n' \
			'apiVersion: kustomize.config.k8s.io/v1beta1' \
			'kind: Kustomization' \
			'resources:' \
			'  - deployment.yaml' \
			'  - service.yaml' \
			'  - ingress.yaml' \
			'images:' \
			'  - name: $(_IMAGE)' \
			'    newTag: latest' \
			> $(TARGET_PATH)/kustomization.yaml ;; \
		backend) \
			printf '%s\n' \
			'apiVersion: kustomize.config.k8s.io/v1beta1' \
			'kind: Kustomization' \
			'resources:' \
			'  - deployment.yaml' \
			'  - service.yaml' \
			'  - ingress.yaml' \
			'  - secrets/$(RESOURCE)-sealed.yaml' \
			'images:' \
			'  - name: $(_IMAGE)' \
			'    newTag: latest' \
			> $(TARGET_PATH)/kustomization.yaml ;; \
		bot) \
			printf '%s\n' \
			'apiVersion: kustomize.config.k8s.io/v1beta1' \
			'kind: Kustomization' \
			'resources:' \
			'  - deployment.yaml' \
			'  - secrets/$(RESOURCE)-sealed.yaml' \
			'images:' \
			'  - name: $(_IMAGE)' \
			'    newTag: latest' \
			> $(TARGET_PATH)/kustomization.yaml ;; \
		esac; \
		echo "📄 Создан $(TARGET_PATH)/kustomization.yaml"; \
	fi

	@# .env заглушка для backend и bot
	@if [ "$(TYPE)" = "backend" ] || [ "$(TYPE)" = "bot" ]; then \
		if [ -f "$(ENV_FILE)" ]; then \
			echo "⚠️  $(ENV_FILE) уже существует, пропускаю"; \
		else \
			echo "# Секреты для $(PARENT)/$(RESOURCE)" > $(ENV_FILE); \
			echo "# Пример: TOKEN=xxx" >> $(ENV_FILE); \
			echo "📄 Создан $(ENV_FILE)"; \
		fi; \
	fi

	@# ArgoCD Application
	@if [ -f "applications/$(PARENT).yml" ]; then \
		echo "⚠️  applications/$(PARENT).yml уже существует, пропускаю"; \
	else \
		printf '%s\n' \
		'apiVersion: argoproj.io/v1alpha1' \
		'kind: Application' \
		'metadata:' \
		'  name: $(PARENT)' \
		'  namespace: argocd' \
		'  finalizers:' \
		'    - resources-finalizer.argocd.argoproj.io' \
		'spec:' \
		'  project: default' \
		'  source:' \
		'    repoURL: https://github.com/week-book/k8s-manifests.git' \
		'    targetRevision: main' \
		'    path: $(PARENT)' \
		'  destination:' \
		'    server: https://kubernetes.default.svc' \
		'    namespace: $(PARENT)' \
		'  syncPolicy:' \
		'    automated:' \
		'      prune: true' \
		'      selfHeal: true' \
		> applications/$(PARENT).yml; \
		echo "📄 Создан applications/$(PARENT).yml"; \
	fi

	@# kustomization.yaml проекта (если нет)
	@if [ -f "$(PARENT)/kustomization.yaml" ]; then \
		echo "⚠️  $(PARENT)/kustomization.yaml уже существует — добавь $(RESOURCE) вручную"; \
	else \
		printf '%s\n' \
		'apiVersion: kustomize.config.k8s.io/v1beta1' \
		'kind: Kustomization' \
		'resources:' \
		'  - $(RESOURCE)' \
		> $(PARENT)/kustomization.yaml; \
		echo "📄 Создан $(PARENT)/kustomization.yaml"; \
	fi

	@echo ""
	@echo "── Готово ───────────────────────────────────────────────"
	@echo ""
	@if [ "$(TYPE)" = "backend" ] || [ "$(TYPE)" = "bot" ]; then \
		echo "  Следующие шаги:"; \
		echo "  1. Заполни $(ENV_FILE)"; \
		echo "  2. make seal PARENT=$(PARENT) RESOURCE=$(RESOURCE)"; \
		echo "  3. Поправь image в $(TARGET_PATH)/kustomization.yaml (newTag)"; \
		if [ "$(TYPE)" = "backend" ]; then \
			echo "  4. Проверь /healthz и /readyz в deployment.yaml"; \
		fi; \
		echo "  5. git add . && git commit && git push"; \
	else \
		echo "  Следующие шаги:"; \
		echo "  1. Поправь image в $(TARGET_PATH)/kustomization.yaml (newTag)"; \
		echo "  2. git add . && git commit && git push"; \
	fi
	@echo ""

# ──────────────────────────────────────────────────────────────
# Управление секретами (ручной режим)
# ──────────────────────────────────────────────────────────────

create: check ## Создать структуру папок и пустой .env для нового ресурса
	mkdir -p $(TARGET_PATH)/secrets
	@if [ ! -f $(TARGET_PATH)/kustomization.yaml ]; then \
		touch $(TARGET_PATH)/kustomization.yaml; \
		echo "📄 Создан $(TARGET_PATH)/kustomization.yaml"; \
	fi
	@if [ ! -f $(ENV_FILE) ]; then \
		touch $(ENV_FILE); \
		echo "📄 Создан $(ENV_FILE)"; \
		echo "   → Заполни .env и запусти: make seal PARENT=$(PARENT) RESOURCE=$(RESOURCE)"; \
	else \
		echo "⚠️  $(ENV_FILE) уже существует, не перезаписываю"; \
	fi

seal: check secret ## Запечатать секрет из .env в SealedSecret
	kubectl create secret generic $(SECRET_NAME) \
		--from-env-file=$(ENV_FILE) \
		--namespace $(NAMESPACE) \
		--dry-run=client -o yaml | \
	kubeseal \
		--cert $(PUBKEY) \
		--format yaml > $(SEALED_FILE)
	@echo "✅ $(SEALED_FILE) обновлён"
	@echo "   → Не забудь добавить его в kustomization.yaml и закоммитить"
	@echo "   → Файл $(ENV_FILE) не коммить — добавь в .gitignore"

# ──────────────────────────────────────────────────────────────
# Диагностика
# ──────────────────────────────────────────────────────────────

status: ## Показать состояние sealed-secrets контроллера и список запечатанных секретов
	@echo ""
	@echo "── Контроллер sealed-secrets ──────────────────────────"
	@kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets \
		2>/dev/null || kubectl get pods -n kube-system | grep sealed
	@echo ""
	@echo "── SealedSecret ресурсы в кластере ────────────────────"
	@kubectl get sealedsecrets -A 2>/dev/null || echo "  (нет или CRD не установлен)"
	@echo ""
	@echo "── .env файлы в репозитории (не должны попасть в git) ──"
	@find . -name "*.env" -not -path "./.git/*" | sort || echo "  (не найдено)"
	@echo ""

pubkey-update: ## Обновить публичный ключ sealed-secrets из кластера
	@echo "🔄 Получаю публичный ключ из кластера..."
	kubeseal --fetch-cert \
		--controller-namespace kube-system \
		--controller-name sealed-secrets \
		> $(PUBKEY)
	@echo "✅ $(PUBKEY) обновлён"
	@echo "   → Закоммить обновлённый ключ если он изменился"
