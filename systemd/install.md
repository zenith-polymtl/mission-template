# Déploiement sur la Jetson

systemd est le programme qui lance des services au démarrage de Linux. Ici, ce n'est qu'un emballage : chaque service lance le même `docker compose` qu'une cible `make` de la section 2 du Makefile. On déploie quand le drone doit démarrer seul au boot ; on ne déploie jamais sur un poste de développement.

1. Sur la Jetson, dans le repo : `cp .env.example .env`, puis décommenter `SITE=` avec le terrain de vol (et `FCU_DEVICE=`, le port série du Pixhawk, selon son commentaire). Sans `SITE`, le service `mission` refuse de démarrer.
2. `make deploy C=<mission>`. Ça copie `systemd/*.service` dans `/etc/systemd/system/` en remplaçant `__REPO__` par le chemin du repo, écrit la mission dans `/etc/aeac/mission`, et active les six services.
3. Vérifier : `make mission-status`, `make mavros-logs`.
4. Changer de mission : `make deploy C=<autre>` réécrit `/etc/aeac/mission`, mais ne relance pas une mission qui tourne déjà : `make mission-restart` ensuite. Changer de terrain : modifier `SITE` dans `.env`, puis `make mission-restart`.
5. Repasser en test à la main : `make undeploy`, puis `make mavros`, `make drone C=<mission>` dans des terminaux séparés.

Ordre au boot : `lo-multicast` d'abord ; `mavros` attend le port série (`FCU_DEVICE`), `zed` attend la caméra, `vision` part après `zed`, `mission` après `mavros`, `zenoh-air` sans attendre personne.
