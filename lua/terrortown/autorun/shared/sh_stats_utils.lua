local Utils = {}

-- function to copy tables (http://lua-users.org/wiki/CopyTable)
function Utils.shallowcopy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == 'table' then
    copy = {}
    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

function Utils.getFormattedDate()
  return os.date("%Y-%m-%d %H:%M:%S")
end

return Utils
