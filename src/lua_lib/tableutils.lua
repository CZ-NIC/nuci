--[[
Copyright 2013, CZ.NIC

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

--[[
Take only the first occurrence of each value in the list. Preserve the order
of the first occurrences.
]]
function table.uniq(list)
	local result = {};
	local seen = {};
	for _, value in ipairs(list) do
		if not seen[value] then
			seen[value] = true;
			table.insert(result, value);
		end
	end
	return result;
end

--[[
Add items from one list into the target list.
]]
function table.extend(target, items)
	-- TODO: This could be optimised (compute the index and then just copy the rest)
	for _, item in ipairs(items) do
		table.insert(target, item);
	end
end

-- Test if table is empty or not
function table.is_empty(table)
	if not table then
		return true;
	end
	if next(table) == nil then
		return true;
	end

	return false;
end

-- Not sure with license
-- Code is from http://lua-users.org/wiki/TableUtils
function table.val_to_str ( v )
  if "string" == type( v ) then
    v = string.gsub( v, "\n", "\\n" )
    if string.match( string.gsub(v,"[^'\"]",""), '^"+$' ) then
      return "'" .. v .. "'"
    end
    return '"' .. string.gsub(v,'"', '\\"' ) .. '"'
  else
    return "table" == type( v ) and table.tostring( v ) or
      tostring( v )
  end
end

function table.key_to_str ( k )
  if "string" == type( k ) and string.match( k, "^[_%a][_%a%d]*$" ) then
    return k
  else
    return "[" .. table.val_to_str( k ) .. "]"
  end
end

function table.tostring( tbl )
  local result, done = {}, {}
  for k, v in ipairs( tbl ) do
    table.insert( result, table.val_to_str( v ) )
    done[ k ] = true
  end
  for k, v in pairs( tbl ) do
    if not done[ k ] then
      table.insert( result,
        table.key_to_str( k ) .. "=" .. table.val_to_str( v ) )
    end
  end
  return "{" .. table.concat( result, "," ) .. "}"
end
