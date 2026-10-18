// Small, dependency-free Markdown → HTML for our own docs. Supports headings,
// paragraphs, lists (incl. `.steps` ordered lists), tables, blockquotes, fenced
// code, images with captions, hr, bold/italic/code/links, <kbd> via ⌘-style text.
function esc(s: string) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
export function slug(t: string) { return t.toLowerCase().replace(/[`*_]/g, "").replace(/[^a-z0-9]+/g, "-").replace(/(^-|-$)/g, ""); }

function inline(s: string) {
  return esc(s)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>")
    .replace(/\[\[([^\]]+)\]\]/g, "<kbd>$1</kbd>")
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
    .replace(/&lt;(https?:\/\/[^&]+)&gt;/g, '<a href="$1">$1</a>');
}

export type Heading = { id: string; text: string; level: number };

export function headings(md: string): Heading[] {
  const out: Heading[] = [];
  let inCode = false;
  for (const l of md.split("\n")) {
    if (l.startsWith("```")) { inCode = !inCode; continue; }
    if (inCode) continue;
    const h = /^(#{2,3}) (.*)/.exec(l);
    if (h) out.push({ id: slug(h[2]), text: h[2].replace(/[`*]/g, ""), level: h[1].length });
  }
  return out;
}

export function render(md: string): string {
  const lines = md.split("\n");
  const out: string[] = [];
  let i = 0;
  const cells = (r: string) => r.replace(/^\||\|$/g, "").split("|").map((c) => c.trim());
  while (i < lines.length) {
    const l = lines[i];
    if (!l.trim()) { i++; continue; }
    if (l.startsWith("```")) {
      const lang = l.slice(3).trim(); const buf: string[] = []; i++;
      while (i < lines.length && !lines[i].startsWith("```")) buf.push(lines[i++]);
      i++; out.push(`<pre><code${lang ? ` class="language-${lang}"` : ""}>${esc(buf.join("\n"))}</code></pre>`); continue;
    }
    if (/^---+$/.test(l.trim())) { out.push("<hr/>"); i++; continue; }
    const h = /^(#{1,3}) (.*)/.exec(l);
    if (h) { const n = h[1].length; out.push(`<h${n} id="${slug(h[2])}">${inline(h[2])}</h${n}>`); i++; continue; }
    const img = /^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"([^"]+)")?\)/.exec(l);
    if (img) { out.push(`<figure><img src="${img[2]}" alt="${esc(img[1])}" loading="lazy" decoding="async"/>${img[3] ? `<figcaption>${inline(img[3])}</figcaption>` : ""}</figure>`); i++; continue; }
    if (l.startsWith("|")) {
      const rows: string[] = [];
      while (i < lines.length && lines[i].startsWith("|")) rows.push(lines[i++]);
      const head = cells(rows[0]); const body = rows.slice(2).map(cells);
      out.push("<table><thead><tr>" + head.map((c) => `<th>${inline(c)}</th>`).join("") + "</tr></thead><tbody>" +
        body.map((r) => "<tr>" + r.map((c) => `<td>${inline(c)}</td>`).join("") + "</tr>").join("") + "</tbody></table>"); continue;
    }
    if (l.startsWith(">")) {
      const q: string[] = [];
      while (i < lines.length && lines[i].startsWith(">")) q.push(lines[i++].replace(/^>\s?/, ""));
      out.push(`<blockquote><p>${inline(q.join(" "))}</p></blockquote>`); continue;
    }
    if (/^\d+\. /.test(l) || l === ":::steps") {
      const steps = l === ":::steps"; if (steps) i++;
      const items: string[] = [];
      while (i < lines.length && (/^\d+\. /.test(lines[i]) || (items.length && /^\s{2,}\S/.test(lines[i])) || (steps && lines[i] === ""))) {
        if (lines[i] === "") { i++; continue; }
        if (/^\d+\. /.test(lines[i])) items.push(lines[i].replace(/^\d+\. /, "")); else items[items.length - 1] += " " + lines[i].trim();
        i++;
      }
      if (steps && lines[i] === ":::") i++;
      out.push(`<ol${steps ? ' class="steps"' : ""}>` + items.map((t) => `<li>${inline(t)}</li>`).join("") + "</ol>"); continue;
    }
    if (/^- /.test(l)) {
      const items: string[] = [];
      while (i < lines.length && (/^- /.test(lines[i]) || (items.length && /^\s{2,}\S/.test(lines[i])))) {
        if (/^- /.test(lines[i])) items.push(lines[i].slice(2)); else items[items.length - 1] += " " + lines[i].trim();
        i++;
      }
      out.push("<ul>" + items.map((t) => `<li>${inline(t)}</li>`).join("") + "</ul>"); continue;
    }
    const p: string[] = [];
    while (i < lines.length && lines[i].trim() && !/^(#|\||>|- |\d+\. |---|```|!\[|:::)/.test(lines[i])) p.push(lines[i++]);
    const lead = p[0]?.startsWith("^ ");
    out.push(`<p${lead ? ' class="lead"' : ""}>${p.map((x) => inline(x.replace(/^\^ /, ""))).join(" ")}</p>`);
  }
  return out.join("\n");
}
