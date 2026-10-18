import Link from "next/link";
import { DOCS, neighbours, readDoc } from "@/lib/docs";
import { headings, render } from "@/lib/markdown";

export default function DocBody({ slug }: { slug: string }) {
  const page = DOCS.find((d) => d.slug === slug)!;
  const md = readDoc(slug);
  const html = render(md);
  const toc = headings(md).filter((h) => h.level === 2);
  const { prev, next } = neighbours(slug);
  return (
    <div className="grid gap-10 xl:grid-cols-[minmax(0,1fr)_200px]">
      <article className="prose min-w-0">
        <div className="mb-2 text-[12.5px] font-medium uppercase tracking-[.08em] text-fg-3">{page.group}</div>
        <div dangerouslySetInnerHTML={{ __html: html }} />
        <nav className="mt-14 grid gap-3 border-t border-line pt-6 sm:grid-cols-2">
          {prev ? <Link href={`/docs/${prev.slug}`} className="rounded-xl border border-line p-4 hover:bg-surface" style={{ textDecoration: "none" }}><div className="text-[12px] text-fg-3">← Previous</div><div className="mt-1 font-medium text-fg">{prev.title}</div></Link> : <span />}
          {next && <Link href={`/docs/${next.slug}`} className="rounded-xl border border-line p-4 text-right hover:bg-surface" style={{ textDecoration: "none" }}><div className="text-[12px] text-fg-3">Next →</div><div className="mt-1 font-medium text-fg">{next.title}</div></Link>}
        </nav>
      </article>
      {toc.length > 1 && (
        <aside className="hidden xl:block">
          <div className="sticky top-24">
            <div className="mb-2 text-[11.5px] font-semibold uppercase tracking-[.08em] text-fg-3">On this page</div>
            <ul className="space-y-1.5 border-l border-line">
              {toc.map((h) => <li key={h.id}><a href={`#${h.id}`} className="-ml-px block border-l border-transparent pl-3.5 text-[13px] text-fg-2 hover:border-line-2 hover:text-fg">{h.text}</a></li>)}
            </ul>
          </div>
        </aside>
      )}
    </div>
  );
}
