import argparse
import contextlib
import fcntl
import http.client
import json
import logging
from logging.handlers import RotatingFileHandler
import os
from pathlib import Path
import select
import socket
import stat
import sys
import time

BASE = Path.home() / 'Library/Application Support/mihomo-party'
STATE = BASE / 'dns-cache-helper'
SUCCESS_MARKERS = ('Initial configuration complete', 'hot reload config completed',
                   'Config reloaded successfully', 'Core restarted successfully')


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, path, timeout=3):
        super().__init__('localhost', timeout=timeout)
        self.path = str(path)

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout)
        self.sock.connect(self.path)


def api(path, method='GET', payload=None, socket_path=None):
    conn = UnixHTTPConnection(socket_path or discover_socket())
    body = json.dumps(payload) if payload is not None else None
    try:
        conn.request(method, path, body, {'Content-Type': 'application/json'} if body else {})
        response = conn.getresponse()
        data = response.read()
        if response.status >= 400:
            raise RuntimeError(f'核心接口 {method} {path} 返回 HTTP {response.status}')
        return response.status, json.loads(data) if data.strip() else None
    finally:
        conn.close()


def discover_socket(directory=Path('/tmp'), uid=None):
    uid = os.getuid() if uid is None else uid
    found = []
    for path in directory.glob(f'mihomo-party-{uid}-*.sock'):
        try:
            # Privileged Clash cores create root-owned sockets; the name identifies the GUI user.
            if not stat.S_ISSOCK(path.stat().st_mode):
                continue
            status, version = api('/version', socket_path=path)
            if status == 200 and version.get('meta') is True and version.get('version'):
                found.append(path)
        except (OSError, RuntimeError, ValueError, http.client.HTTPException):
            continue
    if len(found) > 1:
        raise RuntimeError('发现多个可用 Clash 核心，未执行刷新')
    if not found:
        raise RuntimeError('Clash 核心未运行或接口不可用')
    return found[0]


@contextlib.contextmanager
def locked(state=STATE, name='flush.lock'):
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (state / name).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def flush(socket_path=None, state=STATE):
    with locked(state):
        status, _ = api('/cache/dns/flush', 'POST', socket_path=socket_path)
        if status != 204:
            raise RuntimeError(f'DNS 刷新未确认成功（HTTP {status}）')


class PendingFlush:
    def __init__(self):
        self.due = None
        self.attempts = 0

    def observe(self, text, now):
        if any(marker in text for marker in SUCCESS_MARKERS):
            self.due = now + 1
            self.attempts = 0
            return True
        return False

    def run(self, now, action, logger):
        if self.due is None or now < self.due:
            return
        try:
            action()
        except (OSError, RuntimeError, ValueError, http.client.HTTPException) as error:
            self.attempts += 1
            logger.warning('加载后刷新失败 (%s/3): %s', self.attempts, error)
            self.due = now + 2 if self.attempts < 3 else None
        else:
            self.due = None
            logger.info('配置加载后 DNS 缓存刷新成功')


class LogTail:
    def __init__(self, path, historical=False):
        self.path = path
        self.file = path.open('rb')
        self.identity = os.fstat(self.file.fileno()).st_ino
        self.partial = b''
        if historical:
            self.file.seek(0, os.SEEK_END)

    def read(self):
        if os.fstat(self.file.fileno()).st_size < self.file.tell():
            self.file.seek(0)
            self.partial = b''
        # Bounded reads; process complete lines only, including fragmented writes.
        data = self.partial + self.file.read(1024 * 1024)
        lines = data.split(b'\n')
        self.partial = lines.pop()
        return b'\n'.join(lines).decode('utf-8', errors='replace')

    def close(self):
        self.file.close()


def configure_logger(state):
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    logger = logging.getLogger('clash-dns')
    logger.setLevel(logging.INFO)
    handler = RotatingFileHandler(state / 'events.log', maxBytes=256 * 1024, backupCount=2)
    handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(message)s'))
    logger.addHandler(handler)
    return logger


def watch(base=BASE, state=STATE, socket_path=None):
    logger = configure_logger(state)
    logs = base / 'logs'
    if not logs.is_dir():
        raise RuntimeError('Clash 日志目录不存在')
    # A second LaunchAgent/manual watcher must not replay the same events.
    with locked(state, 'watch.lock'):
        kq = select.kqueue()
        directory_fd = os.open(logs, os.O_RDONLY)
        tails = {}
        flags = select.KQ_NOTE_WRITE | select.KQ_NOTE_RENAME | select.KQ_NOTE_DELETE | select.KQ_NOTE_ATTRIB

        def register(fd):
            kq.control([select.kevent(fd, filter=select.KQ_FILTER_VNODE,
                                     flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR, fflags=flags)], 0)

        register(directory_fd)
        pending = PendingFlush()

        def reconcile(historical=False):
            # Current day's logs plus the previous day handle midnight and clock skew.
            paths = set()
            for prefix in ['core-', 'clash-party-']:
                paths.update(sorted(logs.glob(prefix + '*.log'))[-2:])
            for path, tail in list(tails.items()):
                if path not in paths or not path.exists() or path.stat().st_ino != tail.identity:
                    kq.control([select.kevent(tail.file.fileno(), filter=select.KQ_FILTER_VNODE,
                                             flags=select.KQ_EV_DELETE)], 0)
                    tail.close()
                    del tails[path]
            for path in paths - tails.keys():
                tail = LogTail(path, historical)
                tails[path] = tail
                register(tail.file.fileno())
                pending.observe(tail.read(), time.monotonic())

        try:
            reconcile(historical=True)
            logger.info('监视已启动；只处理新增配置完成日志，无定时刷新')
            try:
                # Catch up once after helper downtime; never replay historical success lines.
                flush(socket_path, state)
                logger.info('辅助工具启动时 DNS 缓存刷新成功')
            except (OSError, RuntimeError, ValueError, http.client.HTTPException) as error:
                logger.warning('启动时未刷新: %s；等待配置完成事件', error)
            while True:
                now = time.monotonic()
                timeout = max(0, pending.due - now) if pending.due is not None else 60
                events = kq.control(None, 32, timeout)
                if any(e.ident == directory_fd for e in events):
                    reconcile()
                for tail in list(tails.values()):
                    pending.observe(tail.read(), time.monotonic())
                pending.run(time.monotonic(), lambda: flush(socket_path, state), logger)
        finally:
            for tail in tails.values():
                tail.close()
            os.close(directory_fd)
            kq.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--flush', action='store_true')
    parser.add_argument('--watch', action='store_true')
    parser.add_argument('--base', type=Path, default=BASE)
    parser.add_argument('--state', type=Path, default=STATE)
    parser.add_argument('--socket', type=Path, help='仅用于隔离测试，日常自动发现')
    args = parser.parse_args()
    if not (args.flush or args.watch) or (args.flush and args.watch):
        parser.error('选择 --flush 或 --watch')
    try:
        if args.flush:
            flush(args.socket, args.state)
            print('Clash DNS 缓存已刷新。')
        else:
            watch(args.base, args.state, args.socket)
    except (OSError, RuntimeError, ValueError, http.client.HTTPException) as error:
        print(f'Clash DNS 刷新失败：{error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
