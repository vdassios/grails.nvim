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

## Against the real server

`tests/spec/integration_spec.lua` runs the plugin against a `grails-language-server` jar on the server repository's `fixtures/grails4` project: trust through `:GrailsTrust`, the status reaching `ready`, hover, `:GrailsReloadProject`, `:GrailsReindex`, and a prompt quit. Without `GRAILS_LS_JAR` and `GRAILS_LS_FIXTURE` it has no tests and prints a `skip` line, so the suite above runs without a jar.

```sh
# in a grails-language-server checkout
./gradlew shadowJar

# here; the server runs on $JAVA_HOME (else `java` on PATH), which must be a JDK 11 for the fixture's Gradle 6.9
GRAILS_LS_JAR=<server>/build/libs/grails-language-server-all.jar \
GRAILS_LS_FIXTURE=<server>/fixtures/grails4 \
JAVA_HOME=<JDK 11> \
nvim --headless -u tests/minimal_init.lua -l tests/run.lua integration_spec
```

The first run resolves the fixture with Gradle, which can download for minutes. The server keeps its cache in a temporary directory. CI's `integration` job builds the jar from the server's `main` and runs this spec on JDK 11.
