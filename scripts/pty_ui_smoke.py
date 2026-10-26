#!/usr/bin/env python3
"""Run the real Flutter/bridge UI regression against Linux pseudo-terminals."""
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import time


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix="skyport-pty-smoke-") as temporary:
        control = Path(temporary) / "control"
        acknowledgement = Path(temporary) / "ack"
        symlink = Path(temporary) / "serial"
        master, slave = pty.openpty()
        os.symlink(os.ttyname(slave), symlink)
        env = os.environ.copy()
        env["SKYPORT_PTY"] = str(symlink)
        env["SKYPORT_PTY_CONTROL"] = str(control)
        env["SKYPORT_PTY_ACK"] = str(acknowledgement)
        expected = b"PTY\r\n\x00\xff\xa5\x0aABAB\r\n"
        received = bytearray()
        replied = False
        current_master, current_slave = master, slave
        master_open = True
        last_command = ""
        try:
            with tempfile.TemporaryFile(mode="w+t") as output:
                process = subprocess.Popen(
                    [str(root / "tool/test_quiet.sh"), "integration_test/data_transfer_test.dart", "-d", "linux"],
                    cwd=root, env=env, stdout=output, stderr=subprocess.STDOUT, start_new_session=True,
                )
                deadline = time.monotonic() + 600
                try:
                    while process.poll() is None:
                        if time.monotonic() >= deadline:
                            raise TimeoutError("Flutter PTY UI smoke exceeded 600 seconds")
                        if control.exists():
                            command = control.read_text().strip()
                            if command and command != last_command:
                                last_command = command
                                if command in ("unplug1", "unplug2"):
                                    symlink.unlink(missing_ok=True)
                                    os.close(current_master)
                                    os.close(current_slave)
                                    if master_open:
                                        master_open = False
                                elif command == "replace":
                                    current_master, current_slave = pty.openpty()
                                    temporary_link = symlink.with_suffix(".new")
                                    os.symlink(os.ttyname(current_slave), temporary_link)
                                    temporary_link.replace(symlink)
                                else:
                                    raise ValueError(f"Unknown PTY control: {command}")
                                acknowledgement.write_text(command)
                        if master_open and select.select([master], [], [], 0.1)[0]:
                            received.extend(os.read(master, 4096))
                            if not expected.startswith(received):
                                raise AssertionError(f"Transport bytes changed: {received.hex()}")
                            if not replied and len(received) >= 5:
                                os.write(master, b"\x00\xff\xfe\r\n")
                                replied = True
                        if not master_open:
                            time.sleep(0.01)
                    if master_open:
                        while select.select([master], [], [], 0)[0]:
                            received.extend(os.read(master, 4096))
                    if process.returncode != 0:
                        raise RuntimeError(f"Flutter UI smoke exited {process.returncode}; observed TX={received.hex()}, RX injected={replied}")
                    if bytes(received) != expected:
                        raise AssertionError(f"Missing transport data: expected {expected.hex()}, got {received.hex()}")
                finally:
                    if process.poll() is None:
                        os.killpg(process.pid, signal.SIGTERM)
                        try:
                            process.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            os.killpg(process.pid, signal.SIGKILL)
                            process.wait()
                    output.seek(0)
                    print(output.read(), end="")
            print(f"FLUTTER_PTY_UI_SMOKE_OK: exact text/Hex TX={received.hex()}, binary RX=00fffe0d0a, dispose/resubscribe, bounded overflow recovery, clear+stats+gap reset, en/zh selection translation, all flow modes saved/reloaded/applied after core restart, reconnect notice/retry/recovery/user-stop/manual-connect regression")
        finally:
            for fd in (current_master, current_slave):
                try:
                    os.close(fd)
                except OSError:
                    pass


if __name__ == "__main__":
    main()
