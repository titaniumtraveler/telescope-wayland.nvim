local M = {}

---@class telescope-wayland.config
---@field groups table<string | integer,telescope-wayland.config.group>
---@field default (string | integer)?

---@class telescope-wayland.config.group: string[]
---@field sources (string | integer)[]

---@class telescope-wayland.opts
---@field dir string?
---@field default (boolean | integer | string)?
---@field config (string | telescope-wayland.config | fun(config_path: string): telescope-wayland.config)?

---@param dir string
function M.config_path(dir)
	return vim.fs.joinpath(dir, "wayland-protocols/protocols.lua")
end

---@param opts telescope-wayland.opts
---@return telescope-wayland.config
function M.resolve_config(opts)
	opts = opts or {}

	local resolved = nil
	local dir = opts.dir or vim.fn.getcwd(-1, -1)

	local config = opts.config
	local config_path = nil

	if not config then
		config_path = M.config_path(dir)
	elseif type(config) == "table" then
		resolved = config
	elseif type(config) == "string" then
		config_path = vim.fs.joinpath(dir, config)
	elseif type(config) == "function" then
		resolved = config(M.config_path(dir))
	end

	if not resolved and config_path then
		---@type telescope-wayland.config
		resolved = assert(loadfile(config_path))()
	end

	if not resolved then
		error("failed to resolve config")
	end

	return resolved
end

---@param config telescope-wayland.config
---@param group_name string?
---@return (integer | string)[]
function M.resolve_sources(config, group_name)
	local group = config.groups[group_name]

	if not group.sources then
		group.sources = {}
		for k, file_name in pairs(group) do
			if type(k) == "number" then
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
	return vim.iter(paths)
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
	local config = M.resolve_config(opts)

	local default = opts.default
	if default == true then
		default = config.default or "default"
	end

	---@cast default string?

	if default then
		require("telescope-wayland.pickers.protocol").picker({
			config = config,
			sources = M.resolve_sources(config, default),
		})
	else
		require("telescope-wayland.pickers.group").picker({ config = config })
	end
end

return M
