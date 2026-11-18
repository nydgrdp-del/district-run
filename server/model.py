"""Authoritative simulation. No client positions, money or damage are trusted.

Single-process development shard. All economy writes are SQLite transactions.
This is an original implementation, not ROB RUN's code or exact balance.
"""
from __future__ import annotations
import hashlib
import json
import math
import secrets
import sqlite3
import time
from dataclasses import dataclass, field
from pathlib import Path

WORLD = json.loads((Path(__file__).resolve().parents[1] / 'client/data/world.json').read_text())
TICK = .05
MAX_PLAYERS = 32
AOI = 100

class Rejected(ValueError):
    pass

def finite(value, low, high):
    if type(value) not in (int, float) or not math.isfinite(value):
        raise Rejected('Invalid number')
    return max(low, min(high, float(value)))

def pack(items):
    grid = set()
    slots = []
    for item in items:
        found = False
        for y in range(4):
            for x in range(6):
                cells = {(x + dx, y + dy) for dx in range(item['w']) for dy in range(item['h'])}
                if x + item['w'] <= 6 and y + item['h'] <= 4 and not cells & grid:
                    grid |= cells
                    slots.append(dict(item, gx=x, gy=y))
                    found = True
                    break
            if found:
                break
        if not found:
            raise Rejected('Bag is full')
    return slots

@dataclass
class Player:
    id: str
    name: str
    x: float = 0
    z: float = 14
    yaw: float = 0
    hp: int = 100
    cash: int = 0
    bank: int = 500
    bag: list = field(default_factory=list)
    role: str = 'civilian'
    masked: bool = False
    heat: int = 0
    ammo: int = 12
    reserve: int = 60
    house: bool = False
    laundry: dict = field(default_factory=dict)
    vehicle: str = ''
    move: tuple = (0, 0)
    sprint: bool = False
    input_at: float = 0
    sequence: int = -1
    shot_at: float = -100
    reload_until: float = 0
    last_action: float = -100
    speed: float = 0

    def public(self):
        return dict(id=self.id, name=self.name, x=round(self.x, 3), z=round(self.z, 3),
                    yaw=round(self.yaw, 3), hp=self.hp, role=self.role, masked=self.masked,
                    heat=self.heat, vehicle=self.vehicle, speed=round(self.speed, 2))

    def private(self):
        return dict(self.public(), cash=self.cash, bank=self.bank, bag=pack(self.bag),
                    ammo=self.ammo, reserve=self.reserve, house=self.house, laundry=self.laundry,
                    reloading=self.reload_until > 0)

class World:
    def __init__(self, db_path, clock=time.time):
        self.clock = clock
        self.db = sqlite3.connect(str(db_path))
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('PRAGMA foreign_keys=ON')
        self.db.executescript('''
        CREATE TABLE IF NOT EXISTS accounts(id TEXT PRIMARY KEY, token_hash TEXT UNIQUE, state TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS actions(account TEXT, request TEXT, response TEXT, PRIMARY KEY(account,request));
        CREATE TABLE IF NOT EXISTS ledger(id INTEGER PRIMARY KEY, account TEXT, kind TEXT, cash INTEGER, bank INTEGER, at REAL);
        CREATE TABLE IF NOT EXISTS state(key TEXT PRIMARY KEY, value TEXT);
        ''')
        self.players = {}
        self.cooldowns = self.load_meta('cooldowns', {})
        self.drops = self.load_meta('drops', {})
        self.vehicles = {v['id']: dict(v, yaw=0, owner='') for v in WORLD['vehicles']}
        self.events = []
        self.tick_id = 0

    def load_meta(self, key, default):
        row = self.db.execute('SELECT value FROM state WHERE key=?', (key,)).fetchone()
        return json.loads(row[0]) if row else default

    def persist(self, p):
        # No input vector or client session is restored after a reconnect.
        fields = ('name','x','z','hp','cash','bank','bag','role','masked','heat','ammo','reserve','house','laundry')
        state = {key: getattr(p, key) for key in fields}
        self.db.execute('UPDATE accounts SET state=? WHERE id=?', (json.dumps(state), p.id))

    def persist_meta(self):
        for key, val in [('cooldowns', self.cooldowns), ('drops', self.drops)]:
            self.db.execute('INSERT OR REPLACE INTO state VALUES (?,?)', (key, json.dumps(val)))

    def login(self, token='', name='Runner'):
        if len(self.players) >= MAX_PLAYERS:
            raise Rejected('Shard is full')
        if not isinstance(token, str) or len(token) > 128:
            raise Rejected('Invalid credential')
        raw = token
        row = self.db.execute('SELECT id,state FROM accounts WHERE token_hash=?',
                              (hashlib.sha256(token.encode()).hexdigest(),)).fetchone() if token else None
        if token and row is None:
            raise Rejected('Credential is unknown. Keep your original device key.')
        if row:
            if row[0] in self.players:
                raise Rejected('Account already connected')
            p = Player(row[0], 'Runner')
            for k, v in json.loads(row[1]).items():
                setattr(p, k, v)
        else:
            if not isinstance(name, str):
                raise Rejected('Invalid name')
            name = ''.join(c for c in name if c.isalnum() or c in ' _-').strip()[:20] or 'Runner'
            raw = secrets.token_urlsafe(32)
            p = Player(secrets.token_hex(8), name)
            with self.db:
                self.db.execute('INSERT INTO accounts VALUES (?,?,?)',
                                (p.id, hashlib.sha256(raw.encode()).hexdigest(), '{}'))
                self.persist(p)
        self.players[p.id] = p
        return p, raw

    def disconnect(self, pid):
        p = self.players.pop(pid, None)
        if p:
            if p.vehicle:
                self.vehicles[p.vehicle]['owner'] = ''
                p.vehicle = ''
            with self.db:
                self.persist(p)

    def input(self, p, data):
        seq = data.get('seq')
        if type(seq) != int or seq <= p.sequence or seq > 2**53:
            return
        x = finite(data.get('x', 0), -1, 1)
        z = finite(data.get('z', 0), -1, 1)
        yaw = finite(data.get('yaw', 0), -10000, 10000)
        length = math.hypot(x, z)
        if length > 1:
            x, z = x / length, z / length
        p.sequence, p.move, p.yaw = seq, (x, z), yaw % math.tau
        p.sprint = data.get('sprint') is True
        p.input_at = self.clock()

    @staticmethod
    def blocked(x, z, radius=.36):
        if abs(x) > WORLD['extent'] - radius or abs(z) > WORLD['extent'] - radius:
            return True
        return any(abs(x-ox) < w/2+radius and abs(z-oz) < d/2+radius
                   for ox, oz, w, d in WORLD['obstacles'])

    def line_clear(self, x, z, tx, tz):
        steps = max(1, math.ceil(math.hypot(tx-x, tz-z) / .2))
        return all(not self.blocked(x+(tx-x)*i/steps, z+(tz-z)*i/steps, .02)
                   for i in range(1, steps+1))

    def step(self, dt=TICK):
        # Caller controls fixed dt; never receive it from clients.
        now = self.clock()
        self.tick_id += 1
        for p in self.players.values():
            x, z = p.move if now - p.input_at < .35 else (0, 0)
            radius = 1.1 if p.vehicle else .36
            if p.vehicle:
                target = -z * 16
                p.speed += max(-8*dt, min(6*dt, target-p.speed))
                car = self.vehicles[p.vehicle]
                car['yaw'] += -x * dt * (p.speed / 12)
                dx, dz = -math.sin(car['yaw']) * p.speed * dt, -math.cos(car['yaw']) * p.speed * dt
                p.yaw = car['yaw']
            else:
                p.speed = math.hypot(x, z) * (6.2 if p.sprint else 3.8)
                dx, dz = x * (6.2 if p.sprint else 3.8)*dt, z*(6.2 if p.sprint else 3.8)*dt
            # Substeps avoid driving through thin walls.
            n = max(1, math.ceil(max(abs(dx), abs(dz)) / .15))
            for _ in range(n):
                if not self.blocked(p.x+dx/n, p.z, radius):
                    p.x += dx/n
                if not self.blocked(p.x, p.z+dz/n, radius):
                    p.z += dz/n
            if p.vehicle:
                self.vehicles[p.vehicle].update(x=p.x, z=p.z)
            if p.reload_until and now >= p.reload_until:
                amount = min(12-p.ammo, p.reserve)
                p.ammo += amount
                p.reserve -= amount
                p.reload_until = 0
        if self.tick_id % 100 == 0:
            with self.db:
                for p in self.players.values():
                    self.persist(p)

    def near(self, p, obj, radius=3.0):
        return math.hypot(p.x-obj['x'], p.z-obj['z']) <= radius

    def require_station(self, p, kind):
        if not any(s['kind'] == kind and self.near(p, s) for s in WORLD['stations']):
            raise Rejected('Move closer to the station')

    def action(self, p, request, kind, target=''):
        if not isinstance(request, str) or not 8 <= len(request) <= 80:
            raise Rejected('Invalid request ID')
        old = self.db.execute('SELECT response FROM actions WHERE account=? AND request=?', (p.id,request)).fetchone()
        if old:
            return json.loads(old[0])
        now = self.clock()
        if now - p.last_action < .12:
            raise Rejected('Too many actions')
        p.last_action = now
        if p.vehicle and kind not in ('vehicle',):
            raise Rejected('Exit the vehicle first')
        message = ''
        # Every branch validates before mutation. Synchronous single-threaded handlers
        # and one DB transaction serialize contested loot, money and request IDs.
        with self.db:
            if kind == 'mask':
                if p.role == 'police':
                    raise Rejected('Police cannot wear a robbery mask')
                if p.masked and p.heat:
                    raise Rejected('Use the police station to surrender first')
                p.masked = not p.masked
                message = 'Mask on: you are vulnerable' if p.masked else 'Mask removed'
            elif kind == 'loot':
                obj = next((v for v in WORLD['loot'] if v['id'] == target), None)
                if not obj or not self.near(p, obj) or not self.line_clear(p.x,p.z,obj['x'],obj['z']):
                    raise Rejected('Loot is out of reach')
                if not p.masked:
                    raise Rejected('Equip your mask to rob the store')
                if now < self.cooldowns.get(target, 0):
                    raise Rejected('Already looted. Restock takes 60 seconds')
                item = dict(obj, uid=secrets.token_hex(8))
                pack(p.bag + [item])
                p.bag.append(item)
                p.heat = min(5, p.heat+1)
                self.cooldowns[target] = now + 60
                message = f"Stolen: {obj['title']}"
            elif kind == 'sell':
                self.require_station(p, 'sell')
                if not p.bag:
                    raise Rejected('Bag is empty')
                value = sum(i['value'] for i in p.bag)
                p.cash += value
                p.bag = []
                message = f'Sold for ${value} dirty cash'
            elif kind == 'launder':
                self.require_station(p, 'launder')
                if p.laundry:
                    if now < p.laundry['ready']:
                        raise Rejected('Laundering is still running')
                    value = p.laundry['amount']
                    p.bank += value
                    p.laundry = {}
                    message = f'Collected ${value} clean funds'
                else:
                    if p.cash < 50:
                        raise Rejected('Requires at least $50 dirty cash')
                    p.laundry = dict(amount=int(p.cash*.9), ready=now+20)
                    p.cash = 0
                    message = 'Laundering started: 20 seconds, 10% fee'
            elif kind == 'police':
                self.require_station(p, 'police')
                if p.heat or p.bag:
                    raise Rejected('Surrender and clear your bag first')
                if p.role != 'police' and sum(v.role=='police' for v in self.players.values()) >= 4:
                    raise Rejected('All four police slots are occupied')
                p.role = 'civilian' if p.role == 'police' else 'police'
                p.masked = False
                message = f'Role: {p.role}'
            elif kind == 'surrender':
                self.require_station(p, 'police')
                p.bag, p.heat, p.masked = [], 0, False
                message = 'Surrendered: bag confiscated, heat cleared'
            elif kind == 'build':
                self.require_station(p, 'build')
                if p.house:
                    raise Rejected('Your plot is already built')
                if p.bank < 300:
                    raise Rejected('Requires $300 clean funds')
                p.bank -= 300
                p.house = True
                message = 'Private starter home built'
            elif kind == 'vehicle':
                if p.vehicle:
                    car = self.vehicles[p.vehicle]
                    exit_pos = next(((p.x+dx,p.z+dz) for dx,dz in [(2,0),(-2,0),(0,3),(0,-3)]
                                     if not self.blocked(p.x+dx,p.z+dz)), None)
                    if exit_pos is None:
                        raise Rejected('No safe exit')
                    p.x, p.z = exit_pos
                    car['owner'] = ''
                    p.vehicle = ''
                    p.speed = 0
                    message = 'Vehicle exited'
                else:
                    car = self.vehicles.get(target)
                    if not car or not self.near(p,car,4) or car['owner']:
                        raise Rejected('Vehicle unavailable')
                    if self.blocked(car['x'],car['z'],1.1):
                        raise Rejected('Vehicle is obstructed')
                    car['owner'], p.vehicle = p.id, target
                    p.x, p.z, p.speed = car['x'], car['z'], 0
                    message = 'Driving: forward / reverse / steering'
            elif kind == 'pickup':
                drop = self.drops.get(target)
                if not drop or not self.near(p,drop):
                    raise Rejected('Drop unavailable')
                pack(p.bag + drop['items'])
                p.bag.extend(drop['items'])
                del self.drops[target]
                message = 'Loot recovered'
            elif kind == 'reload':
                if p.reload_until or p.ammo == 12 or p.reserve == 0:
                    raise Rejected('Cannot reload')
                p.reload_until = now+1.4
                message = 'Reloading'
            else:
                raise Rejected('Unknown action')
            self.persist(p)
            self.persist_meta()
            result = dict(type='result', request=request, ok=True, message=message)
            self.db.execute('INSERT INTO actions VALUES (?,?,?)', (p.id,request,json.dumps(result)))
            self.db.execute('INSERT INTO ledger(account,kind,cash,bank,at) VALUES(?,?,?,?,?)',
                            (p.id,kind,p.cash,p.bank,now))
        return result

    def shoot(self, p):
        now = self.clock()
        if p.vehicle or p.reload_until or p.ammo <= 0 or now-p.shot_at < .28:
            raise Rejected('Weapon is not ready')
        p.shot_at, p.ammo = now, p.ammo-1
        direction = (-math.sin(p.yaw), -math.cos(p.yaw))
        candidates = []
        for q in self.players.values():
            if q.id == p.id or q.vehicle:
                continue
            dx,dz = q.x-p.x,q.z-p.z
            distance = math.hypot(dx,dz)
            along = dx*direction[0]+dz*direction[1]
            across = abs(dx*direction[1]-dz*direction[0])
            if 0 < along < 40 and across < .5 and self.line_clear(p.x,p.z,q.x,q.z):
                candidates.append((distance,q))
        hit = ''
        if candidates:
            distance,q = min(candidates,key=lambda v:v[0])
            if q.masked or q.heat or (p.masked and q.role == 'police'):
                hit = q.id
                q.hp -= max(8, int(25-distance*.35))
                if q.hp <= 0:
                    if (q.masked or q.heat) and q.bag:
                        self.drops[secrets.token_hex(8)] = dict(x=q.x,z=q.z,items=q.bag)
                        q.bag = []
                    q.x,q.z,q.hp,q.heat,q.masked = 0,14,100,0,False
                    q.move = (0,0)
                    q.input_at = 0
                with self.db:
                    self.persist(q)
                    self.persist_meta()
        with self.db:
            self.persist(p)
        event = dict(type='shot', source=p.id, x=p.x,z=p.z,yaw=p.yaw,hit=hit)
        self.events.append(event)
        return event

    def snapshot(self, p):
        nearby = lambda obj: math.hypot(p.x-obj['x'],p.z-obj['z']) <= AOI
        return dict(type='snapshot', tick=self.tick_id, at=self.clock(), you=p.private(),
                    players=[q.public() for q in self.players.values() if q.id!=p.id and nearby(q.public())],
                    vehicles=[v for v in self.vehicles.values() if nearby(v)],
                    drops=[dict(id=k,x=v['x'],z=v['z']) for k,v in self.drops.items() if nearby(v)],
                    loot=[dict(id=v['id'],ready=self.clock()>=self.cooldowns.get(v['id'],0)) for v in WORLD['loot'] if nearby(v)],
                    population=len(self.players))
