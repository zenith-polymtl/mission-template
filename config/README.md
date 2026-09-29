# config/ : ce qui change sans toucher au code

| Fichier | Change quand | Chargé par |
|---|---|---|
| `<mission>.yaml` | On règle la mission : gains, PWM des servos, mapping des interrupteurs de la manette, seuils, chemins de sauvegarde | Le launch file de la mission, qui le passe aux nodes |
| `sites/<site>.yaml` | On change de terrain : coordonnées, altitudes | Le launch file, avec `site:=<nom>` : `SITE=` de `make sim` (par défaut `sim`), `SITE` du `.env` sur la Jetson |
| `drones/<drone>.json5` | On vise un autre drone depuis le sol : adresses Zenoh | `compose/zenoh-ground.yml`, avec `DRONE=<nom>` |
| `mavros.yaml` | Rarement : paramètres mavros | `compose/mavros.yml` |
| `zenoh-air.json5` | Rarement : ce qui a le droit de traverser la radio | `compose/zenoh-air.yml` |
| `zed.yaml` | Réglages de la caméra ZED | `compose/zed.yml` |

Règle : une valeur qui change entre deux drones, deux terrains ou deux essais n'est jamais écrite dans une node ni dans un launch file. Elle est ici.

## Les sites

Un fichier par terrain de vol. `sim.yaml` sert à la simulation, `cimetiere.yaml` au terrain habituel. La cible y est donnée en mètres depuis le home de l'autopilote, là où il a armé : la même valeur marche où que le SITL démarre.

Le fichier est écrit en paramètres ROS 2, sous le joker `/**` qui veut dire « toutes les nodes ». Le launch file n'a donc rien à lire ni à convertir : il donne le fichier tel quel aux nodes.

```yaml
/**:
  ros__parameters:
    site: sim
    target: {north_m: 50.0, east_m: 40.0}   # mètres au nord et à l'est du home
    altitude_agl: 10.0
```

Une node lit ces valeurs sous les noms `target.north_m`, `target.east_m` et `altitude_agl`.

## Exemple de `config/<mission>.yaml`

À copier pour une nouvelle mission. Comme les sites, le fichier est en paramètres ROS 2, mais indexé par nom de node : chaque node a sa section, et le launch file passe le fichier tel quel.

```yaml
demo_mission:                # le nom de la node, celui du name= du launch file
  ros__parameters:
    rc:                      # interrupteurs de la manette, index dans RCIn.channels (0 = canal 1)
      go_channel: 7
      abort_channel: 8
    servo:
      channel: 9
      pwm_open: 1900
      pwm_closed: 1100
    approach:
      speed_mps: 2.0
      arrival_radius_m: 3.0  # plus grand que WPNAV_RADIUS d'ArduPilot (2 m par défaut)
    save_dir: /aeac/bags     # dossier ignoré par git
```
