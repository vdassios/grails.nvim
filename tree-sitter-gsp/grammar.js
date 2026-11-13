/**
 * @file GSP (Groovy Server Pages) grammar for tree-sitter
 * @license Apache-2.0
 *
 * The token set follows the GSP lexer of the IntelliJ Grails plugin
 * (apache/grails-intellij-plugin, lang/gsp/lexer/core/gsp.flex).
 *
 * The tree is flat: GSP constructs (`${}`, `<% %>`, `%{ }%`, comments,
 * directives and namespaced tags such as `<g:link>`) are nodes, and everything
 * else is `content`, meant to be injected as one combined HTML document.
 * GSP constructs are recognised anywhere, including inside HTML attribute
 * values and `<script>`/`<style>` bodies. Tags are not paired.
 */

/// <reference types="tree-sitter-cli/dsl" />
// @ts-check

// Groovy string literals inside `${ }`, so a `}` in a string does not end the expression.
const DQ_STRING = String.raw`"([^"\\\n]|\\.)*"`;
const SQ_STRING = String.raw`'([^'\\\n]|\\.)*'`;
const CODE_ATOM = String.raw`[^{}"']|${DQ_STRING}|${SQ_STRING}`;

/**
 * Balanced `{ }` nested up to `depth + 1` levels deep.
 *
 * @param {number} depth
 * @returns {string}
 */
function braces(depth) {
  const inner = depth === 0 ? CODE_ATOM : `${CODE_ATOM}|${braces(depth - 1)}`;
  return String.raw`\{(${inner})*\}`;
}

// Body of `${ }`: balanced braces (three levels), strings skipped.
const EXPRESSION_CODE = new RegExp(`(${CODE_ATOM}|${braces(2)})+`);
// Bodies that run up to a two-character terminator.
const JSP_CODE = /([^%]|%+[^%>])+/; // up to %>
const GSCRIPT_CODE = /([^}]|\}+[^}%])+/; // up to }%
const GDECLARATION_CODE = /([^}]|\}+[^}!])+/; // up to }!
const GDIRECTIVE_BODY_END = '}';
// `=` between an attribute name and its value; GSP allows whitespace around it.
const EQUALS = /\s*=\s*/;

const JSP_COMMENT = /<%--([^-]|-[^-]|--+[^-%]|--+%[^>-])*-*--%>/;
const GSP_COMMENT = /%\{--([^-]|-[^-]|--+[^-}]|--+\}[^%-])*-*--\}%/;

export default grammar({
  name: 'gsp',

  extras: _ => [],

  rules: {
    document: $ => repeat($._node),

    _node: $ =>
      choice(
        $.content,
        $.expression,
        $.scriptlet,
        $.output_scriptlet,
        $.declaration,
        $.directive,
        $.comment,
        $.gsp_tag_open,
        $.gsp_tag_close,
        $.gsp_tag_self_closing,
      ),

    // Template text (HTML, CSS, JavaScript). Split into small tokens so that
    // the start of every GSP construct ends it; the tokens are hidden.
    content: _ =>
      prec.right(
        repeat1(
          choice(
            /[^<$%!@\\]+/,
            // An HTML tag name: not a GSP tag, because no colon follows it.
            /<\/?[a-zA-Z][a-zA-Z0-9_-]*[^a-zA-Z0-9_:<$%!@\\-]/,
            /<[^a-zA-Z\/%<$]/,
            /<\/[^a-zA-Z%<$]/,
            '$',
            '%',
            '!',
            '@',
            '\\',
            '\\$', // `\${` is literal text
          ),
        ),
      ),

    expression: $ => seq('${', optional(alias(EXPRESSION_CODE, $.code)), '}'),

    scriptlet: $ =>
      choice(seq('<%', optional(alias(JSP_CODE, $.code)), '%>'), seq('%{', optional(alias(GSCRIPT_CODE, $.code)), '}%')),

    output_scriptlet: $ => seq('<%=', optional(alias(JSP_CODE, $.code)), '%>'),

    declaration: $ =>
      choice(seq('<%!', optional(alias(JSP_CODE, $.code)), '%>'), seq('!{', optional(alias(GDECLARATION_CODE, $.code)), '}!')),

    directive: $ => choice(seq('<%@', $._directive_body, '%>'), seq('@{', $._directive_body, GDIRECTIVE_BODY_END)),

    // Grails reads a page directive as `name="value"` pairs, so the leading
    // name (`page`) is optional: `<%@ defaultCodec="HTML" %>`.
    _directive_body: $ =>
      seq(
        optional($._ws),
        choice(field('name', $.directive_name), alias($._directive_first_attribute, $.attribute)),
        repeat(seq($._ws, $.attribute)),
        optional($._ws),
      ),

    _directive_first_attribute: $ =>
      seq(field('name', alias($.directive_name, $.attribute_name)), alias(EQUALS, '='), field('value', $.attribute_value)),

    directive_name: _ => /[a-zA-Z]+/,

    comment: _ => token(choice(JSP_COMMENT, GSP_COMMENT)),

    gsp_tag_open: $ => seq($._gsp_tag_head, '>'),

    gsp_tag_self_closing: $ => seq($._gsp_tag_head, '/>'),

    _gsp_tag_head: $ => seq('<', $._gsp_tag_name, repeat(seq($._ws, $.attribute)), optional($._ws)),

    gsp_tag_close: $ => seq('</', $._gsp_tag_name, optional($._ws), '>'),

    _gsp_tag_name: $ => seq(field('namespace', $.namespace), ':', field('name', $.tag_name)),

    namespace: _ => /[a-zA-Z][a-zA-Z0-9_]*/,

    // `/` separates path segments in `<tmpl:/path/name/>`; a trailing `/` belongs to `/>`.
    tag_name: _ => /\/?[a-zA-Z0-9_-]+(\/[a-zA-Z0-9_-]+)*/,

    // `=` is one token with its surrounding whitespace (`test ="${x}"`), so the
    // lexer's longest match tells it apart from the whitespace between attributes.
    attribute: $ => seq(field('name', $.attribute_name), optional(seq(alias(EQUALS, '='), field('value', $.attribute_value)))),

    attribute_name: _ => /[^\s'"=:$<>\/\\]+/,

    attribute_value: $ =>
      choice(
        seq('"', optional(choice(alias($._map_dq, $.groovy_value), repeat1(choice($.expression, alias($._text_dq, $.text))))), '"'),
        seq("'", optional(choice(alias($._map_sq, $.groovy_value), repeat1(choice($.expression, alias($._text_sq, $.text))))), "'"),
      ),

    // A whole value of the form `[...]` is a Groovy map or list.
    _map_dq: _ => token(prec(1, /\[[^"]*\]/)),
    _map_sq: _ => token(prec(1, /\[[^']*\]/)),

    _text_dq: _ => prec.right(repeat1(choice(/[^"$\\]+/, '$', '\\', '\\$'))),
    _text_sq: _ => prec.right(repeat1(choice(/[^'$\\]+/, '$', '\\', '\\$'))),

    _ws: _ => /\s+/,
  },
});
