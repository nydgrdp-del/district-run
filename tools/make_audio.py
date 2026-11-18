"""Small original procedural placeholder effects; replace during sound production."""
import math, random, struct, wave
from pathlib import Path
random.seed(99)
out=Path(__file__).resolve().parents[1]/'client/assets'
for kind,duration in [('step',.15),('shot',.33)]:
    samples=[]
    for n in range(int(22050*duration)):
        t=n/22050
        if kind=='step':
            v=(random.uniform(-1,1)*.3+math.sin(2*math.pi*85*t)*.25)*math.exp(-t*32)
        else:
            v=(random.uniform(-1,1)*.7+math.sin(2*math.pi*65*t)*.25)*math.exp(-t*20)
        samples.append(struct.pack('<h',int(max(-1,min(1,v))*28000)))
    with wave.open(str(out/f'{kind}.wav'),'wb') as f:
        f.setnchannels(1);f.setsampwidth(2);f.setframerate(22050);f.writeframes(b''.join(samples))
