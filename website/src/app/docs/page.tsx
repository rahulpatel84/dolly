import type { Metadata } from "next";
import DocBody from "@/components/DocBody";
export const metadata: Metadata = { title: "Documentation", description: "Everything about installing and using Dolly." };
export default function DocsIndex() { return <DocBody slug="introduction" />; }
