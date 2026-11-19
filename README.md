# grails.nvim

Grails support for Neovim: a tree-sitter grammar for GSP (Groovy Server Pages), the client for [grails-language-server](https://github.com/vdassios/grails-language-server), and a small Lua server for Grails navigation that needs no JDK.

<!-- Demo GIF: docs/media/ (phase 21b). -->

## Features

- **GSP grammar**: highlights, folds and injections, HTML in the page text and Groovy in `${ }`, scriptlets and attribute values. [More](docs/grammar.md)
- **grails-language-server client** (`grails_ls`): Groovy and GSP diagnostics, completion, hover, definition and signature help with the project's own Groovy and Grails, GORM, and Grails conventions. `:GrailsInstallServer` downloads it.
- **Lua navigation server** (`grails`): go to definition for views, templates, layouts, assets, controllers and actions, the moment a file opens and with no JDK. See [why two servers](#two-language-servers). [More](docs/lua-server.md)
- **`:GrailsAlternate`**: from a controller action to its view and back, and between artefacts of the same name.
- **Default keymaps** for the commands, only in Grails buffers, never over a key that is already mapped. See [Keymaps](#keymaps).

## Requirements

- Neovim 0.11.3 or later.
- A Grails 3 or later project: Gradle layout, with `grails-app/` in each module.
- The `groovy` and `html` tree-sitter parsers. The server reads Groovy files with the `groovy` parser, and GSP pages inject `html` and `groovy`.
- To build the `gsp` parser: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (`main` branch), or the `tree-sitter` CLI and a C compiler ([without nvim-treesitter](docs/grammar.md#without-nvim-treesitter)).
- For `grails_ls`: `curl` (for `:GrailsInstallServer`) and the project's JDK, Java 11 or later (see "Configuration").

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'nvim-treesitter/nvim-treesitter',
  branch = 'main',
  -- grails.nvim registers the `gsp` parser with nvim-treesitter, so it must
  -- load first.
  dependencies = { 'vdassios/grails.nvim' },
  build = ':TSUpdate',
  config = function()
    require('nvim-treesitter').install { 'gsp', 'groovy', 'html' }
  end,
},
{
  'vdassios/grails.nvim',
  lazy = false,
  config = function()
    vim.lsp.enable { 'grails', 'grails_ls' }
  end,
},
```

`vim.lsp.enable { 'grails', 'grails_ls' }` turns on both language servers that come with the plugin; you need no other LSP setup. To use only one, enable only that name. Before you use `grails_ls` for the first time, run `:GrailsInstallServer` to download it.

nvim-treesitter's `main` branch does not start highlighting by itself. If your config does not already do this, start it for GSP:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'gsp',
  callback = function()
    vim.treesitter.start()
  end,
})
```

## Two language servers

grails.nvim comes with two language servers. They do different jobs, and they work best together.

- **`grails_ls`** is [grails-language-server](https://github.com/vdassios/grails-language-server), the full server. It compiles your code with the project's own Groovy and Grails, so it knows types, GORM and the methods Grails adds: errors, completion, hover, go to definition. The cost: it needs the project's JDK and a download, and it runs the project's Gradle build, so it takes a few seconds to get ready (longer the first time, while Gradle resolves the project). Enable it only for projects you trust.
- **`grails`** is a small server written in Lua that runs inside Neovim. It does one thing: go to definition for the names Grails looks up by convention, such as `render(view: 'show')`, `<g:render template="row"/>`, layouts, assets, and controller and action names. It works the moment a file opens, needs no JDK or download, and never runs project code.

With both enabled, `grails` answers go to definition until `grails_ls` is ready, and wherever `grails_ls` cannot run: without a suitable JDK, when the Gradle build fails, or when you have not enabled it. Once `grails_ls` is ready in a buffer, `grails` stops answering there, so go to definition never gives two results. `grails` attaches only to Groovy and GSP files inside a Grails project, `grails_ls` to those inside a Gradle build.

If you also use [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) and it has a `grails_ls` config, the two don't clash: grails.nvim's settings are applied on top of nvim-lspconfig's, and your own `vim.lsp.config('grails_ls', { ... })` is applied on top of both.

## Commands

| Command | Default key | Does |
|---|---|---|
| `:GrailsAlternate` | `<localleader>Ga` | From a controller action, open its view. From a view, go to the matching action. From a domain class, controller or service, cycle to the artefact of the same name. |
| `:GrailsReindex` | `<localleader>Gi` | Drop the Lua server's cached project index. It is also dropped when a file under `grails-app/` is saved. |
| `:GrailsInstallServer` | `<localleader>GI` | Download the jar of the newest grails-language-server release, pre-releases included, to `stdpath('data')/grails.nvim/`. Does nothing when that release is installed; `:GrailsInstallServer!` downloads it again. A running client keeps the old jar until it restarts. |
| `:GrailsReloadProject` | `<localleader>Gr` | `grails_ls` resolves the Gradle project again, ignoring its cache. Run it after a dependency change. |
| `:GrailsDownloadSources` | `<localleader>Gs` | `grails_ls` fetches the sources jars the project's libraries lack, with the project's Gradle, so definition and hover reach library code. Reports how many libraries have sources now. |

### Keymaps

The default keys are set only in Groovy and GSP buffers inside a Grails project, as buffer-local mappings. They start with `<localleader>`, which is `\` unless you set `vim.g.maplocalleader`; Neovim maps nothing under it. A default is not set when its key is already mapped (by you or by another plugin), so grails.nvim never replaces a mapping.

Each command also has a `<Plug>` mapping: `<Plug>(grails-alternate)`, `<Plug>(grails-reindex)`, `<Plug>(grails-install-server)`, `<Plug>(grails-reload-project)` and `<Plug>(grails-download-sources)`. Map your own key to one, and grails.nvim skips the default key for that command:

```lua
vim.keymap.set('n', '<leader>a', '<Plug>(grails-alternate)', { desc = 'Grails: alternate file' })
```

To turn off all default keys, set this before you open a file:

```lua
vim.g.grails_default_mappings = false
```

## Configuration

`after/lsp/grails_ls.lua` starts the server jar on `gsp` and `groovy` buffers of a Gradle build: the root is the nearest directory with `settings.gradle`, `settings.gradle.kts` or `gradlew`. It does not start, and says why once, while the jar or `java` is missing.

**Trust.** The server runs the project's Gradle build scripts and its AST transformations, so it executes project code. The config sends `initializationOptions.trusted = true`: enable `grails_ls` only for projects you trust.

**JDK.** The server must run on the project's JDK (the one its Gradle build uses): it compiles with the project's Groovy, which reads the JDK's class files with its bundled ASM, so Groovy 2.5 (Grails 4) needs JDK 15 or older. The server's docs have [the table](https://github.com/vdassios/grails-language-server/blob/main/docs/editors.md#install). `grails_ls` runs `$JAVA_HOME/bin/java`, else `java` from `PATH`; start Neovim with the project's `JAVA_HOME` (SDKMAN's `sdkman_auto_env` sets it from `.sdkmanrc` on `cd`), or set the path:

```lua
vim.g.grails_ls = {
  java = '/path/to/jdk-11/bin/java', -- default: $JAVA_HOME/bin/java, else java
  jar = '/path/to/grails-language-server-all.jar', -- default: the one :GrailsInstallServer downloads
}
```

Both are read each time the server starts. To change anything else, such as JVM flags, override the whole command: `vim.lsp.config('grails_ls', { cmd = { 'java', '-Xmx2g', '-jar', require('grails.ls').jar() } })`.

**Status.** The server reports `resolving`, `indexing`, `ready` and `failed`. The client turns them into LSP progress, so `vim.lsp.status()` and progress plugins show them, and notifies a failure with its reason.

## Documentation

- [GSP grammar](docs/grammar.md): what it highlights and injects, building it without nvim-treesitter, known limits, the public code it was checked against
- [Lua navigation server](docs/lua-server.md): what go to definition reaches, known limits
- [Development](docs/development.md): grammar and plugin tests
- [grails-language-server](https://github.com/vdassios/grails-language-server): features, editors, how it works

## License

Apache-2.0. The GSP token set and the resolution rules follow the [Apache Grails IntelliJ plugin](https://github.com/apache/grails-intellij-plugin); see `NOTICE`.
