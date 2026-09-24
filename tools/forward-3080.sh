#!/data/data/com.termux/files/usr/bin/bash
# 把只监听 127.0.0.1:3080 的 DSH 控制台，转发到局域网 0.0.0.0:3081。
# 仅在你需要"局域网内从别的设备连 DSH"时用。Ctrl-C 结束。
# 注意：这会把你手机的 3081 端口对**同一局域网**开放。
set -u
python3 - <<'PY'
import socket, threading
LISTEN = ('0.0.0.0', 3081)
TARGET = ('127.0.0.1', 3080)

def pump(a, b):
    try:
        while True:
            d = a.recv(65536)
            if not d:
                break
            b.sendall(d)
    except Exception:
        pass
    finally:
        try: a.close()
        except Exception: pass
        try: b.close()
        except Exception: pass

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(LISTEN)
srv.listen(32)
print('[forward] http://0.0.0.0:3081/  ->  127.0.0.1:3080  （Ctrl-C 结束）')
while True:
    c, addr = srv.accept()
    try:
        t = socket.create_connection(TARGET)
    except Exception:
        c.close(); continue
    threading.Thread(target=pump, args=(c, t), daemon=True).start()
    threading.Thread(target=pump, args=(t, c), daemon=True).start()
PY

