local http = require("plenary.curl").request
local api = vim.api
-- weird nvim lua deprecation issue
-- https://github.com/hrsh7th/nvim-cmp/issues/1017
local unpack = unpack or table.unpack

local CF_MODEL_ID = "@hf/thebloke/deepseek-coder-6.7b-base-awq"
local API_URL = "https://api.cloudflare.com/client/v4/accounts/" .. CF_ACC_ID .. "/ai/run/" .. CF_MODEL_ID
local ns_id = api.nvim_create_namespace("llm_suggestions")

local M = {}

---Use api to get suggestion
---@param prompt string
---@param filetype string
---@return string?
---@return string?
local get_completion = function(prompt, filetype)
    local response = http({
        url = API_URL,
        method = "post",
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. CF_TOKEN,
        },
        body = vim.fn.json_encode({
            --raw = true,
            stream = false,
            max_tokens = 256,
            temperature = 0.1,
            messages = {
                {
                    role = "system",
                    -- stylua: ignore
					content = "You are an AI programming assistant.\n"
						.. "Complete any given snippet with valid " .. filetype .. " code.\n"
						.. "Ensure the code always adheres to best practices.\n"
						.. "Avoid line numbers in code blocks.\n"
						.. "Avoid wrapping the whole response in triple backticks.\n"
						.. "The **INDENTATION FORMAT** of the code remains exactly the **SAME** as the original code.\n"
						.. "Output the code in a **SINGLE** code block, being careful to only return relevant code.\n",
                },
                {
                    role = "user",
                    content = prompt,
                },
            },
        }),
    })
    if response.status == 200 then
        local data = vim.fn.json_decode(response.body)
        return data.result.response
    else
        return nil, "(http " .. response.status .. ") " .. response.body
    end
end

---split string by newlines
---@param str string
---@return string[]
local split = function(str)
    local out = {}
    for line in str:gmatch("([^\n]*)\n?") do
        table.insert(out, line)
    end
    return out
end

---strip trailing newlines from string
---@param str string
---@return string
local strip = function(str)
    return str:match("^(.*[^%s])")
end

---apply lines to buffer
---@param buf integer
---@param line_pos integer
---@param lines string[]
local apply_lines = function(buf, line_pos, lines)
    -- set first line separately,
    -- because nvim_buf_set_lines does not allow appending to existing lines
    api.nvim_buf_set_text(buf, line_pos, -1, line_pos, -1, { lines[1] })
    if #lines > 1 then
        api.nvim_buf_set_lines(buf, line_pos, line_pos, false, { unpack(lines, 2) })
    end
end

---add virtual text to current buffer and allow applying it using a confirmation prompt
---@param line_pos integer line to add text to, 0-indexed. first line will be appended to any existing text on line
---@param text string string of text to apply, will be split by newlines and applied to multiple lines
local add_virtual_text = function(line_pos, text)
    local lines = split(text)
    -- holds 2nd to last lines
    -- first line will be passed as `virt_text`
    local virt_lines = {}
    if #lines > 1 then
        for i = 2, #lines do
            virt_lines[i - 1] = { { lines[i], "Comment" } }
        end
    end
    api.nvim_buf_clear_namespace(api.nvim_get_current_buf(), ns_id, line_pos, line_pos)
    local extmark_id = api.nvim_buf_set_extmark(api.nvim_get_current_buf(), ns_id, line_pos, -1, {
        virt_text_pos = "inline",
        virt_text = {
            -- use the "Comment" highlight group for now
            { lines[1], "Comment" },
        },
        virt_lines = virt_lines,
    })

    vim.ui.input(
        { prompt = "Accept? (y/n): " },
        ---@param input string
        function(input)
            if input == "y" or input == "Y" then
                apply_lines(api.nvim_get_current_buf(), line_pos, lines)
            end
        end
    )
    api.nvim_buf_del_extmark(api.nvim_get_current_buf(), ns_id, extmark_id)
end

---prepare temporary buffer to display suggestion
---@param contents string
---@param target_pos integer
---@param target_buf integer
local prepare_temp_buf = function(contents, target_pos, target_buf)
    local buf = api.nvim_create_buf(false, true)
    local lines = split(strip(contents))
    api.nvim_buf_set_name(buf, "llm://test")
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    api.nvim_set_option_value("filetype", "txt", { buf = buf })
    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    api.nvim_win_set_buf(win, buf)

    api.nvim_buf_create_user_command(buf, "LLMApply", function()
        apply_lines(target_buf, target_pos, lines)
    end, { nargs = 0 })
end

---@param line_start integer
---@param line_end integer
function M.suggest(line_start, line_end)
    -- line indexing needs to be 0 based
    local prompt = api.nvim_buf_get_lines(api.nvim_get_current_buf(), line_start - 1, line_end, false)
    local suggestion, err = get_completion(table.concat(prompt, "\n"), vim.bo.filetype)
    if err then
        vim.notify("Error: " .. (err or "<nil>"), vim.log.levels.ERROR)
        return
    end
    if not suggestion then
        vim.notify("Error: Call succeeded but reply was empty", vim.log.levels.ERROR)
        return
    end

    local line_pos = line_end - 1
    prepare_temp_buf(suggestion, line_pos, api.nvim_get_current_buf())
end

function M.setup()
    api.nvim_create_user_command("LLMComplete", function(opts)
        M.suggest(opts.line1, opts.line2)
    end, { nargs = 0, range = true })
end

return M
