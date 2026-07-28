-- Indentation tweaks
return {
  -- Tree-sitter indentation for Python has edge cases around bracketed expressions
  -- (e.g. list comprehensions) that can produce incorrect autoindent. Prefer the
  -- built-in Vim `indent/python.vim` logic for Python buffers.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.indent = opts.indent or {}
      opts.indent.enable = true

      local disabled = opts.indent.disable
      if disabled == nil then
        opts.indent.disable = { "python" }
        return
      end

      if type(disabled) ~= "table" then
        opts.indent.disable = { "python" }
        return
      end

      if not vim.tbl_contains(disabled, "python") then
        table.insert(disabled, "python")
      end
    end,
  },
}
