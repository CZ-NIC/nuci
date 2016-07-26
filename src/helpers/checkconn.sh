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

# Try to guess if the network is up and what parts of it work

YEAR=$(date +%Y)

if [ "$YEAR" -lt "2000" ] ; then
	# The time is lost, we need NTP badly
	ntpdate 217.31.202.100 || true # If this fails due to network problems, don't abort the script just yet
fi

/etc/init.d/resolver restart # Clean the cache

IP='217.31.205.50 198.41.0.4 199.7.83.42 8.8.8.8'
GATEWAY=$(route -n | grep '^0\.0\.0\.0' |  sed -e 's/^0\.0\.0\.0 *//;s/ *$//;s/ .* /%/')
GATEWAY6=$(route -n -A inet6 | grep '^::/0' | sed -e 's/^::\/0 *//;s/ *$//g;s/ .* /%/')
IP6='2001:1488:0:3::2 2001:500:3::42 2001:500:2d::d 2606:2800:220:6d:26bf:1447:1097:aa7'
NAMES='api.turris.cz www.nic.cz c.root-servers.net'
BAD_NAMES='www.rhybar.cz' # Any others?
TIME=2

do_check() {
	MESSAGE="$1"
	shift
	for ADDRESS in "$@" ; do
		(
			ADDR="$(echo "$ADDRESS" | sed -e 's/%/ -I/')"
			if busybox ping -q -w"$TIME" $ADDR >/dev/null 2>&1 ; then
				echo "$MESSAGE"
			fi
		) &
		KILL="$KILL $!"
	done
}

do_check_dns() {
	MESSAGE="$1"
	shift
	for ADDRESS in "$@" ; do
		(
			if busybox ping -q -w"$TIME" "$ADDRESS" 2>/dev/null | grep -q "^PING $ADDRESS ([0-9a-fA-F.:]*)" >/dev/null 2>&1 ; then
				echo "$MESSAGE"
			fi
		) &
		KILL="$KILL $!"
	done
}

# Unfortunately, even with -w, ping can take a LONG time. So we launch a safety-kill and let it run on background.
# (Double-backgrounded so wait doesn't wait for that one)
KILL=$$
run_timer() {
	(
		sleep 3 && kill $KILL
	) &
}

do_check V4 $IP
do_check V6 $IP6
do_check GATE4 $GATEWAY
do_check GATE6 $GATEWAY6
do_check_dns DNS $NAMES
do_check_dns BADSEC $BAD_NAMES

run_timer >/dev/null 2>&1 &

wait
