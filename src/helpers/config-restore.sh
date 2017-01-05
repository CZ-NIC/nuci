#!/bin/sh

# Copyright 2014, CZ.NIC z.s.p.o. (http://www.nic.cz/)
#
# This file is part of NUCI configuration server.
#
# NUCI is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# NUCI is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NUCI.  If not, see <http://www.gnu.org/licenses/>.

set -e

DIR=/tmp/restore-$$
DEST='/'
if [ "$NUCI_TEST_CONFIG_DIR" ] ; then
	# The variable contains path to UCI configuration dir - strip trailing "/etc/config"
	DEST="${NUCI_TEST_CONFIG_DIR%/etc/config}"
fi
mkdir -p "$DIR"
trap 'rm -rf "$DIR"' EXIT INT QUIT TERM ABRT
cd "$DIR"
base64 -d | bzip2 -cd | tar xp
# Here we have a special-case/hack for foris password. It was requested NOT to restore the
# password, as potentially confusing action. So we unpack the backed-up configuration,
# extract the current password and implant it into the configuration. Then we just copy
# the configs and overwrite the current ones.
PASSWD="$(uci -c "${DEST%/}/etc/config" get foris.auth.password)"
uci -c "$DIR/etc/config" set foris.auth.password="$PASSWD"
uci -c "$DIR/etc/config" commit
cp -rf "$DIR/"* "$DEST"
cd /
rm -rf "$DIR"
trap - EXIT INT QUIT TERM ABRT
# It is legal for the address not to be there, so don't fail on it
uci -c "${DEST%/}/etc/config" get network.lan.ipaddr || true

if [ "$NUCI_TEST_CONFIG_DIR" ] ; then
	exit
fi

if [ '!' -d /tmp/update-state ] ; then
	# There's a short race condition here, but this should be rare enough, so we don't complicate the script
	mkdir -p /tmp/update-state
	echo startup > /tmp/update-state/state
fi

# Run the updater and reboot in the background
(
	sleep 2
	/etc/init.d/network restart
	sleep 5 # Time for the network to start up
	updater.sh -n || true # Don't consider failure here a problem, go ahead and reboot
	reboot
) >/dev/null 2>&1 &
