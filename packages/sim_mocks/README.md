# sim_mocks : ce qui remplace le matériel en simulation

Jamais lancé en vol, jamais inclus par le launch file d'une mission. On les lance à la main, dans un second terminal (`make shell`), pendant que `make sim C=<mission>` tourne. Les deux plus utilisés ont leur cible make : `make rc` et `make takeoff`.

| Node | Remplace | Publie ou appelle | Commande |
|---|---|---|---|
| `rc_simulator` | La manette (interrupteurs) | `/mavros/rc/in` (`mavros_msgs/RCIn`), touches `w s x`, `e d c`, `r f v`, `q` pour quitter | `make rc`, ou `ros2 run sim_mocks rc_simulator` (lit le clavier : il garde son terminal) |
| `target_mock` | Le conteneur vision (une détection) | `geometry_msgs/PointStamped` sur le topic donné en paramètre | `ros2 run sim_mocks target_mock --ros-args -p topic:=/aeac/internal/vision/target -p x:=5.0 -p y:=3.0` |
| `takeoff_test` | Le pilote (GUIDED, armement, décollage) | services `/mavros/set_mode`, `/mavros/cmd/arming`, `/mavros/cmd/takeoff` | `make takeoff`, ou `ros2 run sim_mocks takeoff_test --ros-args -p alt:=10.0` |

Règle pour un nouveau mock : un fichier, un paramètre `topic`, pas de `time.sleep` dans un callback (utiliser un timer). Un node de test qui arme ou change de mode porte le suffixe `_test` et annonce en WARN ce qu'il va faire au démarrage : c'est à ce nom qu'on le reconnaît, et c'est la seule exception à la règle « le code de mission n'arme jamais ».
