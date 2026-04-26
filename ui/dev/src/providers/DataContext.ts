import { iLobby, iPage, iProfile, iTask, iRank } from "@/types/BasicTypes";
import { createContext } from "react";

interface DataContextProps {
  page: iPage;
  setPage: React.Dispatch<React.SetStateAction<iPage>>;
  userProfile: iProfile;
  currentLobby: iLobby;
  isAppRunning: boolean;
  setIsAppRunning: React.Dispatch<React.SetStateAction<boolean>>;
  Tasks: iTask[];
  taskInfo: string | null;
  Ranks: iRank[];
}

export const DataCtx = createContext<DataContextProps>({} as DataContextProps);
