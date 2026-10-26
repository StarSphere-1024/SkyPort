#!/usr/bin/env python3
"""Capture the real Windows UI with deterministic demo data; no serial hardware."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


# Capture only the test application's window, never an arbitrary SkyPort instance.
WINDOW_SCRIPT = r'''
param([int]$AppPid, [int]$Width, [int]$Height, [string]$Output)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class CaptureWindow {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int height, bool repaint);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("dwmapi.dll")] public static extern int DwmFlush();
  public struct RECT { public int L, T, R, B; }
}
'@
[CaptureWindow]::SetProcessDPIAware() | Out-Null
$window = (Get-Process -Id $AppPid).MainWindowHandle
if ($window -eq 0) { throw 'Screenshot application has no desktop window' }
$screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
if ($Width -gt $screen.Width -or $Height -gt $screen.Height) {
  throw 'Requested screenshot is larger than the primary display'
}
$x = [int](($screen.Width - $Width) / 2)
$y = [int](($screen.Height - $Height) / 2)
[CaptureWindow]::ShowWindow($window, 9) | Out-Null
if (![CaptureWindow]::SetForegroundWindow($window)) { throw 'Cannot foreground screenshot window; keep the desktop unlocked' }
if (![CaptureWindow]::MoveWindow($window, $x, $y, $Width, $Height, $true)) { throw 'Cannot resize screenshot window' }
[CaptureWindow]::DwmFlush() | Out-Null
if ($Output) {
  $r = New-Object CaptureWindow+RECT
  if (![CaptureWindow]::GetWindowRect($window, [ref]$r)) { throw 'Cannot read window bounds' }
  if (($r.R-$r.L) -ne $Width -or ($r.B-$r.T) -ne $Height) { throw 'Unexpected capture dimensions' }
  [CaptureWindow]::SetCursorPos($screen.Right-1, $screen.Bottom-1) | Out-Null
  $bitmap = New-Object System.Drawing.Bitmap $Width, $Height
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($r.L, $r.T, 0, 0, $bitmap.Size)
    $bitmap.Save($Output, [System.Drawing.Imaging.ImageFormat]::Png)
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
'''


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
        epilog=('Requires an unlocked Windows desktop, Dart/Flutter, PowerShell, and '
                'the Windows build toolchain. Run flutter pub get in app/ first. '
                'Uses the repository test wrapper with --no-pub and isolated in-memory '
                'preferences. No native core session or serial port is opened. '
                'Do not interact with the desktop during capture. The destination is '
                'replaced only after capture and scenario teardown succeed.'),
    )
    parser.add_argument('--theme', choices=['dark', 'light'], default='dark', help='UI theme')
    parser.add_argument('--language', choices=['zh', 'en'], default='zh', help='UI language')
    parser.add_argument('--output', type=Path, default=root / 'static/images/main_interface.png',
                        help='Destination PNG path')
    parser.add_argument('--width', type=int, default=1280, help='Window width in pixels')
    parser.add_argument('--height', type=int, default=800, help='Window height in pixels')
    parser.add_argument('--timeout', type=int, default=600, help='Total build/scenario deadline in seconds')
    args = parser.parse_args()
    if os.name != 'nt':
        parser.error('Desktop capture currently supports Windows only')
    if args.width < 1000 or args.height < 800 or args.timeout <= 0:
        parser.error('Use a positive timeout and a window of at least 1000 x 800')
    dart = shutil.which('dart')
    flutter = os.environ.get('FLUTTER_BIN') or shutil.which('flutter')
    if not dart or not flutter or not shutil.which('powershell'):
        parser.error('Dart/Flutter and Windows PowerShell must be on PATH')
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='skyport-screenshot-') as temporary:
        work = Path(temporary)
        capture = work / 'capture.ps1'
        capture.write_text(WINDOW_SCRIPT, encoding='utf-8')
        env = os.environ.copy()
        env.update({
            'FLUTTER_BIN': flutter,
            'SKYPORT_SCREENSHOT_DIR': str(work),
            'SKYPORT_SCREENSHOT_THEME': args.theme,
            'SKYPORT_SCREENSHOT_LANGUAGE': args.language,
        })
        # Preserve the previous asset unless capture and scenario teardown succeed.
        staged = output.with_name(output.name + '.pending.png')
        with (work / 'flutter.log').open('w+', encoding='utf-8') as log:
            process = subprocess.Popen(
                [dart, '../tool/quiet_flutter_test.dart',
                 'integration_test/readme_screenshot_test.dart', '-d', 'windows', '--no-pub'],
                cwd=root / 'app', env=env, stdout=log, stderr=subprocess.STDOUT,
            )
            try:
                deadline = time.monotonic() + args.timeout
                framed = captured = False
                while process.poll() is None:
                    if time.monotonic() >= deadline:
                        raise TimeoutError('Screenshot build/scenario deadline exceeded')
                    if (work / 'window.json').exists() and not framed:
                        app_pid = json.loads((work / 'window.json').read_text())['pid']
                        command = ['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                                   '-File', str(capture), '-AppPid', str(app_pid),
                                   '-Width', str(args.width), '-Height', str(args.height)]
                        subprocess.run(command, check=True, timeout=30)
                        (work / 'framed').touch()
                        framed = True
                    if (work / 'ready').exists() and not captured:
                        subprocess.run(command + ['-Output', str(staged)], check=True, timeout=30)
                        (work / 'captured').touch()
                        captured = True
                    time.sleep(0.1)
                if process.returncode != 0 or not captured:
                    raise RuntimeError(f'Screenshot scenario failed (exit {process.returncode})')
                staged.replace(output)
                print(f'SCREENSHOT_OK: {output} ({args.width}x{args.height}, '
                      f'{args.language}, {args.theme}, demo data, no hardware)')
            except BaseException:
                if process.poll() is None:
                    subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    process.wait(timeout=30)
                log.flush()
                log.seek(0)
                print(log.read())
                raise
            finally:
                staged.unlink(missing_ok=True)


if __name__ == '__main__':
    main()
