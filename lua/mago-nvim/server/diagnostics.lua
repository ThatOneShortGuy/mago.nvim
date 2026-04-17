local M = {}

local severity_map = {
  Error = vim.diagnostic.severity.ERROR,
  Warning = vim.diagnostic.severity.WARN,
  Help = vim.diagnostic.severity.HINT,
  Note = vim.diagnostic.severity.INFO,
}

local checkers = {
  {
    name = 'lint',
    check_async = function(filepath, callback)
      require('mago-nvim.run.lint').check_async(filepath, callback)
    end,
  },
  {
    name = 'analyze',
    check_async = function(filepath, callback)
      require('mago-nvim.run.analyze').check_async(filepath, callback)
    end,
  },
  {
    name = 'guard',
    check_async = function(filepath, callback)
      require('mago-nvim.run.guard').check_async(filepath, callback)
    end,
  },
}

local publish_ticks = {}

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
  local pending = #checkers

  if pending == 0 then
    dispatchers.notification('textDocument/publishDiagnostics', {
      uri = uri,
      diagnostics = diagnostics,
    })
    return
  end

  for _, checker in ipairs(checkers) do
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

return M
