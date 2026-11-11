# GNOME compatibility test containers

These images run the extension's model tests and native compositor checks on Ubuntu 26.04/GNOME 50 and Ubuntu 26.10/GNOME 51. GNOME 46 remains covered directly by the Ubuntu 24.04 CI jobs. Run from the repository root with Docker:

```sh
./linux/scripts/test-gnome-container.sh 26.04 .build/smoke/gnome-50
./linux/scripts/test-gnome-container.sh 26.10 .build/smoke/gnome-51
```

The script builds the image for the Docker host's native architecture. CI uses separate x64 and ARM64 runners; an emulated local run is not evidence of native architecture coverage. The runtime container has no network, host display, host D-Bus socket, or host devices. Source files are mounted read-only; only the selected output directory is writable. Tests use software rendering and their own temporary settings, Wayland compositor, and session bus.

`gnome-images.json` pins the official Ubuntu multi-architecture image manifests. The image installs the distribution's current GNOME packages. Before testing, `record-gnome-environment.py` requires the expected Shell major and records the actual OS, package versions, architecture, and base image in `environment.json`. The runtime result and logs remain alongside that record. A package update that changes the expected major must fail instead of silently testing a different compatibility target.

The entrypoint is container-only. It starts a private system D-Bus and removes an empty systemd seat marker that otherwise advertises an unavailable logind service. The compositor's test-only `--unsafe-mode` enables assertions and virtual input in that disposable session; installed extensions never use that flag.

To refresh a base image, verify its official manifest contains both Linux architectures, update the digest, and rerun both native CI jobs before changing a support claim. Do not add Shell versions to extension metadata solely because schemas compile or model tests pass. Physical display scaling, authentication, next-login startup, and recorder compatibility still need manual testing.
