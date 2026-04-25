import React, { useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import "./debug.g";
import { useNuiEvent } from "@/hooks/useNuiEvent";
import { fetchNui } from "@/utils/fetchNui";
import {
  iLobby,
  iPage,
  iPlayer,
  iProfile,
  iRank,
  iTask,
} from "@/types/BasicTypes";
import { DataCtx } from "./DataContext";

export const DataProvider: React.FC<{ children: React.ReactNode }> = ({
  children,
}) => {
  const { i18n } = useTranslation();
  const [page, setPage] = useState<iPage>("garbage");
  const [userProfile, setUserProfile] = useState<iProfile>({} as iProfile);
  const [currentLobby, setCurrentLobby] = useState<iLobby>({} as iLobby);
  const [isAppRunning, setIsAppRunning] = useState<boolean>(false);
  const [Tasks, setTasks] = useState<iTask[]>([]);
  const [taskInfo, setTaskInfo] = useState<string | null>(null);
  const [Ranks, setRanks] = useState<iRank[]>([]);

  useEffect(() => {
    fetchNui("nui:loadUI", true, true);
  }, []);

  useNuiEvent("ui:setupUI", (data) => {
    if (data.setLocale) {
      i18n.addResourceBundle("en", "translation", data.setLocale);
    }
    if (data.setTasks) {
      setTasks(Object.values(data.setTasks));
    }
    fetchNui("nui:onLoadUI", true, true);
  });

  useNuiEvent("ui:setPage", setPage);
  useNuiEvent("ui:setUserProfile", setUserProfile);
  useNuiEvent("ui:setCurrentLobby", setCurrentLobby);
  useNuiEvent("ui:setLobbyMembers", (newMembers: iPlayer[]) => {
    setCurrentLobby((p) => ({
      ...p,
      members: newMembers,
    }));
  });
  // Atualiza mugshot do próprio jogador quando recebido do client
  useNuiEvent("ui:setPlayerMugshot", (mugshot: string) => {
    setUserProfile((p) => ({
      ...p,
      mugshot,
    }));
  });
  useNuiEvent("ui:setTaskProgress", (newProgress) => {
    setCurrentLobby((p) => ({
      ...p,
      taskProgress: newProgress,
    }));
  });
  useNuiEvent("ui:setTasks", setTasks);
  useNuiEvent("ui:setTaskInfo", setTaskInfo);
  useNuiEvent("ui:setRanks", (data) => {
    setRanks(Object.values(data));
  });

  useNuiEvent("ui:setDebug", () => {
    setIsAppRunning(true);
  });

  const value = {
    page,
    setPage,
    userProfile,
    currentLobby,
    isAppRunning,
    setIsAppRunning,
    Tasks,
    taskInfo,
    Ranks,
  };

  return <DataCtx.Provider value={value}>{children}</DataCtx.Provider>;
};
