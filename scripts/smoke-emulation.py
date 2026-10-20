#!/usr/bin/env python3
"""End-to-end smoke test of a running Miminet stack (./miminet.sh smoke).

Goes through the same path as a user in the browser: logs in with the
email/password form, opens the admin panel, creates a network, uploads a
reference topology (switch + hub + 4 hosts, one ping), starts the emulation
and waits for the packets. The result is compared with the reference answer
used by the backend tests, so this checks nginx -> Flask -> RabbitMQ ->
Mininet/OVS worker -> RabbitMQ -> Flask -> PostgreSQL in one go.

Standard library only, so it runs with any python3 on the host.
"""

import argparse
import http.cookiejar
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_CASE = REPO / "back/tests/test_json/switch_and_hub"


class Client:
    def __init__(self, base_url):
        self.base_url = base_url.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.jar)
        )

    def request(self, method, path, form=None, json_body=None):
        headers = {}
        body = None
        if json_body is not None:
            body = json.dumps(json_body).encode()
            headers["Content-Type"] = "application/json"
        elif form is not None:
            body = urllib.parse.urlencode(form).encode()
        # Needed when JWT CSRF protection is on (MODE=prod); harmless in dev.
        csrf = next((c.value for c in self.jar if c.name == "csrf_access_token"), None)
        if csrf:
            headers["X-CSRF-TOKEN"] = csrf
        req = urllib.request.Request(
            self.base_url + path, data=body, method=method, headers=headers
        )
        try:
            with self.opener.open(req, timeout=30) as resp:
                return resp.status, resp.geturl(), resp.read().decode(errors="replace")
        except urllib.error.HTTPError as e:
            return e.code, e.geturl(), e.read().decode(errors="replace")


def labels(packets):
    """Multiset of packet labels' first line, e.g. 'ICMP echo-request'."""
    out = {}
    for step in packets:
        for pkt in step:
            label = pkt["data"]["label"].split("\n")[0]
            out[label] = out.get(label, 0) + 1
    return out


def step(name, ok, detail=""):
    mark = "ok" if ok else "FAIL"
    print(f"  [{mark}] {name}" + (f": {detail}" if detail else ""))
    if not ok:
        sys.exit(1)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--base-url", default="http://localhost")
    ap.add_argument("--email", default="admin@local")
    ap.add_argument("--password", default="admin")
    ap.add_argument(
        "--case",
        default=str(DEFAULT_CASE),
        help="path prefix of <case>_network.json / <case>_answer.json",
    )
    ap.add_argument("--timeout", type=int, default=120, help="seconds to wait")
    args = ap.parse_args()

    net = json.loads(pathlib.Path(args.case + "_network.json").read_text())
    answer = json.loads(pathlib.Path(args.case + "_answer.json").read_text())
    c = Client(args.base_url)
    t0 = time.monotonic()
    print(f"smoke test against {args.base_url}")

    status, _, page = c.request("GET", "/auth/login.html")
    step(
        "login page",
        status == 200 and 'name="password"' in page,
        f"HTTP {status}"
        + ("" if 'name="password"' in page else ", no password form (AUTH_PROVIDERS?)"),
    )

    status, url, _ = c.request(
        "POST",
        "/auth/login.html",
        form={"email": args.email, "password": args.password},
    )
    step("log in as " + args.email, "/auth/login.html" not in url, f"-> {url}")

    status, url, _ = c.request("GET", "/admin/")
    step("admin panel", status == 200 and "/admin" in url, f"HTTP {status} {url}")

    status, url, _ = c.request("GET", "/create_network")
    guid = urllib.parse.parse_qs(urllib.parse.urlparse(url).query).get("guid", [None])[
        0
    ]
    step("create network", bool(guid), f"guid={guid}")

    status, _, body = c.request(
        "POST",
        f"/post_nodes_edges?guid={guid}",
        json_body=[net["nodes"], net["edges"], net["jobs"]],
    )
    step(
        "upload topology",
        status == 201,
        f"{len(net['nodes'])} nodes, {len(net['edges'])} links, {len(net['jobs'])} job(s)",
    )

    status, _, body = c.request("POST", f"/run_simulation?guid={guid}")
    step("start emulation", status == 201, body.strip())
    sim_id = json.loads(body)["simulation_id"]

    packets = None
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        status, _, body = c.request(
            "GET", f"/check_simulation?simulation_id={sim_id}&network_guid={guid}"
        )
        if status == 200:
            raw = json.loads(body).get("packets")
            if raw:
                packets = json.loads(raw) if isinstance(raw, str) else raw
                break
        time.sleep(1)
    step(
        "emulation finished",
        packets is not None,
        f"{time.monotonic() - t0:.1f}s"
        if packets
        else f"no result after {args.timeout}s: is the 'back' service running? (./miminet.sh logs back)",
    )

    got, want = labels(packets), labels(answer)
    step(
        "packets match the reference",
        got == want,
        ", ".join(f"{k} x{v}" for k, v in sorted(got.items()))
        + ("" if got == want else f"; expected {want}"),
    )

    c.request("POST", f"/delete_network?guid={guid}", json_body={})
    print(f"PASS in {time.monotonic() - t0:.1f}s")


if __name__ == "__main__":
    main()
