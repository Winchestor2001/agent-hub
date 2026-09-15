import type { Banner } from "../api/banners";
import { useI18n } from "../i18n/context";

export function Banners({ banners }: { banners: Banner[] }) {
  const { message } = useI18n();
  if (banners.length === 0) return null;
  return (
    <div className="banners" role="status" aria-live="polite">
      {banners.map((banner) => (
        <div key={banner.id} className={`banner banner-${banner.severity}`}>
          <span>{message(banner.message)}</span>
          {banner.message.detail && <code className="banner-detail">{banner.message.detail}</code>}
        </div>
      ))}
    </div>
  );
}
