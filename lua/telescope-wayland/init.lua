local M = {}

---@class telescope-wayland.config
---@field groups table<string | integer,telescope-wayland.config.group>
---@field default (string | integer)?

---@class telescope-wayland.config.group: string[]
---@field sources (string | integer)[]

---@class telescope-wayland.opts
---@field dir string?
---@field sources (string | integer)[]
---@field default (boolean | integer | string)?
---@field config (string | telescope-wayland.config | fun(config_path: string): telescope-wayland.config)?

---@param dir string
function M.config_path(dir)
	return vim.fs.joinpath(dir, "wayland-protocols/protocols.lua")
end

---@param opts telescope-wayland.opts
---@param path string?
---@return telescope-wayland.config
function M.load_config_from_path(opts, path)
	path = path or M.config_path(opts.dir or vim.fn.getcwd(-1, -1))

	return loadfile(path)()
end

---@param opts telescope-wayland.opts
---@return telescope-wayland.config
function M.resolve_config(opts)
	opts = opts or {}

	local dir = opts.dir or vim.fn.getcwd(-1, -1)

	local config = opts.config

	if type(config) == "table" then
		return config
	elseif type(config) == "function" then
		return config(M.config_path(dir))
	elseif not config or type(config) == "string" then
		return M.load_config_from_path(opts, config)
	end

	error("failed to resolve config")
end

---@param opts telescope-wayland.opts
---@param group_name string?
---@return (integer | string)[]
function M.resolve_sources(opts, group_name)
	local dir = opts.dir or vim.fn.getcwd(-1, -1)
	local group = M.resolve_config(opts).groups[group_name]

	if not group.sources then
		group.sources = {}
		for k, file_name in pairs(group) do
			if type(k) == "number" then
				if string.sub(file_name, 1, 1) ~= "/" then
					file_name = vim.fs.joinpath(dir, file_name)
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

	opts.config = config
	if default then
		require("telescope-wayland.pickers.protocol").picker(opts, default)
	else
		require("telescope-wayland.pickers.group").picker(opts)
	end
end

return M
