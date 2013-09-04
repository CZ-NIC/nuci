require ("views");

local view = register_view("networking.yin", "networking");

-- Generate the top-level skeleton with parts to plug things into
hook_get("networking", {}, function ()
	return {
		name = 'networking',
		namespace = view.model_ns,
		children = {
			{
				name = 'internet',
				generate = true
			}
		},
		generate = true,
		known = { 'internet' }
	};
end);

-- This is actually just a dummy stuff, for testing.
hook_get("networking", {'networking', 'internet'}, function ()
	return {
		name = 'internet',
		children = {
			{
				name = 'address',
				text = '192.0.2.42/24'
			},
			{
				name = 'address',
				text = '2001:db8::42/64'
			},
			{
				name = 'nat'
			}
		},
		known = { 'address', 'nat', 'nat6' }
	}
end);

hook_get("networking", {'networking', 'internet'}, function ()
	return {
		name = 'internet',
		children = {
			{
				name = 'gateway',
				text = '192.168.2.1'
			},
			{
				name = 'gateway',
				text = '2001:db8::1'
			},
			{
				name = 'address',
				text = '2001:db8::42/64'
			},
			{
				name = 'address',
				text = '192.0.2.42/24'
			}
		},
		known = { 'gateway', 'address' }
	}
end);

local function erase_internet(doc)
	for i, child in pairs(doc.children) do
		if child.name == 'internet' then
			doc.children[i] = nil;
			return;
		end
	end
end

hook_differ("networking", {'networking', 'internet'}, erase_internet);
hook_differ("networking", {'networking', 'internet', '*'}, erase_internet);

hook_set("networking", {'*'}, function(mode, text, index_path, path)
	io.stderr:write("Set: " .. mode .. " " .. (text or "<nil>") .. "\n");
end);