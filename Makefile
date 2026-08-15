.PHONY: config pull up status logs check backup stop

config:
	docker compose config --quiet

pull:
	docker compose pull

up: config
	docker compose up -d --wait --remove-orphans

status:
	docker compose ps

logs:
	docker compose logs -f --tail=200 backend frontend pacs

check:
	./scripts/check-compose.sh

backup:
	./scripts/backup-compose.sh

stop:
	docker compose down

