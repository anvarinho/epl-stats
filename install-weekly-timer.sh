#!/usr/bin/env bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
unit_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

# Quote literal paths for systemd and then for the sed replacement.
escaped_dir=${project_dir//\\/\\\\}
escaped_dir=${escaped_dir//\"/\\\"}
escaped_dir=${escaped_dir//%/%%}
escaped_dir=${escaped_dir//\$/\$\$}
escaped_dir=${escaped_dir//\\/\\\\}
escaped_dir=${escaped_dir//&/\\&}
escaped_dir=${escaped_dir//|/\\|}
mkdir -p "$unit_dir"
for unit in epl-weekend.service epl-weekend.timer; do
    if [ -f "$unit_dir/$unit" ]; then
        cp -p "$unit_dir/$unit" "$unit_dir/$unit.bak.$(date +%s)"
    fi
done
sed "s|@PROJECT_DIR@|$escaped_dir|g" "$project_dir/systemd/epl-weekend.service.in" > "$unit_dir/epl-weekend.service"
cp "$project_dir/systemd/epl-weekend.timer" "$unit_dir/epl-weekend.timer"
systemctl --user daemon-reload
systemctl --user enable --now epl-weekend.timer
systemctl --user list-timers epl-weekend.timer --no-pager
