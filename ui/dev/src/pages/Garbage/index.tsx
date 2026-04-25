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
    "profile-photo" | "invite" | undefined
  >();
  const [popError, setPopError] = useState<string | undefined>(undefined);
  const [selectedNewPhoto, setSelectedNewPhoto] = useState<number>(
    userProfile.photo
  );
  const [invitedTarget, setInvitedTarget] = useState<number>();
  const [activeTab, setActiveTab] = useState<"tasks" | "ranks">("tasks");

  const handleSavePhoto = async () => {
    await fetchNui("nui:updateProfilePhoto", selectedNewPhoto, true);
  };

  const calcReputationWidth = () => {
    if (!userProfile || !userProfile.exp || !userProfile.nextLevelExp) return 0;
    return (userProfile.exp / userProfile.nextLevelExp) * 100;
  };

  const handleOpenProfilePhotoPopup = () => {
    setPopError(undefined);
    setOpenedPopup("profile-photo");
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

  /* ── Profile photo thumbnail ── */
  const UserProfile: React.FC<{ isLeader: boolean }> = ({ isLeader }) => (
    <button
      onClick={handleOpenProfilePhotoPopup}
      className="relative w-10 h-10 bg-white/10 rounded-md overflow-hidden"
    >
      <img
        src={`images/profiles/${userProfile.photo}.png`}
        alt="profile"
        className="w-full h-full object-cover"
      />
      {isLeader && (
        <FaCrown className="absolute -top-1.5 -left-1.5 text-[#F5C842] z-10 w-3 h-3" />
      )}
    </button>
  );

  /* ── Team invite slots ── */
  const InviteComponent: React.FC = () => (
    <div className="flex gap-1.5">
      {!currentLobby.id && <UserProfile isLeader={true} />}
      {Array(currentLobby.id ? 4 : 3)
        .fill(undefined)
        .map((_, i) => (
          <div key={i} className="relative w-10 h-10 bg-white/10 rounded-md overflow-hidden">
            {currentLobby.id && currentLobby.members[i] ? (
              <>
                <button
                  onClick={
                    currentLobby.members[i]?.source == userProfile.source
                      ? handleOpenProfilePhotoPopup
                      : () => {}
                  }
                  className={classNames(
                    "relative w-full h-full flex items-center justify-center overflow-hidden",
                    {
                      "cursor-default":
                        currentLobby.members[i]?.source != userProfile.source,
                    }
                  )}
                >
                  <img
                    src={`images/profiles/${currentLobby.members[i]?.photo}.png`}
                    alt="profile"
                    className="w-full h-full object-cover"
                  />
                </button>
                {currentLobby.members[i].source == currentLobby.leaderId && (
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
        ))}
    </div>
  );

  /* ── Left panel: profile image (top half) ── */
  const ProfileImage = () => (
    <div className="relative w-full h-44 overflow-hidden rounded-t-lg flex-shrink-0">
      <div
        className="w-full h-full bg-cover bg-center grayscale"
        style={{ backgroundImage: "url(images/app_delivery_bg.png)" }}
      />
      <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/30 to-transparent" />
      <div className="absolute bottom-3 left-3">
        <h1 className="text-sm font-bold text-white leading-tight">
          {t("victor_goods")}
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
          <p className="text-xs text-white/40">{t("victor_goods")}</p>
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
  const PopupContent = () =>
    openedPopup === "profile-photo" ? (
      <>
        <div className="flex flex-wrap items-center justify-center gap-3">
          {[1, 2, 3, 4, 5, 6, 7].map((v) => (
            <button
              key={v}
              onClick={() => setSelectedNewPhoto(v)}
              className={`w-16 h-16 border border-transparent rounded-md bg-white/10 overflow-hidden ${
                selectedNewPhoto === v ? "border-white" : ""
              }`}
            >
              <img src={`images/profiles/${v}.png`} alt="profile-photo" className="w-full h-full object-cover" />
            </button>
          ))}
        </div>
        <div className="flex justify-center mt-4">
          <button
            onClick={handleSavePhoto}
            className="px-8 py-2 text-white rounded-md bg-green-600 hover:bg-green-500 transition"
          >
            <span className="font-bold text-sm">{t("save")}</span>
          </button>
        </div>
      </>
    ) : (
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
        title={
          openedPopup &&
          (openedPopup === "invite" ? t("invite") : t("update_photo"))
        }
        error={popError}
      >
        <PopupContent />
      </Popup>
    </div>
  );
};

export default Garbage;
