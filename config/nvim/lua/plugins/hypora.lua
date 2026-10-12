-- Hypora: keep Neovim's colorscheme in step with the active Hypora theme.
-- Installed to ~/.config/nvim/lua/plugins/hypora.lua on top of the LazyVim starter.
-- Edit anything else under ~/.config/nvim freely; the installer only writes this file.

-- Which Neovim colorscheme goes with which Hypora theme. LazyVim already includes
-- tokyonight and catppuccin; the rest are added below.
--
-- Osakajade is left out on purpose: no Neovim colorscheme matches it. It falls back to the
-- default below, which is a visible mismatch but an honest one.
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
