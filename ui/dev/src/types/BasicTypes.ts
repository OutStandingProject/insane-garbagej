export type iPage = "garbage" | "delivery" | "towtruck";

export interface iProfile {
  source: number;
  level: number;
  exp: number;
  nextLevelExp: number;
  photo: number;
}

export interface iPlayer {
  source: number;
  photo: number;
}

type iTaskGoals = number;

export interface iLobby {
  id: number;
  members: iPlayer[];
  leaderId: number;
  isTaskStarted: boolean;
  taskId: number;
  goals: iTaskGoals;
  taskProgress: iTaskGoals;
}

export interface iTask {
  unique_id: number;
  title: string;
  fee: number;
  exp: number;
  goals: iTaskGoals;
  max_client: number;
  level: number;
}

export interface iRank {
  identifier: string;
  characterName: string;
  exp: number;
  photo: number;
  level: number;
}

export type AppTypes = iPage;
