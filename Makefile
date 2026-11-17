# Point d'entrée unique de la démo : make help liste les cibles.
# Les recettes supposent un shell POSIX (Linux, macOS, WSL ou Git Bash sous Windows).

COMPOSE = docker compose -f docker/compose.yaml --env-file .env
BATCH   = $(COMPOSE) exec -T batch
DATE   ?=
ORDO    = ordonnanceur/ordonnanceur.py $(if $(DATE),--date $(DATE))

.PHONY: help up schema chaine reprise statut test lint down

help:
	@echo "make up        construit les images, démarre la base et le serveur batch, crée le schéma"
	@echo "make chaine    lance la chaîne de nuit (DATE=AAAAMMJJ en option)"
	@echo "make reprise   reprend la chaîne au job en échec"
	@echo "make statut    affiche l'état des jobs du lot"
	@echo "make test      tests bats sous ksh et bash, avec la base"
	@echo "make lint      ShellCheck sur les scripts"
	@echo "make down      arrête les conteneurs (les volumes sont conservés)"

.env:
	@echo "Fichier .env absent : copier .env.example vers .env puis adapter les valeurs." >&2
	@exit 1

up: .env
	$(COMPOSE) up -d --build --wait base batch
	$(MAKE) schema

schema: .env
	$(BATCH) psql -X -q -v ON_ERROR_STOP=1 -f sql/schema.sql

# En démo, la chaîne est lancée à la demande, donc en dehors de sa fenêtre de nuit.
chaine: .env
	$(BATCH) $(ORDO) --forcer-fenetre

reprise: .env
	$(BATCH) $(ORDO) --forcer-fenetre --reprise

statut: .env
	$(BATCH) $(ORDO) --statut

test: .env
	$(COMPOSE) run --rm --build test

lint: .env
	$(COMPOSE) run --rm --build --no-deps test sh tests/lint.sh

down: .env
	$(COMPOSE) down
