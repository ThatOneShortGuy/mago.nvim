local M = {}

local severity_map = {
  Error = vim.diagnostic.severity.ERROR,
  Warning = vim.diagnostic.severity.WARN,
  Help = vim.diagnostic.severity.HINT,
  Note = vim.diagnostic.severity.INFO,
}

local default_checker_names = { 'lint', 'analyze', 'guard' }
local checker_registry = {
  lint = {
    name = 'lint',
    check_async = function(filepath, callback)
      require('mago-nvim.run.lint').check_async(filepath, callback)
    end,
  },
  analyze = {
    name = 'analyze',
    check_async = function(filepath, callback)
      require('mago-nvim.run.analyze').check_async(filepath, callback)
    end,
  },
  guard = {
    name = 'guard',
    check_async = function(filepath, callback)
      require('mago-nvim.run.guard').check_async(filepath, callback)
    end,
  },
}
local active_checkers = {}

local publish_ticks = {}

local function build_checkers(checker_names)
  local result = {}
  local seen = {}

  for _, checker_name in ipairs(checker_names) do
    local checker = checker_registry[checker_name]
    if checker ~= nil and not seen[checker_name] then
      seen[checker_name] = true
      table.insert(result, checker)
    end
  end

  return result
end

local function normalize_checker_names(opts)
  local diagnostics_opts = opts and opts.diagnostics or {}
  local configured = diagnostics_opts.checkers

  if configured == nil then
    return vim.deepcopy(default_checker_names)
  end

  if type(configured) == 'string' then
    return { configured }
  end

  if vim.islist(configured) then
    local names = {}
    for _, checker_name in ipairs(configured) do
      if type(checker_name) == 'string' then
        table.insert(names, checker_name)
      end
    end
    return names
  end

  if type(configured) == 'table' then
    local names = {}
    for _, checker_name in ipairs(default_checker_names) do
      if configured[checker_name] == true then
        table.insert(names, checker_name)
      end
    end
    return names
  end

  return vim.deepcopy(default_checker_names)
end

local function get_range_from_span(span, bufnr)
  local start_line = span.start.line
  local end_line = span['end'].line
  local start_character = span.start.offset - vim.api.nvim_buf_get_offset(bufnr, start_line)
  local end_character = span['end'].offset - vim.api.nvim_buf_get_offset(bufnr, end_line)

  return {
    ['start'] = { line = start_line, character = start_character },
    ['end'] = { line = end_line, character = end_character },
  }
end

local function convert_issue_to_diagnostic(issue, bufnr, source)
  local span = issue.annotations[1].span

  return {
    range = get_range_from_span(span, bufnr),
    severity = severity_map[issue.level],
    message = string.format('[%s] %s', issue.code, issue.message),
    codeDescription = issue.code,
    source = 'mago.nvim',
    data = { source = source },
  }
end

local function get_diagnostics_from_mago_issues(issues, bufnr, source)
  local diagnostics = vim.tbl_map(function(issue)
    return convert_issue_to_diagnostic(issue, bufnr, source)
  end, issues or {})
  return diagnostics
end

function M.publish(uri, dispatchers)
  publish_ticks[uri] = (publish_ticks[uri] or 0) + 1
  local tick = publish_ticks[uri]
  local filepath = vim.uri_to_fname(uri)
  local bufnr = vim.uri_to_bufnr(uri)

  if filepath == nil or filepath == '' then
    return
  end

  local diagnostics = {}
  local pending = #active_checkers

  if pending == 0 then
    dispatchers.notification('textDocument/publishDiagnostics', {
      uri = uri,
      diagnostics = diagnostics,
    })
    return
  end

  for _, checker in ipairs(active_checkers) do
    checker.check_async(filepath, function(issues)
      if publish_ticks[uri] ~= tick then
        return
      end

      local checker_diagnostics = get_diagnostics_from_mago_issues(issues, bufnr, checker.name)
      vim.list_extend(diagnostics, checker_diagnostics)
      pending = pending - 1

      if pending > 0 then
        return
      end

      dispatchers.notification('textDocument/publishDiagnostics', {
        uri = uri,
        diagnostics = diagnostics,
      })
    end)
  end
end

function M.setup(opts)
  local checker_names = normalize_checker_names(opts)
  active_checkers = build_checkers(checker_names)
end

M.setup(nil)

return M
