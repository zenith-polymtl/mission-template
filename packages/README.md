# packages/ : les packages partagés

Un package est **local** à sa mission (dans `workspaces/<mission>_ws/src/`) sauf s'il sert ailleurs. S'il sert à deux workspaces de ce repo, il vit ici comme dossier ordinaire (`sim_mocks`). S'il sert à deux repos (aeac-2027 et SUAS, ou d'une année à l'autre), il vit ici comme submodule, et c'est un lead qui le décide.

| Package | Type | Rôle |
|---|---|---|
| `custom_interfaces` | submodule | Messages, services, et constantes d'enum (états, modes, PWM) |
| `tools` | submodule | `topics.py` (la table des noms de topics), heartbeats, utilitaires |
| `nav_stack` | submodule | Initialisation, conversions GPS et local, waypoints |
| `vision` | submodule | Pipeline ZED et YOLO (conteneur vision) |
| `zed-ros2-wrapper` | submodule tiers, fork `zenith` | Wrapper ZED ; hors des workspaces, construit à part dans son image |
| `sim_mocks` | dossier ordinaire | Ce qui remplace le matériel en simulation |

Chaque submodule a son `package.xml` à la racine de son repo : `packages/tools/package.xml`, `packages/custom_interfaces/package.xml`. `tools/topics.py` est la table des topics, `custom_interfaces/msg/MissionState.msg` porte les états de mission.

Un workspace utilise un package partagé par un symlink dans son `src/` : `make link C=<mission> PKG=<package>`, puis on commet le lien. C'est un geste de lead : une recrue reçoit un workspace dont les liens sont déjà là. `ls -l workspaces/<mission>_ws/src` dit ce que la mission utilise et ce qui est partagé.

Submodules, trois choses à savoir : on clone avec `--recurse-submodules` ; `make init` rattrape si on a oublié ; si `make status` dit qu'un submodule est modifié localement, demander à un lead avant de continuer. Le reste (`make bump`, créer un submodule) est dans `ARCHITECTURE.md`, section leads.
