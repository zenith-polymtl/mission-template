# Repo de mission

Le code qui vole sur les drones de Zenith : nodes ROS 2, conteneurs, configuration, déploiement. Une mission = un workspace dans `workspaces/`. Lire [ARCHITECTURE.md](ARCHITECTURE.md) (une page) avant de toucher à quoi que ce soit.

## Démarrage rapide (poste WSL, formation 2 faite)

```bash
git clone --recurse-submodules <url du repo>
cd <repo>
make init                 # submodules, réglages git, dossiers ignorés
make build C=gcs          # construit le workspace gcs_ws dans le conteneur de développement
make dev                  # entre dans le conteneur ; tout le repo est dans /aeac
```

Les shells des conteneurs sourcent ROS 2 et le workspace du dossier courant tout seuls : `ros2 topic list` marche dès l'ouverture.

Pour simuler une mission : lancer le SITL dans Mission Planner (formation 1), puis `make sim C=<mission>`. mavros se branche sur le SITL et la mission tourne dans le conteneur `dev`. Ctrl-C n'arrête que la mission ; `make down` arrête tout. Dans un second terminal : `make takeoff` arme et décolle, `make rc` simule la manette, `make echo T=<topic>` affiche un topic, `make shell` ouvre un terminal dans `dev` (voir [packages/sim_mocks/README.md](packages/sim_mocks/README.md)). Une autre source de simulation que Mission Planner se choisit avec `SITL=` (voir le Makefile).

`make help` liste toutes les commandes, en trois sections : développement et simulation, test sur véhicule, déploiement. Une commande qu'on retape souvent devient une cible du Makefile. `make check` avant chaque PR.

## Règles du repo

- `main` = ce qui vole. On travaille sur une branche, on ouvre une PR, un lead merge.
- Le code de mission n'arme jamais et ne change jamais de mode : c'est le pilote. Les seules nodes qui le font sont les `*_test` de `sim_mocks`, jamais inclus par un launch file de mission.
- Un nom de topic s'écrit une fois, dans `tools/topics.py`. `/aeac/external/...` traverse la radio, `/aeac/internal/...` reste sur le drone.
- Ce qui change entre deux drones, deux terrains ou deux essais est dans `config/`, pas dans le code.
- Chaque mission a son workspace. `gcs_ws` est le workspace du sol : rien de spécifique à un drone ou à une mission n'y entre.
- Code en anglais ; docs, logs et commentaires de haut niveau en français.
- Ce qu'on apprend et qu'on n'a pas le temps de ranger va dans [NOTES.md](NOTES.md).

## Créer un repo de mission à partir de ce template

Ce repo est un modèle : il contient tout sauf les missions, submodules et liens des workspaces compris. Pour les leads, une fois par repo (aeac-2027, suas-2027) :

1. Sur GitHub, créer le nouveau repo dans `zenith-polymtl` à partir de ce modèle (bouton « Use this template »).
2. Le cloner avec `--recurse-submodules`, puis `make init` et `make check`.
3. Vérifier dans `.gitmodules` la branche suivie par chaque submodule (`branch =`, `main` sinon) : c'est elle que `make bump` suit. `tools` et `custom_interfaces` suivent `aeac-2027` tant que cette branche n'est pas mergée dans leur `main`.
4. Protéger `main` (Settings, Branches) : PR obligatoire, un lead merge.

Les formations de l'équipe contrôle (Formations-Controle, formation 5) se font directement sur un clone de ce repo.

Ajouter une mission : ce qu'elle contient est dans [ARCHITECTURE.md](ARCHITECTURE.md), section « Une mission » ; la marche à suivre pas à pas est l'annexe 5.4 des formations de l'équipe contrôle (repo Formations-Controle).

## Sur le drone

Voir [procédure.md](procédure.md) (checklist jour J) et [systemd/install.md](systemd/install.md) (démarrage au boot). Sur la Jetson, `.env` (copié de `.env.example`) donne le terrain de vol, `SITE`, obligatoire, et le port série du Pixhawk, `FCU_DEVICE` ; l'utilisateur doit être dans le groupe `dialout`.

## Dépannage

- `ros2 topic list` vide dans un conteneur : vérifier `ROS_DOMAIN_ID` (2 sur le drone, 3 au sol, `SIM_DOMAIN` de `.env` en simulation) et que `lo-multicast` est actif sur la Jetson (`make lo-multicast-status`).
- `make build` construit moins de packages que prévu : `make status` ; un submodule vide se règle avec `make init`, un symlink cassé apparaît dans `make check`.
- `make sim` ne joint pas le SITL : `make print-vars` montre `FCU_URL` ; voir `SITL` et `SITL_HOST` en tête du Makefile et `.env.example` (WSL en mode NAT, Gazebo, autre machine).
- Fichiers appartenant à root après un build : les conteneurs tournent en root pour l'instant ; `sudo chown -R $USER:$USER .` dans le repo.
- Le reste des problèmes de poste (WSL, Docker, ports) est dans les formations, fichier `DEPANNAGE.md`.
