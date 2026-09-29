#!/usr/bin/env python3
"""Node de test : passe en GUIDED, arme et décolle.

    ros2 run sim_mocks takeoff_test --ros-args -p alt:=10.0

Le suffixe _test dit ce que c'est : une node qui touche au matériel, pour aller plus vite en
simulation. C'est la seule façon d'armer depuis le code dans ce repo : une node de mission n'arme
jamais et ne change jamais de mode, c'est le pilote qui le fait. Il n'est inclus par aucun
launch file, et il annonce au démarrage ce qu'il va faire.
"""

import rclpy
from mavros_msgs.srv import CommandBool, CommandTOL, SetMode
from rclpy.node import Node


class TakeoffTest(Node):
    def __init__(self):
        super().__init__('takeoff_test')
        self.declare_parameter('alt', 10.0)
        self.get_logger().warn('node de test : arme et décolle le drone')
        alt = float(self.get_parameter('alt').value)
        # Les trois étapes, dans l'ordre : ce qu'on logue, le service, la requête, et comment
        # lire la réponse. Une étape refusée (SITL pas encore prêt) est renvoyée à la seconde suivante.
        self.steps = [
            ('mode GUIDED', self.create_client(SetMode, '/mavros/set_mode'),
             SetMode.Request(custom_mode='GUIDED'), lambda r: r.mode_sent),
            ('armement', self.create_client(CommandBool, '/mavros/cmd/arming'),
             CommandBool.Request(value=True), lambda r: r.success),
            (f'décollage à {alt} m', self.create_client(CommandTOL, '/mavros/cmd/takeoff'),
             CommandTOL.Request(altitude=alt), lambda r: r.success),
        ]
        self.step = 0
        self.announced = -1
        self.pending = None
        self.timer = self.create_timer(1.0, self.tick)  # une tentative par seconde, sans bloquer

    def tick(self):
        if self.pending is not None:
            if not self.pending.done():
                return
            label, _, _, accepted = self.steps[self.step]
            if accepted(self.pending.result()):
                self.step += 1
            else:
                self.get_logger().warn(f"{label} refusé par l'autopilote, nouvel essai")
            self.pending = None
        if self.step == len(self.steps):
            self.get_logger().info('terminé')
            raise SystemExit
        label, client, request, _ = self.steps[self.step]
        if not client.wait_for_service(timeout_sec=0.5):
            self.get_logger().warn(f'{client.srv_name} absent, mavros est-il lancé ?')
            return
        if self.announced != self.step:
            self.get_logger().info(label)
            self.announced = self.step
        self.pending = client.call_async(request)


def main(args=None):
    rclpy.init(args=args)
    try:
        node = TakeoffTest()
        rclpy.spin(node)
    except (KeyboardInterrupt, SystemExit) as e:
        if str(e):
            print(e)
    finally:
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == '__main__':
    main()
