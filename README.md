# grails.nvim

Grails support for Neovim: a tree-sitter grammar for GSP (Groovy Server Pages) and an in-process language server, written in Lua, for Grails navigation.

The server needs no JDK, nothing to install and no build. It applies Grails' naming conventions to the syntax tree and answers only what it recognises, so it runs next to a Groovy server (`groovyls`) and their results merge.

Status: stage 1. GSP highlighting and go to definition for views, templates, layouts, assets, controllers and actions. Completion, hover and GORM finders are not implemented yet.

## Requirements

- Neovim 0.11.3 or later.
- A Grails 3 or later project: Gradle layout, with `grails-app/` in each module.
- The `groovy` and `html` tree-sitter parsers. The server reads Groovy files with the `groovy` parser, and GSP pages inject `html` and `groovy`.
- To build the `gsp` parser: [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) (`main` branch), or the `tree-sitter` CLI and a C compiler.

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
    vim.lsp.enable 'grails'
  end,
},
```

The plugin ships `lsp/grails.lua`, so `vim.lsp.enable 'grails'` is all the server needs. It attaches to `gsp` and `groovy` buffers inside a Grails project and to nothing else.

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

### Go to definition

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
| `:GrailsReindex` | Drop the cached project index. It is also dropped when a file under `grails-app/` is saved. |

## Known limits

- **No type inference.** The server works on syntax and naming conventions. Members of an instance (`book.save()`, `book.author`), dynamic finders, and Grails methods such as `render` and `params` are neither completed nor resolved.
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
