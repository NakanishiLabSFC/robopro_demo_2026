from setuptools import setup

package_name = 'geoglyph'

setup(
    name=package_name,
    version='0.1.0',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Hyu',
    maintainer_email='hyu0627@keio.jp',
    description='生成AIで地上絵の軌跡を生成しPathとして配信するノード群',
    license='MIT',
    entry_points={
        'console_scripts': [
            # テキスト -> (Claude APIまたはMOCK) -> 軌跡 -> map座標変換 -> /geoglyph_path
            'geoglyph_generator = geoglyph.geoglyph_generator:main',
            # /geoglyph_path -> nav2 FollowWaypoints へ送信（巡回）
            'waypoint_sender = geoglyph.waypoint_sender:main',
        ],
    },
)
