-- pgide.lua — WezTerm glue for pgide. install.sh copies this to ~/.config/wezterm/pgide.lua
-- and adds a marked block to your wezterm.lua (before `return config`):
--
--     require('pgide').apply(config)                                  -- LEADER + d, else CMD|SHIFT + p
--     require('pgide').apply(config, { key = 'd', mods = 'CMD|SHIFT' })  -- or pick a key
--
-- What it adds:
--   • a key that opens a new tab running the pgide connection picker
--   • red tabs for connections flagged as production (pgide sets the title to "⚠ pg:<name>"),
--     tinted tabs for other pgide sessions; every other tab is left alone
--   • with { option_as_alt = true }: left Option behaves as Alt, so rainfrog's Alt+1…5 work
--
-- If you already have a 'format-tab-title' handler, merge the colouring below into it
-- rather than registering a second one.
local wezterm = require 'wezterm'
local act = wezterm.action

local M = {}

local function pgide_bin()
  local home = os.getenv('HOME') or ''
  return home .. '/.local/bin/pgide'
end

function M.apply(config, opts)
  opts = opts or {}
  config.keys = config.keys or {}
  local key, mods = opts.key, opts.mods
  if not key then
    if config.leader then key, mods = 'd', 'LEADER' else key, mods = 'p', 'CMD|SHIFT' end
  end
  table.insert(config.keys, {
    key = key,
    mods = mods,
    action = act.SpawnCommandInNewTab { args = { pgide_bin() } },
  })
  if opts.option_as_alt then
    config.send_composed_key_when_left_alt_is_pressed = false
  end
end

wezterm.on('format-tab-title', function(tab, tabs, panes, cfg, hover, max_width)
  local title = tab.tab_title
  if not title or #title == 0 then
    title = tab.active_pane.title
  end
  local text = wezterm.truncate_right(' ' .. title .. ' ', max_width)
  if title:find('⚠', 1, true) then
    return {
      { Background = { Color = tab.is_active and '#b3261e' or '#6e1a14' } },
      { Foreground = { Color = '#ffffff' } },
      { Attribute = { Intensity = 'Bold' } },
      { Text = text },
    }
  elseif title:sub(1, 3) == 'pg:' then
    return {
      { Foreground = { Color = tab.is_active and '#9ccfd8' or '#5f8f98' } },
      { Text = text },
    }
  end
  return text
end)

return M
