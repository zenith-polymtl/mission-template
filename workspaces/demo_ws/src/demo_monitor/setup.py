from setuptools import find_packages, setup

package_name = 'demo_monitor'

setup(
    name=package_name,
    version='0.0.0',
    packages=find_packages(),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Nour Karoui',
    maintainer_email='nour.karoui@etud.polymtl.ca',
    description='Moniteur de batterie et d état de la mission',
    license='Apache-2.0',
    entry_points={
        'console_scripts': [
            'monitor = demo_monitor.monitor:main',
        ],
    },
)
