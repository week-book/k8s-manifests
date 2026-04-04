NAMESPACE := default
PUBKEY    := sealed-secrets.pub.pem

RESOURCE ?=
PARENT   ?=

FULL_RESOURCE_NAME := $(PARENT)-$(RESOURCE)
TARGET_PATH        := $(PARENT)/$(RESOURCE)
ENV_FILE           := $(TARGET_PATH)/secrets/$(FULL_RESOURCE_NAME).env
SEALED_FILE        := $(TARGET_PATH)/secrets/$(FULL_RESOURCE_NAME)-sealed.yaml
SECRET_NAME        := $(RESOURCE)-secrets

.PHONY: help seal create check secret status pubkey-update

# ──────────────────────────────────────────────────────────────
# Документация
# ──────────────────────────────────────────────────────────────

help: ## Показать список доступных команд
	@echo ""
	@echo "  Управление секретами в k8s-manifests"
	@echo ""
	@echo "  Обязательные параметры для большинства команд:"
	@echo "    PARENT   — имя приложения  (например: web-site)"
	@echo "    RESOURCE — имя компонента  (например: minio, frontend)"
	@echo ""
	@echo "  Примеры:"
	@echo "    make create  PARENT=web-site RESOURCE=minio"
	@echo "    make seal    PARENT=web-site RESOURCE=minio"
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

# ──────────────────────────────────────────────────────────────
# Основные команды
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
