"""Launch the server first, then run this script against a disposable database."""
import asyncio
import json
from websockets.asyncio.client import connect

async def read_until(ws, predicate):
    async with asyncio.timeout(5):
        while True:
            msg = json.loads(await ws.recv())
            if predicate(msg):
                return msg

async def join(ws, token=''):
    await ws.send(json.dumps(dict(type='hello',protocol=1,token=token)))
    return await read_until(ws, lambda m: m['type']=='welcome')

async def run():
    url='ws://127.0.0.1:8765'
    async with connect(url) as observer:
        await join(observer)
        async with connect(url) as runner:
            account=await join(runner)
            await runner.send(json.dumps(dict(type='action',request='mask-test-01',kind='mask')))
            await read_until(observer,lambda m: any(p['id']==account['id'] and p['masked'] for p in m.get('players',[])))
        await read_until(observer,lambda m: m.get('population')==1)
        async with connect(url) as returning:
            await join(returning,account['token'])
            await read_until(returning,lambda m: m.get('you',{}).get('masked') is True)
    print('PASS: second player saw mask; reconnect restored same account and mask.')

asyncio.run(run())
