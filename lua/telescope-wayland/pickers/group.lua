local M = {}

local action_set = require("telescope.actions.set")
local action_state = require("telescope.actions.state")
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values

---@param opts telescope-wayland.opts
function M.picker(opts)
	pickers
		.new(opts, {
			prompt_title = "Wayland Protocol Group",
			finder = finders.new_table({
				results = vim.iter(pairs(require("telescope-wayland").resolve_opts(opts).config.groups))
					:map(function(key)
						return key
					end)
					:totable(),
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(_)
				action_set.select:replace(function(_, _) ---@diagnostic disable-line:undefined-field
					local name = action_state.get_selected_entry()[1]
					require("telescope-wayland.pickers.protocol").picker(opts, name)
				end)
				return true
			end,
		})
		:find()
end

return M
