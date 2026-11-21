"""Render the original, short in-game cues with Python's standard library."""
from pathlib import Path
import math
import random
import struct
import wave

folder = Path(__file__).resolve().parents[1] / 'IronFront/Art/Audio'
folder.mkdir(exist_ok=True)
for name, length, base, end in [('select', .08, 440, 590), ('order', .13, 420, 760),
                                ('complete', .28, 570, 880), ('contact', .20, 98, 41)]:
    rng = random.Random(821)
    samples = bytearray()
    for i in range(int(22050*length)):
        t = i/22050
        envelope = min(1, t/.008) * (1-t/length)**2
        tone = math.sin(2*math.pi*(base*t + (end-base)*t*t/(2*length)))
        if name == 'contact':
            tone = .55*tone + .45*rng.uniform(-1,1)
        samples.extend(struct.pack('<h', int(tone*envelope*11500)))
    with wave.open(str(folder/(name+'.wav')), 'wb') as f:
        f.setparams((1,2,22050,0,'NONE','not compressed'))
        f.writeframes(samples)
