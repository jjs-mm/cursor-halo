#!/bin/bash
# CI-only dependency installation. Keep package authentication and source fields
# intact; use an independent Ubuntu mirror only after the configured sources fail.
set -euo pipefail

supported_ubuntu() {
    [[ "$1" == ubuntu ]] && [[ "$2" == noble || "$2" == resolute || "$2" == stonking ]]
}

fallback_uri() {
    local architecture="$1" scheme="$2"
    case "$architecture" in
        amd64) printf '%s://ftp.fau.de/ubuntu/\n' "$scheme" ;;
        arm64) printf '%s://ftp.fau.de/ubuntu-ports/\n' "$scheme" ;;
        *) printf 'Unsupported CI architecture: %s\n' "$architecture" >&2; return 1 ;;
    esac
}

prepare_fallback_sources() {
    local source_root="$1" destination="$2" mirror_file_uri="$3" source target changed=false
    mkdir -p "$destination/sources.list.d" "$destination/lists/partial"
    chmod 755 "$destination" "$destination/sources.list.d" "$destination/lists" "$destination/lists/partial"
    : > "$destination/sources.list"
    for source in "$source_root/sources.list" "$source_root/sources.list.d/"*.list "$source_root/sources.list.d/"*.sources; do
        [[ -f "$source" ]] || continue
        if [[ "$source" == "$source_root/sources.list" ]]; then target="$destination/sources.list"
        else target="$destination/sources.list.d/${source##*/}"; fi
        # Change only known Ubuntu repository URIs. Preserve suites, components,
        # architecture filters, Signed-By and every other source option. Direct
        # URIs retain their transport scheme. Hosted-runner mirror+file sources
        # use HTTPS when a system CA bundle is available.
        sed -E \
            -e 's@(https?://)([[:alnum:]-]+\.)*archive\.ubuntu\.com/ubuntu/?([[:space:]]|$)@\1ftp.fau.de/ubuntu/\3@g' \
            -e 's@(https?://)security\.ubuntu\.com/ubuntu/?([[:space:]]|$)@\1ftp.fau.de/ubuntu/\2@g' \
            -e 's@(https?://)ports\.ubuntu\.com/ubuntu-ports/?([[:space:]]|$)@\1ftp.fau.de/ubuntu-ports/\2@g' \
            -e "s@mirror\+file:/etc/apt/apt-(security-)?mirrors\.txt([[:space:]]|\$)@${mirror_file_uri}\\2@g" \
            "$source" > "$target"
        chmod 644 "$target"
        if ! cmp -s "$source" "$target"; then changed=true; fi
    done
    if [[ "$changed" != true ]]; then
        printf 'No recognized Ubuntu sources were found for the CI mirror fallback.\n' >&2
        return 1
    fi
}

run_apt_update() {
    timeout --signal=TERM --kill-after=10s 180s apt-get \
        -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 \
        -o APT::Update::Error-Mode=any "$@" update
}

run_apt_install() {
    timeout --signal=TERM --kill-after=10s 900s apt-get \
        -o Acquire::Retries=1 -o Acquire::http::Timeout=20 -o Acquire::https::Timeout=20 \
        "$@"
}

install_dependencies() (
    local source_root="$1" mirror_file_uri="$2"; shift 2
    if run_apt_update && run_apt_install install --no-install-recommends -y "$@"; then return 0; fi

    printf 'Configured APT sources failed; retrying Ubuntu dependencies using the FAU mirror.\n' >&2
    local fallback
    fallback="$(mktemp -d /tmp/cursor-halo-apt.XXXXXX)"
    trap 'rm -rf -- "$fallback"' EXIT
    prepare_fallback_sources "$source_root" "$fallback" "$mirror_file_uri" || return 1
    local options=(
        -o "Dir::Etc::sourcelist=$fallback/sources.list"
        -o "Dir::Etc::sourceparts=$fallback/sources.list.d"
        -o "Dir::State::lists=$fallback/lists"
    )
    # A fresh private list cache prevents a failed mirror refresh from falling
    # back to a runner's stale package indexes. All normal APT checks remain on.
    run_apt_update "${options[@]}" || return 1
    run_apt_install "${options[@]}" install --no-install-recommends -y "$@"
)

main() {
    if [[ "$(id -u)" != 0 || "$#" == 0 ]]; then
        printf 'Usage: sudo bash %s <package> [package ...]\n' "$0" >&2
        return 2
    fi
    local package
    for package in "$@"; do
        if [[ ! "$package" =~ ^[a-z0-9][a-z0-9+.-]*(:[a-z0-9][a-z0-9-]*)?$ ]]; then
            printf 'Expected a package name, got: %s\n' "$package" >&2; return 2
        fi
    done
    # The file is supplied by the runner or pinned official Ubuntu base image.
    . /etc/os-release
    if ! supported_ubuntu "${ID:-}" "${VERSION_CODENAME:-}"; then
        printf 'This helper supports Ubuntu noble, resolute, and stonking CI environments only.\n' >&2
        return 2
    fi
    local scheme=http mirror_uri
    if [[ -s /etc/ssl/certs/ca-certificates.crt ]]; then scheme=https; fi
    mirror_uri="$(fallback_uri "$(dpkg --print-architecture)" "$scheme")" || return 2
    export DEBIAN_FRONTEND=noninteractive
    install_dependencies /etc/apt "$mirror_uri" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
