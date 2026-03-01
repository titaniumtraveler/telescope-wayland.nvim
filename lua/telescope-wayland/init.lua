local M = {}

---@class telescope-wayland.config
---@field groups table<string | integer,telescope-wayland.config.group>?
---@field default (string | integer)?

---@class telescope-wayland.config.resolved
---@field groups table<string | integer,telescope-wayland.config.group>
---@field default (string | integer)?

---@class telescope-wayland.config.group: string[]
---@field sources (string | integer)[]

---@class telescope-wayland.opts.resolved
---@field dir string
---@field sources (string | integer)[]?
---@field default (integer | string | boolean)?
---@field base_url string
---@field config telescope-wayland.config.resolved

---@class telescope-wayland.opts: telescope-wayland.opts.resolved
---@field dir string?
---@field sources (string | integer)[]?
---@field default (boolean | integer | string)?
---@field config (string | telescope-wayland.config | fun(config_path: string, opts: telescope-wayland.opts): telescope-wayland.config)?
---@field base_url string?
---@field include_default_config boolean?

---@param dir string
function M.config_path(dir)
  return vim.fs.joinpath(dir, "wayland-protocols/protocols.lua")
end

---@param opts telescope-wayland.opts
---@param path string?
---@return telescope-wayland.config?
function M.load_config_from_path(opts, path)
  path = path or M.config_path(opts.dir or vim.fn.getcwd(-1, -1))

  if not vim.uv.fs_stat(path) then
    return nil
  end

  return loadfile(path)()
end

---@type telescope-wayland.opts.resolved
M.default_opts = {
  sources = {},
  dir = vim.fn.getcwd(-1, -1),
  config = { groups = {} },
  base_url = "https://wayland.app/protocols/",
}

---@param opts telescope-wayland.opts
---@return boolean
local function should_include_default(opts)
  if not (type(opts.include_default_config) == "boolean" and not opts.include_default_config) then
    return true
  else
    return false
  end
end

---@param opts telescope-wayland.opts
---@return telescope-wayland.opts.resolved
---@return (integer | string)?
function M.resolve_opts(opts)
  local include_default = should_include_default(opts)

  local dir = opts.dir
  if include_default then
    dir = dir or M.default_opts.dir
  end
  dir = dir or vim.fn.getcwd(-1, -1)

  local config = (function()
    local config = opts.config

    if type(config) == "table" then
      return config
    elseif type(config) == "function" then
      return config(M.config_path(dir), opts)
    elseif not config or type(config) == "string" then
      return M.load_config_from_path(opts, config)
    end
  end)() or { groups = {} }

  ---@type telescope-wayland.config.resolved
  local config = { ---@diagnostic disable-line:redefined-local
    default = config.default,
    groups = config.groups or {},
  }
  if include_default then
    config.default = config.default or M.default_opts.config.default
  end

  if include_default then
    for name, group in pairs(M.default_opts.config.groups) do
      if not config.groups[name] then
        config.groups[name] = group
      end
    end
  end

  local opts_default = opts.default
  if include_default and type(opts_default) == "nil" then
    opts_default = M.default_opts.default
  end

  local default = opts_default
  if type(default) == "boolean" then
    if default then
      default = config.default
    else
      default = nil
    end
  end

  local base_url = opts.base_url
  if include_default and not base_url then
    base_url = M.default_opts.base_url
  end
  base_url = base_url or "https://wayland.app/protocols/"

  ---@type telescope-wayland.opts.resolved
  local resolved = {
    dir = dir,
    default = opts_default,
    config = config,
    base_url = base_url,
  }
  return resolved, default
end

---@param opts telescope-wayland.opts
---@param group_name (integer | string)?
---@return (integer | string)[]
function M.resolve_sources(opts, group_name)
  local opts, default = M.resolve_opts(opts) ---@diagnostic disable-line:redefined-local
  group_name = group_name or default
  local group = opts.config and opts.config.groups and opts.config.groups[group_name]
  if not group then
    return {}
  end

  if not group.sources then
    group.sources = {}
    for k, file_name in pairs(group) do
      if type(k) == "number" then
        if string.sub(file_name, 1, 1) ~= "/" then
          file_name = vim.fs.joinpath(opts.dir, file_name)
        end
        local bufnr = vim.fn.bufadd(file_name)
        vim.fn.bufload(bufnr)
        group.sources[#group.sources + 1] = bufnr
      end
    end
  end

  return group.sources
end

---@param paths string[]
function M.find_protocols(paths)
  return vim
    .iter(paths)
    :map(function(path)
      return vim.fs.find(function(name)
        return name:match(".*%.xml$")
      end, {
        type = "file",
        path = path,
        limit = math.huge,
      })
    end)
    :flatten(1)
    :totable()
end

---@param opts telescope-wayland.opts
function M.ui(opts)
  local opts, default = M.resolve_opts(opts) ---@diagnostic disable-line:redefined-local

  ---@cast opts telescope-wayland.opts
  if default then
    require("telescope-wayland.pickers.protocol").picker(opts, default)
  else
    require("telescope-wayland.pickers.group").picker(opts)
  end
end

---@param opts telescope-wayland.opts
function M.setup(opts)
  M.default_opts = M.resolve_opts(opts)
end

return M
