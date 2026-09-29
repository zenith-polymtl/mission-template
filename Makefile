# Makefile du repo de mission. Trois sections :
#   1. Développement et simulation  (poste WSL)
#   2. Test sur véhicule            (Jetson ou portable, à la main, en avant-plan)
#   3. Déploiement                  (Jetson, systemd ; leads)
# `make help` liste les cibles par section. Lire ARCHITECTURE.md avant tout.

# ----- Variables (surchargeables : make build C=demo IMG=drone) -----
# C     : la mission, donc le workspace workspaces/$(C)_ws
# IMG   : le conteneur dans lequel on travaille : dev | drone | gcs | vision
# DRONE : la config Zenoh sol, config/drones/$(DRONE).json5
# SITE  : le terrain, config/sites/$(SITE).yaml ; sur la Jetson, obligatoire dans .env (make drone)
# T     : le topic de make echo ; PKG : le package de make link et make bump
# SITL, SITL_HOST : la source de la simulation, plus bas

# Réglages locaux de ce poste (SITL_HOST, SITL, SIM_DOMAIN ; sur la Jetson, SITE et FCU_DEVICE).
# Voir .env.example. Ignoré par git.
-include .env

# Le terrain de vol : SITE de .env ou de la ligne de commande, lu avant le défaut sim ci-dessous.
FLIGHT_SITE := $(SITE)

C      ?= gcs
IMG    ?= dev
DRONE  ?= hexa
SITE   ?= sim
WS     := workspaces/$(C)_ws
COMPOSE := compose/$(IMG).yml

# SITL : d'où vient la simulation, donc où mavros se branche (FCU_URL).
#   mp      Mission Planner, en TCP sur le port 5762 de SITL_HOST (le défaut)
#   gazebo  le SITL de Gazebo, qui envoie en UDP sur le port 14550 ; mavros suit l'horloge de la sim
#   <URL>   n'importe quelle autre source, en URL mavros : make sim C=demo SITL=tcp://192.168.1.50:5760
# SITL_HOST : l'adresse de Mission Planner vue depuis un conteneur. 127.0.0.1 en WSL Mirrored
# (formation 2) et sous Linux. WSL en mode NAT (Windows 10) : l'adresse de ip route show default,
# dans .env (voir .env.example).
SITL      ?= mp
SITL_HOST ?= 127.0.0.1
SIM_TIME  := false
ifeq ($(SITL),mp)
FCU_URL := tcp://$(SITL_HOST):5762
else ifeq ($(SITL),gazebo)
FCU_URL := udp://:14550@
SIM_TIME := true
else
FCU_URL := $(SITL)
endif
MODELS_URL ?=
export C IMG DRONE SITE FCU_URL SIM_TIME SIM_DOMAIN FCU_DEVICE
# dev.yml et sim.yml forment un seul projet compose : sans ceci, chacun traite l'autre d'orphelin.
export COMPOSE_IGNORE_ORPHANS := True

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
	       echo "Choisissez le vôtre : IMG=<dev|drone|gcs|vision>"; exit 1; fi; \
	fi
endef

# Les nodes de sim_mocks (mocks et nodes de test) ne se lancent que dans le conteneur dev, celui de la simulation.
define only_sim
case "$$NAME" in aeac-dev) ;; *) echo "Cette cible ne sert qu'en simulation (conteneur dev). Trouvé : $$NAME"; exit 1;; esac
endef

# Un lien vers packages/ copié depuis Windows arrive en fichier texte qui contient son chemin,
# et colcon l'ignore. On le remplace par le vrai lien avant de construire.
define repair_links
for f in $(WS)/src/*; do \
	  if [ -f "$$f" ] && [ ! -L "$$f" ] && grep -qx '\.\./\.\./\.\./packages/[A-Za-z0-9_-]*' "$$f"; then \
	    t=$$(cat "$$f"); rm "$$f" && ln -s "$$t" "$$f" && echo "Lien réparé : $$f -> $$t"; \
	  fi; \
	done
endef

.DEFAULT_GOAL := help

##@ 1. Développement et simulation (poste WSL)

help: ## Affiche cette aide
	@awk 'BEGIN {FS = ":.*##"} \
	  /^##@/ {printf "\n%s\n", substr($$0, 5)} \
	  /^[a-zA-Z0-9_%-]+:.*##/ {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Variables : C=$(C) (mission)  IMG=$(IMG) (conteneur)  DRONE=$(DRONE)  SITE=$(SITE)  SITL=$(SITL) (simulation)"
	@echo "Une commande qu'on retape souvent devient une cible d'ici : c'est fait pour."

print-vars: ## Affiche les variables résolues (pour déboguer)
	@echo "C=$(C)  WS=$(WS)  IMG=$(IMG)  COMPOSE=$(COMPOSE)  DRONE=$(DRONE)  SITE=$(SITE)  SITL=$(SITL)  FCU_URL=$(FCU_URL)"

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
	@$(repair_links)
	docker compose -f $(COMPOSE) run --rm $(IMG) bash -lc \
	  'source /opt/ros/humble/setup.bash && cd /aeac/$(WS) && colcon build --symlink-install'

dev: ## Entre dans le conteneur de développement (tout le repo est monté dans /aeac)
	docker compose -f compose/dev.yml up -d dev
	docker compose -f compose/dev.yml exec dev bash

# Le conteneur dev est celui de la mission C : changer de C le recrée dans le bon workspace.
# Ctrl-C n'arrête que le launch ; mavros-sim et dev restent, make down arrête tout.
sim: ## Simulation de la mission C : mavros vers la source SITL, puis le launch file dans le conteneur dev avec sim:=true et le site SITE
	docker compose -f compose/sim.yml up -d mavros-sim
	docker compose -f compose/dev.yml up -d dev
	docker compose -f compose/dev.yml exec dev bash -lc '$(SOURCE) && ros2 launch $(C)_bringup mission.launch.py sim:=true site:=$(SITE)'

shell: ## Ouvre un terminal dans le conteneur en cours (IMG=dev, gcs... pour en choisir un autre)
	@$(pick_container); docker exec -it $$NAME bash

down: ## Arrête tous les conteneurs aeac-* de ce poste (dev, mavros-sim, ...)
	@docker ps --format '{{.Names}}' | grep '^aeac-' | xargs -r docker stop

logs: ## Suit les logs du conteneur en cours (IMG=mavros-sim pour ceux de mavros en simulation)
	@$(pick_container); docker logs -f $$NAME

takeoff: ## Arme et fait décoller le drone en simulation (node de test de sim_mocks)
	@$(pick_container); $(only_sim); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 run sim_mocks takeoff_test'

rc: ## Simule la manette au clavier (mock de sim_mocks, garde le terminal)
	@$(pick_container); $(only_sim); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 run sim_mocks rc_simulator'

# Le daemon ros2 ne part que dans un shell interactif (.bashrc). Sans lui, en WSL Mirrored,
# ros2 topic echo attend deux minutes avant d'échouer : on le démarre d'abord.
echo: ## Affiche un topic : make echo T=/mavros/state
	@test -n "$(T)" || { echo "Usage : make echo T=/le/topic"; exit 1; }
	@$(pick_container); docker exec -it $$NAME bash -lc '$(SOURCE) && ros2 daemon start > /dev/null 2>&1; ros2 topic echo $(T)'

link: ## Lie un package partagé au workspace de C : make link C=demo PKG=tools
	@test -n "$(PKG)" || { echo "Usage : make link C=<mission> PKG=<package de packages/>"; exit 1; }
	@test -d packages/$(PKG) || { echo "packages/$(PKG) n'existe pas"; exit 1; }
	cd $(WS)/src && ln -s ../../../packages/$(PKG) $(PKG)
	@echo "Lien créé : $(WS)/src/$(PKG). Pensez à le commit."

# La date vient du poste, à son heure : dans le conteneur, date donnerait l'heure UTC.
# Au sol (conteneur gcs), mavros n'arrive pas : seuls les /aeac/external/... traversent la radio.
bag: ## Enregistre un rosbag daté dans bags/ (/aeac/* et mavros ; au sol, /aeac/external/* seulement)
	@$(pick_container); docker exec -it $$NAME bash -lc \
	  '$(SOURCE) && ros2 bag record -o /aeac/bags/$(shell date +%F_%H-%M) \
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

# SITE vient de .env ou de la ligne de commande, jamais du défaut sim : vide, compose/drone.yml refuse de partir.
drone: ## La mission C sur le drone, sur le terrain SITE de .env (Jetson)
	SITE=$(FLIGHT_SITE) docker compose -f compose/drone.yml up

# Sans C=, C vaut gcs, qui n'a pas de launch sol : on demande la mission au lieu d'échouer plus loin.
gcs: ## Les nodes sol de la mission C + pont Zenoh vers DRONE (portable)
	@test "$(C)" != gcs || { echo "Usage : make gcs C=<mission> DRONE=<drone> (C=base : le heartbeat seul)"; exit 1; }
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

# La branche suivie est celle de .gitmodules (branch = ...), main sinon. Un pointeur ne recule
# jamais : si le commit actuel n'est pas dans cette branche, bump refuse et demande un lead.
bump: ## Avance un submodule sur sa branche (.gitmodules, main par défaut) et prépare le commit : make bump PKG=tools
	@test -n "$(PKG)" || { echo "Usage : make bump PKG=<submodule>"; exit 1; }
	@BRANCH=$$(git config -f .gitmodules submodule.packages/$(PKG).branch || echo main); \
	  git -C packages/$(PKG) fetch origin && \
	  { git -C packages/$(PKG) merge-base --is-ancestor HEAD origin/$$BRANCH || \
	    { echo "Le commit actuel de $(PKG) n'est pas dans origin/$$BRANCH : bump le ferait reculer. Voir un lead."; exit 1; }; } && \
	  echo "Branche suivie : $$BRANCH. Commits gagnés :" && \
	  git -C packages/$(PKG) log --oneline HEAD..origin/$$BRANCH && \
	  git -C packages/$(PKG) checkout -q --detach origin/$$BRANCH
	git -C packages/$(PKG) tag -f $(notdir $(CURDIR))-$$(date +%F)
	git add packages/$(PKG)
	@echo "Pointeur stagé. Commit avec : git commit -m 'bump $(PKG)'  puis  git push --recurse-submodules=on-demand"

.PHONY: help print-vars init status check models build dev sim shell logs down takeoff rc echo link bag \
        mavros zed zenoh-air vision drone gcs deploy undeploy bump
