-- Keep Neovim's colorscheme in step with the Hypora theme; only this file is installed, edit the rest freely.

-- Map Hypora themes to Neovim colorschemes; Osakajade is left out because none matches, so it falls back to the default.
local schemes = {
  Nord = "nord",
  TokyoNight = "tokyonight-night",
  CatppuccinMocha = "catppuccin-mocha",
  Gruvbox = "gruvbox",
  Kanagawa = "kanagawa-wave",
}

local function hypora_theme()
  local path = vim.fn.expand("~/.config/hypora/current/name")
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines[1] then
    return nil
  end
  return vim.trim(lines[1])
end

local scheme = schemes[hypora_theme() or ""] or "tokyonight-night"

return {
  { "shaunsingh/nord.nvim", lazy = true },
  { "ellisonleao/gruvbox.nvim", lazy = true },
  { "rebelot/kanagawa.nvim", lazy = true },

  -- LazyVim reads this to decide the colorscheme
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = scheme },
  },
}
