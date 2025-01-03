---@class graft.Git.Sync
---@field install_plugins? boolean Install missing plugins (default: true)
---@field update_plugins? boolean Update all plugin submodules (default: false)
---@field remove_plugins? boolean Remove plugins which are no longer defined (default: false)

---@class graft.Git
local M = {}

-- Get the graft instance
local graft = require("graft")

-- Update status in neovim without user input
---@param msg string
local function show_status(msg)
	vim.cmd.redraw()
	vim.cmd.echo("'" .. msg .. "'")
end

---@param spec graft.Spec
---@return boolean
M.is_installed = function(spec)
	local ok, _ = pcall(require, spec.name)
	if ok then
		return true
	end

	if vim.fn.isdirectory(M.full_pack_dir(spec)) == 1 then
		return true
	end

	return false
end

---@param spec graft.Spec
---@return string
M.full_pack_dir = function(spec) return M.root_dir() .. "/" .. M.pack_dir(spec) end

---@param spec graft.Spec
---@return string
M.pack_dir = function(spec) return "pack/graft/" .. spec.type .. "/" .. spec.dir end

---@param spec graft.Spec
---@return string
M.git_url = function(spec) return "https://github.com/" .. spec.repo end

---@return string
M.root_dir = function()
	---@diagnostic disable-next-line: return-type-mismatch
	return vim.fn.stdpath("config")
end

---@param spec graft.Spec
---@return boolean
M.add_submodule = function(spec)
	show_status("Adding " .. spec.repo .. "...")

	local cmd = { "git", "-C", M.root_dir(), "submodule", "add", "-f", M.git_url(spec), M.pack_dir(spec) }

	local success, output = M.run_git(cmd)

	if not success then
		vim.notify("Failed to add submodule: " .. output, vim.log.levels.ERROR)
		show_status("Adding " .. spec.repo .. " [failed]")
		return false
	else
		show_status("Adding " .. spec.repo .. " [ok]")
	end

	if spec.tag then
		M.checkout_tag(spec)
	elseif spec.branch then
		M.checkout_branch(spec)
	end

	return success
end

---@param spec graft.Spec
---@return boolean
M.checkout_branch = function(spec)
	if not spec.branch then
		return true
	end

	-- set submodule to follow branch
	M.run_git({
		"git",
		"-C",
		M.root_dir(),
		"config",
		"-f",
		".gitmodules",
		"submodule." .. M.pack_dir(spec) .. ".branch",
		spec.branch,
	})

	M.update_plugin(spec)

	return true
end

-- Update a plugin
---@param spec graft.Spec
---@return boolean
M.update_plugin = function(spec)
	-- update the submodule
	local checkout_cmd = { "git", "-C", M.root_dir(), "submodule", "update", "--remote", M.pack_dir(spec) }
	local success, output = M.run_git(checkout_cmd)
	if not success then
		vim.print("Unable to update repo " .. spec.repo .. ": " .. output)
		return false
	end

	return true
end

-- Set the submodule to follow a tag
---@param spec graft.Spec
---@return boolean
M.checkout_tag = function(spec)
	if not spec.tag then
		return true
	end

	local checkout_cmd = { "git", "-C", M.full_pack_dir(spec), "checkout", spec.tag }
	local success, output = M.run_git(checkout_cmd)
	if not success then
		vim.print("Error checking out tag " .. spec.tag .. " for repo " .. spec.repo .. ": " .. output)
		return false
	end

	return true
end

-- Run a git command and return a type of result and output
---@param cmd table
---@return boolean, string
M.run_git = function(cmd)
	local output = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0

	return success, output
end

---@param spec graft.Spec
---@return boolean
M.remove_submodule = function(spec)
	show_status("Removing " .. spec.dir .. "...")

	local cmds = {
		{ "git", "-C", M.root_dir(), "submodule", "deinit", "-f", M.pack_dir(spec) },
		{ "git", "-C", M.root_dir(), "rm", "-f", M.pack_dir(spec) },
	}

	for _, cmd in ipairs(cmds) do
		local success, output = M.run_git(cmd)
		if not success then
			vim.notify("Failed to remove submodule: " .. output, vim.log.levels.ERROR)
			return false
		end
	end

	show_status("Removing " .. spec.dir .. " [ok]")

	return true
end

-- Find all directories in pack/graft
---@param type string The type of pack to find (start or opt)
---@return table<string, table>
M.find_in_pack_dir = function(type)
	local pack_dir = M.root_dir() .. "/pack/graft/" .. type

	local plugins_by_dir = {}

	if vim.fn.isdirectory(pack_dir) == 1 then
		---@diagnostic disable-next-line: undefined-field
		local handle = vim.loop.fs_scandir(pack_dir)
		if handle then
			while true do
				---@diagnostic disable-next-line: undefined-field
				local name, ftype = vim.loop.fs_scandir_next(handle)
				if not name then
					break
				end
				if ftype == "directory" then
					plugins_by_dir[type .. ":" .. name] = { name = name, type = type }
				end
			end
		end
	end

	return plugins_by_dir
end

---@param plugins graft.Plugin
---@param opts? graft.Git.Sync
M.sync = function(plugins, opts)
	---@type graft.Git.Sync
	local defaults = {
		install_plugins = true,
		update_plugins = false,
		remove_plugins = false,
	}

	opts = vim.tbl_deep_extend("force", defaults, opts or {})

	local desired = {}

	if opts.remove_plugins then
		for _, plugin in pairs(plugins) do
			if plugin.dir ~= "" then
				desired[plugin.type .. ":" .. plugin.dir] = true
			end
		end
	end

	if opts.remove_plugins then
		local installed_start = M.find_in_pack_dir("start")
		local installed_opt = M.find_in_pack_dir("opt")

		local installed = vim.tbl_extend("force", installed_start, installed_opt)

		-- Remove plugins that aren't in the plugin_list
		for installed_name, installed_data in pairs(installed) do
			if not desired[installed_name] then
				show_status("Removing " .. installed_data.name .. "...")
				M.remove_submodule({ dir = installed_data.name, type = installed_data.type })
			end
		end
	end

	-- Install missing plugins
	for _, spec in pairs(plugins) do
		if opts.install_plugins and not M.is_installed(spec) then
			show_status("Installing " .. spec.repo .. "...")
			M.add_submodule(spec)
		elseif opts.update_plugins then
			show_status("Updating " .. spec.repo .. "...")
			if spec.tag then
				M.checkout_tag(spec)
			elseif spec.branch then
				M.checkout_branch(spec)
			else
				M.update_plugin(spec)
			end
		end
	end

	show_status("Graft sync complete.")
end

---Setup graft-git
---@param opts? graft.Git.Sync Configuration options
M.setup = function(opts)
	-- Register our hooks with graft
	graft.register("tlj/graft-git.nvim", { type = "start" })
	graft.register_hook("post_register", function(plugins) M.sync(plugins, opts) end)

	vim.api.nvim_create_user_command(
		"GraftInstall",
		function() M.sync(graft.plugins, { install_plugins = true, remove_plugins = false, update_plugins = false }) end,
		{}
	)
	vim.api.nvim_create_user_command(
		"GraftRemove",
		function() M.sync(graft.plugins, { install_plugins = false, remove_plugins = true, update_plugins = false }) end,
		{}
	)
	vim.api.nvim_create_user_command(
		"GraftUpdate",
		function() M.sync(graft.plugins, { install_plugins = false, remove_plugins = false, update_plugins = true }) end,
		{}
	)
	vim.api.nvim_create_user_command(
		"GraftSync",
		function() M.sync(graft.plugins, { install_plugins = true, remove_plugins = true, update_plugins = true }) end,
		{}
	)
end

return M
