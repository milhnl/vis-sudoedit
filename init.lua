local state = {}

local get_cmd = function(cmd)
  local fz = io.popen(cmd)
  if fz then
    local out = fz:read('*a')
    local _, _, statusop = fz:close()
    if status == 0 then
      return out:gsub('\n$', '')
    end
  end
  return nil
end

vis.events.subscribe(vis.events.FILE_OPEN, function(file)
  if not file.path then
    return
  end
  local escaped = file.path:gsub("'", "'\\''")
  state[file.path] = {
    writable = 'true' == get_cmd([[
      dir="$(dirname ']] .. escaped .. [[')"
      [ -d "$dir" ] || exit 1
      if [ -e ']] .. escaped .. [[' ]; then
        [ -w ']] .. escaped .. [[' ] && echo "true"
      else
        [ -w "$dir" ] && echo "true"
      fi
    ]]),
    escaped = escaped,
  }
end)

vis.events.subscribe(vis.events.FILE_SAVE_PRE, function(file)
  if state[file.path] and not state[file.path].writable then
    state[file.path].owner = get_cmd([[
      ls -l ']] .. state[file.path].escaped .. [[' | cut -d' ' -f4
      sudo chown "$(whoami)" ']] .. state[file.path].escaped .. [[' >/dev/null
    ]])
  end
end)

vis.events.subscribe(vis.events.FILE_SAVE_POST, function(file)
  if state[file.path] and not state[file.path].writable then
    get_cmd(
      "sudo chown '"
        .. state[file.path].owner:gsub("'", "'\\''")
        .. "' '"
        .. state[file.path].escaped
        .. "'"
    )
  end
end)
