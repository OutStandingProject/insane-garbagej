import Popup from "@/components/Popup";
import useData from "@/hooks/useData";
import { fetchNui } from "@/utils/fetchNui";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { FaCrown } from "react-icons/fa";
import classNames from "classnames";
import { Ranks, Tasks } from "./Partials";
import { IoMdHome } from "react-icons/io";
import { FaRankingStar } from "react-icons/fa6";
import { BsEnvelopeFill } from "react-icons/bs";
import { IoTrendingUp } from "react-icons/io5";

const Garbage: React.FC = () => {
  const { t } = useTranslation();
  const { userProfile, currentLobby } = useData();
  const [openedPopup, setOpenedPopup] = useState<
    "invite" | undefined
  >();
  const [popError, setPopError] = useState<string | undefined>(undefined);
  const [invitedTarget, setInvitedTarget] = useState<number>();
  const [activeTab, setActiveTab] = useState<"tasks" | "ranks">("tasks");

  const calcReputationWidth = () => {
    if (!userProfile || !userProfile.exp || !userProfile.nextLevelExp) return 0;
    return (userProfile.exp / userProfile.nextLevelExp) * 100;
  };

  const handleOpenInvitePopup = () => {
    setPopError(undefined);
    setOpenedPopup("invite");
  };

  const handleSendInvite = async () => {
    const response = await fetchNui("nui:sendInviteToPlayer", invitedTarget, {
      error: undefined,
    });
    setInvitedTarget(undefined);
    if (response.error) {
      setPopError(response.error);
    } else {
      setPopError(undefined);
      setOpenedPopup(undefined);
    }
  };

  /* ── Avatar helper: usa mugshot (headshot nativo do GTA) se disponível, senão fallback ── */
  const PlayerAvatar: React.FC<{ mugshot?: string; photo?: number; size?: string }> = ({
    mugshot,
    photo,
    size = "w-10 h-10",
  }) => {
    if (mugshot && mugshot.length > 0) {
      return (
        <img
          src={`nui://insane-garbagej/ui/build/headshots/${mugshot}`}
          alt="avatar"
          className={`${size} object-cover rounded-md`}
          onError={(e) => {
            (e.currentTarget as HTMLImageElement).src = `images/profiles/${photo ?? 7}.png`;
          }}
        />
      );
    }
    return (
      <img
        src={`images/profiles/${photo ?? 7}.png`}
        alt="avatar"
        className={`${size} object-cover rounded-md`}
      />
    );
  };

  /* ── Team invite slots ── */
  const InviteComponent: React.FC = () => {
    // Slot 0 é sempre o próprio player (mesmo sem lobby ativo)
    // Slots 1-3 são membros do lobby ou botões de convite
    const selfSlot = (
      <div key="self" className="relative w-10 h-10 bg-white/10 rounded-md overflow-hidden flex-shrink-0">
        <PlayerAvatar mugshot={userProfile.mugshot} photo={userProfile.photo} />
        {/* Crown se for líder ou não tiver lobby */}
        {(!currentLobby.id || currentLobby.leaderId === userProfile.source) && (
          <FaCrown className="absolute -top-1 -left-1 text-[#F5C842] z-10 w-3 h-3" />
        )}
      </div>
    );

    const memberSlots = Array(3)
      .fill(undefined)
      .map((_, i) => {
        // Quando há lobby, preencher com membros (excluindo o próprio jogador que já está no slot 0)
        const otherMembers = currentLobby.id
          ? (currentLobby.members || []).filter((m) => m.source !== userProfile.source)
          : [];
        const member = otherMembers[i];

        return (
          <div key={i} className="relative w-10 h-10 bg-white/10 rounded-md overflow-hidden flex-shrink-0">
            {member ? (
              <>
                <PlayerAvatar mugshot={member.mugshot} photo={member.photo} />
                {member.source === currentLobby.leaderId && (
                  <FaCrown className="absolute -top-1 -left-1 text-[#F5C842] z-10 w-3 h-3" />
                )}
              </>
            ) : (
              <button
                onClick={handleOpenInvitePopup}
                className="relative w-full h-full flex items-center justify-center group"
              >
                <BsEnvelopeFill className="w-4 h-4 text-white/30 group-hover:text-white/70 transition" />
              </button>
            )}
          </div>
        );
      });

    return (
      <div className="flex gap-1.5">
        {selfSlot}
        {memberSlots}
      </div>
    );
  };

  /* ── Left panel: profile image com mugshot real do GTA ── */
  const ProfileImage = () => (
    <div className="relative w-full h-44 overflow-hidden rounded-t-lg flex-shrink-0">
      {/* Background: mugshot do player ou imagem padrão */}
      {userProfile.mugshot && userProfile.mugshot.length > 0 ? (
        <img
          src={`nui://insane-garbagej/ui/build/headshots/${userProfile.mugshot}`}
          alt="player"
          className="w-full h-full object-cover grayscale"
          onError={(e) => {
            (e.currentTarget as HTMLImageElement).src = "images/app_delivery_bg.png";
          }}
        />
      ) : (
        <div
          className="w-full h-full bg-cover bg-center grayscale"
          style={{ backgroundImage: "url(images/app_delivery_bg.png)" }}
        />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent" />
      <div className="absolute bottom-3 left-3">
        <h1 className="text-sm font-bold text-white leading-tight">
          {userProfile.characterName || t("victor_goods")}
        </h1>
        <p className="text-xs text-white/50 font-medium">Sanitation Worker</p>
      </div>
    </div>
  );

  /* ── Reputation bar ── */
  const ReputationBar = () => (
    <div className="px-3 pt-2.5 pb-3 flex flex-col gap-2" style={{ background: "rgba(16,16,16,.55)" }}>
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-white/60">{t("reputation")}</span>
        <span className="text-xs font-semibold text-white/60">
          {(userProfile.exp ?? 0).toLocaleString()} / {(userProfile.nextLevelExp ?? 0).toLocaleString()} XP
        </span>
      </div>
      <div className="h-1.5 bg-white/10 rounded-full relative overflow-hidden">
        <div
          className="absolute h-full bg-white/80 rounded-full transition-all"
          style={{ width: `${calcReputationWidth()}%` }}
        />
      </div>
      <div>
        <span className="text-[11px] text-white/50 border border-white/20 rounded px-2 py-0.5">
          Level {userProfile.level}
        </span>
      </div>
    </div>
  );

  /* ── Garbage about info ── */
  const GarbageInfo = () => (
    <div
      className="p-3 rounded-lg flex flex-col gap-2.5 flex-1 min-h-0"
      style={{ background: "rgba(255,255,255,0.06)" }}
    >
      <div className="flex justify-between items-start">
        <div className="flex flex-col">
          <h1 className="font-semibold text-sm text-white">{t("garbage_about")}</h1>
          <p className="text-xs text-white/40">{userProfile.characterName || t("victor_goods")}</p>
        </div>
        <InviteComponent />
      </div>
      <p className="text-[11px] text-white/50 leading-relaxed line-clamp-4">
        {t("desc_garbage_about")}
      </p>
    </div>
  );

  /* ── Sparkline graph ── */
  const Graph = () => (
    <div
      className="rounded-lg overflow-hidden flex-shrink-0"
      style={{ background: "rgba(255,255,255,0.06)", minHeight: "80px" }}
    >
      <div className="w-full h-full relative">
        <div
          className="w-full h-full bg-center bg-cover"
          style={{ backgroundImage: "url(images/graph.png)", minHeight: "80px" }}
        />
        <div className="absolute top-2 right-3 flex items-center gap-1">
          <IoTrendingUp className="w-3 h-3 text-emerald-400" />
          <span className="text-[11px] font-semibold text-emerald-400">+24%</span>
        </div>
      </div>
    </div>
  );

  /* ── Popup content ── */
  const PopupContent = () => (
    <div className="flex flex-col gap-3">
      <input
        autoFocus
        className="rounded-md bg-transparent ring-0 outline-none p-1.5 border border-white/30 focus:border-white/70 text-center text-sm font-semibold"
        placeholder={t("player_id") + "..."}
        type="number"
        value={invitedTarget}
        onChange={(e) => setInvitedTarget(parseInt(e.currentTarget.value))}
      />
      <button
        onClick={handleSendInvite}
        className="font-semibold text-sm text-[#F5C842] bg-[#F5C842]/15 hover:bg-[#F5C842]/25 transition p-1.5 rounded-md border border-[#F5C842]/40"
      >
        {t("invite")}
      </button>
    </div>
  );

  /* ── Tab switcher ── */
  const TabSwitcher = () => (
    <div className="flex gap-1.5">
      <button
        onClick={() => setActiveTab("tasks")}
        className={classNames(
          "flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-semibold border transition-colors",
          {
            "bg-[#F5C842]/20 border-[#F5C842]/60 text-[#F5C842]": activeTab === "tasks",
            "bg-white/5 border-white/10 text-white/40 hover:text-white/70": activeTab !== "tasks",
          }
        )}
      >
        <IoMdHome className="w-4 h-4" />
        Tasks
      </button>
      <button
        onClick={() => setActiveTab("ranks")}
        className={classNames(
          "flex items-center gap-1.5 px-3 py-1.5 rounded-md text-xs font-semibold border transition-colors",
          {
            "bg-[#F5C842]/20 border-[#F5C842]/60 text-[#F5C842]": activeTab === "ranks",
            "bg-white/5 border-white/10 text-white/40 hover:text-white/70": activeTab !== "ranks",
          }
        )}
      >
        <FaRankingStar className="w-4 h-4" />
        Ranks
      </button>
    </div>
  );

  return (
    <div className="relative flex flex-col gap-3 p-4 w-full h-full overflow-hidden">
      {/* Top bar */}
      <div className="flex items-center justify-between flex-shrink-0">
        <h2 className="text-sm font-bold text-white/70 tracking-wide uppercase">
          {activeTab === "tasks" ? t("title") : "Rankings"}
        </h2>
        <TabSwitcher />
      </div>

      {/* Main layout */}
      <div className="flex gap-3 w-full flex-1 min-h-0 overflow-hidden">

        {/* Left column */}
        <div className="w-[220px] min-w-[220px] flex flex-col gap-2.5 overflow-hidden">
          <div
            className="flex flex-col rounded-lg overflow-hidden flex-shrink-0"
            style={{ boxShadow: "0 4px 24px rgba(0,0,0,0.4)" }}
          >
            <ProfileImage />
            <ReputationBar />
          </div>
          <GarbageInfo />
          <Graph />
        </div>

        {/* Right column */}
        <div className="flex-1 min-w-0 flex flex-col overflow-hidden">
          {activeTab === "tasks" && <Tasks />}
          {activeTab === "ranks" && <Ranks />}
        </div>
      </div>

      <Popup
        isOpen={!!openedPopup}
        onClose={() => setOpenedPopup(undefined)}
        title={openedPopup === "invite" ? t("invite") : undefined}
        error={popError}
      >
        <PopupContent />
      </Popup>
    </div>
  );
};

export default Garbage;
