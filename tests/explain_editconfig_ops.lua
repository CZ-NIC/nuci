#!bin/test_runner

--[[
This script is based on editconfig_test.lua and generates basically
dump of editconfig function's output. It is auxiliary script
for creating tests.
]]
package.path = 'src/lua_lib/?.lua;' .. package.path;
require("editconfig");

local yang_ns = 'urn:ietf:params:xml:ns:yang:yin:1';
local small_model = [[
<module name='test' xmlns='urn:ietf:params:xml:ns:yang:yin:1'>
  <yang-version value='1'/>
  <namespace uri='http://example.org/'/>
  <prefix value='prefix'/>
  <container name='data'>
    <leaf name='value'>
      <type name='int32'/>
    </leaf>
    <leaf name='value2'>
      <type name='int32'/>
    </leaf>
  </container>
</module>
]];
local bigger_model = [[
<module name='test' xmlns='urn:ietf:params:xml:ns:yang:yin:1'>
  <yang-version value='1'/>
  <namespace uri='http://example.org/'/>
  <prefix value='prefix'/>
  <container name='data'>
    <leaf name='value'>
      <type name='int32'/>
    </leaf>
    <container name='data2'>
		<leaf name='value2'>
			<type name='int32'/>
		</leaf>
	</container>
  </container>
</module>
]];
local uci_model = [[
<?xml version="1.0" encoding="UTF-8"?>
<module name="uci-raw" xmlns="urn:ietf:params:xml:ns:yang:yin:1">
  <yang-version value="1"/>
  <namespace uri="http://www.nic.cz/ns/router/uci-raw"/>
  <prefix value="uci-raw"/>
  <typedef name="uci-name">
    <description>
      <text>Type for UCI identifiers and file names.</text>
    </description>
    <reference>
      <text>http://wiki.openwrt.org/doc/uci#file.syntax</text>
    </reference>
    <type name="string">
      <pattern value="[a-z0-9_]+"/>
    </type>
  </typedef>
  <container name="uci">
    <description>
      <text>Top-level container for all UCI configurations.</text>
    </description>
    <list name="config">
      <key value="name"/>
      <leaf name="name">
        <type name="uci-name"/>
      </leaf>
      <list name="section">
        <key value="name"/>
        <leaf name="name">
          <type name="uci-name"/>
        </leaf>
        <leaf name="type">
          <mandatory value='true'/>
          <type name="string"/>
        </leaf>
        <leaf name="anonymous">
          <type name="empty"/>
        </leaf>
        <list name="option">
          <key value="name"/>
          <leaf name="name">
            <type name="uci-name"/>
          </leaf>
          <leaf name="value">
            <type name="string"/>
            <mandatory value='true'/>
          </leaf>
        </list>
        <list name="list">
          <key value="name"/>
          <leaf name="name">
            <type name="uci-name"/>
          </leaf>
          <list name='value'>
            <key value='index'/>
            <leaf name='index'>
              <type name='decimal64'/> <!-- So we support insertion in the middle. The numbers from server are always integers. -->
            </leaf>
            <leaf name='content'>
              <type name='string'/>
              <mandatory value='true'/>
            </leaf>
          </list>
          <min-elements value='1'/>
        </list>
      </list>
    </list>
  </container>
</module>
]];

local tests = {
	["Complex UCI"]={
		command=[[<edit>        <uci xmlns="http://www.nic.cz/ns/router/uci-raw">
            <config>
                <name>complex_test</name>
                <section>
                    <name>s3</name>
                    <list>
                        <name>l1</name>
                        <value xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0" nc:operation="remove">
                            <index>4</index>
                        </value>
                    </list>
                </section>
                <section>
                    <name>s2</name>
                    <option  xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0" nc:operation="remove">
                        <name>o2</name>
                    </option>
                </section>
                <section xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0" nc:operation="remove">
                    <name>s1</name>
                </section>
                <section xmlns:nc="urn:ietf:params:xml:ns:netconf:base:1.0" nc:operation="create">
                    <name>s8</name>
                    <type>section</type>
          <option>
            <name>o1</name>
            <value>abc</value>
          </option>
          <option>
            <name>o3</name>
            <value>ghi</value>
          </option>
          <list>
            <name>l1</name>
            <value>
              <index>1</index>
              <content>123</content>
            </value>
            <value>
              <index>2</index>
              <content>456</content>
            </value>
            <value>
              <index>3</index>
              <content>789</content>
            </value>
          </list>
          <option>
            <name>o5</name>
            <value>mno</value>
          </option>
          <option>
            <name>o4</name>
            <value>jkl</value>
          </option>
          <option>
            <name>o2</name>
            <value>def</value>
          </option>
                </section>
            </config>
        </uci>
</edit>]],
		config=[[<config><uci xmlns="http://www.nic.cz/ns/router/uci-raw">
      <config>
        <name>complex_test</name>
        <section>
          <name>s1</name>
          <type>section</type>
          <option>
            <name>o1</name>
            <value>abc</value>
          </option>
          <option>
            <name>o3</name>
            <value>ghi</value>
          </option>
          <list>
            <name>l1</name>
            <value>
              <index>1</index>
              <content>123</content>
            </value>
            <value>
              <index>2</index>
              <content>456</content>
            </value>
            <value>
              <index>3</index>
              <content>789</content>
            </value>
          </list>
          <option>
            <name>o5</name>
            <value>mno</value>
          </option>
          <option>
            <name>o4</name>
            <value>jkl</value>
          </option>
          <option>
            <name>o2</name>
            <value>def</value>
          </option>
        </section>
        <section>
          <name>s2</name>
          <type>section</type>
          <option>
            <name>o4</name>
            <value>jkl</value>
          </option>
          <list>
            <name>l1</name>
            <value>
              <index>1</index>
              <content>123</content>
            </value>
            <value>
              <index>2</index>
              <content>456</content>
            </value>
            <value>
              <index>3</index>
              <content>789</content>
            </value>
          </list>
          <option>
            <name>o5</name>
            <value>mno</value>
          </option>
          <option>
            <name>o3</name>
            <value>ghi</value>
          </option>
          <option>
            <name>o2</name>
            <value>def</value>
          </option>
        </section>
        <section>
          <name>s3</name>
          <type>section</type>
          <option>
            <name>o1</name>
            <value>abc</value>
          </option>
          <option>
            <name>o3</name>
            <value>ghi</value>
          </option>
          <option>
            <name>o5</name>
            <value>mno</value>
          </option>
          <list>
            <name>l1</name>
            <value>
              <index>1</index>
              <content>123</content>
            </value>
            <value>
              <index>2</index>
              <content>125643</content>
            </value>
            <value>
              <index>3</index>
              <content>3</content>
            </value>
            <value>
              <index>4</index>
              <content>456</content>
            </value>
          </list>
          <option>
            <name>o2</name>
            <value>def</value>
          </option>
        </section>
      </config>
      <config>
        <name>test</name>
        <section>
          <name>named</name>
          <type>section</type>
          <option>
            <name>xyz</name>
            <value>123</value>
          </option>
          <list>
            <name>abc</name>
            <value>
              <index>1</index>
              <content>345</content>
            </value>
            <value>
              <index>2</index>
              <content>678</content>
            </value>
          </list>
        </section>
      </config>
    </uci></config>]],
		model=uci_model,
		ns='http://www.nic.cz/ns/router/uci-raw',
		expected_ops={
			{
				name='add-tree',
				command_node_name='data',
				model_node_name='container'
			}
		}
	},
	["Create command (exist)"]={
		--[[
		Replace the leaf with value.
		]]
		command=[[<edit><data xmlns='http://example.org/' xmlns:xc='urn:ietf:params:xml:ns:netconf:base:1.0'><value xc:operation='create'/></data></edit>]];
		config=[[<config><data xmlns='http://example.org/'><badvalue>42</badvalue></data></config>]],
		model=small_model,
		ns='http://example.org/',
		expected_ops = {
			name='add-tree',
			command_node_name='data',
			model_node_name='container'
		}
	}
};

local function perform_test(name, test)
	io.write('Running "', name, '"\n');
	local command_xml = xmlwrap.read_memory(test.command);
	local config_xml = xmlwrap.read_memory(test.config);
	local model_xml = xmlwrap.read_memory(test.model);

	local ops, err = editconfig(config_xml, command_xml, model_xml, test.ns, test.defop or 'merge', nil);

	if err then
		error(err.msg);
	end
	io.write("\n");
	for index, op in ipairs(ops) do
		io.write("Index: " .. index .. ", op: (\n")
		for k, v in pairs(op) do
			io.write("\t" .. k .. ": ");
			if v == nil then
				io.write("nil");
			elseif type(v) == "string" then
				io.write(v);
			else
				n, ns = v:name();
				if k ~= "model_node" then
					txt = v:text();
				else
					txt ="";
				end
				txt = string.gsub(txt, " ", "");
				txt = string.gsub(txt, "\n", "_");
				io.write(n .. " (" .. txt .. ") " .. "{" .. ns .. "}");
			end
			 io.write("\n");
		end
		io.write(")\n");
	end
end

for name, test in pairs(tests) do
	perform_test(name, test);
end

