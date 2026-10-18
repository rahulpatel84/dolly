import fs from "node:fs";
import path from "node:path";
import { DOCS } from "./docs-list";
export { DOCS } from "./docs-list";
export type { DocPage } from "./docs-list";

export function readDoc(slug: string): string {
  return fs.readFileSync(path.join(process.cwd(), "content", "docs", `${slug}.md`), "utf8");
}
export function neighbours(slug: string) {
  const i = DOCS.findIndex((d) => d.slug === slug);
  return { prev: i > 0 ? DOCS[i - 1] : null, next: i < DOCS.length - 1 ? DOCS[i + 1] : null };
}
