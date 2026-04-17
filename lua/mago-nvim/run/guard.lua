local M = {}

local function mago()
  return require 'mago-nvim.executable'
end

local function decode_issues(output)
  if output == nil or output == '' then
    return {}
  end

  local ok, decoded = pcall(vim.json.decode, output)
  if not ok or type(decoded) ~= 'table' then
    return {}
  end

  return decoded.issues or {}
end

function M.check(filepath)
  local output = mago().run { 'guard', '--reporting-format', 'json', filepath }
  return decode_issues(output)
end

function M.check_async(filepath, callback)
  mago().run_async({ 'guard', '--reporting-format', 'json', filepath }, nil, function(output)
    callback(decode_issues(output))
  end)
end

function M.list_files()
  return mago().run { 'list-files', '--command', 'guard' }
end

return M
