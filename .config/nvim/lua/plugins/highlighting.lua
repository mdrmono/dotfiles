-- Make Python keywords stand out more
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
        disable = {}, -- keep python enabled; avoids muted keywords when TS is off
      },
    },
  },
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "moon",
      on_highlights = function(hl, c)
        local keyword = { fg = c.magenta, bold = true }
        hl["@keyword"] = keyword
        hl["@keyword.import"] = keyword
        hl["@keyword.operator"] = { fg = c.red1, bold = true }
      end,
    },
  },
}
