#!/usr/bin/env python3
"""Keep a bounded kubectl port-forward alive across closed upgraded streams."""
import signal
import subprocess
import sys
import time

child = None
stopping = False


def stop(signum, frame):
    global stopping
    stopping = True
    if child is not None and child.poll() is None:
        child.terminate()


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)
for attempt in range(20):
    if stopping:
        break
    child = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL)
    code = child.wait()
    child = None
    if stopping or code == 0:
        break
    print(f'Port-forward exited {code}; reconnect {attempt + 1}/20', flush=True)
    time.sleep(0.25)
else:
    sys.exit('Port-forward exhausted its bounded reconnect budget')
