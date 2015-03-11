require("datastore");
require("nutils"); -- viz src/lua_lib

local datastore = datastore("securris.yin");

function send_to_socket(text)
	-- TODO
end

-- RPC je jméno toho rpc, data je ten kus XML jako string.
function datastore:user_rpc(rpc, data)
	local xml = xmlwrap.read_memory(data);
	local root = xml:root();

	if rpc == 'pair' then
		local node = find_node_name_ns(root, 'transmit', self.model_ns);
		local transmit = "on";
		if node then
			local text = node:text();
			if text == 'false' or text == '0' then
				transmit = "off";
			end
			-- TODO: Ošetření chyb
		end
		nlog(NLOG_INFO, "Setting pairing mode");
		send_to_socket("pair " .. transmit .. "\n");
		return "<ok/>"; -- String s XML. Mohl bych i sestavit, ale u takto jednoduchého je to jedno.
	else
		-- Vracím strukturu popisující chybu
		return nil, {
			msg = "Command '" .. rpc .. "' not known",
			app_tag = 'unknown-element',
			info_badelem = rpc,
			info_badns = self.model_ns
		};
	end
end

function datastore:get()
	-- Nevím, jak bude vypadat ten status, takže jen nástřel, aby tu něco bylo.
	local xml = xmlwrap.new_xml_doc('status', self.model_ns);
	local root = xml:root();
	root:add_child('alarm'):add_text('666'); -- Alarm na device 666.
	return xml:strdump();
end

-- Přidání do nuci
register_datastore_provider(datastore);
