#!/usr/bin/env python3
"""Offline two-pass integration. Input must be a ONE-page synthetic CUPS raster.
Requires the confirmation agent and original HP converter to be installed.
No USB backend is started; printer bytes are captured in memory.
"""
import concurrent.futures
import os
import pathlib
import pwd
import subprocess
import sys
import tempfile
import time
base=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(sys.argv[1]).read_bytes()
assert source[:4] in (b'RaSt',b'tSaR',b'RaS2',b'2SaR',b'RaS3',b'3SaR'), 'Not a CUPS raster stream'
ipc=pathlib.Path('/Users/Shared/hp1020-duplex-'+str(os.getuid()))
initial={p.name for p in ipc.glob('*.request')}
with tempfile.TemporaryDirectory(prefix='hp1020-integration-') as tmp:
    raster=pathlib.Path(tmp)/'two-pages.ras'
    # A raster file has one four-byte sync word, followed by page records.
    raster.write_bytes(source+source[4:])
    env=dict(os.environ,PPD=str(base/'build/HP1020-ManualDuplex.ppd'),TMPDIR=tmp)
    p=subprocess.Popen([str(base/'build/hp1020duplex'),'123',pwd.getpwuid(os.getuid()).pw_name,
                        'Synthetic offline integration test','1','HPManualDuplex=LongEdge HPResolution=600dpi',
                        str(raster)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    requests=[]
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            output=pool.submit(p.communicate,timeout=15)
            deadline=time.monotonic()+15
            while not output.done():
                for request in ipc.glob('*.request'):
                    if request.name in initial or request in requests: continue
                    assert request.stat().st_uid==os.getuid(), 'Unexpected request owner'
                    assert request.read_text().strip()=='123\t2\t1\t1', 'Unexpected test request'
                    requests.append(request)
                    request.with_suffix('.reply').write_text('continue\n')
                if time.monotonic()>deadline:
                    p.kill()
                    raise AssertionError('Full two-pass integration timed out')
                time.sleep(.02)
            stdout,stderr=output.result()
        assert p.returncode==0, stderr.decode(errors='replace')[-2000:]
        assert len(requests)==1 and len(stdout)>20000, (len(requests),len(stdout))
        assert all(not r.exists() and not r.with_suffix('.reply').exists() for r in requests)
        print('PASS: real HP converter, two raster passes, confirmation handshake, clean exit; output bytes:',len(stdout))
    finally:
        if p.poll() is None: p.kill(); p.wait()
        for request in requests:
            request.unlink(missing_ok=True)
            request.with_suffix('.reply').unlink(missing_ok=True)
