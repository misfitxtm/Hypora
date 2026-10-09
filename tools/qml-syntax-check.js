#!/usr/bin/env node
// Catch ?? mixed with || or && in QML bindings, using Node's own parser.
//
// Written after `savedPrimary || (a ?? b)?.name ?? ""` shipped and stopped the entire shell
// from loading. Mixing ?? with || or && in one expression is an ES2020 SyntaxError, not a
// precedence subtlety; QML reports it as "Left-hand side may not contain || or &&". A brace
// count cannot see it, and a hand-rolled scanner I tried first got it wrong — so this hands
// every candidate expression to the real parser and believes what it says.
const fs = require("fs");

// Blank comments and string bodies, preserving offsets and line breaks.
function strip(src) {
  const out = src.split("");
  const blank = (a, b) => { for (let k = a; k < b && k < out.length; k++) if (out[k] !== "\n") out[k] = " "; };
  let i = 0;
  while (i < src.length) {
    const c = src[i], n = src[i + 1];
    if (c === "/" && n === "/") { let j = src.indexOf("\n", i); if (j < 0) j = src.length; blank(i, j); i = j; }
    else if (c === "/" && n === "*") { let j = src.indexOf("*/", i + 2); j = j < 0 ? src.length : j + 2; blank(i, j); i = j; }
    else if (c === '"' || c === "'" || c === "`") {
      let j = i + 1;
      while (j < src.length && src[j] !== c) { if (src[j] === "\\") j++; j++; }
      blank(i + 1, Math.min(j, src.length)); i = Math.min(j + 1, src.length);
    } else i++;
  }
  return out.join("");
}

const balanced = t => {
  let d = 0;
  for (const c of t) { if ("([{".includes(c)) d++; else if (")]}".includes(c)) d--; }
  return d <= 0;
};

let problems = 0;
for (const path of process.argv.slice(2)) {
  const raw = fs.readFileSync(path, "utf8");
  const lines = strip(raw).split("\n");
  const rawLines = raw.split("\n");

  for (let i = 0; i < lines.length; i++) {
    // A binding: `name: expression`. Skip QML grouped properties (`anchors { ... }`) and
    // anything whose value opens an object/closure block rather than an expression.
    const m = /^\s*(?:readonly\s+)?(?:property\s+\S+\s+)?([A-Za-z_][\w.]*)\s*:\s*(.*)$/.exec(lines[i]);
    if (!m) continue;
    let expr = m[2].trim();
    if (expr.startsWith("{")) continue;   // grouped property or closure body, not an expression

    // Join continuation lines until the expression's brackets balance, so multi-line
    // bindings are checked as the single expression QML actually compiles.
    let j = i;
    // An empty value means the expression begins on the next line — which is exactly the
    // shape the original bug had, and exactly what an earlier version of this check skipped.
    while (j + 1 < lines.length
           && (expr === "" || !balanced(expr) || /(\?\?|\|\||&&|[+\-*/,.:?])$/.test(expr))) {
      j++;
      expr += "\n" + lines[j].trim();
      if (j - i > 25) break;
    }
    if (!/\?\?|\|\||&&/.test(expr)) continue;   // only expressions where this class can bite

    try {
      new Function(`return (${expr});`);
    } catch (e) {
      if (!(e instanceof SyntaxError)) continue;
      // Only the ??-mixing class is reported. Everything else this parser objects to is a
      // QML construct that is not a JS expression at all — `stdout: StdioCollector {}`,
      // `delegate: Item {}`, `onTriggered: if (...)`, two statements separated by `;` — and
      // a check that cries wolf nineteen times is a check nobody runs. Narrow and trusted
      // beats broad and ignored.
      if (!/\?\?/.test(e.message)) continue;
      console.log(`${path}:${i + 1}: ${e.message}`);
      console.log(`    ${rawLines[i].trim()}`);
      if (j > i) console.log(`    ${rawLines[j].trim()}`);
      problems++;
    }
  }
}
console.log(problems ? `\n${problems} problem(s) found` : "no ?? mixed with || or && in any QML binding");
process.exit(problems ? 1 : 0);
