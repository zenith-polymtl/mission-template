# Procédure d'opération (jour J)

## Préparation

1. Manette allumée, batterie du portable chargée, radio SIYI alimentée.
2. Démarrer le portable GCS, ouvrir un terminal WSL dans le repo.
3. Démarrer la Jetson. Les services partent seuls (`make deploy` a été fait) ; attendre une minute.

## Démarrage

1. Se connecter au drone : `ssh zenith@<adresse SIYI du drone>` (tableau « Plan d'adressage » d'`ARCHITECTURE.md`).
2. Sur le drone, dans le repo : `grep SITE .env` doit afficher le terrain du jour ; sinon, corriger `.env` puis `make mission-restart`. Ensuite `make mission-status`, `make mavros-status` : tout doit être `active (running)`.
3. Sur le portable : `make gcs C=<mission> DRONE=<drone>` dans un terminal, puis `make bag` dans un autre. Il enregistre depuis le conteneur `gcs`, qui doit déjà tourner, et ne reçoit que les topics `/aeac/external/...` : mavros ne traverse pas la radio. Le bag complet, mavros compris, s'enregistre sur le drone : `make bag IMG=drone` dans la session ssh.
4. Vérifier que le sol voit le drone : `make shell IMG=gcs` puis `ros2 topic hz /aeac/external/<un topic de la mission>`.
5. Le pilote arme et décolle. Le code ne le fait jamais.

## Debug, dans l'ordre

1. **Côté drone, les topics** : `make shell IMG=drone` puis `ros2 topic list`. S'il manque des topics mavros : `make mavros-logs`. S'il manque des topics de la mission : `make mission-logs`.
2. **Un service** : `make <service>-status`, `make <service>-logs`, `make <service>-restart` pour `mavros`, `zed`, `zenoh-air`, `vision`, `mission`.
3. **Le sol ne voit rien** : `ros2 topic list` vide côté sol veut dire réseau. Vérifier dans l'ordre : un `ping` vers l'adresse SIYI du drone, puis vers son adresse Tailscale (`ARCHITECTURE.md`), `docker logs aeac-zenoh-ground` (le pont se connecte-t-il ?), le `DRONE=` passé à `make gcs`.
4. **Pour reprendre la main** : `make undeploy` sur le drone, puis `make mavros` et `make drone C=<mission>` dans deux terminaux, logs à l'écran.

## Après le vol

1. `Ctrl-C` sur chaque `make bag` ; le rosbag est dans `bags/` sur la machine qui l'a enregistré (ignoré par git).
2. Télécharger le log dataflash depuis Mission Planner (formation 9).
3. Une ligne dans `NOTES.md` : ce qui a marché, ce qui a cassé.
