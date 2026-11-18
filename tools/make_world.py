"""Original deterministic district layout. Shared by renderer and authority."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
buildings = []
for ix in range(-4, 4):
    for iz in range(-4, 4):
        for side in [-1, 1]:
            x, z = ix * 60 + side * 18, iz * 60 - 10
            style = ['shop', 'house', 'apartment'][(ix + iz + (side == 1)) % 3]
            if ix == iz == 0:
                style = 'shop' if side == -1 else 'police'
            buildings.append(dict(id=f'b{ix}_{iz}_{side}', x=x, z=z, style=style))
obstacles = []
for b in buildings:
    x, z = b['x'], b['z']
    # Front (+Z) has a 2.8m opening, including the server collision model.
    for dx, dz, w, d in [(-6, 0, .35, 10), (6, 0, .35, 10), (0, -5, 12, .35),
                          (-3.7, 5, 4.6, .35), (3.7, 5, 4.6, .35)]:
        obstacles.append([x + dx, z + dz, w, d])
world = dict(version=1, extent=250, chunk_size=60, spawn=[0, 14], buildings=buildings,
             obstacles=obstacles,
             stations=[dict(id='fence', title='SALES CENTER', x=-9, z=10, kind='sell'),
                       dict(id='bank', title='LAUNDRY / BANK', x=12, z=9, kind='launder'),
                       dict(id='police', title='POLICE RECRUITMENT', x=18, z=-8, kind='police'),
                       dict(id='home', title='YOUR FIRST PLOT', x=-18, z=30, kind='build')],
             loot=[dict(id='till', x=-18, z=-12, title='Market register', value=180, w=2, h=1),
                   dict(id='electronics', x=-21, z=-9, title='Electronics', value=250, w=2, h=2),
                   dict(id='cargo', x=-14, z=-10, title='Sealed cargo', value=320, w=3, h=2)],
             vehicles=[dict(id='car1', x=4, z=9), dict(id='car2', x=4, z=-20)])
(ROOT / 'client/data/world.json').write_text(json.dumps(world, indent=2))
print(f'{len(buildings)} buildings; {len(obstacles)} collision walls; 500m boundary')
