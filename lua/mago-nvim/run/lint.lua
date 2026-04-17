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
  local output = mago().run { 'lint', '--reporting-format', 'json', filepath }
  return decode_issues(output)
end

function M.check_async(filepath, callback)
  mago().run_async({ 'lint', '--reporting-format', 'json', filepath }, nil, function(output)
    callback(decode_issues(output))
  end)
end

function M.explain(rule)
  --
  return mago().run { 'lint', '--explain', rule }
end

function M.fix(filepath, rule)
  local cmd = { 'lint', '--fix', filepath, '--format-after-fix' }

  if rule ~= nil then
    table.insert(cmd, '--only')
    table.insert(cmd, rule)
  end

  return mago().run(cmd)
end

function M.list_files()
  return mago().run { 'list-files', '--command', 'linter' }
end

return M
