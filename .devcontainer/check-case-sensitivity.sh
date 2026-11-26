#!/usr/bin/env bash
# Warns when the workspace is on a case-insensitive filesystem (a bind mount from Windows or macOS).
# Then casing bugs that break the Linux CI build do not show up in this dev container.
probe=".case-sensitivity-probe"
rm -f "$probe" "${probe^^}"
touch "$probe"
if [ -e "${probe^^}" ]; then
  echo "WARNING: this workspace is NOT case-sensitive (it is probably bind-mounted from Windows)." >&2
  echo "         Casing bugs that fail the Linux build will not show up here." >&2
  echo "         Use 'Dev Containers: Clone Repository in Container Volume...' instead." >&2
else
  echo "OK: workspace is case-sensitive, like the Linux CI build."
fi
rm -f "$probe"
