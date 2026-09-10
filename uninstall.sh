#!/usr/bin/env bash
# Remove the ProArt PX13 (Strix Halo) audio workaround and restore defaults.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}"
WP_DST="$CFG/wireplumber/wireplumber.conf.d"
SD_DST="$CFG/systemd/user"

echo "==> Disabling tas2783-amp-cap.service"
systemctl --user disable --now tas2783-amp-cap.service 2>/dev/null || true
rm -f "$SD_DST/tas2783-amp-cap.service"
systemctl --user daemon-reload

echo "==> Removing suspend/resume recovery service"
RESUME_UNIT="/etc/systemd/system/proart-audio-resume.service"
if [ -f "$RESUME_UNIT" ]; then
  if [ "$(id -u)" = 0 ]; then SUDO=""; else SUDO="sudo"; fi
  $SUDO systemctl disable --now proart-audio-resume.service 2>/dev/null || true
  $SUDO rm -f "$RESUME_UNIT"
  $SUDO systemctl daemon-reload
fi

echo "==> Removing WirePlumber drop-in"
rm -f "$WP_DST/99-proart-px13-audio.conf"

echo "==> Restoring TAS2783 analog gain to chip maximum (+21 dB)"
amixer -c amdsoundwire sset 'tas2783-1 Amp' 20 2>/dev/null || true
amixer -c amdsoundwire sset 'tas2783-2 Amp' 20 2>/dev/null || true

echo "==> Stripping saved card profile / default-node choices for this card"
for f in default-profile default-nodes; do
  p="$STATE/wireplumber/$f"
  [ -f "$p" ] && sed -i '/amd_sdw/d' "$p" || true
done

echo "==> Restarting the audio stack"
systemctl --user restart wireplumber pipewire pipewire-pulse 2>/dev/null \
  || systemctl --user restart wireplumber pipewire

echo
echo "Done. Note: without this workaround the kernel bug is still there, so the"
echo "speakers will most likely fall back to a Dummy Output until a fixed kernel"
echo "ships. Re-run ./install.sh to get sound back."
