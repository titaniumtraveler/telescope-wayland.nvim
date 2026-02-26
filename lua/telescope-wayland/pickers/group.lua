local M = {}

local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values

function M.picker(opts)
	return pickers
		.new(opts, {
			prompt_title = "Wayland Protocol Group",
			finder = finders.new_table({
				results = vim.iter(pairs(opts.config.groups))
					:map(function(key)
						return key
					end)
					:totable(),
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(prompt_bufnr)
				action_set.select:replace(function(_, _) ---@diagnostic disable-line:undefined-field
					local name = action_state.get_selected_entry()[1]
					actions.close(prompt_bufnr)

					opts.sources = require("telescope-wayland").resolve_sources(opts.config, name)
					require("telescope-wayland.pickers.protocol").picker(opts)
				end)
				return true
			end,
		})
		:find()
end

return M
