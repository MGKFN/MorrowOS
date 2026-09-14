"""
MorrowStore — Backend installer
Supports APT, Flatpak, Snap, and direct .deb URLs (for Tech Haven Studios
apps that aren't in any repo).
Runs installs in a background thread to keep UI responsive.
"""
import os
import subprocess
import tempfile
import threading
import shutil
import urllib.request

_AGENT_CHECKED = False
_AGENT_OK = False


def _polkit_agent_running() -> bool:
    """pkexec silently no-ops with no visible error if no graphical polkit
    agent is running — this is the #1 cause of 'install does nothing'."""
    global _AGENT_CHECKED, _AGENT_OK
    if _AGENT_CHECKED:
        return _AGENT_OK
    _AGENT_CHECKED = True
    try:
        out = subprocess.run(["pgrep", "-f", "polkit.*agent"],
                              capture_output=True, text=True)
        _AGENT_OK = out.returncode == 0
    except Exception:
        _AGENT_OK = False
    return _AGENT_OK


class Installer:
    def install_async(self, app: dict, callback):
        """Non-blocking install — runs in thread, calls callback(app, success, error) on finish."""
        t = threading.Thread(
            target=self._install_worker,
            args=(app, callback),
            daemon=True
        )
        t.start()

    def _install_worker(self, app: dict, callback):
        method = app.get("method", "apt")
        pkg = app.get("package")

        try:
            if method == "apt":
                if not shutil.which("pkexec"):
                    raise RuntimeError("pkexec is not installed")
                if not _polkit_agent_running():
                    raise RuntimeError(
                        "No polkit auth agent running — install/enable "
                        "polkit-kde-agent-1")
                self._run(["pkexec", "apt-get", "install", "-y", pkg])
            elif method == "flatpak":
                remote = app.get("remote", "flathub")
                if not shutil.which("flatpak"):
                    raise RuntimeError("flatpak is not installed")
                remotes = subprocess.run(
                    ["flatpak", "remotes", "--columns=name"],
                    capture_output=True, text=True
                ).stdout.split()
                if remote not in remotes:
                    raise RuntimeError(
                        f"Flatpak remote '{remote}' isn't configured. Run: "
                        f"flatpak remote-add --if-not-exists {remote} "
                        f"https://flathub.org/repo/flathub.flatpakrepo")
                self._run(["flatpak", "install", "-y", "--noninteractive",
                           remote, pkg])
            elif method == "snap":
                if not shutil.which("pkexec"):
                    raise RuntimeError("pkexec is not installed")
                if not _polkit_agent_running():
                    raise RuntimeError(
                        "No polkit auth agent running — install/enable "
                        "polkit-kde-agent-1")
                self._run(["pkexec", "snap", "install", pkg])
            elif method == "deb_url":
                url = app.get("url")
                if not url:
                    raise ValueError("deb_url app entry is missing 'url'")
                if not shutil.which("pkexec"):
                    raise RuntimeError("pkexec is not installed")
                if not _polkit_agent_running():
                    raise RuntimeError(
                        "No polkit auth agent running — install/enable "
                        "polkit-kde-agent-1")
                with tempfile.TemporaryDirectory() as td:
                    debpath = os.path.join(td, "package.deb")
                    urllib.request.urlretrieve(url, debpath)
                    try:
                        self._run(["pkexec", "apt-get", "install", "-y", debpath])
                    except subprocess.CalledProcessError:
                        # fall back to dpkg + fix deps
                        self._run(["pkexec", "dpkg", "-i", debpath])
                        self._run(["pkexec", "apt-get", "install", "-y", "-f"])
            else:
                raise ValueError(f"Unknown install method: {method}")
            callback(app, True)
        except subprocess.CalledProcessError as e:
            callback(app, False, e.stderr or str(e))
        except Exception as e:
            callback(app, False, str(e))

    def _run(self, cmd):
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True
        )
        return result

    def is_installed(self, app: dict) -> bool:
        method = app.get("method", "apt")
        pkg = app.get("package")
        if method in ("apt", "deb_url"):
            if not pkg:
                return False
            r = subprocess.run(
                ["dpkg", "-s", pkg],
                capture_output=True
            )
            return r.returncode == 0
        elif method == "flatpak":
            r = subprocess.run(
                ["flatpak", "info", pkg],
                capture_output=True
            )
            return r.returncode == 0
        elif method == "snap":
            r = subprocess.run(
                ["snap", "list", pkg],
                capture_output=True
            )
            return r.returncode == 0
        return False
