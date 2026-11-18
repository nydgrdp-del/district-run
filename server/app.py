import asyncio
import json
import logging
import os
import time
from collections import deque
from pathlib import Path
from websockets.asyncio.server import serve
from websockets.exceptions import ConnectionClosed
from model import World, Rejected, TICK

LOG = logging.getLogger('district')

class GameServer:
    def __init__(self, db):
        self.world = World(db)
        self.clients = {}

    async def handler(self, ws):
        player = None
        try:
            # Idle and malformed unauthenticated sockets don't occupy player slots.
            raw = await asyncio.wait_for(ws.recv(), timeout=8)
            data = json.loads(raw)
            if not isinstance(data, dict) or data.get('type') != 'hello' or data.get('protocol') != 1:
                raise Rejected('Unsupported protocol')
            player, token = self.world.login(data.get('token',''),data.get('name','Runner'))
            self.clients[player.id] = ws
            await ws.send(json.dumps(dict(type='welcome',id=player.id,token=token,protocol=1)))
            window = deque()
            async for raw in ws:
                now = time.monotonic()
                while window and window[0] < now-1:
                    window.popleft()
                window.append(now)
                if len(window) > 65:
                    await ws.close(1008, 'Rate limit')
                    break
                request = ''
                try:
                    data = json.loads(raw)
                    if not isinstance(data, dict):
                        raise Rejected('Expected object')
                    kind = data.get('type')
                    if kind == 'input':
                        self.world.input(player, data)
                    elif kind == 'action':
                        request = data.get('request', '')
                        if not isinstance(data.get('target',''),str):
                            raise Rejected('Invalid target')
                        result = self.world.action(player, request, data.get('kind'), data.get('target',''))
                        await ws.send(json.dumps(result))
                    elif kind == 'shoot':
                        self.world.shoot(player)
                    elif kind == 'ping':
                        await ws.send(json.dumps(dict(type='pong',stamp=data.get('stamp'))))
                    else:
                        raise Rejected('Unknown message')
                except (Rejected, json.JSONDecodeError) as exc:
                    await ws.send(json.dumps(dict(type='result',ok=False,request=request,message=str(exc))))
        except (Rejected, json.JSONDecodeError, TypeError, asyncio.TimeoutError) as exc:
            try:
                await ws.send(json.dumps(dict(type='error',message=str(exc))))
                await ws.close(1008, 'Handshake rejected')
            except ConnectionClosed:
                pass
        except ConnectionClosed:
            pass
        finally:
            if player:
                self.clients.pop(player.id, None)
                self.world.disconnect(player.id)

    async def simulation(self):
        deadline = time.monotonic()
        while True:
            self.world.step()
            if self.world.tick_id % 2 == 0:
                # Bound slow client writes so they cannot pause world simulation.
                jobs = []
                for pid, ws in list(self.clients.items()):
                    p = self.world.players.get(pid)
                    if p:
                        data = self.world.snapshot(p)
                        data['events'] = [e for e in self.world.events
                                          if ((p.x-e['x'])**2+(p.z-e['z'])**2) < 100**2]
                        jobs.append(self.send_snapshot(ws, data))
                self.world.events.clear()
                if jobs:
                    await asyncio.gather(*jobs)
            deadline += TICK
            if deadline < time.monotonic()-TICK:
                deadline = time.monotonic()
            await asyncio.sleep(max(0, deadline-time.monotonic()))

    @staticmethod
    async def send_snapshot(ws, data):
        try:
            await asyncio.wait_for(ws.send(json.dumps(data, separators=(',',':'))), .025)
        except (ConnectionClosed, asyncio.TimeoutError):
            await ws.close(1013, 'Slow connection')

async def main():
    db = Path(os.getenv('DISTRICT_DB', 'district.sqlite3'))
    db.parent.mkdir(parents=True,exist_ok=True)
    server = GameServer(db)
    # Default is local development. Expose only behind a TLS proxy for public use.
    host, port = os.getenv('HOST','127.0.0.1'), int(os.getenv('PORT','8765'))
    async with serve(server.handler,host,port,max_size=4096,max_queue=16,
                     ping_interval=15,ping_timeout=15,compression=None):
        LOG.info('District shard listening on %s:%s',host,port)
        try:
            await server.simulation()
        finally:
            for pid in list(server.world.players):
                server.world.disconnect(pid)
            server.world.db.close()

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    asyncio.run(main())
