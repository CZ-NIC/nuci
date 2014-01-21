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

DIR=/tmp/backup-$$
mkdir -p "$DIR"/etc
trap 'rm -rf "$DIR"' EXIT INT QUIT TERM ABRT
cd "$DIR"/etc
cp -r /etc/config .
cd ..
uci -c "$DIR"/etc/config delete foris.auth.password
uci -c "$DIR"/etc/config commit
tar c etc/config | bzip2 -9c | base64