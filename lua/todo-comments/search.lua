local Config = require("todo-comments.config")
local Highlight = require("todo-comments.highlight")
local Util = require("todo-comments.util")

local M = {}

local function status_filter(statuses)
  if not statuses then
    return nil
  end
  
  -- Split comma-separated statuses
  local status_list = vim.split(statuses, ",")
  -- Trim whitespace from each status
  for i, s in ipairs(status_list) do
    status_list[i] = vim.trim(s)
  end
  
  return status_list
end

function M.process(lines, opts)
  opts = opts or {}
  local status_filters = status_filter(opts.status)
  
  local results = {}
  for _, line in pairs(lines) do
    local file, row, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
    if file then
      local item = {
        filename = file,
        lnum = tonumber(row),
        col = tonumber(col),
        line = text,
      }

      -- Parse markdown checklist format: [-+*]|[0-9]+\. \[[- x/<>?!*"lb~]\] .+
      local checklist_match = text:match("^%s*([%-+*]%s*)%[%s*([xX/<>?!*\"lb~]-)%s*%]%s*(.*)$")
      local numbered_match = text:match("^%s*(%d+%.%s*)%[%s*([xX/<>?!*\"lb~]-)%s*%]%s*(.*)$")
      
      if checklist_match or numbered_match then
        local prefix, status, content
        if checklist_match then
          prefix, status, content = text:match("^%s*([%-+*]%s*)%[%s*([xX/<>?!*\"lb~]-)%s*%]%s*(.*)$")
        else
          prefix, status, content = text:match("^%s*(%d+%.%s*)%[%s*([xX/<>?!*\"lb~]-)%s*%]%s*(.*)$")
        end
        
        if status then
          -- Map status to appropriate tag
          local tag
          if status == "" or status == " " then
            tag = "TODO"  -- Unchecked
          elseif status:lower() == "x" then
            tag = "DONE"  -- Checked
          elseif status == ">" then
            tag = "IN_PROGRESS"  -- In progress
          elseif status == "?" then
            tag = "QUESTION"  -- Questionable
          elseif status == "!" then
            tag = "IMPORTANT"  -- Important
          else
            tag = "TODO"  -- Default for other statuses
          end
          
          -- Apply status filtering if specified
          if status_filters == nil or vim.tbl_contains(status_filters, tag) then
            item.tag = tag
            item.text = vim.trim(text)
            item.message = vim.trim(content)
            table.insert(results, item)
          end
        end
      end
    end
  end
  return results
end

function M.search(cb, opts)
  opts = opts or {}
  opts.cwd = opts.cwd or "."
  opts.cwd = vim.fn.fnamemodify(opts.cwd, ":p")
  opts.disable_not_found_warnings = opts.disable_not_found_warnings or false
  if not Config.loaded then
    Util.error("todo-comments isn't loaded. Did you run setup()?")
    return
  end

  local command = Config.options.search.command

  if vim.fn.executable(command) ~= 1 then
    Util.error(command .. " was not found on your path")
    return
  end

  local ok, Job = pcall(require, "plenary.job")
  if not ok then
    Util.error("search requires https://github.com/nvim-lua/plenary.nvim")
    return
  end

  local args = {}
  vim.list_extend(args, Config.options.search.args)
  vim.list_extend(args, { Config.search_regex(), opts.cwd })

  Job:new({
    command = command,
    args = args,
    on_exit = vim.schedule_wrap(function(j, code)
      if code == 2 then
        local error = table.concat(j:stderr_result(), "\n")
        Util.error(command .. " failed with code " .. code .. "\n" .. error)
      end
      if code == 1 and opts.disable_not_found_warnings ~= true then
        Util.warn("no todos found")
      end
      local lines = j:result()
      cb(M.process(lines, opts))
    end),
  }):start()
end

local function parse_opts(opts)
  if not opts or type(opts) ~= "string" then
    return opts
  end
  return {
    status = opts:match("status=(%S*)"),  -- For markdown, we might filter by status
    cwd = opts:match("cwd=(%S*)"),
  }
end

function M.setqflist(opts)
  M.setlist(opts)
end

function M.setloclist(opts)
  M.setlist(opts, true)
end

function M.setlist(opts, use_loclist)
  opts = parse_opts(opts) or {}
  opts.open = (opts.open ~= nil and { opts.open } or { true })[1]
  M.search(function(results)
    if use_loclist then
      vim.fn.setloclist(0, {}, " ", { title = "Todo", id = "$", items = results })
    else
      vim.fn.setqflist({}, " ", { title = "Todo", id = "$", items = results })
    end
    if opts.open then
      if use_loclist then
        vim.cmd([[lopen]])
      else
        vim.cmd([[copen]])
      end
    end
    local win = vim.fn.getqflist({ winid = true })
    if win.winid ~= 0 then
      Highlight.highlight_win(win.winid, true)
    end
  end, opts)
end

return M
