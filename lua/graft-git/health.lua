local M = {}

function M.check()
	local health = vim.health

	health.start("graft-git.nvim")

	-- Check if graft can be required
	local has_graft, _ = pcall(require, "graft")
	if has_graft then
		health.ok("graft.nvim is installed")
	else
		health.error("graft.nvim is not installed")
	end

	-- Check if git is installed
	local git_exec = vim.fn.executable("git")
	if git_exec == 1 then
		health.ok("git is installed")
	else
		health.error("git is not installed")
	end

	-- Check if config directory is in git
	local config_path = vim.fn.stdpath("config")
	local is_git_repo = vim.fn.system("git -C " .. vim.fn.shellescape(config_path) .. " rev-parse --is-inside-work-tree")

	if vim.v.shell_error == 0 then
		health.ok("neovim config is in a git repository")
	else
		health.error("neovim config is not in a git repository")
	end
end

return M
