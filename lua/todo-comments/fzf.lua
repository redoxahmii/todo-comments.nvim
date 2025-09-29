local Config = require("todo-comments.config")
local Search = require("todo-comments.search")
local Grep = require("fzf-lua.providers.grep")

local M = {}

---@param opts? {status: string[]}
function M.todo(opts)
  opts = opts or {}
  -- Use the same search infrastructure as other commands for consistency
  -- The status filtering is handled in the Search.search function
  local search_pattern = Config.search_regex()
  
  -- Pass through status filtering options to be handled by grep provider
  opts.search = search_pattern
  opts.no_esc = true
  opts.multiline = true
  
  -- Process results if status filtering is specified
  if opts.status then
    local original_callback = opts.resume_cb or opts.cb
    opts.resume_cb = function(line)
      -- This is a simplified filter approach - parse the line to check status
      local _, _, _, text = line:match("^(.+):(%d+):(%d+):(.*)$") or {nil, nil, nil, line}
      if text then
        local _, _, kw = require("todo-comments.highlight").match(text)
        if kw then
          local status_filters = opts.status
          if type(status_filters) == "string" then
            status_filters = vim.split(status_filters, ",")
            for i, s in ipairs(status_filters) do
              status_filters[i] = vim.trim(s)
            end
          end
          
          if not status_filters or vim.tbl_contains(status_filters, kw) then
            -- Call original callback if status matches filter
            if original_callback then
              original_callback(line)
            end
          end
        else
          -- If no keyword is matched, still call callback (or don't based on preference)
          if original_callback then
            original_callback(line)
          end
        end
      else
        if original_callback then
          original_callback(line)
        end
      end
    end
  end
  
  return Grep.grep(opts)
end

return M
