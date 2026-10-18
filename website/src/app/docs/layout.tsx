import SiteHeader from "@/components/SiteHeader";
import SiteFooter from "@/components/SiteFooter";
import DocsSidebar from "@/components/DocsSidebar";

export default function DocsLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <SiteHeader active="Docs" />
      <div className="mx-auto grid max-w-[1200px] gap-10 px-5 py-10 lg:grid-cols-[220px_minmax(0,1fr)]">
        <DocsSidebar />
        <div className="min-w-0">{children}</div>
      </div>
      <SiteFooter />
    </>
  );
}
