local M = {}
local sequence = 0
local STATE_PATH = os.getenv("HOME") .. "/Library/Rime/pi-ime-window.state"
local REQUEST_PATH = os.getenv("HOME") .. "/Library/Rime/pi-ime-window.request"

local function read_state()
  local state = { current = "prompt", active = "0" }
  local file = io.open(STATE_PATH, "r")
  if not file then return state end
  for line in file:lines() do
    local key, value = line:match("^(%w+)=(.*)$")
    if key then state[key] = value end
  end
  file:close()
  return state
end

local function write_state(state)
  local file = io.open(STATE_PATH, "w")
  if not file then return end
  for _, key in ipairs({ "current", "active", "prompt", "browse", "comment" }) do
    if state[key] ~= nil then file:write(key .. "=" .. tostring(state[key]) .. "\n") end
  end
  file:close()
end

local function ascii_flag(ctx)
  return ctx:get_option("ascii_mode") and "1" or "0"
end

local function apply_request(ctx)
  local file = io.open(REQUEST_PATH, "r")
  if not file then return false end
  local line = file:read("*l") or ""
  file:close()
  os.remove(REQUEST_PATH)
  local name = line:match("^(%w+)")
  if name ~= "prompt" and name ~= "browse" and name ~= "comment" then return false end
  local state = read_state()
  local cur = state.current or "prompt"
  if cur == "prompt" or cur == "browse" or cur == "comment" then state[cur] = ascii_flag(ctx) end
  if state[name] == nil then
    state[name] = name == "comment" and "0" or (name == "browse" and "1" or ascii_flag(ctx))
  end
  state.current = name
  state.active = name == "prompt" and "0" or "1"
  write_state(state)
  if ctx:is_composing() then ctx:clear() end
  ctx:set_option("ascii_mode", state[name] == "1")
  return true
end

local function remember_live(ctx)
  local state = read_state()
  if state.active ~= "1" then return end
  local cur = state.current
  if cur ~= "browse" and cur ~= "comment" then return end
  state[cur] = ascii_flag(ctx)
  write_state(state)
end

local function record(env, kind, candidate)
  local ascii = false
  pcall(function() ascii = env.engine.context:get_option("ascii_mode") == true end)
  local file = io.open(env.route_log, "a")
  if not file then return end
  file:write(string.format(
    "[DEBUG-input-route] time=%d session=%d kind=%s events=%d updates=%d commits=%d candidate=%s ascii=%s\n",
    os.time(), env.route_session, kind, env.route_events, env.route_updates,
    env.route_commits, tostring(candidate == true), tostring(ascii)))
  file:close()
end

local function observe(env, kind, candidate)
  pcall(record, env, kind, candidate)
end

function M.init(env)
  sequence = sequence + 1
  env.route_session = sequence
  env.route_events, env.route_updates, env.route_commits = 0, 0, 0
  env.route_log = env.engine.schema.config:get_string("input_route_probe/log_path")
  local context = env.engine.context
  env.route_update = context.update_notifier:connect(function(ctx)
    env.route_updates = env.route_updates + 1
    local ok, candidate = pcall(function() return ctx:get_selected_candidate() ~= nil end)
    observe(env, "update", ok and candidate)
  end)
  env.route_commit = context.commit_notifier:connect(function()
    env.route_commits = env.route_commits + 1
    observe(env, "commit", false)
  end)
  observe(env, "init", false)
end

function M.func(key, env)
  env.route_events = env.route_events + 1
  observe(env, "key", false)
  local ok, repr = pcall(function() return key:repr() end)
  local ctx = env.engine.context
  if ok and (repr == "F18" or repr == "Release+F18") then
    if repr == "F18" then apply_request(ctx) end
    return 1
  end
  if apply_request(ctx) then
    -- 焦点已经换到另一个逻辑窗口；当前按键按那个窗口记住的中英文处理。
  end
  if ok and repr == "F19" then
    -- Match Caps Lock commit_code: dump raw preedit as English, then toggle.
    if ctx:is_composing() then
      local input = ctx.input
      if input and #input > 0 then
        env.engine:commit_text(input)
      end
      ctx:clear()
    end
    ctx:set_option("ascii_mode", not ctx:get_option("ascii_mode"))
    remember_live(ctx)
    return 1 -- kAccepted
  end
  if ok and repr == "Release+F19" then return 1 end
  return 2 -- kNoop: preserve the existing processor chain.
end

function M.fini(env)
  if env.route_update then env.route_update:disconnect() end
  if env.route_commit then env.route_commit:disconnect() end
  observe(env, "fini", false)
end

return M
