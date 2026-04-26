import useData from "@/hooks/useData";
import { fetchNui } from "@/utils/fetchNui";
import { useTranslation } from "react-i18next";
import { FaUserFriends, FaUser, FaUsers } from "react-icons/fa";
import { HiLocationMarker } from "react-icons/hi";

const Tasks = () => {
  const { Tasks, userProfile } = useData();
  const { t } = useTranslation();

  const handleStartTask = async (taskId: number) => {
    await fetchNui("nui:startLobbyWithTask", taskId, true);
  };

  const calcTaskExp = (exp: number) => {
    if (
      !userProfile ||
      typeof userProfile?.exp != "number" ||
      !userProfile.nextLevelExp
    )
      return 0;
    const currentExp = userProfile.exp;
    const taskExp = exp;
    const nextLevelExp = userProfile.nextLevelExp;
    return currentExp + taskExp >= nextLevelExp
      ? 100
      : ((currentExp + taskExp) / nextLevelExp) * 100;
  };

  const TasksComponent = () => {
    return Tasks.map((v, i) => (
      <div
        key={i}
        className="grid items-center h-14 border-b border-white/5 hover:bg-white/[0.04] transition-colors"
        style={{ gridTemplateColumns: "56px 1fr 52px 110px 130px 52px" }}
      >
        {/* Map thumbnail */}
        <div className="w-14 h-14 overflow-hidden flex items-center justify-center bg-white/5 flex-shrink-0">
          <img
            className="w-14 h-14 object-cover opacity-60"
            src="images/gta_atlas.png"
            alt="gta_atlas"
          />
        </div>

        {/* Title + players */}
        <div className="flex items-center gap-2 px-3 min-w-0">
          <span className="text-sm font-semibold text-white whitespace-nowrap overflow-hidden text-ellipsis">
            {v.title}
          </span>
          <span className="text-xs font-semibold text-white/40 whitespace-nowrap">
            [1-{v.max_client}]
          </span>
          {v.max_client === 1 ? (
            <FaUser className="text-white/30 w-3.5 h-3.5 flex-shrink-0" />
          ) : v.max_client === 2 ? (
            <FaUserFriends className="text-white/30 w-4 h-4 flex-shrink-0" />
          ) : (
            <FaUsers className="text-white/30 w-4 h-4 flex-shrink-0" />
          )}
        </div>

        {/* Level badge */}
        <div className="flex items-center justify-center">
          <div className="w-8 h-8 rounded-md flex items-center justify-center bg-[#7A5C1E]/80">
            <span className="text-sm font-bold text-[#F5C842]">{v.level}</span>
          </div>
        </div>

        {/* Rewards badge */}
        <div className="flex items-center justify-center px-1">
          <div className="h-8 px-3 rounded-md flex items-center justify-center bg-[#F5C842]/10 border border-[#F5C842]/40 whitespace-nowrap">
            <span className="text-sm font-semibold text-[#F5C842]">
              {t("money_type")}{v.fee.toLocaleString()}
            </span>
          </div>
        </div>

        {/* Rep progress bar */}
        <div className="flex items-center px-3">
          <div className="w-full h-1.5 bg-white/10 rounded-full overflow-hidden">
            <div
              className="h-full bg-white/60 rounded-full transition-all"
              style={{ width: calcTaskExp(v.exp) + "%" }}
            />
          </div>
        </div>

        {/* GPS button */}
        <div className="flex items-center justify-center">
          <button
            onClick={() => handleStartTask(v.unique_id)}
            className="w-9 h-9 rounded-md flex items-center justify-center border border-[#F5C842]/50 bg-[#F5C842]/15 hover:bg-[#F5C842]/30 transition-colors"
          >
            <HiLocationMarker className="w-4 h-4 text-[#F5C842]" />
          </button>
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
          gridTemplateColumns: "56px 1fr 52px 110px 130px 52px",
          background: "rgba(255,255,255,0.06)",
        }}
      >
        <span className="text-white/40 text-center">{t("maps")}</span>
        <span className="text-white/40 pl-3">{t("title")}</span>
        <span className="text-white/40 text-center">{t("level")}</span>
        <span className="text-white/40 text-center">{t("rewards")}</span>
        <span className="text-white/40 pl-3">{t("rep")}</span>
        <span className="text-white/40 text-center">{t("gps")}</span>
      </div>

      {/* Task rows */}
      <div className="w-full h-full overflow-y-auto scrollbar-hide flex flex-col">
        <TasksComponent />
      </div>
    </div>
  );
};

export { Tasks };
