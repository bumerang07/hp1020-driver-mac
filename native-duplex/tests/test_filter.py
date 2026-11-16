#!/usr/bin/env python3
"""Real CUPS raster I/O and real filter subprocess; vendor and user are simulated."""
import os, pathlib, pwd, signal, subprocess, tempfile, time
BASE = pathlib.Path(__file__).resolve().parents[1]
USER = pwd.getpwuid(os.getuid()).pw_name

def build(cmd):
    subprocess.run(cmd, check=True)

with tempfile.TemporaryDirectory(prefix='hp1020-tests-') as tmp:
    root = pathlib.Path(tmp)
    fixture = root / 'vendor'
    executable = root / 'filter'
    ipc_prefix = str(root / 'user-')
    ipc = pathlib.Path(ipc_prefix + str(os.getuid()))
    ipc.mkdir(mode=0o1733)
    ipc.chmod(0o1733)
    build(['xcrun','clang','-Wno-deprecated-declarations',str(BASE/'tests/raster_fixture.c'),'-lcups','-o',str(fixture)])
    build(['xcrun','clang','-std=c11','-Wall','-Wextra','-Werror','-Wno-deprecated-declarations',
           '-DHP_FILTER="'+str(fixture)+'"','-DIPC_BASE="'+ipc_prefix+'"','-DWAIT_SECONDS=3',
           str(BASE/'filter.c'),'-lcups','-o',str(executable)])
    def run(count, depth=1, mode='LongEdge', replies=None, copies=1, cancel=False, live=True, truncated=False, spoof=False):
        for p in ipc.iterdir(): p.unlink()
        if live: (ipc/'heartbeat').write_text('ready')
        raster = subprocess.check_output([str(fixture),'--generate',str(count),str(depth)])
        source = root/'input.ras'
        source.write_bytes(raster[:-1] if truncated else raster)
        out = root/'output.txt'
        with out.open('wb') as output, (root/'stderr').open('wb') as err:
            process=subprocess.Popen([str(executable),'123',USER,'Test',str(copies),
                                      ('HPManualDuplex='+mode) if mode is not None else '',str(source)],stdout=output,stderr=err)
            replied=set()
            deadline=time.monotonic()+12
            try:
                while process.poll() is None:
                    assert time.monotonic()<deadline, 'filter hung'
                    requests=list(ipc.glob('*.request'))
                    for request in requests:
                        if request.name in replied: continue
                        replied.add(request.name)
                        assert len(out.read_text().split('PASS copies='))-1 == len(replied)*2-1, 'back pass emitted before confirmation'
                        if cancel:
                            process.send_signal(signal.SIGTERM)
                        elif replies is not None:
                            response = replies[len(replied)-1]
                            if spoof:
                                request.with_suffix('.reply').symlink_to(source)
                            else:
                                request.with_suffix('.reply').write_text(response+'\n')
                    time.sleep(.02)
                result=process.wait()
            finally:
                if process.poll() is None: process.kill(); process.wait()
        assert not list(ipc.glob('*.request')), 'request leaked'
        assert not list(ipc.glob('*.reply')), 'reply leaked'
        return result, out.read_text(), (root/'stderr').read_text()
    def pages(text): return [line.split()[-1] for line in text.splitlines() if line.startswith('PAGE ')]
    def raw(n, depth=1): return bytes([n,0x80,0x80+n,0]) if depth==1 else bytes([n,0x80,0x33,0xff,0x80+n,0,0x55,0xff])
    def rotated(data, depth):
        if depth==8: return bytes(data[4:7][::-1]+b'\xff'+data[:3][::-1]+b'\xff')
        rows=[data[:2],data[2:]]
        result=b''
        for row in rows[::-1]:
            bits=''.join(f'{b:08b}' for b in row)[:9][::-1]+'0'*7
            result+=int(bits,2).to_bytes(2,'big')
        return result
    code,text,_=run(4,mode=None,replies=['continue'])
    assert code==0 and pages(text)==[raw(1).hex(),raw(3).hex(),raw(4).hex(),raw(2).hex()]
    for count in (2,4,5):
        code,text,_=run(count,replies=['continue'])
        expected=[raw(n).hex() for n in range(1,count+1,2)]
        expected+=['00000000'] if count%2 else []
        expected += [raw(n).hex() for n in range(count if count%2==0 else count-1,1,-2)]
        assert code==0 and pages(text)==expected, (text, expected)
    for depth in (1,8):
        code,text,_=run(4,depth=depth,mode='ShortEdge',replies=['continue'])
        assert code==0 and pages(text)==[raw(1,depth).hex(),raw(3,depth).hex(),rotated(raw(4,depth),depth).hex(),rotated(raw(2,depth),depth).hex()]
    code,text,_=run(1)
    assert code==0 and pages(text)==[raw(1).hex()]
    code,text,_=run(4,replies=['cancel'])
    assert code==0 and pages(text)==[raw(1).hex(),raw(3).hex()]
    code,text,_=run(4,cancel=True)
    assert code==0 and len(pages(text))==2
    code,text,_=run(4)  # timeout must never print backs
    assert code!=0 and len(pages(text))==2
    code,text,_=run(4,live=False)
    assert code!=0 and not text
    code,text,_=run(4,truncated=True)
    assert code!=0 and not text
    code,text,_=run(4,copies=2,replies=['continue','cancel'])
    assert code==0 and len(pages(text))==6
    code,text,_=run(4,mode='Off',copies=2,live=False)
    assert code==0 and 'PASS copies=2' in text and len(pages(text))==4
    code,text,_=run(4,replies=['continue'],spoof=True)
    assert code!=0 and len(pages(text))==2
    code,text,_=run(5,depth=8,replies=['continue'])
    assert code==0 and pages(text)==[raw(1,8).hex(),raw(3,8).hex(),raw(5,8).hex(),'ffffffffffffffff',raw(4,8).hex(),raw(2,8).hex()]
    code,text,_=run(4,mode='Invalid')
    assert code!=0 and not text
    print('PASS: raster parity/padding; 1/8-bit 180-degree rotation with padding; one page; copies; cancel; SIGTERM; timeout; missing agent; truncated input; simplex passthrough; symlink rejection; white blank padding; invalid option')
