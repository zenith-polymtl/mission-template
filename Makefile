# Makefile du repo de mission. Trois sections :
#   1. Développement et simulation  (poste WSL)
#   2. Test sur véhicule            (Jetson ou portable, à la main, en avant-plan)
#   3. Déploiement                  (Jetson, systemd ; leads)
# `make help` liste les cibles par section. Lire ARCHITECTURE.md avant tout.

# ----- Variables (surchargeables : make build C=water IMG=drone) -----
# C     : la mission, donc le workspace workspaces/$(C)_ws
# IMG   : le conteneur dans lequel on travaille : dev | drone | gcs | vision | sim
# DRONE : la config Zenoh sol, config/drones/$(DRONE).json5
# SITE  : le terrain en simulation, config/sites/$(SITE).yaml

# Réglages locaux, une ligne chacun (SITL_HOST par exemple) : voir .env.example. Ignoré par git.
-include .env

C      ?= gcs
IMG    ?= dev
DRONE  ?= hexa
SITE   ?= sim
WS     := workspaces/$(C)_ws
COMPOSE := compose/$(IMG).yml

# SITL_HOST : l'adresse où joindre le SITL de Mission Planner (TCP 5762) depuis un conteneur.
# WSL en mode NAT, le défaut : la passerelle par défaut, ce que calcule la ligne ci-dessous.
# WSL en mode mirrored et Linux natif : 127.0.0.1. Mac, avec Docker Desktop : host.docker.internal.
# Pour changer : make sim SITL_HOST=127.0.0.1, ou une ligne SITL_HOST= dans .env (voir .env.example).
SITL_HOST ?= $(shell ip route 2>/dev/null | awk '/default/ {print $$3; exit}')
MODELS_URL ?=
export C IMG DRONE SITE SITL_HOST

SERVICES := lo-multicast mavros zed zenoh-air vision mission

# Tout ce qu'on lance dans un conteneur source ROS 2 puis le workspace du dossier courant.
SOURCE := source /opt/ros/humble/setup.bash && source install/setup.bash

# Quel conteneur ? Avec IMG sur la ligne de commande, c'est aeac-$(IMG). Sinon on prend le
# conteneur de travail en cours : un nom aeac-* qui n'est ni mavros ni zenoh, ces deux-là n'ayant
# pas de workspace. S'il y en a un seul, on y entre ; s'il y en a plusieurs, on liste et on demande IMG=.
IMG_SET := $(filter command line,$(origin IMG))
define pick_container
if [ -n "$(IMG_SET)" ]; then NAME=aeac-$(IMG); else \
	  LIST=$$(docker ps --format '{{.Names}}' | grep '^aeac-' | grep -Ev 'mavros|zenoh' || true); \
	  N=$$(printf '%s\n' "$$LIST" | grep -c . || true); \
	  if [ "$$N" = "1" ]; then NAME=$$LIST; \
	  elif [ "$$N" = "0" ]; then echo "Aucun conteneur en cours. Lancez make sim C=<mission> ou make dev."; exit 1; \
	  else echo "Plusieurs conteneurs en cours :"; printf '  %s\n' $$LIST; \
	       echo "Choisissez le vôtre : IMG=<dev|sim|drone|gcs|vision>"; exit 1; fi; \
	fi
endef

# Les nodes de test qui arment le drone ne se lancent que dans le conteneur de simulation ou de développement.
define only_sim
case "$$NAME" in aeac-sim|aeac-dev) ;; *) echo "Cette cible ne sert qu'en simulation (conteneur sim ou dev). Trouvé : $$NAME"; exit 1;; esac
endef

.DEFAULT_GOAL := help

##@ 1. Développement et simulation (poste WSL)

help: ## Affiche cette aide
	@awk 'BEGIN {FS = ":.*##"} \
	  /^##@/ {printf "\n%s\n", substr($$0, 5)} \
	  /^[a-zA-Z0-9_%-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables : C=$(C) (mission)  IMG=$(IMG) (conteneur)  DRONE=$(DRONE)  SITE=$(SITE) (simulation)"
	@echo "Une commande qu'on retape souvent devient une cible d'ici : c'est fait pour."

print-vars: ## Affiche les variables résolues (pour déboguer)
	@echo "C=$(C)  WS=$(WS)  IMG=$(IMG)  COMPOSE=$(COMPOSE)  DRONE=$(DRONE)  SITE=$(SITE)  SITL_HOST=$(SITL_HOST)"

init: ## Après le clone : submodules, réglages git, dossiers ignorés. Sans risque à relancer.
	@git submodule update --init --recursive
	@git config submodule.recurse true
	@git config push.recurseSubmodules on-demand
	@mkdir -p models bags
	@echo "Submodules initialisés, réglages git posés, dossiers models/ et bags/ créés."

status: ## État de git et des submodules en une page
	@echo "Branche : $$(git branch --show-current)"
	@echo "Submodules (espace = à jour, + = commit différent du pointeur, - = non initialisé) :"
	@git submodule status
	@git status --short | head -20

check: ## Vérifie le repo (package.xml, liens, submodules, README). À lancer avant une PR.
	python3 scripts/check.py

models: ## Télécharge les modèles de vision dans models/ (hors git)
	@test -n "$(MODELS_URL)" || { echo "Renseignez MODELS_URL dans le Makefile (lien vers l'archive des modèles)."; exit 1; }
	mkdir -p models && curl -L "$(MODELS_URL)" | tar -xz -C models

build: ## Construit le workspace de C dans le conteneur IMG (colcon)
	docker compose -f $(COMPOSE) run --rm $(IMG) bash -lc \
	  'source /opt/ros/humble/setup.bash && cd /aeac/$(WS) && colcon build --symlink-install'

dev: ## Entre dans le conteneur de développement (tout le repo est monté dans /aeac)
	docker compose -f compose/dev.yml up -d dev
	docker compose -f compose/dev.yml exec dev bash

sim: ## Simulation de la mission C : mavros vers le SITL + le launch file avec sim:=true et le site SITE
	docker compose -f compose/sim.yml up --abort-on-container-exit

shell: ## Ouvre un terminal dans le conteneur en cours (IMG=dev, sim... pour en choisir un autre)
	@$(pick_container); docker exec -it $$NAME bash

down: ## Arrête tous les conteneurs aeac-* de ce poste (dev, sim, ...)
	@docker ps --format '{{.Names}}' | grep '^aeac-' | xargs -r docker stop

logs: ## Suit les logs du conteneur en cours
	@$(pick_container); docker logs -f $$NAME

takeoff: ## Arme et fait décoller le drone en simulation (node de test de sim_mocks)
	@$(pick_container); $(only_sim); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 run sim_mocks takeoff_test'

rc: ## Simule la manette au clavier (node de test de sim_mocks, garde le terminal)
	@$(pick_container); $(only_sim); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 run sim_mocks rc_simulator'

echo: ## Affiche un topic : make echo T=/aeac/internal/mission/state
	@test -n "$(T)" || { echo "Usage : make echo T=/le/topic"; exit 1; }
	@$(pick_container); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 topic echo $(T)'

link: ## Lie un package partagé au workspace de C : make link C=water PKG=tools
	@test -n "$(PKG)" || { echo "Usage : make link C=<mission> PKG=<package de packages/>"; exit 1; }
	@test -d packages/$(PKG) || { echo "packages/$(PKG) n'existe pas"; exit 1; }
	cd $(WS)/src && ln -s ../../../packages/$(PKG) $(PKG)
	@echo "Lien créé : $(WS)/src/$(PKG). Pensez à le commettre."

bag: ## Enregistre un rosbag daté dans bags/ (topics /aeac/* et mavros utiles)
	@$(pick_container); docker exec -it $$NAME bash -lc \
	  '$(SOURCE) && ros2 bag record -o /aeac/bags/$$(date +%F_%H-%M) \
	   -e "/aeac/.*|/mavros/(state|rc/in|local_position/pose|global_position/global)"'

##@ 2. Test sur véhicule (à la main, en avant-plan, Ctrl-C pour arrêter)

mavros: ## mavros vers le Pixhawk (Jetson)
	docker compose -f compose/mavros.yml up

zed: ## Caméra ZED (Jetson)
	docker compose -f compose/zed.yml up

zenoh-air: ## Pont Zenoh côté drone (Jetson)
	docker compose -f compose/zenoh-air.yml up

vision: ## Conteneur vision GPU (Jetson)
	docker compose -f compose/vision.yml up

drone: ## La mission C sur le drone (Jetson)
	docker compose -f compose/drone.yml up

gcs: ## Les nodes sol de la mission C + pont Zenoh vers DRONE (portable)
	docker compose -f compose/gcs.yml -f compose/zenoh-ground.yml up

##@ 3. Déploiement (Jetson, systemd ; leads)

deploy: ## Installe les services systemd depuis systemd/ et fixe la mission C au boot
	sudo mkdir -p /etc/aeac
	echo "$(C)" | sudo tee /etc/aeac/mission > /dev/null
	for s in $(SERVICES); do sed "s#__REPO__#$(CURDIR)#g" systemd/$$s.service | sudo tee /etc/systemd/system/$$s.service > /dev/null; done
	sudo systemctl daemon-reload
	sudo systemctl enable --now $(SERVICES)
	@echo "Déployé. Mission au boot : $(C). Pour tester à la main : make undeploy puis make drone C=$(C)"

undeploy: ## Arrête et désactive tous les services (pour repasser en test à la main)
	sudo systemctl disable --now $(SERVICES) || true

%-status: ## État d'un service : make mavros-status, make mission-status, ...
	systemctl status $* --no-pager

%-logs: ## Logs d'un service en direct : make mission-logs
	journalctl -u $* -f

%-restart: ## Redémarre un service : make zenoh-air-restart
	sudo systemctl restart $*

bump: ## Avance un submodule sur origin/main et prépare le commit : make bump PKG=tools
	@test -n "$(PKG)" || { echo "Usage : make bump PKG=<submodule>"; exit 1; }
	git -C packages/$(PKG) fetch origin
	@echo "Commits gagnés :"; git -C packages/$(PKG) log --oneline HEAD..origin/main
	git -C packages/$(PKG) checkout --detach origin/main
	git -C packages/$(PKG) tag -f $(notdir $(CURDIR))-$$(date +%F)
	git add packages/$(PKG)
	@echo "Pointeur stagé. Commit avec : git commit -m 'bump $(PKG)'  puis  git push --recurse-submodules=on-demand"

.PHONY: help print-vars init status check models build dev sim shell logs down takeoff rc echo link bag \
        mavros zed zenoh-air vision drone gcs deploy undeploy bump
