# Architecture du repo de mission

Une page. Ce qu'il faut savoir avant de lire du code.

## Le repo d'un coup d'œil

```
<repo de mission>/
├── workspaces/   une mission, un workspace
├── packages/     les packages partagés
├── config/       les réglages, hors code
├── compose/      ce qui lance les conteneurs
├── docker/       les recettes des images
├── systemd/      le démarrage au boot
├── scripts/      les vérifications du repo
├── models/       les modèles de vision (hors git)
└── bags/         les enregistrements de vol (hors git)
```

## Cinq mots à connaître avant de lire la suite

- **systemd** : ce qui lance nos conteneurs au démarrage de la Jetson, sans personne au clavier. Sur le terrain, on branche la batterie et tout part tout seul.
- **DDS** : la couche réseau de ROS 2, celle qui fait se trouver et se parler les nodes. On ne la configure presque jamais ; ici, on la garde sur la machine.
- **Zenoh** : le pont qui fait passer certains topics par la radio. Sans lui, un topic du drone reste sur le drone.
- **domaine ROS** : un numéro qui isole des réseaux ROS entre eux. Deux machines sur des numéros différents ne se voient pas, même sur le même réseau.
- **namespace de topics** : le préfixe `/aeac/external` ou `/aeac/internal` dans le nom du topic. C'est lui qui dit si le topic a le droit de traverser la radio.

## Qui tourne où

```
  Poste WSL (dev et simulation)      Jetson, sur le drone         Portable GCS, au sol
  ┌───────────────────────────┐     ┌────────────────────┐       ┌────────────────────┐
  │ conteneur dev : la        │     │ mavros    zed      │       │ conteneur gcs      │
  │ mission de C= avec        │     │ vision    mission  │ radio │ zenoh-ground       │
  │ sim:=true                 │     │ zenoh-air          │<=====>│                    │
  │ mavros-sim vers le SITL   │     │                    │       │                    │
  │ de Mission Planner        │     │                    │       │                    │
  └───────────────────────────┘     └────────────────────┘       └────────────────────┘
         domaine ROS 3                  domaine ROS 2                domaine ROS 3
```

| Machine | Régime | Ce qui tourne | Lancé par | Domaine ROS |
|---|---|---|---|---|
| Poste WSL | Développement | conteneur `dev` : coder, construire un workspace, rviz, `ros2 topic` | `make dev` | 3 |
| Poste WSL | Simulation | conteneur `dev` + `mavros-sim` vers le SITL de Mission Planner ; la mission de `C=` lancée dans `dev` avec `sim:=true` ; mocks à la main | `make sim C=` | 3 |
| Jetson | Test sur véhicule | `mavros`, `zed`, `zenoh-air`, `vision`, la mission : les mêmes compose qu'en déploiement, en avant-plan | `make mavros`, `make vision`, `make drone C=` | 2 |
| Jetson | Déploiement | exactement les mêmes compose, démarrés au boot et relancés s'ils tombent | systemd (`make deploy`) | 2 |
| Portable GCS | Vol | conteneur `gcs` (workspace `gcs_ws`) + `zenoh-ground` vers le drone choisi | `make gcs C= DRONE=` | 3 |

systemd n'est qu'un emballage : tout ce qu'il lance a une cible `make` qui lance la même chose en avant-plan. Pour tester sur le véhicule : `make undeploy`, puis les cibles à la main.

Tous les conteneurs sont en réseau hôte (`network_mode: host` dans les compose) : ils utilisent le réseau de leur machine comme un programme ordinaire. Les nodes de deux conteneurs d'une même machine se voient donc, et `127.0.0.1` dans un conteneur désigne la machine elle-même.

## Ce qui traverse la radio

```
Jetson (domaine 2, DDS local seulement)                 Portable (domaine 3, DDS local seulement)
   nodes mission ──► /aeac/internal/...   (reste ici)
   nodes mission ──► /aeac/external/...  ──► zenoh-air ══ SIYI ou Tailscale ══ zenoh-ground ──► nodes GCS
                     /tf, /tf_static     ──►                                                ──►
```

Le nom du topic dit où il voyage. DDS ne sort jamais d'une machine : c'est `ROS_LOCALHOST_ONLY=1` dans les compose, et le service `lo-multicast` permet aux conteneurs de la Jetson de se trouver malgré ce réglage. Zenoh ne porte que les topics `/aeac/external/...` et `/tf`, `/tf_static` (listes `allow` de `config/zenoh-air.json5` et `config/drones/*.json5`). Les deux domaines différents sont une ceinture de sécurité : un DDS mal configuré ne traverse pas la radio par accident. Enfin, les ponts Zenoh ne cherchent pas leurs voisins tout seuls (pas de découverte automatique) : deux drones sur le même réseau ne se trouvent pas par surprise.

## Plan d'adressage

| Drone | SIYI (lien principal) | Tailscale (secours LTE) | Fichier |
|---|---|---|---|
| Hexa | 192.168.144.30 | 100.87.171.82 | `config/drones/hexa.json5` |
| OS | 192.168.144.31 | 100.64.95.10 | `config/drones/os.json5` |

Un nouveau drone = un fichier de plus dans `config/drones/` et une ligne ici. SSH : `ssh zenith@<adresse>`.

## Une mission

Une mission, c'est trois choses :

1. `workspaces/<mission>_ws/` : ses packages locaux dans `src/`, et des symlinks vers les packages partagés de `packages/`. Un symlink est un raccourci : le package apparaît dans `src/`, mais ses fichiers restent dans `packages/`. Les poser est un geste de lead (`make link`), versionné dans git. Le package `<mission>_bringup` contient `launch/mission.launch.py`, lancé sur le drone.
2. `config/<mission>.yaml` : tout ce qui se règle (gains, PWM, interrupteurs, seuils). Le launch file le charge et le passe aux nodes. Rien de tout ça dans le code.
3. `gcs_ws/src/gcs_bringup/launch/<mission>.launch.py` : ce que le portable lance pour cette mission.

Chaque mission a son workspace, y compris pendant le développement. `gcs_ws` est le workspace du sol : on n'y met rien de spécifique à un drone ou à une mission. Le conteneur `dev` monte tout le repo dans `/aeac` et sert à construire n'importe quel workspace : `make build C=<mission>`.

`make build C=<mission>` construit ce workspace et rien d'autre. `make sim C=<mission>` le simule. `make drone C=<mission>` le lance sur la Jetson. Le launch file est le même en simulation et en vol : `sim:=true` passe un paramètre `sim` aux nodes qui touchent au matériel, et elles regroupent leurs appels matériels derrière un `if not self.sim`, en un seul endroit de la node si possible. `site:=<nom>` choisit `config/sites/<nom>.yaml` (coordonnées du terrain, en paramètres ROS 2 prêts à passer aux nodes) ; en simulation, `make sim C=<mission> SITE=<nom>`, et sur la Jetson, `SITE=<nom>` dans `.env` (obligatoire).

## Se simplifier la vie

Une commande qu'on retape dix fois par séance devient une cible du Makefile. `make takeoff`, `make rc` et `make echo T=<topic>` sont nées comme ça. Ajouter une cible est normal, et `make help` la montre à tout le monde.

## Règles de code

- **Le code de mission n'arme jamais et ne change jamais de mode.** C'est le pilote. Seules les nodes `*_test` de `sim_mocks` le font ; on les reconnaît à leur suffixe, elles annoncent en WARN ce qu'elles vont faire, et aucun launch file de mission ne les inclut. C'est la seule exception.
- **Un nom de topic s'écrit une fois**, dans `tools/topics.py` : `from tools import topics`, puis `topics.DEMO_STATE`. Jamais de littéral dans une node ni un launch file. Seule exception : les topics de mavros, un package tiers, deviennent des constantes en tête de la node qui les utilise.
- **Un enum, une constante de message** dans `custom_interfaces` (états, modes, PWM). Jamais redéfini dans une node.
- **Pas de `time.sleep` dans un callback, pas de `spin_until_future_complete` depuis un callback.** Timers et `call_async`.
- **Pas de vérification factice.** Une fonction de readiness vérifie ou n'existe pas.
- **Logs en français**, `INFO` pour les événements (jamais du périodique), `WARN` pour ce qui demande un regard, `ERROR` pour ce qui arrête. Code, topics, commits en anglais.
- **`package.xml` est le contrat** : toute dépendance y est déclarée. Le Dockerfile installe ce que `rosdep` ne couvre pas et le dit en commentaire.
- **Pas de tests, pas de dossier `test/`.** `make check` vérifie ce qui se vérifie sans en écrire.

## Submodules

Un submodule est un repo dans un repo : un package partagé vit dans son propre repo GitHub, et le repo de mission retient seulement à quel commit il le veut (voir `packages/README.md`). On clone avec `--recurse-submodules`. `make init` rattrape si on a oublié. Si `make status` dit qu'un submodule est modifié localement, on demande à un lead avant de continuer.

## Pour les leads

- **Avancer un package partagé** : `make bump PKG=tools` (fetch, checkout de la branche suivie, celle de `branch =` dans `.gitmodules` ou `main`, tag daté, pointeur stagé ; refuse si le pointeur reculerait), puis `git commit -m "bump tools"` et `git push --recurse-submodules=on-demand`.
- **Contribuer à un package partagé** : `git -C packages/tools switch <branche suivie>` (voir `.gitmodules`), coder, commit, push, PR dans le repo du package, puis `make bump PKG=tools` ici.
- **Créer un package partagé** : repo GitHub avec `package.xml` à la racine, `git submodule add <url> packages/<nom>`, une ligne dans `packages/README.md`.
- **Sortir un package du partage** : `git submodule deinit packages/<nom>`, copier le dossier dans le workspace concerné, `git rm packages/<nom>`.
- **Lier un package partagé à un workspace** : `make link C=<mission> PKG=<package>`, depuis WSL (sous Windows, git écrit les symlinks comme des fichiers texte), puis un commit du lien. Les recrues reçoivent les liens déjà faits.
- **Déployer** : `make deploy C=<mission>` sur la Jetson (voir `systemd/install.md`).
- **Après la compétition** : tag `<compétition>-<année>` sur `main`, puis suppression des workspaces et packages de mission qui ne serviront plus.
- **Modèles de vision** : `models/` est ignoré par git ; `make models` télécharge l'archive dont l'URL est dans le Makefile (`MODELS_URL`).
