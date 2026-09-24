# config/ : ce qui change sans toucher au code

| Fichier | Change quand | Chargé par |
|---|---|---|
| `<mission>.yaml` | On règle la mission : gains, PWM des servos, mapping des interrupteurs de la manette, seuils, chemins de sauvegarde | Le launch file de la mission, qui le passe aux nodes |
| `sites/<site>.yaml` | On change de terrain : coordonnées, altitudes | Le launch file, avec `site:=<nom>` (par défaut `sim`) |
| `drones/<drone>.json5` | On vise un autre drone depuis le sol : adresses Zenoh | `compose/zenoh-ground.yml`, avec `DRONE=<nom>` |
| `mavros.yaml` | Rarement : paramètres mavros | `compose/mavros.yml` |
| `zenoh-air.json5` | Rarement : ce qui a le droit de traverser la radio | `compose/zenoh-air.yml` |
| `zed.yaml` | Réglages de la caméra ZED | `compose/zed.yml` |

Règle : une valeur qui change entre deux drones, deux terrains ou deux essais n'est jamais écrite dans un node ni dans un launch file. Elle est ici.

## Les sites

Un fichier par terrain de vol. `sim.yaml` est la position de départ du SITL (Canberra), `cimetiere.yaml` le terrain habituel.

Le fichier est écrit en paramètres ROS 2, sous le joker `/**` qui veut dire « tous les nodes ». Le launch file n'a donc rien à lire ni à convertir : il donne le fichier tel quel aux nodes.

```yaml
/**:
  ros__parameters:
    site: sim
    home: {lat: -35.363262, lon: 149.165237, alt: 584.0}   # alt en mètres AMSL
    target: {lat: -35.362800, lon: 149.165700}
    altitude_agl: 10.0
```

Un node lit ces valeurs sous les noms `home.lat`, `home.lon`, `home.alt`, `target.lat`, `target.lon` et `altitude_agl`.

## Exemple de `config/<mission>.yaml`

À copier pour une nouvelle mission :

```yaml
mission:
  name: water
  rc:                  # interrupteurs de la manette, numéro de canal (0 = premier canal)
    go: 7
    abort: 8
  servo:
    channel: 9
    pwm_open: 1900
    pwm_closed: 1100
  approach:
    speed_mps: 2.0
    tolerance_m: 1.5
  save_dir: /aeac/bags  # dossier ignoré par git
```
