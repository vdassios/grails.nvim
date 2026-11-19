# grails.nvim

Grails support for Neovim:

- a tree-sitter grammar for GSP (Groovy Server Pages);
- the client for [grails-language-server](https://github.com/vdassios/grails-language-server) (`grails_ls`): Groovy and GSP diagnostics, completion, hover, definition and signature help with the project's own Groovy and Grails, GORM, and Grails conventions. `:GrailsInstallServer` downloads it;
- a small in-process language server written in Lua (`grails`) for Grails navigation, which needs no JDK, nothing to install and no build. It applies Grails' naming conventions to the syntax tree. Once `grails_ls` has the project ready in a buffer, the Lua server leaves definition to it there.

Status: GSP highlighting; `grails_ls` setup, install and commands; the Lua server's go to definition for views, templates, layouts, assets, controllers and actions.

## Requirements

- Neovim 0.11.3 or later.
- A Grails 3 or later project: Gradle layout, with `grails-app/` in each module.
- The `groovy` and `html` tree-sitter parsers. The server reads Groovy files with the `groovy` parser, and GSP pages inject `html` and `groovy`.
- To build the `gsp` parser: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (`main` branch), or the `tree-sitter` CLI and a C compiler.
- For `grails_ls`: `curl` (for `:GrailsInstallServer`) and the project's JDK, Java 11 or later (see "grails-language-server").

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

The plugin ships `lsp/grails.lua` and `lsp/grails_ls.lua`, so `vim.lsp.enable` is all the servers need. `grails` attaches to `gsp` and `groovy` buffers inside a Grails project and to nothing else. Enable either alone if you want only one. For `grails_ls`, run `:GrailsInstallServer` once.

nvim-treesitter's `main` branch does not start highlighting by itself. If your config does not already do this, start it for GSP:

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'gsp',
  callback = function()
    vim.treesitter.start()
  end,
})
```

### Without nvim-treesitter

Build the parser into a `parser/` directory on the runtimepath. The queries in `queries/gsp/` are already on it:

```sh
tree-sitter build -o ~/.local/share/nvim/site/parser/gsp.so /path/to/grails.nvim/tree-sitter-gsp
```

The `groovy` and `html` parsers are needed as well.

## Features

### GSP language

- Highlights, folds and injections: HTML in the page text, Groovy in `${ }`, `<% %>`, `%{ }%`, `<%= %>`, `<%! %>`, `!{ }!` and in `[...]` attribute values (`model="[book: book]"`).
- GSP is recognised everywhere, including inside HTML attribute values and `<script>` and `<style>` bodies.
- `commentstring` is `<%-- %s --%>`.
- `K` shows LSP hover when a server attached to the buffer answers it, and otherwise says there is none. It never falls back to `:Man`, so `K` on `<head>` does not open `man head`.

### grails-language-server

`lsp/grails_ls.lua` starts the server jar on `gsp` and `groovy` buffers of a Gradle build: the root is the nearest directory with `settings.gradle`, `settings.gradle.kts` or `gradlew`. It does not start, and says why once, while the jar or `java` is missing.

**Trust.** The server runs the project's Gradle build scripts and its AST transformations, so it executes project code. The config sends `initializationOptions.trusted = true`: enable `grails_ls` only for projects you trust.

**JDK.** The server must run on the project's JDK (the one its Gradle build uses): it compiles with the project's Groovy, which reads the JDK's class files with its bundled ASM, so Groovy 2.5 (Grails 4) needs JDK 15 or older. The server's README has the table. `grails_ls` runs `$JAVA_HOME/bin/java`, else `java` from `PATH`; start Neovim with the project's `JAVA_HOME` (SDKMAN's `sdkman_auto_env` sets it from `.sdkmanrc` on `cd`), or set the path:

```lua
vim.g.grails_ls = {
  java = '/path/to/jdk-11/bin/java', -- default: $JAVA_HOME/bin/java, else java
  jar = '/path/to/grails-language-server-all.jar', -- default: the one :GrailsInstallServer downloads
}
```

Both are read each time the server starts. To change anything else, such as JVM flags, override the whole command: `vim.lsp.config('grails_ls', { cmd = { 'java', '-Xmx2g', '-jar', require('grails.ls').jar() } })`.

**Status.** The server reports `resolving`, `indexing`, `ready` and `failed`. The client turns them into LSP progress, so `vim.lsp.status()` and progress plugins show them, and notifies a failure with its reason.

### Go to definition (Lua server)

| Under the cursor | Goes to |
|---|---|
| `<g:render template="...">`, `render(template: ...)`, `<tmpl:name/>` | `/a/b` opens `views/a/_b.gsp`. `b` opens `_b.gsp` beside the current view, or `views/<controller>/_b.gsp` from a controller. A `contextPath` attribute is a prefix. `<tmpl:/a/b/>` is `/a/b`. |
| `render(view: ...)`, `view` attribute of a `g:` tag (`g:include`) | `/a/b` opens `views/a/b.gsp`. `b` opens `views/<controller>/b.gsp`. `.gsp`, then `.jsp`, then `.gson`. |
| `<meta name="layout" content="x">`, `<g:applyLayout name="x">`, `static layout = 'x'` | `views/layouts/x.gsp` |
| `src` or `href` of `asset:stylesheet`, `asset:javascript`, `asset:image`, `asset:assetPath`, `asset:link` | The file under any `grails-app/assets/*/` directory. Without an exact match: `.css .scss .sass .less` for stylesheets, `.js .es6 .ts .coffee` for scripts. |
| `controller` attribute of a GSP tag; `controller:` of `redirect`, `chain`, `forward`, `createLink`, `g.link` | The controller class |
| `action` in the same places | The action in the named controller, or in the current one. In a view, that is the controller named after the view's directory. An action is a method that is not private, protected or static, or a property assigned a closure. |

Lookups search every module of a multi-module build, the current one first, because views and controllers often live in different modules. A target that does not exist, or a value computed with `${}` or a GString, gives no result.

### Commands

| Command | Does |
|---|---|
| `:GrailsAlternate` | From a controller action, open its view. From a view, go to the matching action. From a domain class, controller or service, cycle to the artefact of the same name. |
| `:GrailsReindex` | Drop the Lua server's cached project index. It is also dropped when a file under `grails-app/` is saved. |
| `:GrailsInstallServer` | Download the jar of the newest grails-language-server release, pre-releases included, to `stdpath('data')/grails.nvim/`. Does nothing when that release is installed; `:GrailsInstallServer!` downloads it again. A running client keeps the old jar until it restarts. |
| `:GrailsReloadProject` | `grails_ls` resolves the Gradle project again, ignoring its cache. Run it after a dependency change. |
| `:GrailsDownloadSources` | `grails_ls` fetches the sources jars the project's libraries lack, with the project's Gradle, so definition and hover reach library code. Reports how many libraries have sources now. |

## Known limits

These are the Lua server's; grails-language-server has its own list in its README.

- **No type inference.** The Lua server works on syntax and naming conventions. Members of an instance (`book.save()`, `book.author`), dynamic finders, and Grails methods such as `render` and `params` are neither completed nor resolved.
- **Workspace source only.** Views, templates, taglibs and members that come from Grails plugins (jars on the classpath) are unknown.
- **tree-sitter-groovy parse errors.** The `groovy` parser fails on parts of many real Grails files. It mostly recovers locally, but a file can become a single error node. When the cursor is inside one, the server falls back to reading `call(key: 'value')` or `call key: 'value'` from the cursor line.
- **GSP right after `<` or an HTML tag name.** `<${name}>`, `<option${attrs}>` and `<table<g:if ...>>` are parse errors. The page still highlights around them.
- **Nesting limits.** `${ }` balances braces eight levels deep, and `[...]` attribute values balance brackets four levels deep. Deeper code ends the construct early.
- **No `indents.scm` for GSP.** Indentation comes from the html injection.

The grammar has been checked against public Grails code:

| Source | Files | With errors |
|---|---|---|
| [openboxes](https://github.com/openboxes/openboxes) | 622 | 0 |
| [asgard](https://github.com/Netflix/asgard) | 146 | 0 |
| [collectory](https://github.com/AtlasOfLivingAustralia/collectory) | 145 | 0 |
| [apache/grails-core](https://github.com/apache/grails-core), every `.gsp` | 694 | 2: an unclosed `<%@` directive in the page itself, and `<table<g:if ...>>` (limit above) |
| Templates taken from grails-core's GSP tests | 585 | 4: `<${"title"}>` (limit above), and 3 the extraction cut off |

## Development

```sh
# grammar (inside tree-sitter-gsp/)
tree-sitter generate          # commit the regenerated src/
tree-sitter test -p .

# plugin
stylua --check .
nvim --headless -u tests/minimal_init.lua -l tests/run.lua
```

The test run builds the `gsp` parser from the checkout and needs the `groovy` and `html` parsers under `stdpath('data')/site/parser/`. Install them with nvim-treesitter (`:TSInstall groovy html`), or build them into a scratch directory and point `XDG_DATA_HOME` at it, as CI does (`.github/workflows/ci.yml`).

## License

Apache-2.0. The GSP token set and the resolution rules follow the [Apache Grails IntelliJ plugin](https://github.com/apache/grails-intellij-plugin); see `NOTICE`.
