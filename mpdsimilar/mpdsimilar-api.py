#!/usr/bin/env python3
"""Small HTTP API that switches mpdsimilar.sh on or off.

mpdsimilar.sh (for example, run from cron) reads
~/.config/mpd-scripts/mpdsimilar/state and skips its run when the file
says "off". This daemon reads and writes that
same file, so the switch can be flipped from a browser, a bookmark or curl.

Endpoints (GET or POST for the switches, so a bookmark works):
  /          status page with Toggle / On / Off buttons
  /status    current state: "on" or "off" (JSON with ?format=json or an
             Accept: application/json header)
  /on        set the state to "on"
  /off       set the state to "off"
  /toggle    flip the state

After a switch the browser is sent on with a 303 redirect: to ?next=URL
when given and allowed, otherwise to default_redirect from the config, and
with neither the response is the status page (browsers) or plain text.
A ?next= URL must be http/https with a host listed in
allowed_redirect_hosts, or a path on this server ("/..."). A refused URL
does not undo the switch; the response says why it was not followed.

A missing state file counts as "on". Any content other than "on" or "off"
is reported as invalid; /on and /off overwrite it, /toggle refuses. Writes
are atomic (temp file + rename).

Inputs:  command-line options (run with no arguments for help) and the
         [api] section of ~/.config/mpd-scripts/mpdsimilar/api.conf, which
         is copied from api.conf.example next to this script on first run.
         Standard library only; needs Python 3.8 or newer.
Outputs: HTTP responses; one log line per request on stderr.
Exit codes: 0 clean stop, 2 usage or config error, 1 could not start the
server (for example, the port is in use).
"""

from __future__ import annotations

import argparse
import configparser
import html
import json
import os
import shutil
import signal
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

CONFIG_DIR = Path.home() / ".config" / "mpd-scripts" / "mpdsimilar"
DEFAULT_CONFIG_PATH = CONFIG_DIR / "api.conf"
EXAMPLE_CONFIG_PATH = Path(__file__).resolve().parent / "api.conf.example"
STATE_PATH = CONFIG_DIR / "state"
VALID_STATES = ("on", "off")
MAX_BODY_BYTES = 4096

state_lock = threading.Lock()


class ConfigError(Exception):
    """Raised when api.conf is missing a setting or holds a bad value."""


class StateError(Exception):
    """Raised when the state file cannot be read or holds an unknown value."""


def read_state() -> str:
    """Return "on" or "off" from the state file; a missing file is "on".

    Raises:
        StateError: the file cannot be read or holds anything else.
    """
    try:
        value = STATE_PATH.read_text(encoding="utf-8").strip().lower()
    except FileNotFoundError:
        return "on"
    except OSError as error:
        raise StateError(
            f"cannot read {STATE_PATH}: {error.strerror}"
        ) from error

    if value not in VALID_STATES:
        raise StateError(
            f"{STATE_PATH} must contain 'on' or 'off', got {value!r}"
        )
    return value


def write_state(new_state: str) -> None:
    """Write "on" or "off" to the state file atomically (temp + rename)."""
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(dir=STATE_PATH.parent, prefix=".state.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as temp_file:
            temp_file.write(new_state + "\n")
        os.chmod(temp_name, 0o644)
        os.replace(temp_name, STATE_PATH)
    except BaseException:
        Path(temp_name).unlink(missing_ok=True)
        raise


def check_redirect(url: str, allowed_hosts: set[str]) -> str | None:
    """Return why a ?next= URL is refused, or None when it may be followed.

    Allowed: a path on this server ("/..." but not "//..."), or an
    http/https URL whose host is in allowed_hosts.
    """
    if url.startswith("/") and not url.startswith("//") and "\\" not in url:
        return None

    parts = urlsplit(url)
    if parts.scheme not in ("http", "https"):
        return "only http and https URLs (or paths on this server) are allowed"
    if not parts.hostname:
        return "the URL has no host"
    if parts.hostname.lower() not in allowed_hosts:
        return f"host {parts.hostname!r} is not in allowed_redirect_hosts"
    return None


def load_config(config_path: Path) -> dict:
    """Read the [api] section of api.conf and return validated settings.

    Copies api.conf.example to the default location first when that file
    does not exist yet. Never overwrites an existing config.

    Raises:
        ConfigError: the file is missing or a setting is invalid.
    """
    if config_path == DEFAULT_CONFIG_PATH and not config_path.exists():
        if not EXAMPLE_CONFIG_PATH.exists():
            raise ConfigError(
                f"{config_path} is missing and so is {EXAMPLE_CONFIG_PATH}"
            )
        config_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(EXAMPLE_CONFIG_PATH, config_path)
        print(
            f"Created {config_path} from {EXAMPLE_CONFIG_PATH.name}",
            file=sys.stderr,
        )

    parser = configparser.ConfigParser()
    try:
        with open(config_path, encoding="utf-8") as config_file:
            parser.read_file(config_file)
    except FileNotFoundError as error:
        raise ConfigError(f"config file {config_path} not found") from error
    except (OSError, configparser.Error) as error:
        raise ConfigError(f"cannot read {config_path}: {error}") from error

    if not parser.has_section("api"):
        raise ConfigError(f"{config_path} has no [api] section")
    section = parser["api"]

    bind = section.get("bind", "127.0.0.1").strip()
    if not bind:
        raise ConfigError(
            "[api] bind must be an address, for example 127.0.0.1"
        )

    try:
        port = section.getint("port", 8095)
    except ValueError as error:
        raise ConfigError(
            "[api] port must be a whole number from 1 to 65535"
        ) from error
    if not 1 <= port <= 65535:
        raise ConfigError("[api] port must be a whole number from 1 to 65535")

    allowed_hosts = {
        host.strip().lower()
        for host in section.get("allowed_redirect_hosts", "").split(",")
        if host.strip()
    }

    default_redirect = section.get("default_redirect", "").strip()
    if default_redirect:
        parts = urlsplit(default_redirect)
        is_local_path = default_redirect.startswith(
            "/"
        ) and not default_redirect.startswith("//")
        if not is_local_path and (
            parts.scheme not in ("http", "https") or not parts.hostname
        ):
            raise ConfigError(
                "[api] default_redirect must be an http(s) URL or a path "
                f"starting with /, got {default_redirect!r}"
            )

    return {
        "bind": bind,
        "port": port,
        "allowed_hosts": allowed_hosts,
        "default_redirect": default_redirect,
    }


def render_page(state: str | None, message: str = "") -> str:
    """Return the status page HTML. state is None when the file is invalid."""
    shown = state if state else "invalid"
    notice = f'<p class="note">{html.escape(message)}</p>' if message else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>mpdsimilar switch</title>
<style>
  :root {{ color-scheme: light dark; }}
  body {{ font-family: system-ui, sans-serif; max-width: 28rem;
         margin: 3rem auto; padding: 0 1rem; }}
  .state {{ font-size: 2rem; font-weight: 700; }}
  .on {{ color: #1a7f37; }}
  .off {{ color: #cf222e; }}
  .invalid {{ color: #9a6700; }}
  form {{ display: inline; }}
  button {{ font-size: 1rem; padding: 0.5rem 1.25rem; margin-right: 0.5rem;
           cursor: pointer; }}
  .note {{ padding: 0.5rem 0.75rem; border-left: 4px solid #9a6700; }}
</style>
</head>
<body>
<h1>mpdsimilar</h1>
<p>Adding similar tracks from cron is
  <span class="state {shown}">{shown}</span></p>
{notice}
<form method="post" action="/toggle">
  <input type="hidden" name="next" value="/">
  <button type="submit">Toggle</button>
</form>
<form method="post" action="/on">
  <input type="hidden" name="next" value="/">
  <button type="submit">On</button>
</form>
<form method="post" action="/off">
  <input type="hidden" name="next" value="/">
  <button type="submit">Off</button>
</form>
</body>
</html>
"""


class SwitchHandler(BaseHTTPRequestHandler):
    """Serves the status page and the on/off/toggle endpoints."""

    server_version = "mpdsimilar-api"
    settings: dict = {}

    def do_GET(self) -> None:  # noqa: N802 (name set by http.server)
        """Handle GET for every endpoint."""
        self.route(self.query_params())

    def do_POST(self) -> None:  # noqa: N802 (name set by http.server)
        """Handle POST; form fields count the same as query parameters."""
        params = self.query_params()
        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY_BYTES:
            self.send_text(413, "request body too large\n")
            return
        body = (
            self.rfile.read(length).decode("utf-8", "replace")
            if length
            else ""
        )
        content_type = self.headers.get("Content-Type", "")
        if body and content_type.startswith(
            "application/x-www-form-urlencoded"
        ):
            for key, values in parse_qs(body).items():
                params.setdefault(key, values[-1])
        self.route(params)

    def query_params(self) -> dict[str, str]:
        """Return the URL's query parameters, last value wins."""
        query = urlsplit(self.path).query
        return {key: values[-1] for key, values in parse_qs(query).items()}

    def wants_json(self, params: dict[str, str]) -> bool:
        """True when the client asked for JSON."""
        return params.get(
            "format"
        ) == "json" or "application/json" in self.headers.get("Accept", "")

    def wants_html(self) -> bool:
        """True for browsers (they send text/html in Accept); curl does not."""
        return "text/html" in self.headers.get("Accept", "")

    def route(self, params: dict[str, str]) -> None:
        """Dispatch the request by path."""
        path = urlsplit(self.path).path.rstrip("/") or "/"

        if path == "/":
            self.respond_state(params, message="")
        elif path == "/status":
            self.respond_state(params, message="", page=False)
        elif path in ("/on", "/off", "/toggle"):
            self.switch(path[1:], params)
        else:
            self.send_text(404, "not found\n")

    def switch(self, action: str, params: dict[str, str]) -> None:
        """Change the state, then redirect or report the new state."""
        with state_lock:
            if action == "toggle":
                try:
                    current = read_state()
                except StateError as error:
                    self.send_text(409, f"cannot toggle: {error}\n")
                    return
                new_state = "off" if current == "on" else "on"
            else:
                new_state = action
            try:
                write_state(new_state)
            except OSError as error:
                self.send_text(
                    500, f"cannot write {STATE_PATH}: {error.strerror}\n"
                )
                return

        target = params.get("next", "").strip()
        message = ""
        if target:
            refusal = check_redirect(target, self.settings["allowed_hosts"])
            if refusal:
                message = (
                    f"Switched {new_state}, but did not redirect to "
                    f"{target}: {refusal}."
                )
                target = ""
        else:
            target = self.settings["default_redirect"]

        if target:
            body = f"{new_state}\n".encode("utf-8")
            self.send_response(303)
            self.send_header("Location", target)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return

        self.respond_state(params, message=message)

    def respond_state(
        self, params: dict[str, str], message: str, page: bool = True
    ) -> None:
        """Send the current state as the HTML page, JSON or plain text."""
        try:
            state = read_state()
            error = ""
        except StateError as state_error:
            state = None
            error = str(state_error)

        if self.wants_json(params):
            payload = {"state": state}
            if error:
                payload["error"] = error
            if message:
                payload["message"] = message
            self.send_body(
                200 if state else 500,
                json.dumps(payload) + "\n",
                "application/json",
            )
        elif page and self.wants_html():
            self.send_body(
                200, render_page(state, message or error), "text/html"
            )
        elif state:
            text = f"{state}\n" + (f"{message}\n" if message else "")
            self.send_text(200, text)
        else:
            self.send_text(500, f"invalid: {error}\n")

    def send_text(self, status: int, text: str) -> None:
        """Send a plain-text response."""
        self.send_body(status, text, "text/plain")

    def send_body(self, status: int, text: str, content_type: str) -> None:
        """Send a complete response with the given status and body."""
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(
        self, format: str, *args
    ) -> None:  # noqa: A002 (signature set by http.server)
        """Log one short line per request to stderr (the systemd journal)."""
        print(
            f"{self.address_string()} {format % args}",
            file=sys.stderr,
            flush=True,
        )


def build_parser() -> argparse.ArgumentParser:
    """Return the command-line parser."""
    parser = argparse.ArgumentParser(
        description="HTTP switch that turns mpdsimilar.sh's cron runs "
        "on or off.",
    )
    parser.add_argument(
        "-s",
        "--serve",
        action="store_true",
        help="start the HTTP server (without this, only this help is shown)",
    )
    parser.add_argument(
        "-c",
        "--config",
        type=Path,
        default=DEFAULT_CONFIG_PATH,
        help=f"path to the INI config file (default: {DEFAULT_CONFIG_PATH})",
    )
    parser.add_argument(
        "-b",
        "--bind",
        help="address to listen on, overriding [api] bind "
        "(the example config uses 127.0.0.1)",
    )
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        help="port to listen on, overriding [api] port",
    )
    return parser


def stop_on_sigterm(_signum: int, _frame) -> None:
    """Let systemd's SIGTERM stop the server the same way Ctrl+C does."""
    raise KeyboardInterrupt


def main() -> int:
    """Parse options, load the config and run the server until stopped."""
    parser = build_parser()
    if len(sys.argv) == 1:
        parser.print_help()
        return 0
    args = parser.parse_args()
    if not args.serve:
        parser.print_help()
        return 0

    try:
        settings = load_config(args.config)
    except ConfigError as error:
        print(f"Config error: {error}", file=sys.stderr)
        return 2

    if args.bind:
        settings["bind"] = args.bind
    if args.port is not None:
        if not 1 <= args.port <= 65535:
            print("Error: -p/--port must be from 1 to 65535.", file=sys.stderr)
            return 2
        settings["port"] = args.port

    SwitchHandler.settings = settings
    address = f"{settings['bind']}:{settings['port']}"
    try:
        server = ThreadingHTTPServer(
            (settings["bind"], settings["port"]), SwitchHandler
        )
    except OSError as error:
        print(
            f"Cannot listen on {address}: {error.strerror}",
            file=sys.stderr,
        )
        return 1

    signal.signal(signal.SIGTERM, stop_on_sigterm)

    print(
        f"mpdsimilar-api listening on http://{address}/ "
        f"(state file {STATE_PATH})",
        file=sys.stderr,
        flush=True,
    )
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
