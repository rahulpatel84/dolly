import type { Metadata } from "next";
import { notFound } from "next/navigation";
import DocBody from "@/components/DocBody";
import { DOCS } from "@/lib/docs";

export function generateStaticParams() { return DOCS.map((d) => ({ slug: d.slug })); }
export async function generateMetadata({ params }: { params: Promise<{ slug: string }> }): Promise<Metadata> {
  const { slug } = await params; const d = DOCS.find((x) => x.slug === slug);
  return d ? { title: d.title, description: d.description } : {};
}
export default async function DocPage({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!DOCS.some((d) => d.slug === slug)) notFound();
  return <DocBody slug={slug} />;
}
