--[[
Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)

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

require("views_supervisor");
require("nutils");

local self = {};
-- Consider this example
--[[
<networking xmlns="http://www.nic.cz/ns/router/networking">
	<internet>
		<interface>
			<name>eth0</name>
			<address>10.0.0.2</address>
			<gateway>10.0.0.1</gateway>
			<dns>10.0.0.1</dns>
			<nat/>
		</interface>
		<interface>
			<name>eth1</name>
			<address>10.0.1.5</address>
			<gateway>10.0.1.1</gateway>
			<dns>10.0.1.1</dns>
		</interface>
	</internet>
	<lan>
		<interface>
			<name>eth2</name>
			<address>192.168.1.1</address>
			<dhcp/>
		</interface>
		<interface>
			<name>eth3</name>
			<address>192.168.1.2</address>
		</interface>
	</lan>
</networking>
]]

-- Some dummy testing stuff
self.watch = {
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'address'},
		keys = {{}, {}, {}, {name = "eth0", xyz = "abcd"}, {}},
		multival = {"10.11.12.13", "10.11.12.14", "10.11.12.15"}
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'gateway'},
		keys = {{}, {}, {}, {name = "eth0"}, {}},
		val = "10.11.12.1"
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'dns'},
		keys = {{}, {}, {}, {name = "eth0"}, {}},
		multival = {"10.11.12.2"}
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'nat'},
		keys = {{}, {}, {}, {name = "eth0"}, {}}
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'address'},
		keys = {{}, {}, {}, {name = "eth1"}, {}},
		multival = {"10.11.22.13"}
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'gateway'},
		keys = {{}, {}, {}, {name = "eth1"}, {}},
		val = "10.11.22.1"
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'xxx'},
		keys = {{}, {}, {}, {}, {}},
		val = "10.11.22.1",
		collision_priority = 20
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'xxx'},
		keys = {{}, {}, {}, {}, {}},
		val = "10.11.22.2",
		collision_priority = 10
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'dns'},
		keys = {{}, {}, {}, {name = "eth1"}, {}},
		multival = {"10.11.22.2"}
	},
	{
		path = {'supervisor-test', 'networking', 'internet', 'interface', 'nat'},
		keys = {{}, {}, {}, {name = "eth1"}, {}}
	},
	{
		path = {'supervisor-test', 'networking', 'lan', 'interface', 'address'},
		keys = {{}, {}, {}, {name = "eth3"}, {}},
		multival = {"192.168.1.1"}
	},
	{ -- WTF? Like, which DHCP server we should ask? The sole purpose of DHCP is not to configure anything!
		path = {'supervisor-test', 'networking', 'lan', 'interface', 'dhcp'},
		keys = {{}, {}, {}, {name = "eth3"}, {}},
		val = "192.168.1.0"
	},
	{
		path = {'supervisor-test', 'networking', 'lan', 'interface', 'address'},
		keys = {{}, {}, {}, {name = "eth4"}, {}},
		multival = {"192.168.1.1"}
	}
}

--[[
Return paths in which I'm interested.

FIXME:
This is a bit broken, since we return a path multiple times. The supervisor can handle that, but it is
not nice. Probably OK for test plugin.

Fix by removal of the the file, in #2706.
]]
function self:positions()
	local result = {};
	for _, value in ipairs(self.watch) do
		table.insert(result, value.path);
	end
	return result;
end

--[[
Return paths in which I'm able to solve collision.
]]
function self:collision_handlers()
	local result = {};
	for _, value in ipairs(self.watch) do
		if value.collision_priority then
			table.insert(result, { path = value.path, priority = value.collision_priority });
		end
	end
	return result;
end

function self:collision(tree, node, path, keyset)
	node.errors = nil;

	return true;
end
--[[
Return values. Parameters are ignored here and we return everything all the time.
This is legal, the parameters are optimisation only and the caller would filter
it anyway.
]]
function self:get(path, keyset)
	return self.watch;
end

supervisor:register_plugin(self);
