local Util = require("todo-comments.util")

--- @class TodoConfig
local M = {}

M.keywords = {}
--- @type TodoOptions
M.options = {}
M.loaded = false

M.ns = vim.api.nvim_create_namespace("todo-comments")

--- @class TodoOptions
-- TODO: add support for markdown todos
local defaults = {
  signs = true, -- show icons in the signs column
  sign_priority = 8, -- sign priority
  -- default status types for markdown checklist items
  keywords = {
    TODO = {
      icon = "󰥔 ", -- icon used for the sign, and in search results
      color = "info", -- can be a hex color, or a named color (see below)
    },
    DONE = { 
      icon = " ", 
      color = "hint" 
    },
    IN_PROGRESS = { 
      icon = "󰐊 ", 
      color = "warning" 
    },
    QUESTION = { 
      icon = " ", 
      color = "info" 
    },
    IMPORTANT = { 
      icon = " ", 
      color = "error" 
    },
  },
  gui_style = {
    fg = "NONE", -- The gui style to use for the fg highlight group.
    bg = "BOLD", -- The gui style to use for the bg highlight group.
  },
  merge_keywords = true, -- when true, custom keywords will be merged with the defaults
  -- highlighting of the line containing the todo comment
  -- * before: highlights before the checklist marker (typically the bullet or number)
  -- * keyword: highlights of the checkbox [ ]
  -- * after: highlights after the checkbox (todo text)
  highlight = {
    multiline = true, -- enable multiline todo comments
    multiline_pattern = "^.", -- lua pattern to match the next multiline from the start of the matched checklist item
    multiline_context = 10, -- extra lines that will be re-evaluated when changing a line
    before = "", -- "fg" or "bg" or empty
    keyword = "wide", -- "fg", "bg", "wide" or empty. (wide is the same as bg, but will also highlight surrounding characters)
    after = "fg", -- "fg" or "bg" or empty
    -- pattern can be a string, or a table of regexes that will be checked
    pattern = [[.*\S\s\[[- x/<>?!*"lb~]\]\s.*]], -- pattern or table of patterns, used for highlighting markdown checklists (vim regex)
    comments_only = false, -- don't use treesitter since we're working with markdown, not comments
    max_line_len = 400, -- ignore lines longer than this
    exclude = {}, -- list of file types to exclude highlighting
    throttle = 200,
  },
  -- list of named colors where we try to extract the guifg from the
  -- list of hilight groups or use the hex color if hl not found as a fallback
  colors = {
    error = { "DiagnosticError", "ErrorMsg", "#DC2626" },
    warning = { "DiagnosticWarn", "WarningMsg", "#FBBF24" },
    info = { "DiagnosticInfo", "#2563EB" },
    hint = { "DiagnosticHint", "#10B981" },
    default = { "Identifier", "#7C3AED" },
    test = { "Identifier", "#FF00FF" },
  },
  search = {
    command = "rg",
    args = {
      "--color=never",
      "--no-heading",
      "--with-filename",
      "--line-number",
      "--column",
      "--glob=*.md",
      "--glob=*.markdown",
      "--glob=*.mdx",
    },
    -- regex that will be used to match markdown checklist patterns
    pattern = [[([\-+*]|[0-9]+\.?) \[[- x/<>?!*"lb~]\] .+]], -- ripgrep regex for markdown checklists
  },
}

M._options = nil

function M.setup(options)
  if vim.fn.has("nvim-0.8.0") == 0 then
    error("todo-comments needs Neovim >= 0.8.0. Use the 'neovim-pre-0.8.0' branch for older versions")
  end
  M._options = options
  if vim.api.nvim_get_vvar("vim_did_enter") == 0 then
    vim.defer_fn(function()
      M._setup()
    end, 0)
  else
    M._setup()
  end
end

function M._setup()
  M.options = vim.tbl_deep_extend("force", {}, defaults, M.options or {}, M._options or {})

  -- -- keywords should always be fully overriden
  if M._options and M._options.keywords and M._options.merge_keywords == false then
    M.options.keywords = M._options.keywords
  end

  for kw, opts in pairs(M.options.keywords) do
    M.keywords[kw] = kw
    for _, alt in pairs(opts.alt or {}) do
      M.keywords[alt] = kw
    end
  end

  function M.search_regex(keywords)
    -- For markdown checklist search, we don't need to substitute keywords
    -- The pattern is already set for markdown checklist format
    return M.options.search.pattern
  end

  M.hl_regex = {}
  local patterns = M.options.highlight.pattern
  patterns = type(patterns) == "table" and patterns or { patterns }
  for _, p in pairs(patterns) do
    -- For markdown checklist highlighting, we don't need to substitute keywords
    table.insert(M.hl_regex, p)
  end
  M.colors()
  M.signs()
  require("todo-comments.highlight").start()
  if Snacks and pcall(require, "snacks.picker") then
    Snacks.picker.sources.todo_comments = require("todo-comments.snacks").source
  end
  M.loaded = true
end

function M.signs()
  for kw, opts in pairs(M.options.keywords) do
    vim.fn.sign_define("todo-sign-" .. kw, {
      text = opts.icon,
      texthl = "TodoSign" .. kw,
    })
  end
end

function M.colors()
  local normal = Util.get_hl("Normal")
  local normal_fg = normal.foreground
  local normal_bg = normal.background
  local default_dark = "#000000"
  local default_light = "#FFFFFF"
  if not normal_fg and not normal_bg then
    normal_fg = default_light
    normal_bg = default_dark
  elseif not normal_fg then
    normal_fg = Util.maximize_contrast(normal_bg, default_dark, default_light)
  elseif not normal_bg then
    normal_bg = Util.maximize_contrast(normal_fg, default_dark, default_light)
  end
  local fg_gui = M.options.gui_style.fg
  local bg_gui = M.options.gui_style.bg

  local sign_hl = Util.get_hl("SignColumn")
  local sign_bg = (sign_hl and sign_hl.background) and sign_hl.background or "NONE"

  for kw, opts in pairs(M.options.keywords) do
    local kw_color = opts.color or "default"
    local hex

    if kw_color:sub(1, 1) == "#" then
      hex = kw_color
    else
      local colors = M.options.colors[kw_color]
      colors = type(colors) == "string" and { colors } or colors

      for _, color in pairs(colors) do
        if color:sub(1, 1) == "#" then
          hex = color
          break
        end
        local c = Util.get_hl(color)
        if c and c.foreground then
          hex = c.foreground
          break
        end
      end
    end
    if not hex then
      error("Todo: no color for " .. kw)
    end
    local fg = Util.maximize_contrast(hex, normal_fg, normal_bg)

    vim.cmd("hi def TodoBg" .. kw .. " guibg=" .. hex .. " guifg=" .. fg .. " gui=" .. bg_gui)
    vim.cmd("hi def TodoFg" .. kw .. " guibg=NONE guifg=" .. hex .. " gui=" .. fg_gui)
    vim.cmd("hi def TodoSign" .. kw .. " guibg=" .. sign_bg .. " guifg=" .. hex .. " gui=NONE")
  end
end

return M
