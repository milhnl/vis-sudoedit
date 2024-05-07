local state = {}

vis.events.subscribe(vis.events.FILE_OPEN, function(file)
  if not file.path then
    return
  end
  local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
    file=']] .. file.path:gsub("'", "'\\''") .. [['
    if [ -e "$file" ]; then
      [ -w "$file" ]
    elif dir="$(dirname "$file")"; [ -d "$dir" ]; then
      [ -w "$dir" ]
    else
      false
    fi
  ]])
  state[file.path] = {
    writable = status == 0,
  }
end)

vis.events.subscribe(vis.events.FILE_SAVE_PRE, function(file)
  if state[file.path] and not state[file.path].writable then
    local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
      file=']] .. file.path:gsub("'", "'\\''") .. [['
      ls -l "$file" | cut -d' ' -f4 || exit 1
      sudo chown "$(whoami)" "$file" >/dev/null
    ]])
    state[file.path].owner = out:gsub('\n$', '')
  end
end)

vis.events.subscribe(vis.events.FILE_SAVE_POST, function(file)
  if state[file.path] and not state[file.path].writable then
    local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
      file=']] .. file.path:gsub("'", "'\\''") .. [['
      owner=']] .. state[file.path].owner:gsub("'", "'\\''") .. [['
      sudo chown "$owner" "$file"
   ]])
  end
end)
