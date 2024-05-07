local state = {}

vis.events.subscribe(vis.events.FILE_OPEN, function(file)
  if not file.path then
    return
  end
  local escaped = file.path:gsub("'", "'\\''")
  local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
    dir="$(dirname ']] .. escaped .. [[')"
    [ -d "$dir" ] || exit 1
    if [ -e ']] .. escaped .. [[' ]; then
      [ -w ']] .. escaped .. [[' ]
    else
      [ -w "$dir" ]
    fi
  ]])
  state[file.path] = {
    writable = status == 0,
  }
end)

vis.events.subscribe(vis.events.FILE_SAVE_PRE, function(file)
  if state[file.path] and not state[file.path].writable then
    local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
      ls -l ']] .. state[file.path].escaped .. [[' | cut -d' ' -f4
      sudo chown "$(whoami)" ']] .. state[file.path].escaped .. [[' >/dev/null
    ]])
    state[file.path].owner = out:gsub('\n$', '')
  end
end)

vis.events.subscribe(vis.events.FILE_SAVE_POST, function(file)
  if state[file.path] and not state[file.path].writable then
    local status, out, err = vis:pipe(file, { start = 0, finish = 0 },
      "sudo chown '"
        .. state[file.path].owner:gsub("'", "'\\''")
        .. "' '"
        .. state[file.path].escaped
        .. "'"
    )
  end
end)
