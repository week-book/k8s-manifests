NAMESPACE := default
PUBKEY    := sealed-secrets.pub.pem

.PHONY: seal check create secret

RESOURCE ?=
PARENT ?=

FULL_RESOURCE_NAME :=$(PARENT)-$(RESOURCE)
TARGET_PATH  := $(PARENT)/$(FULL_RESOURCE_NAME)
ENV_FILE    := $(TARGET_PATH)/secrets/$(FULL_RESOURCE_NAME).env
SEALED_FILE := $(TARGET_PATH)/secrets/$(FULL_RESOURCE_NAME)-sealed.yaml
SECRET_NAME := $(FULL_RESOURCE_NAME)-secrets

check:
	@test -n "$(RESOURCE)" || (echo "❌ Укажи RESOURCE=имя ресурса"; exit 1)
	@test -n "$(PARENT)" || (echo "❌ Укажи PARENT=имя приложения"; exit 1)

secret:
	@test -f $(ENV_FILE) || (echo "❌ Нет $(ENV_FILE)"; exit 1)
	@test -f $(PUBKEY) || (echo "❌ Нет $(PUBKEY)"; exit 1)

seal: check secret
	kubectl create secret generic $(SECRET_NAME) \
		--from-env-file=$(ENV_FILE) \
		--namespace $(NAMESPACE) \
		--dry-run=client -o yaml | \
	kubeseal \
		--cert $(PUBKEY) \
		--format yaml > $(SEALED_FILE)
	@echo "✅ $(SEALED_FILE) обновлён"

create: check
	mkdir -p $(TARGET_PATH)/secrets
	touch $(TARGET_PATH)/kustomization.yaml
	touch $(TARGET_PATH)/secrets/$(FULL_RESOURCE_NAME).env

