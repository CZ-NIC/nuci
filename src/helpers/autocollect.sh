#!/bin/sh

# Copyright 2017 CZ.NIC z.s.p.o. (http://www.nic.cz/)
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

# The script checks if the router still has a valid contract. If so, it makes
# sure the i_agree_datacollect user list is enabled.
#
# This should be run after installation. Also, we want to run it periodically,
# for two reasons. One, we want to readd it if user removes it. Another, if the
# internet connection doesn't work when we run it after the installation, it
# would add nothing, so we want to fix that.

set -e

# Some constants
TIMEOUT=120
CA_FILE=/etc/ssl/www_turris_cz_ca.pem
CHALLENGE_URL=https://api.turris.cz/challenge.cgi
CONTRACT_URL='https://www.turris.cz/api/contract-valid.txt?registration_code='
# Get today's registration code
CODE=$(curl -k -m $TIMEOUT "$CHALLENGE_URL" | atsha204cmd challenge-response | head -c 16)
# Ask for the status of the contract
RESULT=$(curl -s -S -L -H "Accept: plain/text" --cacert "$CA_FILE" --cert-status -m "$TIMEOUT" "$CONTRACT_URL$CODE" | sed -ne 's/^result: *\(..*\)/\1/p')

if [ "$RESULT" = "valid" ] ; then
	if uci -d'
' get updater.pkglists.lists | grep -q -F i_agree_datacollect ; then
		: # Already there
	else
		echo "The contract is still valid, force-adding i_agree_datacollect user list" | logger -t nuci -p daemon.warning
		uci add_list updater.pkglists.lists=i_agree_datacollect
		uci commit updater
	fi

	# update contract if needed
	if uci -q show foris | grep -q "foris.contract.valid='1'" ; then
		: # Already there
	else
		echo "Mark that contract is valid." | logger -t nuci -p daemon.warning
		uci set foris.contract=config
		uci set foris.contract.valid=1
		uci commit foris
	fi
else
	# update contract if needed
	if uci -q show foris | grep -q "foris.contract.valid='0'" ; then
		: # Already there
	else
		echo "Mark that contract is invalid." | logger -t nuci -p daemon.warning
		uci set foris.contract=config
		uci set foris.contract.valid=0
		uci commit foris
	fi
fi
