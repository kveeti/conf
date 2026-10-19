import argparse
import os
from pathlib import Path
import re
import stat
import subprocess
import sys

RUNTIME = Path('/run')


def server_pid(name):
    if not re.fullmatch(r'[A-Za-z0-9_-]+', name):
        raise RuntimeError('Invalid server name')
    result = subprocess.run(
        ['systemctl', 'show', f'minecraft-{name}.service',
         '--property=LoadState,ActiveState,MainPID'],
        capture_output=True, text=True, check=True, timeout=5,
    )
    state = dict(line.split('=', 1) for line in result.stdout.splitlines())
    if state.get('LoadState') == 'not-found' or state.get('ActiveState') in ('inactive', 'failed'):
        return None
    if state.get('ActiveState') != 'active' or int(state.get('MainPID', '0')) == 0:
        raise RuntimeError(f'Minecraft server {name} is starting or stopping; try again shortly')
    return int(state['MainPID'])


def send_command(name, command, expected_pid=None):
    pid = server_pid(name)
    if pid is None:
        raise RuntimeError(f'Minecraft server {name} is not running')
    if expected_pid is not None and pid != expected_pid:
        raise RuntimeError(f'Minecraft server {name} restarted; refusing to send a stale command')
    if not command.strip() or '\n' in command or '\r' in command or '\0' in command:
        raise RuntimeError('Provide one non-empty Minecraft command')
    path = RUNTIME / f'minecraft-{name}.stdin'
    fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    try:
        if not stat.S_ISFIFO(os.fstat(fd).st_mode):
            raise RuntimeError(f'{path} is not a command pipe')
        data = (command + '\n').encode()
        if len(data) > os.fpathconf(fd, 'PC_PIPE_BUF'):
            raise RuntimeError('Minecraft command is too long')
        os.write(fd, data)
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description='Send a Minecraft command; view replies with journalctl -fu minecraft-servu')
    parser.add_argument('--server', default='servu')
    parser.add_argument('command')
    args = parser.parse_args()
    try:
        send_command(args.server, args.command)
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f'mc-command: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
