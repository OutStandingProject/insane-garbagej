import useData from "@/hooks/useData";
import { useTranslation } from "react-i18next";

const Ranks = () => {
  const { Ranks } = useData();
  const { t } = useTranslation();

  const RanksComponent = () => {
    return Ranks.map((v, i) => (
      <div
        key={i}
        className="grid items-center h-14 border-b border-white/5 hover:bg-white/[0.04] transition-colors"
        style={{ gridTemplateColumns: "56px 1fr 52px 110px" }}
      >
        {/* Rank number */}
        <div className="flex items-center justify-center">
          <span className="text-sm font-bold text-[#F5C842]">#{i + 1}</span>
        </div>

        {/* Player info */}
        <div className="flex items-center gap-2.5 px-3 min-w-0">
          <div className="w-8 h-8 rounded-md overflow-hidden bg-white/10 flex-shrink-0">
            {v.mugshot && v.mugshot.length > 0 ? (
              <img
                src={`nui://insane-garbagej/ui/build/headshots/${v.mugshot}`}
                alt="profile"
                className="w-full h-full object-cover"
                onError={(e) => {
                  (e.currentTarget as HTMLImageElement).src = `images/profiles/${v.photo ?? 7}.png`;
                }}
              />
            ) : (
              <img
                src={`images/profiles/${v.photo ?? 7}.png`}
                alt="profile"
                className="w-full h-full object-cover"
              />
            )}
          </div>
          <span className="text-sm font-semibold text-white whitespace-nowrap overflow-hidden text-ellipsis">
            {v.characterName || "—"}
          </span>
        </div>

        {/* Level badge */}
        <div className="flex items-center justify-center">
          <div className="w-8 h-8 rounded-md flex items-center justify-center bg-[#7A5C1E]/80">
            <span className="text-sm font-bold text-[#F5C842]">{v.level}</span>
          </div>
        </div>

        {/* Exp badge */}
        <div className="flex items-center justify-center px-1">
          <div className="h-8 px-3 rounded-md flex items-center justify-center bg-[#F5C842]/10 border border-[#F5C842]/40">
            <span className="text-sm font-semibold text-[#F5C842]">{v.exp} XP</span>
          </div>
        </div>
      </div>
    ));
  };

  return (
    <div
      className="flex flex-col h-full overflow-hidden rounded-lg"
      style={{ background: "rgba(255,255,255,0.04)" }}
    >
      {/* Column header */}
      <div
        className="grid flex-shrink-0 py-2 text-xs border-b border-white/10"
        style={{
          gridTemplateColumns: "56px 1fr 52px 110px",
          background: "rgba(255,255,255,0.06)",
        }}
      >
        <span className="text-white/40 text-center">Rank</span>
        <span className="text-white/40 pl-3">{t("name")}</span>
        <span className="text-white/40 text-center">{t("level")}</span>
        <span className="text-white/40 text-center">{t("rep")}</span>
      </div>

      {/* Rank rows */}
      <div className="w-full h-full overflow-y-auto scrollbar-hide flex flex-col">
        <RanksComponent />
      </div>
    </div>
  );
};

export { Ranks };
