--[[
Copyright 2016, CZ.NIC z.s.p.o. (http://www.nic.cz/)

This file is part of NUCI configuration server.

NUCI is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

NUCI is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
]]

require("cert");
require("datastore");
require("nutils");
require("uci");

local datastore = datastore('openvpn-client.yin');

function dirname(path)
	return path:match("^(.*)/");
end

function read_file(path)
	local file, err = io.open(path);
	if not file then
		return nil, err;
	end
	local content = file:read("*a");
	file:close();
	return content;
end

function get_device_ip(device)
	local ecode, stdout, stderr = run_command(nil, 'ip',  'addr',  'show', 'dev', device);
	if ecode == 0 then
		-- try to guess the ip address
		-- note that this doesn't have to be so accurate
		local ip = stdout:match("inet (%d+%.%d+%.%d+%.%d+)");
		if ip then
			return ip;
		end
	end
	return "<insert-ip-or-hostname>";
end

function cond_true_false(condition, if_true, if_false)
	if condition then return if_true else return if_false end
end

function build_config(settings)
	local text = [[
##############################################
# Sample client-side OpenVPN 2.0 config file #
# for connecting to multi-client server.     #
#                                            #
# This configuration can be used by multiple #
# clients, however each client should have   #
# its own cert and key files.                #
#                                            #
# On Windows, you might want to rename this  #
# file so it has a .ovpn extension           #
##############################################

# Specify that we are a client and that we
# will be pulling certain config file directives
# from the server.
client

# Use the same setting as you are using on
# the server.
# On most systems, the VPN will not function
# unless you partially or fully disable
# the firewall for the TUN/TAP interface.
;dev tap
;dev tun
%s

# Windows needs the TAP-Win32 adapter name
# from the Network Connections panel
# if you have more than one.  On XP SP2,
# you may need to disable the firewall
# for the TAP adapter.
;dev-node MyTap

# Are we connecting to a TCP or
# UDP server?  Use the same setting as
# on the server.
;proto tcp
;proto udp
%s

# The hostname/IP and port of the server.
# You can have multiple remote entries
# to load balance between the servers.
;remote my-server-1 1194
;remote my-server-2 1194
%s

# Choose a random host from the remote
# list for load-balancing.  Otherwise
# try hosts in the order specified.
;remote-random

# Keep trying indefinitely to resolve the
# host name of the OpenVPN server.  Very useful
# on machines which are not permanently connected
# to the internet such as laptops.
resolv-retry infinite

# Most clients don't need to bind to
# a specific local port number.
nobind

# Downgrade privileges after initialization (non-Windows only)
;user nobody
;group nobody

# Try to preserve some state across restarts.
persist-key
persist-tun

# If you are connecting through an
# HTTP proxy to reach the actual OpenVPN
# server, put the proxy server/IP and
# port number here.  See the man page
# if your proxy server requires
# authentication.
;http-proxy-retry # retry on connection failures
;http-proxy [proxy server] [proxy port #]

# Wireless networks often produce a lot
# of duplicate packets.  Set this flag
# to silence duplicate packet warnings.
mute-replay-warnings

# SSL/TLS parms.
# See the server config file for more
# description.  It's best to use
# a separate .crt/.key file pair
# for each client.  A single ca
# file can be used for all clients.
;ca ca.crt
;cert client.crt
;key client.key
%s
%s
%s

# Verify server certificate by checking that the
# certicate has the correct key usage set.
# This is an important precaution to protect against
# a potential attack discussed here:
#  http://openvpn.net/howto.html#mitm
#
# To use this feature, you will need to generate
# your server certificates with the keyUsage set to
#   digitalSignature, keyEncipherment
# and the extendedKeyUsage to
#   serverAuth
# EasyRSA can do this for you.
remote-cert-tls server

# If a tls-auth key is used on the server
# then every client must also have the key.
;tls-auth ta.key 1
%s

# Select a cryptographic cipher.
# If the cipher option is used on the server
# then you must also specify it here.
# Note that 2.4 client/server will automatically
# negotiate AES-256-GCM in TLS mode.
# See also the ncp-cipher option in the manpage
;cipher AES-256-CBC
%s

# Enable compression on the VPN link.
# Don't enable this unless it is also
# enabled in the server config file.
;comp-lzo
%s

# Set log file verbosity.
verb 3

# Silence repeating messages
;mute 20
]];
	return text:format(
		'dev ' .. settings.dev,
		'proto ' .. settings.proto,
		'remote ' .. settings.remote,  -- ip and port
		'<ca>\n' .. settings.ca .. '</ca>',
		'<cert>\n' .. settings.cert .. '</cert>',
		'<key>\n' .. settings.key .. '</key>',
		cond_true_false(settings.tls_auth, '<tls-auth>\n' .. (settings.tls_auth or '') .. '</tls_auth>', ''),
		cond_true_false(settings.cipher, 'cipher ' .. (settings.cipher or ''), ''),
		cond_true_false(settings.comp_lzo, 'comp-lzo', '')
	)
end

function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'download-config' then
		-- get certificate name
		local cert_name_node = find_node_name_ns(root, 'cert-name', self.model_ns);
		if not cert_name_node then
			return nil, {
				msg = "Missing the <cert-name> parameter.",
				app_tag = 'data-missing',
				info_badelem = 'cert-name',
				info_badns = self.model_ns
			}
		end
		local cert_name = cert_name_node:text();
		-- validate cert_name
		if not verify_cert_name(cert_name) then
			return nil, {
			msg = "Invalid cert-name",
			app_tag = 'invalid-value',
			info_badelem = 'name',
			info_badns = self.model_ns
			}
		end

		-- get config name
		local config_name_node = find_node_name_ns(root, 'config-name', self.model_ns);
		if not config_name_node then
			return nil, {
				msg = "Missing the <config-name> parameter.",
				app_tag = 'data-missing',
				info_badelem = 'config-name',
				info_badns = self.model_ns
			}
		end
		local config_name = config_name_node:text();

		local settings = {};
		-- read uci
		cursor = get_uci_cursor();
		uci_data = cursor:get_all('openvpn', config_name);
		if not uci_data then
			return nil, "Server configuration is missing. (" .. config_name .. ")"
		end
		settings.dev = uci_data.dev;
		settings.proto = uci_data.proto;
		settings.ca_path = uci_data.ca;
		settings.tls_auth_path = uci_data.tls_auth;
		settings.cipher = uci_data.cipher;
		settings.comp_lzo = uci_data.comp_lzo;
		settings.port = uci_data.port;
		local wan_device = cursor:get('network', 'wan', 'ifname');
		reset_uci_cursor();

		-- check settings
		if not settings.dev or not settings.proto or not settings.port then
			return nil, "Openvpn server is not well configured."
		end

		-- try to get server ip
		settings.remote = get_device_ip(wan_device) .. " " .. settings.port;

		-- read ca
		local ca_content, err = read_file(settings.ca_path);
		if not ca_content then
			return nil, err;
		end
		settings.ca = ca_content;

		-- read client cert
		local cert_content, err = read_file(dirname(settings.ca_path) .. "/client-" .. cert_name .. ".crt");
		if not cert_content then
			return nil, err;
		end
		settings.cert = cert_content;

		-- read key
		local key_content, err = read_file(dirname(settings.ca_path) .. "/client-" .. cert_name .. ".key");
		if not key_content then
			return nil, err;
		end
		settings.key = key_content;

		-- read tls_auth if set
		if settings.tls_auth_path then
			local tls_auth_content, err = read_file(settings.tls_auth_path);
			if not tls_auth_content then
				return nil, err;
			end
			settings.tls_auth = tls_auth_content;
		end

		-- prepare output
		local new_xml = xmlwrap.new_xml_doc(self.model_name, self.model_ns);
		local new_root = new_xml:root();
		new_root:add_child('configuration'):set_text(build_config(settings));
		return new_xml:strdump();
	end
end

register_datastore_provider(datastore)
