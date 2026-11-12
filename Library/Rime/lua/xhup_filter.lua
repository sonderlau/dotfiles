-- Xiaohé double-pinyin candidate narrowing with an optional shape-code suffix.
-- Example: an`f queries the xhup table for anf and keeps candidates for 按.

local f = {}

local function escape_pattern(text)
    return text:gsub("([%%%^%$%(%)%%.%[%]%*%+%-%?])", "%%%1")
end

local function first_char(text)
    local second = utf8.offset(text, 2)
    if second then return text:sub(1, second - 1) end
    return text
end

local function cover_input(candidate, end_pos)
    -- Make the candidate span the whole "syllable`shape" input so the shape
    -- code is consumed on commit instead of being left behind.
    if candidate._end >= end_pos then return candidate end
    local extended = Candidate(candidate.type, candidate.start, end_pos, candidate.text, candidate.comment)
    extended.quality = candidate.quality
    extended.preedit = candidate.preedit
    return extended
end

local function tags_match(seg, tags)
    for _, tag in ipairs(tags) do
        if seg:has_tag(tag) then return true end
    end
    return false
end

function f.init(env)
    local config = env.engine.schema.config
    local lookup_schema = config:get_string("xhup_filter/lookup_schema") or "xhup_lookup"
    local search_key = config:get_string("xhup_filter/search_key") or "`"
    local configured_tags = config:get_list("xhup_filter/tags")

    env.lookup = Memory(env.engine, Schema(lookup_schema))
    env.search_key = escape_pattern(search_key)
    env.search_limit = config:get_int("xhup_filter/search_limit") or 512
    env.show_other_candidates = config:get_bool("xhup_filter/show_other_candidates")
    env.tags = { "abc" }

    if configured_tags and configured_tags.size > 0 then
        env.tags = {}
        for index = 0, configured_tags.size - 1 do
            table.insert(env.tags, configured_tags:get_value_at(index).value)
        end
    end
end

function f.func(input, env)
    local context = env.engine.context
    local base_code, shape_code = context.input:match("^([a-z]+)" .. env.search_key .. "([a-z]+)$")

    -- One Xiaohé syllable plus one or two shape keys is the supported form.
    if not base_code or #base_code > 2 or #shape_code > 2 then
        for candidate in input:iter() do yield(candidate) end
        return
    end

    local matched_chars = {}
    if env.lookup:dict_lookup(base_code .. shape_code, true, env.search_limit) then
        for entry in env.lookup:iter_dict() do
            if entry.text and utf8.len(entry.text) == 1 then
                matched_chars[entry.text] = true
            end
        end
    end

    local end_pos = #context.input
    local long_candidates = {}
    local other_candidates = {}
    local single_char_first = context:get_option("search_single_char")

    for candidate in input:iter() do
        if candidate.type ~= "sentence" then
            local text = candidate.text
            if matched_chars[first_char(text)] then
                local covered = cover_input(candidate, end_pos)
                if single_char_first and utf8.len(text) > 1 then
                    table.insert(long_candidates, covered)
                else
                    yield(covered)
                end
            elseif env.show_other_candidates then
                table.insert(other_candidates, candidate)
            end
        end
    end

    for _, candidate in ipairs(long_candidates) do yield(candidate) end
    for _, candidate in ipairs(other_candidates) do yield(candidate) end
end

function f.tags_match(seg, env)
    return tags_match(seg, env.tags)
end

function f.fini(env)
    if env.lookup and env.lookup.disconnect then env.lookup:disconnect() end
    env.lookup = nil
end

return f
