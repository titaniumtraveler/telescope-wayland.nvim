local api = vim.api

local action_state = require("telescope.actions.state")
local scheduler = require("plenary.async.util").scheduler
local entry_display = require("telescope.pickers.entry_display")
local make_entry = require("telescope.make_entry")
local pickers = require("telescope.pickers")
local utils = require("telescope.utils")
local conf = require("telescope.config").values
local ts = vim.treesitter

local M = {}

---@return fun(bufnr: integer): string
function M.get_filename_fn()
  ---@type {[integer]: string}
  local bufnr_name_cache = {}
  return function(bufnr)
    bufnr = vim.F.if_nil(bufnr, 0)
    local c = bufnr_name_cache[bufnr]
    if c then
      return c
    end

    local n = api.nvim_buf_get_name(bufnr)
    bufnr_name_cache[bufnr] = n
    return n
  end
end

api.nvim_set_hl(0, "wayland_protocol", { fg = "#A855F7" })
api.nvim_set_hl(0, "wayland_interface", { fg = "#3B82F6" })
api.nvim_set_hl(0, "wayland_request", { fg = "#EC4899" })
api.nvim_set_hl(0, "wayland_event", { fg = "#10B981" })
api.nvim_set_hl(0, "wayland_enum", { fg = "#F97316" })

M.treesitter_type_highlight = {
  ["protocol"] = "wayland_protocol",
  ["interface"] = "wayland_interface",
  ["request"] = "wayland_request",
  ["event"] = "wayland_event",
  ["enum"] = "wayland_enum",
}

function M.gen_entry(opts)
  opts = opts or {}

  local displayer = entry_display.create({
    separator = "",
    items = {
      { remaining = true },
      { remaining = true },
      { remaining = true },
      { remaining = true },
    },
  })

  local type_highlight = opts.symbol_highlights or M.treesitter_type_highlight

  ---@param entry telescope-wayland.entry.display
  local display = function(entry)
    ---@type (string | [string,string])[]
    local columns = {}

    if entry.protocol then
      columns[#columns + 1] = { entry.protocol, type_highlight["protocol"] }
    end

    if entry.interface then
      columns[#columns][1] = columns[#columns][1] .. "::"
      columns[#columns + 1] = { entry.interface, type_highlight["interface"] }
    end

    if entry.item then
      columns[#columns][1] = columns[#columns][1] .. "."
      columns[#columns + 1] = { entry.item .. "()", type_highlight[entry.kind] }
    end

    return displayer(columns)
  end

  ---@param entry telescope-wayland.entry
  return function(entry)
    ---@cast entry telescope-wayland.entry.display

    do
      local start_row, start_col, end_row, _ = unpack(entry.range)
      entry.lnum = start_row + 1
      entry.col = start_col
      entry.start = start_row
      entry.finish = end_row
    end

    do
      ---@type string
      local protocol, interface, item = "", "", ""

      if entry.protocol then
        protocol = string.format("%s:%s", entry.kind, entry.protocol)
      end
      if entry.interface then
        interface = string.format("::%s", entry.interface)
      end
      if entry.item then
        item = string.format(".%s()", entry.item)
      end

      entry.ordinal = protocol .. interface .. item
    end

    entry.display = display

    return make_entry.set_default_entry_mt(entry, opts)
  end
end

---@alias telescope-wayland.entry.kind
---| "protocol"
---| "interface"
---| "enum"
---| "request"
---| "event"

---@alias telescope-wayland.entry.item_kind
---| "enum"
---| "request"
---| "event"

---@class telescope-wayland.entry
---@field kind      telescope-wayland.entry.kind
---@field protocol  string?
---@field interface string?
---
---@field item_kind telescope-wayland.entry.item_kind?
---@field item      string?
---
---@field filename  string?
---@field range     Range4?

---@class telescope-wayland.entry.display: telescope-wayland.entry
---@field lnum    integer
---@field col     integer
---@field start   integer
---@field finish  integer
---
---@field ordinal string
---@field display fun(entry: telescope-wayland.entry.display): string

---@param source integer|string bufnr string
---@param filename string?
---@param cb fun(entry: telescope-wayland.entry): true?
function M.collect_results(source, filename, cb)
  local lang = "xml"
  if not (lang and ts.language.add(lang)) then
    utils.notify("builtin.treesitter", {
      msg = "No parser for the current buffer",
      level = "ERROR",
    })
    return
  end

  local query = vim.treesitter.query.get("xml", "wayland")
  if not query then
    utils.notify("treesitter.wayland", {
      msg = "failed to parse query",
      level = "ERROR",
    })
    return
  end

  ---@type vim.treesitter.LanguageTree
  local parser
  if type(source) == "string" then
    parser = ts.get_string_parser(source, lang)
  elseif type(source) == "number" then
    parser = assert(ts.get_parser(source, lang))
  end
  parser:parse()
  local root = parser:trees()[1]:root()

  local captures = {
    protocol = 1,
    protocol_name_val = 1,
    interface = 1,
    interface_name_val = 1,
    request = 1,
    request_name_val = 1,
    event = 1,
    event_name_val = 1,
    enum = 1,
    enum_name_val = 1,
  }

  vim
    .iter(pairs(query.captures))
    :filter(function(_, name)
      return captures[name] and true
    end)
    :each(function(id, name)
      ---@type {[string]: integer }
      captures[name] = id
    end)

  ---@type string?, string?
  local protocol, interface
  for _, match, metadata in query:iter_matches(root, source) do
    local kind = metadata.kind --[[@as telescope-wayland.entry.kind ]]

    ---@param id integer
    ---@return string
    ---@return Range4
    local function get_node_text(id)
      local node = match[id][1]
      local node_data = metadata[id]

      ---@type integer,integer,integer,integer,integer,integer
      local row_s, col_s, _, row_e, col_e, _ = unpack(ts.get_range(node, source, node_data))

      local text = ts.get_node_text(node, source, { metadata = node_data })
      return text, { row_s, col_s, row_e, col_e }
    end

    ---@type string, telescope-wayland.entry.item_kind, Range4
    local item, item_kind, range
    if kind == "protocol" then
      protocol, range = get_node_text(captures.protocol_name_val)
      interface = nil
    elseif kind == "interface" then
      interface, range = get_node_text(captures.interface_name_val)
    elseif kind == "request" then
      item_kind = "request"
      item, range = get_node_text(captures.request_name_val)
    elseif kind == "event" then
      item_kind = "event"
      item, range = get_node_text(captures.event_name_val)
    elseif kind == "enum" then
      item_kind = "enum"
      item, range = get_node_text(captures.enum_name_val)
    else
      error("invalid match")
    end

    if
      cb({
        kind = kind,

        protocol = protocol,
        interface = interface,

        item_kind = item_kind,
        item = item,

        filename = filename,
        range = range,
      })
    then
      break
    end
  end
end

---@param entry telescope-wayland.entry
---@param base_url string
---@return string?
function M.entry_url(entry, base_url)
  local url = entry and entry.filename and vim.fs.basename(entry.filename)
  if not url then
    return
  end

  if vim.endswith(url, ".xml") then
    url = url:sub(1, -5)
  end

  url = base_url .. url

  if entry.interface then
    url = url .. "#" .. entry.interface
  end

  if entry.item then
    url = url .. ":" .. entry.item_kind .. ":" .. entry.item
  end

  return url
end

---@param entry telescope-wayland.entry
---@return string
function M.entry_name(entry)
  ---@type string
  local protocol, interface, item = "", "", ""

  if entry.protocol then
    protocol = string.format("%s", entry.protocol)
  end
  if entry.interface then
    interface = string.format("::%s", entry.interface)
  end
  if entry.item then
    item = string.format(".%s()", entry.item)
  end

  return protocol .. interface .. item
end

---@param entry telescope-wayland.entry
---@param base_url string
---@return string?
function M.entry_ref(entry, base_url)
  local name, url = M.entry_name(entry), M.entry_url(entry, base_url)
  if name and url then
    return string.format("[`%s`](%s)", name, url)
  end
end

---@param opts telescope-wayland.opts
---@param name (integer | string)?
function M.picker(opts, name)
  if name then
    opts.sources = require("telescope-wayland").resolve_sources(opts, name)
  end
  opts.sources = opts.sources or { vim.api.nvim_get_current_buf() }

  local stop = false
  local complete = false
  local results = {}
  pickers
    .new(opts, {
      prompt_title = "Wayland protocol",
      finder = setmetatable({
        results = results,
        close = function()
          stop = true
        end,
      }, {
        __call = function(_, _, process_result, process_complete)
          if complete then
            for _, v in pairs(results) do
              process_result(v)
            end
            process_complete()
            return
          end

          if stop then
            results = {}
            stop = false
          end

          local entry_maker = M.gen_entry(opts)

          for _, source in pairs(opts.sources) do
            ---@type string?
            local filename
            if type(source) == "string" then
              filename = nil
            elseif type(source) == "number" then
              filename = api.nvim_buf_get_name(source)
            else
              error("invalid wayland source: " .. vim.inspect(source))
            end

            M.collect_results(source, filename, function(entry)
              results[#results + 1] = entry_maker(entry)
              results[#results].index = #results

              if process_result(results[#results]) or stop then
                stop = true
                return true
              end
            end)

            scheduler()

            if stop then
              process_complete()
              return
            end
          end

          complete = true
          process_complete()
        end,
      }),

      previewer = conf.grep_previewer(opts),
      sorter = conf.generic_sorter(opts),
      push_cursor_on_edit = true,
      attach_mappings = function(_, map)
        local opts = require("telescope-wayland").resolve_opts(opts) ---@diagnostic disable-line:redefined-local
        ---@cast opts telescope-wayland.opts

        map({ "n", "i" }, "<C-b>", function()
          require("telescope-wayland.pickers.group").picker(opts)
        end)

        map({ "n", "i" }, "<C-o>", function()
          ---@type telescope-wayland.entry.display?
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end

          local url = M.entry_url(entry, opts.base_url)
          if not url then
            return
          end

          vim.ui.open(url)
        end)

        map({ "n", "i" }, "<C-c>", function()
          ---@type telescope-wayland.entry.display?
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          vim.fn.setreg("+", M.entry_ref(entry, opts.base_url))
        end)

        return true
      end,
    })
    :find()
end

return M
