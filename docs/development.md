# Development

```sh
# grammar (inside tree-sitter-gsp/)
tree-sitter generate          # commit the regenerated src/
tree-sitter test -p .

# plugin
stylua --check .
nvim --headless -u tests/minimal_init.lua -l tests/run.lua
```

The test run builds the `gsp` parser from the checkout and needs the `groovy` and `html` parsers under `stdpath('data')/site/parser/`. Install them with nvim-treesitter (`:TSInstall groovy html`), or build them into a scratch directory and point `XDG_DATA_HOME` at it, as CI does (`.github/workflows/ci.yml`).
