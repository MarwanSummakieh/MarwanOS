#!/usr/bin/env bash
# Build only in a disposable Fedora 43 build stage. Never run on the appliance.
# Preserve Fedora's source/dependency pins and RPM packaging; only source patch
# and local release suffix differ. Containerfile owns trusted Fedora repo keys.
set -euo pipefail
readonly SOURCE_NAME=gamescope-3.16.23-1.fc43.src.rpm
readonly SOURCE_URL="https://kojipkgs.fedoraproject.org/packages/gamescope/3.16.23/1.fc43/src/${SOURCE_NAME}"
readonly SOURCE_SHA256=d224583dc3e62752f0e74afd19631742a173f18d3b42277b2af5ba6b459427ee
usage() { echo "Usage: $0 --output DIRECTORY [--source-rpm FILE] [--prepare-only]" >&2; }
output= source_rpm= prepare_only=0
while (($#)); do
    case "$1" in
        --output) (($# >= 2)) || { usage; exit 2; }; output=$2; shift 2 ;;
        --source-rpm) (($# >= 2)) || { usage; exit 2; }; source_rpm=$2; shift 2 ;;
        --prepare-only) prepare_only=1; shift ;;
        *) usage; exit 2 ;;
    esac
done
[[ -n "$output" ]] || { usage; exit 2; }
readonly repository=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
readonly work=$(mktemp -d /var/tmp/marwanos-gamescope-build.XXXXXXXX)
trap 'rm -rf -- "$work"' EXIT
if [[ -z "$source_rpm" ]]; then
    source_rpm="$work/$SOURCE_NAME"
    curl --fail --location --silent --show-error --retry 3 "$SOURCE_URL" -o "$source_rpm"
fi
source_rpm=$(realpath -- "$source_rpm")
printf '%s  %s\n' "$SOURCE_SHA256" "$source_rpm" | sha256sum --check --status
[[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$source_rpm") == gamescope-3.16.23-1.fc43 ]] || exit 1
mkdir -p "$work/rpm" "$output"
# Do not install the source RPM into the host's default RPM build tree.
rpm --define "_topdir $work/rpm" -i "$source_rpm"
cp -- "$repository/os/gamescope/nvidia_dispatch_lifetime.hpp" "$work/rpm/SOURCES/"
cp -- "$repository/os/gamescope/nvidia_output_cleanup.hpp" "$work/rpm/SOURCES/"
cp -- "$repository/os/gamescope/gamescope-3.16.23-nvidia-lifetime.patch" "$work/rpm/SOURCES/"
python3 - "$work/rpm/SPECS/gamescope.spec" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
source = path.read_text()
for needle in ('Release:        %autorelease\n', '\n%description\n', '\n%autopatch -p1\n'):
    if source.count(needle) != 1:
        raise SystemExit('unexpected Fedora spec structure: ' + repr(needle))
source = source.replace('Release:        %autorelease\n', 'Release:        1.pc1.3%{?dist}\n')
source = source.replace('\n%description\n', '\nSource998: nvidia_output_cleanup.hpp\nSource999: nvidia_dispatch_lifetime.hpp\nPatch999: gamescope-3.16.23-nvidia-lifetime.patch\n\n%description\n')
source = source.replace('\n%autopatch -p1\n', '\n%autopatch -p1\ncp %{SOURCE998} src/nvidia_output_cleanup.hpp\ncp %{SOURCE999} src/nvidia_dispatch_lifetime.hpp\n')
path.write_text(source)
PY
if ((prepare_only)); then
    # Dependency-free source/patch verification; no compilation or package install.
    rpmbuild --nodeps -bp --define "_topdir $work/rpm" "$work/rpm/SPECS/gamescope.spec"
    cp -a "$work/rpm/BUILD" "$output/prepared"
    exit 0
fi
# Toolchain installation is owned by the disposable Containerfile stage. Keep
# the source's complete Fedora BuildRequires instead of hand-picked dependencies.
dnf -y builddep "$work/rpm/SPECS/gamescope.spec"
rpmbuild -bb --define "_topdir $work/rpm" --define '_smp_build_ncpus 2' "$work/rpm/SPECS/gamescope.spec"
readonly built="$work/rpm/RPMS/x86_64/gamescope-3.16.23-1.pc1.3.fc43.x86_64.rpm"
[[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' "$built") == gamescope-3.16.23-1.pc1.3.fc43.x86_64 ]] || exit 1
cp -- "$built" "$output/"
# Keep an exact patched source RPM alongside the payload for source attribution.
rpmbuild -bs --define "_topdir $work/rpm" "$work/rpm/SPECS/gamescope.spec"
cp -- "$work/rpm/SRPMS/gamescope-3.16.23-1.pc1.3.fc43.src.rpm" "$output/"
