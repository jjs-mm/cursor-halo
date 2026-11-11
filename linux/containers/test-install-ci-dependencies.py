#!/usr/bin/env python3
"""Exercise source preservation and fallback control flow without root/network."""
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest


HELPER = Path(__file__).with_name("install-ci-dependencies.sh")


class DependencyFallbackTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="cursor-halo-apt-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sources = self.root / "apt"
        (self.sources / "sources.list.d").mkdir(parents=True)

    def shell(self, code, *args, env=None):
        return subprocess.run(["bash", "-c", 'source "$1"; shift; ' + code,
                               "test", str(HELPER), *map(str, args)],
                              text=True, capture_output=True, env=env)

    def test_direct_sources_preserve_signatures_suites_architecture_and_transport(self):
        original = ("Types: deb\nURIs: https://archive.ubuntu.com/ubuntu/\n"
                    "Suites: noble noble-updates noble-backports\nComponents: main universe\n"
                    "Architectures: amd64\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\n"
                    "Types: deb\nURIs: http://security.ubuntu.com/ubuntu\nSuites: noble-security\n"
                    "Components: main\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n")
        path = self.sources / "sources.list.d/ubuntu.sources"
        path.write_text(original)
        output = self.root / "fallback"
        result = self.shell('prepare_fallback_sources "$1" "$2" "$3"', self.sources, output,
                            "https://ftp.fau.de/ubuntu/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_text(), original)
        expected = original.replace("https://archive.ubuntu.com/ubuntu/", "https://ftp.fau.de/ubuntu/").replace(
            "http://security.ubuntu.com/ubuntu", "http://ftp.fau.de/ubuntu/")
        self.assertEqual((output / "sources.list.d/ubuntu.sources").read_text(), expected)

    def test_private_source_permissions_are_preserved(self):
        source = self.sources / "sources.list.d/ubuntu.sources"
        source.write_text("Types: deb\nURIs: https://archive.ubuntu.com/ubuntu/\n"
                          "Suites: noble\nComponents: main\nX-Private: token\n")
        source.chmod(0o600)
        output = self.root / "fallback"
        result = self.shell('prepare_fallback_sources "$1" "$2" "$3"', self.sources, output,
                            "https://ftp.fau.de/ubuntu/")
        self.assertEqual(result.returncode, 0, result.stderr)
        copied = output / "sources.list.d/ubuntu.sources"
        self.assertEqual(stat.S_IMODE(copied.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(source.stat().st_mode), 0o600)
        self.assertIn("X-Private: token", copied.read_text())

    def test_fallback_never_copies_world_write_or_execute_bits(self):
        source = self.sources / "sources.list.d/ubuntu.sources"
        source.write_text("URIs: https://archive.ubuntu.com/ubuntu/\n")
        source.chmod(0o777)
        output = self.root / "fallback"
        result = self.shell('prepare_fallback_sources "$1" "$2" "$3"', self.sources, output,
                            "https://ftp.fau.de/ubuntu/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(stat.S_IMODE((output / "sources.list.d/ubuntu.sources").stat().st_mode), 0o644)

    def test_ports_legacy_and_runner_mirror_files(self):
        (self.sources / "sources.list").write_text(
            "deb [arch=arm64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] http://ports.ubuntu.com/ubuntu-ports/ resolute main universe\n")
        runner = "Types: deb\nURIs: mirror+file:/etc/apt/apt-mirrors.txt\nSuites: noble noble-updates\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n\nTypes: deb\nURIs: mirror+file:/etc/apt/apt-security-mirrors.txt\nSuites: noble-security\nComponents: main\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n"
        (self.sources / "sources.list.d/runner.sources").write_text(runner)
        unrelated = "deb [signed-by=/usr/share/keyrings/vendor.gpg] https://packages.example.test/ubuntu noble main\n"
        (self.sources / "sources.list.d/vendor.list").write_text(unrelated)
        output = self.root / "fallback"
        result = self.shell('prepare_fallback_sources "$1" "$2" "$3"', self.sources, output,
                            "https://ftp.fau.de/ubuntu-ports/")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("http://ftp.fau.de/ubuntu-ports/ resolute", (output / "sources.list").read_text())
        self.assertEqual((output / "sources.list.d/vendor.list").read_text(), unrelated)
        result = (output / "sources.list.d/runner.sources").read_text()
        self.assertNotIn("mirror+file:", result)
        self.assertEqual(result.count("URIs: https://ftp.fau.de/ubuntu-ports/"), 2)
        self.assertIn("Suites: noble-security", result)
        self.assertIn("Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg", result)

    def test_unknown_sources_are_not_replaced(self):
        (self.sources / "sources.list").write_text("deb https://example.test/ubuntu noble main\n")
        result = self.shell('prepare_fallback_sources "$1" "$2" "$3"', self.sources,
                            self.root / "fallback", "https://ftp.fau.de/ubuntu/")
        self.assertNotEqual(result.returncode, 0)

    def test_supported_environment_is_explicit(self):
        for codename in ("noble", "resolute", "stonking"):
            self.assertEqual(self.shell('supported_ubuntu "$1" "$2"', "ubuntu", codename).returncode, 0)
        for distro, codename in (("debian", "noble"), ("ubuntu", "devel"), ("ubuntu", "jammy")):
            self.assertNotEqual(self.shell('supported_ubuntu "$1" "$2"', distro, codename).returncode, 0)
        self.assertEqual(self.shell('fallback_uri arm64 https').stdout.strip(), "https://ftp.fau.de/ubuntu-ports/")
        self.assertNotEqual(self.shell('fallback_uri s390x https').returncode, 0)

    def exercise_install(self, mode):
        source = self.sources / "sources.list"
        original = "deb http://azure.archive.ubuntu.com/ubuntu/ noble main universe\n"
        source.write_text(original)
        binaries = self.root / "bin"
        binaries.mkdir()
        log = self.root / "calls.jsonl"
        apt = binaries / "apt-get"
        apt.write_text(f"#!{sys.executable}\n" + """
import json, os, pathlib, sys
args = sys.argv[1:]
fallback = any(a.startswith('Dir::Etc::sourcelist=') for a in args)
action = 'update' if 'update' in args else 'install'
with open(os.environ['APT_TEST_LOG'], 'a') as stream:
    stream.write(json.dumps({'args': args, 'fallback': fallback, 'action': action}) + '\\n')
if fallback:
    lists = next(a.split('=', 1)[1] for a in args if a.startswith('Dir::State::lists='))
    if action == 'update':
        assert not list(pathlib.Path(lists).glob('*InRelease'))
        if os.environ['APT_TEST_MODE'] == 'bad-signature':
            print('NO_PUBKEY: signature verification failed', file=sys.stderr)
            sys.exit(100)
    sys.exit(0)
mode = os.environ['APT_TEST_MODE']
sys.exit(100 if (mode in ('update-fails', 'bad-signature') and action == 'update') or
                (mode == 'install-fails' and action == 'install') else 0)
""")
        apt.chmod(0o755)
        timeout = binaries / "timeout"
        timeout.write_text('#!/bin/sh\nshift 3\nexec "$@"\n')
        timeout.chmod(0o755)
        env = {**os.environ, "PATH": str(binaries) + os.pathsep + os.environ["PATH"],
               "APT_TEST_MODE": mode, "APT_TEST_LOG": str(log)}
        result = self.shell('install_dependencies "$1" "$2" cmake g++', self.sources,
                            "https://ftp.fau.de/ubuntu/", env=env)
        self.assertEqual(source.read_text(), original)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        for call in calls:
            if call["action"] == "update":
                self.assertIn("APT::Update::Error-Mode=any", call["args"])
            if call["fallback"]:
                cache = next(a.split("=", 1)[1] for a in call["args"] if a.startswith("Dir::State::lists="))
                self.assertFalse(Path(cache).exists(), "Temporary indexes must be removed after completion")
        return result, [(c["fallback"], c["action"]) for c in calls]

    def test_default_success_does_not_use_fallback(self):
        result, calls = self.exercise_install("success")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [(False, "update"), (False, "install")])

    def test_update_failure_uses_fresh_authenticated_fallback(self):
        result, calls = self.exercise_install("update-fails")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls, [(False, "update"), (True, "update"), (True, "install")])

    def test_install_failure_also_falls_back(self):
        result, calls = self.exercise_install("install-fails")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[-2:], [(True, "update"), (True, "install")])

    def test_failed_signature_stops_before_install(self):
        result, calls = self.exercise_install("bad-signature")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(calls, [(False, "update"), (True, "update")])


if __name__ == "__main__":
    unittest.main()
