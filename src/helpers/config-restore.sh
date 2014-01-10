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

cd /
base64 -d | bzip -cd | tar xp
uci get network.lan.ipaddr

if [ '!' -d /tmp/update-state ] ; then
	# There's a short race condition here, but this should be rare enough, so we don't complicate the script
	echo startup > /tmp/update-state/state
fi

# Run the updater and reboot in the background
(
	sleep 1
	/etc/init.d/network restart
	sleep 5 # Time for the network to start up
	updater.sh -n
	reboot
) & >/dev/null 2>&1 &
