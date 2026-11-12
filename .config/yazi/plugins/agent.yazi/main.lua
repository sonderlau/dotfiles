--- @since 25.5.31

local AGENTS = {
	{ on = "1", desc = "π pi", cmd = "pi" },
	{ on = "2", desc = "󰚩 claude", cmd = "claude" },
	{ on = "3", desc = " codex", cmd = "codex" },
	{ on = "4", desc = " opencode", cmd = "opencode" },
	{ on = "5", desc = " gemini", cmd = "gemini" },
}

local function entry()
	local cands = {}
	for _, agent in ipairs(AGENTS) do
		cands[#cands + 1] = { on = agent.on, desc = agent.desc }
	end

	local idx = ya.which { cands = cands }
	if not idx then
		return
	end

	-- shell runs in the active pane's directory and blocks until the agent exits
	ya.emit("shell", { AGENTS[idx].cmd, block = true, confirm = true })
end

return { entry = entry }
