local api = vim.api

local entry_display = require("telescope.pickers.entry_display")
local finders = require("telescope.finders")
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
		},
	})

	local type_highlight = opts.symbol_highlights or M.treesitter_type_highlight

	local make_display = function(entry)
		---@type [string,string][]
		local columns = {}

		if entry.protocol then
			columns[#columns + 1] = { entry.protocol, type_highlight["protocol"] }
		end

		if entry.interface then
			columns[#columns][1] = columns[#columns][1] .. "::"
			columns[#columns + 1] = { entry.interface, type_highlight["interface"] }
		end

		if entry.name then
			columns[#columns][1] = columns[#columns][1] .. "."
			columns[#columns + 1] = { entry.name .. "()", type_highlight[entry.kind] }
		end

		return displayer(columns)
	end

	return function(entry)
		local start_row, start_col, end_row, _ = unpack(entry.range)

		---@type string
		local ordinal = entry.kind .. ":"
		if entry.protocol then
			ordinal = ordinal .. entry.protocol
		end

		if entry.interface then
			ordinal = ordinal .. "::" .. entry.interface
		end

		if entry.name then
			ordinal = ordinal .. "." .. entry.name .. "()"
		end

		return make_entry.set_default_entry_mt({
			protocol = entry.protocol,
			interface = entry.interface,
			name = entry.name,

			kind = entry.kind,
			ordinal = ordinal,

			display = make_display,
			filename = entry.filename,
			-- need to add one since the previewer substacts one
			lnum = start_row + 1,
			col = start_col,
			start = start_row,
			finish = end_row,
		}, opts)
	end
end

---@param source integer|string bufnr string
---@param filename string?
---@param results table?
function M.collect_results(source, filename, results)
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

	results = results or {}

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

	vim.iter(pairs(query.captures))
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
		local kind = metadata.kind --[[@as string ]]

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

		---@type string, Range4
		local name, range
		if kind == "protocol" then
			protocol, range = get_node_text(captures.protocol_name_val)
			interface = nil
		elseif kind == "interface" then
			interface, range = get_node_text(captures.interface_name_val)
		elseif kind == "request" then
			name, range = get_node_text(captures.request_name_val)
		elseif kind == "event" then
			name, range = get_node_text(captures.event_name_val)
		elseif kind == "enum" then
			name, range = get_node_text(captures.enum_name_val)
		else
			error("invalid match")
		end

		table.insert(results, {
			protocol = protocol,
			interface = interface,
			name = name,
			kind = kind,
			filename = filename,
			range = range,
		})
	end

	if vim.tbl_isempty(results) then
		return
	end

	return results
end

function M.picker(opts)
	opts.sources = opts.sources or { vim.api.nvim_get_current_buf() }

	local results = {}
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
		M.collect_results(source, filename, results)
	end

	return pickers
		.new(opts, {
			prompt_title = "Wayland protocol",
			finder = finders.new_table({
				results = results,
				entry_maker = opts.entry_maker or M.gen_entry(opts),
			}),
			previewer = conf.grep_previewer(opts),
			sorter = conf.generic_sorter(opts),
			push_cursor_on_edit = true,
			attach_mappings = function(_, map)
				if opts.groups then
					map("n", "<C-l>", function()
						require("telescope-wayland.pickers.group").picker(opts)
					end)
				end

				return true
			end,
		})
		:find()
end

return M
