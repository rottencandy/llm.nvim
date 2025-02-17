local http = require("plenary.curl").request

local M = {}
local CF_MODEL_ID = "@hf/thebloke/deepseek-coder-6.7b-base-awq"
local API_URL = "https://api.cloudflare.com/client/v4/accounts/" .. CF_ACC_ID .. "/ai/run/" .. CF_MODEL_ID

-- use api to get suggestion
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
					content = "You are an AI programming assistant."
						.. "Complete any given snippet with valid ".. filetype .. " code."
						.. "Ensure the code always adheres to best practices."
						.. "Avoid line numbers in code blocks."
						.. "Avoid wrapping the whole response in triple backticks."
						.. "The **INDENTATION FORMAT** of the code remains exactly the **SAME** as the original code."
						.. "Output the code in a **SINGLE** code block, being careful to only return relevant code.",
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
		return nil, "Status " .. response.status .. ": " .. response.body
	end
end

-- split string by newlines
local split = function(str)
	local out = {}
	for line in str:gmatch("([^\n]*)\n?") do
		table.insert(out, line)
	end
	return out
end

function M.complete(line_start, line_end)
	-- indexing is 0 based
	local prompt = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)
	local suggestion, err = get_completion(table.concat(prompt), vim.bo.filetype)
	if suggestion then
		--vim.api.nvim_buf_set_extmark(0)
		vim.api.nvim_buf_set_lines(0, line_start, line_end, false, split(suggestion))
	else
		vim.notify("Got Err: " .. (err or "<nil>"), vim.log.levels.ERROR)
	end
end

function M.setup()
	vim.api.nvim_create_user_command("LLMComplete", function(opts)
		M.complete(opts.line1, opts.line2)
	end, { nargs = 0, range = true })
end

return M
