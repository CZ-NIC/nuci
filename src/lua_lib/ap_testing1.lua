require("abstraction_plugin");
require("views_supervisor");

local self = abstraction_plugin('ap_testing1');
-- Consider this example
--[[
<networking xmlns="http://www.nic.cz/ns/router/networking">
	<internet>
		<interface>
			<name>eth0</name>
			<address>10.0.0.2</address>
			<gateway>10.0.0.1</gateway>
			<dns>10.0.0.1</dns>
			<nat>true</nat>
			<nat6>false</nat6>
		</interface>
		<interface>
			<name>eth1</name>
			<address>10.0.1.5</address>
			<gateway>10.0.1.1</gateway>
			<dns>10.0.1.1</dns>
			<nat>false</nat>
			<nat6>false</nat6>
		</interface>
	</internet>
	<lan>
		<interface>
			<name>eth2</name>
			<address>192.168.1.1</address>
			<dhcp>true</dhcp>
			<bridge>none</bridge>
		</interface>
		<interface>
			<name>eth3</name>
			<address>192.168.1.2</address>
			<dhcp>false</dhcp>
			<bridge>none</bridge>
		</interface>
	</lan>
</networking>
]]

-- Some dummy testing stuff
self.watch = {
	{
		path = {'networking', 'internet', 'interface', 'address'},
		key = {nil, nil, {["name"] = "eth0"}, nil},
		devvals = "10.11.12.13"
	},
	{
		path = {'networking', 'internet', 'interface', 'gateway'},
		key = {nil, nil, {["name"] = "eth0"}, nil},
		devvals = "10.11.12.1"
	},
	{
		path = {'networking', 'internet', 'interface', 'dns'},
		key = {nil, nil, {["name"] = "eth0"}, nil},
		devvals = "10.11.12.2"
	},
	{
		path = {'networking', 'internet', 'interface', 'nat'},
		key = {nil, nil, {["name"] = "eth0"}, nil},
		devvals = "true"
	},
	{
		path = {'networking', 'internet', 'interface', 'nat6'},
		key = {nil, nil, {["name"] = "eth0"}, nil},
		devvals = "false"
	},
	{
		path = {'networking', 'internet', 'interface', 'address'},
		key = {nil, nil, {["name"] = "eth1"}, nil},
		devvals = "10.11.12.13"
	},
	{
		path = {'networking', 'internet', 'interface', 'gateway'},
		key = {nil, nil, {["name"] = "eth1"}, nil},
		devvals = "10.11.12.1"
	},
	{
		path = {'networking', 'internet', 'interface', 'dns'},
		key = {nil, nil, {["name"] = "eth1"}, nil},
		devvals = "10.11.12.2"
	},
	{
		path = {'networking', 'internet', 'interface', 'nat'},
		key = {nil, nil, {["name"] = "eth1"}, nil},
		devvals = "true"
	},
	{
		path = {'networking', 'internet', 'interface', 'nat6'},
		key = {nil, nil, {["name"] = "eth1"}, nil},
		devvals = "false"
	},
	{
		path = {'networking', 'lan', 'interface', 'address'},
		key = {nil, nil, {["name"] = "eth3"}, nil},
		devvals = "192.168.1.1"
	},
	{
		path = {'networking', 'lan', 'interface', 'dhcp'},
		key = {nil, nil, {["name"] = "eth3"}, nil},
		devvals = "192.168.1.0"
	},
	{
		path = {'networking', 'lan', 'interface', 'address'},
		key = {nil, nil, {["name"] = "eth4"}, nil},
		devvals = "192.168.1.1"
	}
}

function self:register_values()
	for _,item in pairs(self.watch) do
		supervisor:register_value(self, item.path, item.key);
	end

	return true;
end;

supervisor:register_ap(self, self.id);
