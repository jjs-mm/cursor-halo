# GNOME compatibility test containers

These images run the extension's model tests and native compositor checks on Ubuntu 26.04/GNOME 50 and Ubuntu 26.10/GNOME 51. GNOME 46 remains covered directly by the Ubuntu 24.04 CI jobs. Run from the repository root with Docker:

```sh
./linux/scripts/test-gnome-container.sh 26.04 .build/smoke/gnome-50
./linux/scripts/test-gnome-container.sh 26.10 .build/smoke/gnome-51
```

The script builds the image for the Docker host's native architecture. CI uses separate x64 and ARM64 runners; an emulated local run is not evidence of native architecture coverage. The runtime container has no network, host display, host D-Bus socket, or host devices. Source files are mounted read-only; only the selected output directory is writable. Tests use software rendering and their own temporary settings, Wayland compositor, and session bus.

`gnome-images.json` pins the official Ubuntu multi-architecture image manifests. The image installs the distribution's current GNOME packages. Before testing, `record-gnome-environment.py` requires the expected Shell major and records the actual OS, package versions, architecture, and base image in `environment.json`. The runtime result and logs remain alongside that record. A package update that changes the expected major must fail instead of silently testing a different compatibility target.

The entrypoint is container-only. It starts a private system D-Bus and removes an empty systemd seat marker that otherwise advertises an unavailable logind service. The compositor's test-only `--unsafe-mode` enables assertions and virtual input in that disposable session; installed extensions never use that flag.

## Dependency-download fallback

The container build and hosted Ubuntu CI jobs use `install-ci-dependencies.sh`. It tries the configured APT sources first, with bounded acquisition timeouts and index errors treated as failures. If updating or installing fails, it retries through [FAU's officially listed Ubuntu mirror](https://launchpad.net/ubuntu/+archivemirrors): `ftp.fau.de/ubuntu/` for the main archive and `ftp.fau.de/ubuntu-ports/` for ports. [FAU publishes both mirrors and their synchronization status](https://ftp.fau.de/); Ubuntu also [lists FAU's ports mirror](https://wiki.ubuntu.com/ppc64el/CommonQuestions#Mirrors).

The fallback recognizes only Ubuntu archive/security/ports URLs and GitHub's `mirror+file:/etc/apt/apt-mirrors.txt` and `mirror+file:/etc/apt/apt-security-mirrors.txt` source forms. It copies source definitions to a temporary directory and keeps their suites, components, architecture filters, and signing options intact. Runner source files are never changed. A separate empty package-index cache prevents stale runner indexes from masking a failed refresh. Both temporary sources and indexes are removed when the helper finishes. Only Ubuntu 24.04 (`noble`), 26.04 (`resolute`), and 26.10 (`stonking`) on amd64/arm64 are accepted.

Direct repository URLs retain their original HTTP or HTTPS scheme. GitHub's file-based mirror selector uses HTTPS when the runner has a CA bundle. Minimal official Ubuntu images use their existing HTTP transport and Ubuntu archive keyring; no certificate checks or [APT Release-signature authentication](https://manpages.ubuntu.com/manpages/noble/man8/apt-secure.8.html) are disabled. The helper does not alter the GNOME runtime's `--network none`, base-image digests, test matrix, or required checks.

Run its source-preservation and failure-path checks without root or network:

```sh
python3 linux/containers/test-install-ci-dependencies.py
```

The fallback addresses repeated CI DNS failures observed on November 11, 2026. It is dependency-download infrastructure, not an alternate desktop compatibility test. FAU base, updates, security, and backports release endpoints were checked for all three supported distributions under both archive trees before adding the fallback.

To refresh a base image, verify its official manifest contains both Linux architectures, update the digest, and rerun both native CI jobs before changing a support claim. Do not add Shell versions to extension metadata solely because schemas compile or model tests pass. Physical display scaling, authentication, next-login startup, and recorder compatibility still need manual testing.
