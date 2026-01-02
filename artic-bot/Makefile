NAMESPACE := default
PUBKEY    := sealed-secrets.pub.pem

.PHONY: seal check

BOT ?=

ENV_FILE    := secrets/$(BOT).env
SEALED_FILE := secrets/$(BOT)-sealed.yaml
SECRET_NAME := $(BOT)-secrets

check:
	@test -n "$(BOT)" || (echo "❌ Укажи BOT=имя_бота"; exit 1)
	@test -f $(ENV_FILE) || (echo "❌ Нет $(ENV_FILE)"; exit 1)
	@test -f $(PUBKEY) || (echo "❌ Нет $(PUBKEY)"; exit 1)

seal: check
	kubectl create secret generic $(SECRET_NAME) \
		--from-env-file=$(ENV_FILE) \
		--namespace $(NAMESPACE) \
		--dry-run=client -o yaml | \
	kubeseal \
		--cert $(PUBKEY) \
		--format yaml > $(SEALED_FILE)
	@echo "✅ $(SEALED_FILE) обновлён"

