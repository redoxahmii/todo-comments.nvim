---@diagnostic disable: inject-field
local Config = require("todo-comments.config")
local Highlight = require("todo-comments.highlight")

---@module 'snacks'

local M = {}

---@class snacks.picker.todo.Config: snacks.picker.grep.Config
---@field status? string[]  -- For markdown checklists, filter by status (TODO, DONE, etc.)

---@type snacks.picker.todo.Config|{}
M.source = {
  finder = "grep",
  live = false,
  supports_live = true,
  search = function(picker)
    -- For markdown checklists, we use the fixed pattern instead of keywords
    return Config.search_regex()
  end,
  ---@param item snacks.picker.Item
  ---@param picker snacks.Picker
  format = function(item, picker)
    local _, _, kw = Highlight.match(item.text)

    -- Get the standard file formatting first
    local file_parts = Snacks.picker.format.file(item, picker) or {}

    -- Create todo-specific prefix parts
    local prefix_parts = {}
    if kw then
      kw = Config.keywords[kw] or kw
      local icon = vim.tbl_get(Config.options.keywords, kw, "icon") or ""

      if icon and icon ~= "" then
        -- Add icon with highlight
        table.insert(prefix_parts, { icon, "TodoFg" .. kw })
        -- Add a single space
        table.insert(prefix_parts, { " ", nil })
        -- Add keyword with highlight
        table.insert(prefix_parts, { kw, "TodoBg" .. kw })
        -- Add another space
        table.insert(prefix_parts, { " ", nil })
      end
    end

    -- Insert prefix parts at the beginning of file_parts
    for i = #prefix_parts, 1, -1 do
      table.insert(file_parts, 1, prefix_parts[i])
    end

    return file_parts
  end,
  previewer = function(ctx)
    Snacks.picker.preview.file(ctx)
    Highlight.highlight_win(ctx.preview.win.win, true)
    Highlight.update()
  end,
}

---@param opts snacks.picker.todo.Config
function M.pick(opts)
  return Snacks.picker.pick("todo", opts)
end

return M
