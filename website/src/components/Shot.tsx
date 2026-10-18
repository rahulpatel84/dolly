/** A real product screenshot in a restrained frame. Width/height keep layout stable. */
export default function Shot({ src, alt, w, h, caption, className = "" }: { src: string; alt: string; w: number; h: number; caption?: string; className?: string }) {
  return (
    <figure className={className}>
      <div className="shot"><img src={src} alt={alt} width={w} height={h} loading="lazy" decoding="async" /></div>
      {caption && <figcaption className="mt-2.5 text-[13px] text-fg-3">{caption}</figcaption>}
    </figure>
  );
}
