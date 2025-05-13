local state = {}
local dir = debug.getinfo(1, 'S').source:sub(2):match('(.*/)')

local run = function(cmd)
  local fz = io.popen(cmd)
  if fz then
    local out = fz:read('*a')
    local _, _, status = fz:close()
    if status == 0 then
      return out
    end
  end
end

vis.events.subscribe(vis.events.INIT, function()
  local argv = run([[
    set -- $(ps -o ppid= $$)
    case "$(uname -s)" in
      Linux)
        cat "/proc/$1/cmdline"
        ;;
      Darwin)
        dir=']] .. dir:gsub("'", "'\\''") .. [['
        [ -e "$dir/cmdline" ] || swiftc -o "$dir/cmdline" "$dir/cmdline.swift"
        "$dir/cmdline" "$1"
    esac
  ]])
  local i = 0
  local sep = 0
  local args = 'set --'
  for arg in argv:gmatch('([^%z]*)%z') do
    if sep == 0 and arg == '--' then
      sep = 1
    elseif
      sep ~= 0 or not (i == 0 or arg:find('^%+') or not arg:find('/'))
    then
      args = args
        .. " '"
        .. arg:gsub('/?[^/]*$', '/'):gsub("'", "'\\''")
        .. "'"
    end
    i = i + 1
  end
  run([[
    ]] .. args .. [[;
    dirs=''
    for dir in "$@"; do
      if ! [ -d "$dir" ]; then
        dirs="${dirs:+$dirs }'$(printf "${dir%/}" | sed "s/'/'\\\\''/g")'"
      fi
    done
    eval "set -- $dirs"
    [ $# -gt 0 ] || exit
    if command -v fzf >/dev/null 2>&1; then
      REPLY="$({
        printf "Create the following directories:\n\n"
        printf "%s\n" "$@"
        printf "\nYes\nNo\n" "$@"
      } | fzf --header-lines="$(($# + 3))" --no-input)" || exit
      [ $REPLY = Yes ] || exit
    else
      printf "Will create the following directories. \r\n" >/dev/tty
      printf "Ctrl+C in 3 s to cancel\r\n" >/dev/tty
      printf "\r\n" >/dev/tty
      printf "%s\r\n" "$@" >/dev/tty
      sleep 3
    fi
    for dir in "$@"; do
      mkdir -p "$dir"
    done
  ]])
end)

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
    if status > 0 then
      if err then
        vis:message('Could not change owner for writing:\n\n' .. err)
      end
      error()
    end
  end
end)

vis.events.subscribe(vis.events.FILE_SAVE_POST, function(file)
  if state[file.path] and not state[file.path].writable then
    local status, out, err = vis:pipe(file, { start = 0, finish = 0 }, [[
      file=']] .. file.path:gsub("'", "'\\''") .. [['
      owner=']] .. state[file.path].owner:gsub("'", "'\\''") .. [['
      sudo chown "$owner" "$file"
   ]])
    if status > 0 then
      vis:message(
        'Could not change owner back to '
          .. state[file.path].owner
          .. (err and (':\n\n' .. err .. '\n') or '. ')
          .. 'You will need to fix this manually.'
      )
    end
  end
end)
